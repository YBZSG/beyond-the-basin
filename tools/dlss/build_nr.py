"""Prepare a fresh pinned NVIDIA Godot tree, then build the optional native NR editor.

SDKs stay outside this repository. See NR_README.md for official sources/licenses.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--engine", type=Path, required=True)
p.add_argument("--nr-sdk", type=Path, required=True)
p.add_argument("--ngx-sdk", type=Path, required=True)
p.add_argument("--apply", action="store_true", help="Apply patches to a fresh pinned tree once")
p.add_argument("--jobs", type=int, default=12)
args = p.parse_args()
engine, nr_sdk, ngx_sdk = args.engine.resolve(), args.nr_sdk.resolve(), args.ngx_sdk.resolve()
assert (engine / "SConstruct").is_file(), engine
assert (nr_sdk / "include/nvsdk_ngx_helpers_dlssnr_vk.h").is_file(), nr_sdk
assert (ngx_sdk / "include/nvsdk_ngx_defs.h").is_file(), ngx_sdk
assert (ngx_sdk / "lib/nvsdk_ngx_s.lib").is_file(), ngx_sdk
if args.apply:
    for name in ["engine-taa-rg16f.patch", "engine-fg-rt.patch", "engine-camera-visibility.patch", "engine-scene-retirement.patch", "engine-dlss-nr.patch", "engine-dlss-nr-controls.patch"]:
        # Git checkouts may expose patches as CRLF on Windows; git apply needs LF.
        with tempfile.TemporaryDirectory(prefix="poolcore-nr-patch-") as directory:
            patch = Path(directory) / name
            patch.write_text(Path(__file__).with_name(name).read_text(encoding="utf8"), encoding="utf8", newline="\n")
            subprocess.run(["git", "apply", "--check", str(patch)], cwd=engine, check=True)
            subprocess.run(["git", "apply", str(patch)], cwd=engine, check=True)
env = os.environ.copy()
env.update(POOLCORE_NR_SDK=str(nr_sdk), POOLCORE_NGX_SDK=str(ngx_sdk), PYTHONUTF8="1")
subprocess.run([sys.executable, "-m", "SCons", "platform=windows", "target=editor", "arch=x86_64", "d3d12=no", "accesskit=no", "use_streamline=yes", "dev_build=no", "debug_symbols=no", "optimize=speed", f"-j{args.jobs}"], cwd=engine, env=env, check=True)
