#!/usr/bin/env python3
"""Check shipped ABI targets, sole entry-point export, and zero dependencies."""
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

root = Path(__file__).resolve().parent
entry_point = "source_water_library_init"
report = {"targets": {}, "source_sha256": {}}

def run(*args):
    return subprocess.check_output(args, text=True)

for name, machine, label in [
    ("libsource_water.linux.x86_64.so", 62, "linux.x86_64"),
    ("libsource_water.android.arm64.so", 183, "android.arm64"),
]:
    path = root / "bin" / name
    data = path.read_bytes()
    assert data[:6] == b"\x7fELF\x02\x01", f"Not ELF64 little endian: {name}"
    assert struct.unpack_from("<H", data, 18)[0] == machine, f"Wrong architecture: {name}"
    dynamic = run("readelf", "--dynamic", str(path))
    assert "(NEEDED)" not in dynamic, f"External runtime dependency: {name}"
    symbols = run("readelf", "--dyn-syms", "--wide", str(path))
    exports = [line.split()[-1] for line in symbols.splitlines() if " GLOBAL " in line and " DEFAULT " in line]
    assert exports == [entry_point], (name, exports)
    assert not any(" UND " in line and len(line.split()) > 7 for line in symbols.splitlines()), name
    program_headers = run("readelf", "--program-headers", "--wide", str(path))
    stack = [line for line in program_headers.splitlines() if "GNU_STACK" in line]
    assert stack and "RWE" not in stack[0], f"Executable stack: {name}"
    if machine == 183:
        loads = [line.split()[-1] for line in program_headers.splitlines() if line.strip().startswith("LOAD")]
        assert all(int(align, 16) >= 16384 for align in loads), f"Android 16 KiB pages unsupported: {name}"
    report["targets"][label] = {
        "filename": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        "format": "ELF64 little endian", "machine": machine,
        "exports": exports, "dependencies": [], "executable_stack": False,
        "runtime_verified": label == "linux.x86_64",
    }

path = root / "bin/source_water.windows.x86_64.dll"
data = path.read_bytes()
assert data[:2] == b"MZ"
pe = struct.unpack_from("<I", data, 0x3c)[0]
assert data[pe:pe + 4] == b"PE\0\0"
assert struct.unpack_from("<H", data, pe + 4)[0] == 0x8664
optional = pe + 24
assert struct.unpack_from("<H", data, optional)[0] == 0x20b
assert struct.unpack_from("<I", data, optional + 16)[0] == 0, "Unexpected CRT entry point"
assert struct.unpack_from("<II", data, optional + 120) == (0, 0), "Unexpected DLL import directory"
dump = run("objdump", "--private-headers", str(path))
assert "DLL Name:" not in dump
exports_section = dump.split("[Ordinal/Name Pointer] Table", 1)[1]
exports = re.findall(r"^\s*\[\s*\d+\]\s+\+base\[.*", exports_section, flags=re.M)
assert entry_point in exports_section
assert re.search(r"\[Name Pointer/Ordinal\] Table\s+00000001", dump), "Expected one Windows export"
report["targets"]["windows.x86_64"] = {
    "filename": path.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
    "format": "PE32+ DLL", "machine": 0x8664, "exports": [entry_point],
    "dependencies": [], "crt_entry_point": None, "runtime_verified": False,
}
for name in ["source_water.c", "readback_core.h", "occlusion_core.h", "particle_gate_core.h", "particle_gate_binding.inc", "vendor/gdextension_interface.h", "build.sh"]:
    report["source_sha256"][name] = hashlib.sha256((root / name).read_bytes()).hexdigest()
report["notes"] = [
    "Windows and Android artifacts are cross-built and statically audited, not executed on those platforms.",
    "Linux is verified by the Godot 4.6.3 headless contract and typed ABI suites.",
    "Android ELF load alignment is compatible with 16 KiB pages.",
    "No C, C++, compiler-rt, Godot-cpp, or OS-library runtime imports.",
]
output = root / "verification/binaries.json"
output.parent.mkdir(exist_ok=True)
output.write_text(json.dumps(report, indent=2) + "\n")
print("SOURCE_NATIVE_READBACK_BINARIES_PASS targets=3 dependencies=0 exports=1_per_target")
