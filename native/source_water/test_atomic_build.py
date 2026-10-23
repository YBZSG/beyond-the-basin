#!/usr/bin/env python3
"""Build/audit only in an isolated fixture; never replace project libraries."""
import hashlib
import json
import mmap
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent
artifacts = ["libsource_water.linux.x86_64.so", "source_water.windows.x86_64.dll", "libsource_water.android.arm64.so"]
digest = lambda data: hashlib.sha256(data).hexdigest()

with tempfile.TemporaryDirectory(prefix="source-water-atomic-build-") as temporary:
    fixture = Path(temporary)
    for name in ["source_water.c", "readback_core.h", "occlusion_core.h", "particle_gate_core.h", "particle_gate_binding.inc", "build.sh", "verify_binaries.py"]:
        shutil.copy2(root / name, fixture / name)
    shutil.copytree(root / "vendor", fixture / "vendor")
    subprocess.run(["bash", "build.sh", "all"], cwd=fixture, check=True)
    subprocess.run(["python3", "verify_binaries.py"], cwd=fixture, check=True)
    first = {name: digest((fixture / "bin" / name).read_bytes()) for name in artifacts}
    shipped = {name: digest((root / "bin" / name).read_bytes()) for name in artifacts}
    assert first == shipped, "Isolated rebuild differs from tested production artifacts"
    handles = [(fixture / "bin" / name).open("rb") for name in artifacts]
    mappings = [mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) for handle in handles]
    old_inodes = [(fixture / "bin" / name).stat().st_ino for name in artifacts]
    subprocess.run(["bash", "build.sh", "all"], cwd=fixture, check=True)
    for i, name in enumerate(artifacts):
        assert (fixture / "bin" / name).stat().st_ino != old_inodes[i], "Mapped output inode was reused"
        assert digest(mappings[i][:]) == first[name], "Previously mapped bytes changed"
        assert digest((fixture / "bin" / name).read_bytes()) == first[name], "Rebuild is not reproducible"
    for mapping in mappings:
        mapping.close()
    for handle in handles:
        handle.close()
    # Fail after the Linux staged build but before Windows completes. Nothing
    # may be published to any target, and temporary stage directories clean up.
    clang = os.environ.get("CLANG")
    if not clang:
        llvm_root = os.environ.get("SOURCE_WATER_LLVM_ROOT")
        clang = str(Path(llvm_root) / "bin/clang-19") if llvm_root else shutil.which("clang")
    assert clang, "A compiler is needed for the injected-failure fixture"
    reject_windows = fixture / "reject-windows.sh"
    reject_windows.write_text('#!/usr/bin/env bash\nfor arg in "$@"; do\n  if [[ "$arg" == --target=x86_64-pc-windows-msvc ]]; then exit 92; fi\ndone\nexec ' + json.dumps(clang) + ' "$@"\n')
    reject_windows.chmod(0o755)
    before_failure = [(fixture / "bin" / name).stat().st_ino for name in artifacts]
    env = os.environ.copy(); env["CLANG"] = str(reject_windows)
    failed = subprocess.run(["bash", "build.sh", "all"], cwd=fixture, env=env)
    assert failed.returncode == 92, "Failure injection did not execute"
    for i, name in enumerate(artifacts):
        assert (fixture / "bin" / name).stat().st_ino == before_failure[i], "Partial failed build was published"
        assert digest((fixture / "bin" / name).read_bytes()) == first[name], "Failed build changed an artifact"
    assert not list((fixture / "build").glob("stage.*")), "Build staging directories leaked"
    report = {"scope": "Isolated temporary build; live project binaries were read only", "targets": first,
              "cross_target_audit": json.loads((fixture / "verification/binaries.json").read_text()),
              "reproducible": True, "replaces_inode_atomically": True, "old_mappings_unchanged": True,
              "failed_compile_publishes_nothing": True, "staging_cleanup": True}
    (root / "verification/atomic_build.json").write_text(json.dumps(report, indent=2) + "\n")
print("SOURCE_NATIVE_ATOMIC_BUILD_PASS targets=3 reproducible=1 old_mappings_unchanged=1 failed_build_published=0")
