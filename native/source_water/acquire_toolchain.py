#!/usr/bin/env python3
"""Fetch pinned official Debian LLVM archives into an explicit external folder.

No apt invocation, privileged action, system install, or repository payloads.
Needs a compatible Linux x86_64 host with libLLVM19 and ordinary Clang runtime
dependencies already present. Checksum mismatch is fatal, never ignored.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--destination", type=Path, required=True)
args = parser.parse_args()
here = Path(__file__).resolve().parent
destination = args.destination.resolve()
project = here.parent.parent
if destination == project or project in destination.parents:
    parser.error("Choose a directory outside the Godot project for the toolchain.")
destination.mkdir(parents=True, exist_ok=True)
metadata = json.loads((here / "toolchain-packages.json").read_text())
for package, entry in metadata.items():
    archive = destination / Path(entry["Filename"]).name
    if not archive.exists():
        subprocess.run(["curl", "--fail", "--location", "--max-time", "120",
                        "https://deb.debian.org/debian/" + entry["Filename"],
                        "--output", str(archive)], check=True)
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual != entry["SHA256"]:
        raise SystemExit(f"Checksum mismatch for {package}; stop and inspect {archive}.")
    subprocess.run(["dpkg-deb", "--extract", str(archive), str(destination / "root")], check=True)
print(f"export SOURCE_WATER_LLVM_ROOT={destination / 'root/usr'}")
print("Toolchain extracted locally. System packages were not changed.")
