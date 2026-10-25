#!/usr/bin/env python3
"""Build one ordinary ZIP containing a verified solid-XZ SOURCE payload.

Input is an already frozen/verified expanded stage. Neither that stage nor any
project is changed. Standard library only; no network, engine, exec, or cleanup.
"""
from __future__ import annotations

import argparse
import json
import lzma
from pathlib import Path
import sys
import tarfile
import zipfile

import update_source as core
import compact_source_update as compact
import baseline_prerequisites as prerequisites


ROOT_FILES = ("manifest.json", "README-SOURCE-UPDATE.md", "update_source.py",
              "compact_source_update.py", "APPLY_SOURCE_UPDATE.cmd", "ROLLBACK_SOURCE_UPDATE.cmd")


def build(stage, output, zip_path, baseline, closure_report, baseline_inventory):
    stage, manifest = core.load_package(stage)
    output, zip_path = core.checked_path(output), core.checked_path(zip_path)
    compact.require(not output.exists() and not zip_path.exists(), "Output directory and ZIP must be new; nothing overwritten")
    compact.require(stage not in output.parents and stage not in zip_path.parents,
                    "Compact outputs must be outside the expanded stage")
    compact.require(output != zip_path and output not in zip_path.parents,
                    "ZIP must be outside the compact output directory")
    baseline = core.project_root(baseline)
    compact.require(output != baseline and baseline not in output.parents and baseline not in zip_path.parents,
                    "Compact outputs must not modify the prerequisite baseline")
    sizes = {}
    for item in manifest["files"]:
        sizes[item["path"]] = core.member(stage / "payload", item["path"]).stat().st_size
    compact.require(all(size <= compact.MAX_FILE_BYTES for size in sizes.values())
                    and sum(sizes.values()) <= compact.MAX_TOTAL_BYTES, "Payload exceeds compact size limits")
    compact.verify_payload(stage / "payload", manifest, sizes)
    compact.require(core.file_hash(stage / "update_source.py") == core.file_hash(Path(__file__).parent / "update_source.py"),
                    "Expanded stage installer differs from the reviewed unchanged core")
    required_base = prerequisites.generate(stage, manifest, baseline, closure_report, baseline_inventory)
    core.safe_mkdir(output)
    try:
        core.atomic_write(output / compact.PREREQUISITES,
                          data=(json.dumps(required_base, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        for name in ROOT_FILES:
            source = stage / name if name in {"manifest.json", "README-SOURCE-UPDATE.md", "update_source.py"} else Path(__file__).parent / name
            core.atomic_write(output / name, source=source, expected_hash=core.file_hash(source))
        archive_path = output / compact.ARCHIVE
        # Related .blend/.glb basenames are adjacent in one solid stream.
        ordered = sorted(manifest["files"], key=lambda e: (Path(e["path"]).stem.casefold(),
                                                          Path(e["path"]).suffix, e["path"]))
        with lzma.open(archive_path, "xb", format=lzma.FORMAT_XZ, preset=9) as compressed:
            with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.USTAR_FORMAT, encoding="utf-8") as archive:
                for item in ordered:
                    relative = item["path"]
                    source = core.member(stage / "payload", relative)
                    info = tarfile.TarInfo(relative)
                    info.size = sizes[relative]
                    info.mode = 0o644
                    info.mtime = 0
                    info.uid = info.gid = 0
                    with source.open("rb") as stream:
                        archive.addfile(info, stream)
        descriptor = {"format": compact.FORMAT, "archive": compact.ARCHIVE,
                      "archive_sha256": core.file_hash(archive_path), "archive_size": archive_path.stat().st_size,
                      "tar_size": compact.tar_size(sizes),
                      "prerequisites_sha256": core.file_hash(output / compact.PREREQUISITES),
                      "manifest_sha256": core.manifest_digest(manifest),
                      "files": [{"path": p, "size": sizes[p]} for p in sorted(sizes)]}
        core.atomic_write(output / compact.DESCRIPTOR,
                          data=(json.dumps(descriptor, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        descriptor, sizes = compact.read_descriptor(output, manifest)
        compact.inspect_archive(output, manifest, descriptor, sizes)
        core.safe_mkdir(zip_path.parent)
        with zipfile.ZipFile(zip_path, "x", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
            for path in sorted(output.iterdir()):
                compact.require(path.is_file(), "Unexpected directory in compact outer package")
                archive.write(path, arcname=path.name)
        with zipfile.ZipFile(zip_path) as archive:
            compact.require(archive.testzip() is None, "Outer ZIP CRC verification failed")
            compact.require(set(archive.namelist()) == set(ROOT_FILES) | {compact.DESCRIPTOR, compact.ARCHIVE, compact.PREREQUISITES},
                            "Unexpected outer ZIP members")
    except BaseException as exc:
        raise core.UpdateError("Compact build failed; keep/inspect the new output directory and any partial ZIP: "
                               + str(output) + "; " + str(zip_path) + "; " + str(exc)) from exc
    return {"result": "built", "output": str(output), "zip": str(zip_path),
            "files": len(sizes), "payload_bytes": sum(sizes.values()),
            "archive_bytes": archive_path.stat().st_size, "zip_bytes": zip_path.stat().st_size,
            "required_base_files": len(required_base["files"]),
            "zip_sha256": core.file_hash(zip_path), "manifest_sha256": core.manifest_digest(manifest),
            "project_modified": False, "expanded_stage_removed": False, "uploaded": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--zip", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--closure-report", type=Path, required=True)
    parser.add_argument("--baseline-inventory", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.stage, args.output, args.zip, args.baseline, args.closure_report, args.baseline_inventory), ensure_ascii=False, indent=2))
        return 0
    except (core.UpdateError, OSError, ValueError) as exc:
        print("REFUSED / ERROR: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
