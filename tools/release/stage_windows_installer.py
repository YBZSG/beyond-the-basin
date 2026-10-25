"""Stage an explicit runtime allowlist, excluding all developer profiles/logs.

python tools/release/stage_windows_installer.py --runtime ../nr-test-build \
  --pack /path/to/PoolCore.fixed.pck --output /path/to/payload --commit <git-sha>
Then compile windows_installer.iss with Inno Setup 7, /DPayload and /DReleaseOutput.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

EXECUTABLES = ["PoolCore.exe", "PoolCoreEditor.exe"]
DLLS = [
    "source_water.windows.x86_64.dll", "NvLowLatencyVk.dll",
    "nvngx_dlss.dll", "nvngx_dlssd.dll", "nvngx_dlssg.dll", "nvngx_dlssnr.dll",
    "sl.common.dll", "sl.dlss.dll", "sl.dlss_d.dll", "sl.dlss_g.dll",
    "sl.interposer.dll", "sl.nis.dll", "sl.pcl.dll", "sl.reflex.dll",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[2]
    if args.output.exists():
        raise SystemExit("Output already exists; choose a fresh staging folder.")
    required = [args.runtime / n for n in EXECUTABLES + DLLS] + [args.pack]
    for path in required:
        if not path.is_file():
            raise SystemExit(f"Missing runtime dependency: {path}")
    args.output.mkdir(parents=True)
    for name in EXECUTABLES + DLLS:
        shutil.copy2(args.runtime / name, args.output / name)
    shutil.copy2(args.pack, args.output / "PoolCore.pck")
    shutil.copytree(args.runtime / "licenses", args.output / "licenses")
    for pattern in ("Launch-PoolCore*.cmd", "Start-PoolCore-Scene.ps1"):
        for path in (source / "tools/dlss").glob(pattern):
            shutil.copy2(path, args.output / path.name)
    for name in ("README.md", "CREDITS.md"):
        shutil.copy2(source / name, args.output / name)
    shutil.copytree(source / "source_provenance/ithappy", args.output / "licenses/ithappy-provenance")
    patchdir = args.output / "engine-patches"
    patchdir.mkdir()
    for pattern in ("engine-*.patch", "NR_DEPENDENCIES.json", "NR_README.md", "build_nr.py"):
        for path in (source / "tools/dlss").glob(pattern):
            shutil.copy2(path, patchdir / path.name)
    (args.output / "INSTALL.txt").write_text(
        "PoolCore PC 0.6.13 - Windows x64\n\n"
        "Close the old game before upgrading. Start PoolCore from the Start menu.\n"
        "First launch prepares shaders and rooms. Experimental NR/RT/FG are off by default.\n"
        "Saves: <installation folder>/profile. Existing saves are not overwritten.\n"
        "The installer includes PoolCoreEditor.exe for opening the matching GitHub source.\n"
        "Keep all DLLs beside the executables. See README.md for the source workflow.\n"
        "No private player profile is bundled. Uninstall keeps your profile folder.\n\n"
        "Third-party components retain their own licenses under licenses/.\n"
        "Game: https://github.com/YBZSG/beyond-the-basin\n",
        encoding="utf-8",
    )
    manifest = {"version": "0.6.13", "source_commit": args.commit, "files": {}}
    for path in sorted(args.output.rglob("*")):
        if path.is_file():
            manifest["files"][path.relative_to(args.output).as_posix()] = {
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
    (args.output / "RELEASE-MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"files": len(manifest["files"]), "payload": str(args.output)}))


if __name__ == "__main__":
    main()
