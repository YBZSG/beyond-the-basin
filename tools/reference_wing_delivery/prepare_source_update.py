#!/usr/bin/env python3
"""Prepare an UNARCHIVED source package from an explicit final file allowlist.

Run only after integration is frozen. This does not export, upload, or run Godot.
One path per line in the allowlist; no globs or directory recursion.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import update_source as updater


def git(root, *args, check=True):
    result = subprocess.run(["git", "-C", str(root), *args], check=False,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise updater.UpdateError("Git baseline lookup failed: " + result.stderr.decode("utf-8", "replace"))
    return result


def prepare(root, allowlist, output, update_id):
    root = updater.project_root(root)
    output = updater.checked_path(output)
    if output.exists():
        raise updater.UpdateError("Package output must be a new directory; will not overwrite: " + str(output))
    if not updater.ID_RE.fullmatch(update_id):
        raise updater.UpdateError("Unsafe update_id")
    # The user-facing update intentionally supports exactly one original base.
    git(root, "cat-file", "-e", updater.BASELINE + "^{commit}")
    baseline_project = git(root, "show", updater.BASELINE + ":project.godot").stdout
    project_hash = updater.sha_bytes(baseline_project)
    if updater.file_hash(root / "project.godot") != project_hash:
        raise updater.UpdateError("Current project.godot differs from the required 351f baseline")
    entries = []
    paths = [line.strip() for line in Path(allowlist).read_text(encoding="utf-8").splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    for relative in paths:
        updater.validate_relative(relative)
        source = updater.member(root, relative)
        new_hash = updater.file_hash(source)
        if new_hash is None:
            raise updater.UpdateError("Allowlisted source is missing: " + relative)
        blob = git(root, "cat-file", "-e", updater.BASELINE + ":" + relative, check=False)
        old_hash = None
        if blob.returncode == 0:
            old_hash = updater.sha_bytes(git(root, "show", updater.BASELINE + ":" + relative).stdout)
        if old_hash == new_hash:
            raise updater.UpdateError("Allowlist includes an unchanged baseline file: " + relative)
        entries.append({"path": relative, "old_sha256": old_hash, "new_sha256": new_hash})
    manifest = updater.validate_manifest({"format": updater.FORMAT, "update_id": update_id,
        "baseline_commit": updater.BASELINE, "anchors": [{"path": "project.godot", "sha256": project_hash}],
        "files": entries})
    # Validation and every source hash are complete before output creation.
    output.mkdir(parents=True)
    try:
        for item in manifest["files"]:
            updater.atomic_write(updater.member(output / "payload", item["path"]),
                                 source=updater.member(root, item["path"]),
                                 expected_hash=item["new_sha256"])
        for name in ("update_source.py", "compact_source_update.py", "APPLY_SOURCE_UPDATE.cmd", "ROLLBACK_SOURCE_UPDATE.cmd"):
            shutil.copyfile(Path(__file__).parent / name, output / name)
        shutil.copyfile(root / "docs/reference_wing/INSTALL-源码更新.md", output / "README-SOURCE-UPDATE.md")
        updater.atomic_write(output / "manifest.json",
                             data=(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
        updater.load_package(output)
    except BaseException:
        # No cleanup recursion: preserve an inspectable failed staging directory.
        print("Staging failed; keep/inspect the incomplete directory: " + str(output), file=sys.stderr)
        raise
    return {"output": str(output), "files": len(entries), "baseline_commit": updater.BASELINE,
            "manifest_sha256": updater.manifest_digest(manifest), "archived": False, "uploaded": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--allowlist", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--update-id", required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.project, args.allowlist, args.output, args.update_id),
                         ensure_ascii=False, indent=2))
    except (updater.UpdateError, OSError) as exc:
        print("REFUSED / ERROR: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
