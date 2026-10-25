#!/usr/bin/env python3
"""Frozen-package review. Never packages, imports Godot, renders, or modifies baseline.

Default: read-only base/source checks, plus JSON report creation. A compact package
may prepare its own payload; the selected pristine project stays read-only.
--exercise-copy NEW_PATH: also copy baseline and exercise ONLY that disposable copy.
Do not run against an unfinished candidate or before integration authorizes the test.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile


REPO = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("delivery_updater", REPO / "tools/reference_wing_delivery/update_source.py")
u = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(u)
ROOMS = ("stair_gallery", "colonnade", "cyan_corridor", "octagonal_bath", "ball_lounge")
BLENDS = ("tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend",
          "tools/blender/reference_wing/water_sources/colonnade.blend",
          "tools/blender/reference_wing/water_sources/cyan_corridor.blend",
          "tools/blender/reference_wing/water_sources/octagonal_bath.blend",
          "tools/blender/reference_wing/lounge_sources/ball_lounge.blend")
BUILDERS = ("tools/blender/reference_wing/stair_gallery/build_stair_gallery.py",
            "tools/blender/reference_wing/water_rooms_build.py",
            "tools/blender/reference_wing/lounge_build.py",
            "tools/materials/reference_wing/blender_materials.py",
            "tools/materials/reference_wing/generate.py",
            "tools/materials/reference_wing/surface_math.py")
RESOURCE = re.compile(r'''["']res://([^"'\r\n]+)["']''')
TEXT_EXTS = {".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres"}
UI_FIXTURE_CONSUMER = "tests/reference_wing/ui_contract.gd"
UI_FIXTURE_GENERATOR = "tests/reference_wing/ui_run_contract.py"
UI_GENERATED_INPUTS = {"tests/reference_wing/ui_host.gd",
                       "tests/reference_wing/ui_desktop_settings.gd",
                       "tests/reference_wing/ui_sources.json"}


def require(ok, message):
    if not ok:
        raise u.UpdateError(message)


def tree(root, *, mtimes=False, skip_state=False):
    result = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if skip_state and relative.split("/")[0] == u.STATE_DIR:
            continue
        require(not path.is_symlink(), "Tree contains a symlink: " + str(path))
        if path.is_file():
            info = path.stat()
            result[relative] = {"sha256": u.file_hash(path), "mode": info.st_mode & 0o777}
            if mtimes:
                result[relative]["mtime_ns"] = info.st_mtime_ns
    return result


def verify_exact_baseline(source, baseline):
    """Read the commit archive as a stream; never extract it or change Git state."""
    expected = {}
    process = subprocess.Popen(["git", "-C", str(source), "archive", "--format=tar", u.BASELINE],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for entry in archive:
                if entry.isdir():
                    continue
                require(entry.isfile(), "Baseline archive contains a nonordinary file: " + entry.name)
                digest = hashlib.sha256()
                stream = archive.extractfile(entry)
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
                expected[entry.name] = digest.hexdigest()
        stderr = process.stderr.read().decode("utf-8", "replace")
        require(process.wait() == 0, "Cannot read exact baseline archive: " + stderr)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    actual = tree(baseline)
    require({p: v["sha256"] for p, v in actual.items()} == expected,
            "The pristine baseline is not exactly the complete 351f archive")
    return actual


def glb_external_uris(path):
    with path.open("rb") as stream:
        magic, version, length = struct.unpack("<4sII", stream.read(12))
        require(magic == b"glTF" and version == 2 and length == path.stat().st_size,
                "Invalid GLB header: " + str(path))
        chunk_length, chunk_type = struct.unpack("<II", stream.read(8))
        require(chunk_type == 0x4E4F534A, "GLB first chunk is not JSON: " + str(path))
        data = json.loads(stream.read(chunk_length))
    return [item["uri"] for group in ("buffers", "images") for item in data.get(group, [])
            if item.get("uri") and not item["uri"].startswith("data:")]


def generated_fixture_reference(consumer, target, package, files):
    """Three exact UI-contract inputs are created only inside its isolated runner.

    Never exempt the same path if production code references it, or exempt any
    other missing test path. The generating runner must itself be delivered.
    """
    if consumer != UI_FIXTURE_CONSUMER or target not in UI_GENERATED_INPUTS:
        return None
    require(UI_FIXTURE_GENERATOR in files, "Generated UI fixture requires its delivered runner")
    syntax = ast.parse((package / "payload" / UI_FIXTURE_GENERATOR).read_text(encoding="utf-8"))
    written = set()
    for node in ast.walk(syntax):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "write_text"):
            continue
        destination = node.func.value
        if (isinstance(destination, ast.BinOp) and isinstance(destination.op, ast.Div)
                and isinstance(destination.left, ast.Name) and destination.left.id == "fixture"
                and isinstance(destination.right, ast.Constant) and isinstance(destination.right.value, str)):
            written.add(destination.right.value)
    require(UI_GENERATED_INPUTS <= written, "Delivered UI runner no longer writes all three generated inputs")
    return {"from": consumer, "path": target, "generator": UI_FIXTURE_GENERATOR,
            "reason": "Exact isolated test-fixture input written by the delivered runner before its engine invocation; not a production runtime dependency."}


def dependencies(source, baseline, package, manifest):
    files = {entry["path"] for entry in manifest["files"]}
    required = set(BLENDS) | set(BUILDERS)
    required |= {str(Path(path).parent / ".gdignore") for path in BLENDS}
    required |= {f"assets/models/reference_wing/{room}{suffix}"
                 for room in ROOMS for suffix in (".glb", ".glb.import", ".geometry.json")}
    required |= {"scripts/main.gd", "scripts/app/world_restart.gd",
                 "scripts/rendering/rt_material_refresh.gd", "docs/reference_wing/INSTALL-源码更新.md"}
    # All production runtime files, not the old suggested manifest. Excludes no-op UIDs
    # only when the same file already exists in the exact baseline.
    for folder in ("scripts/reference_wing", "shaders/reference_wing", "assets/materials/reference_wing"):
        required |= {p.relative_to(source).as_posix() for p in (source / folder).rglob("*")
                     if p.is_file() and "__pycache__" not in p.parts}
    # Resolve local Python helper imports without running Blender or importing helpers.
    local_modules = {}
    for folder in ("tools/blender/reference_wing", "tools/materials/reference_wing"):
        for path in (source / folder).rglob("*.py"):
            if "candidates" not in path.parts:
                local_modules.setdefault(path.stem, []).append(path.relative_to(source).as_posix())
    queue = list(BUILDERS)
    scanned = set()
    while queue:
        relative = queue.pop()
        if relative in scanned:
            continue
        scanned.add(relative)
        syntax = ast.parse((source / relative).read_text(encoding="utf-8"))
        for node in ast.walk(syntax):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.endswith(".json"):
                adjacent = Path(relative).parent / node.value
                if (source / adjacent).is_file():
                    required.add(adjacent.as_posix())
            names = [a.name.split(".")[0] for a in node.names] if isinstance(node, ast.Import) else (
                [node.module.split(".")[0]] if isinstance(node, ast.ImportFrom) and node.module else [])
            for name in names:
                choices = local_modules.get(name, [])
                require(len(choices) <= 1, "Ambiguous local helper, review manually: " + name)
                for helper in choices:
                    required.add(helper)
                    queue.append(helper)
    missing = sorted(p for p in required if p not in files and not (baseline / p).is_file())
    require(not missing, "Final manifest omits production/source dependencies: " + repr(missing))
    resources = set()
    generated_outputs = set()
    generated_fixture_inputs = []
    for relative in files:
        if Path(relative).suffix in TEXT_EXTS:
            text = (package / "payload" / relative).read_text(encoding="utf-8")
            for match in RESOURCE.finditer(text):
                path = match.group(1)
                fixture = generated_fixture_reference(relative, path, package, files)
                if fixture is not None:
                    generated_fixture_inputs.append(fixture)
                    continue
                if path.startswith("output/"):
                    generated_outputs.add(path)
                    continue
                if not path.endswith("/"):
                    require("%" not in path, "Dynamic resource path needs manual review: " + path)
                    resources.add(path)
    unresolved = sorted(p for p in resources if p not in files and not (baseline / p).is_file())
    require(not unresolved, "Unresolved literal runtime resources: " + repr(unresolved))
    external = {room: glb_external_uris(package / "payload/assets/models/reference_wing" / (room + ".glb"))
                for room in ROOMS}
    require(not any(external.values()), "Unexpected external GLB resources need explicit resolution: " + repr(external))
    excluded = [p for p in files if p.endswith(".blend1") or "candidate" in Path(p).name.lower()
                or p.startswith("tests/reference_wing/delivery_review/exercise-")]
    require(not excluded, "Candidate/backup/disposable paths present in final payload: " + repr(excluded))
    return {"required_paths": sorted(required), "literal_resources": sorted(resources),
            "generated_test_fixture_inputs_excluded": generated_fixture_inputs,
            "generated_output_literals_excluded": sorted(generated_outputs),
            "local_python_helpers": sorted(scanned), "glb_external_uris": external,
            "limitation": "Static source closure only. Does not reopen Blender image links or run Godot/4.8 graphics."}


def cli(package, command, project):
    entry = "compact_source_update.py" if (package / "compact_source_update.py").is_file() else "update_source.py"
    arguments = [sys.executable, str(package / entry), command, str(project), "--package", str(package)]
    if entry == "compact_source_update.py" and not (package / "compact_payload.json").exists():
        arguments.append("--expanded")
    process = subprocess.run(arguments, capture_output=True,
                             text=True, encoding="utf-8")
    return process, json.loads(process.stdout) if process.returncode == 0 else None


def exercise(package, baseline, copy, manifest):
    require(not copy.exists(), "Exercise destination must be a new directory")
    require(copy.resolve() != baseline.resolve() and baseline.resolve() not in copy.resolve().parents,
            "Exercise destination must not be inside baseline")
    shutil.copytree(baseline, copy)
    original = tree(copy)
    full_before = tree(copy, mtimes=True)
    process, checked = cli(package, "check", copy)
    require(process.returncode == 0 and checked["result"] == "ready", "check failed: " + process.stderr)
    require(tree(copy, mtimes=True) == full_before, "check unexpectedly wrote files")
    process, applied = cli(package, "apply", copy)
    require(process.returncode == 0 and applied["result"] == "installed", "apply failed: " + process.stderr)
    expected = {p: v["sha256"] for p, v in original.items()}
    expected.update({e["path"]: e["new_sha256"] for e in manifest["files"]})
    require({p: v["sha256"] for p, v in tree(copy, skip_state=True).items()} == expected,
            "Applied source tree does not equal baseline plus the exact allowlist")
    installed = tree(copy, mtimes=True)
    process, repeated = cli(package, "apply", copy)
    require(process.returncode == 0 and repeated["result"] == "already_applied", "Repeat apply was not idempotent")
    require(tree(copy, mtimes=True) == installed, "Repeat apply modified bytes/modes/mtimes")
    process, status = cli(package, "status", copy)
    require(process.returncode == 0 and all(e["matches_installed"] for e in status["files"]),
            "Installed status did not verify every payload file")
    # A later edit must refuse the entire rollback without even changing the receipt.
    changed = copy / manifest["files"][0]["path"]
    changed_bytes = changed.read_bytes()
    changed.write_bytes(changed_bytes + b"\nINDEPENDENT DISPOSABLE TEST EDIT\n")
    edited = tree(copy, mtimes=True)
    process, _ = cli(package, "rollback", copy)
    require(process.returncode != 0 and "later edit/deletion" in process.stderr,
            "Rollback failed to refuse a later edit")
    require(tree(copy, mtimes=True) == edited, "Refused rollback changed files")
    changed.write_bytes(changed_bytes)
    process, rolled = cli(package, "rollback", copy)
    require(process.returncode == 0 and rolled["result"] == "rolled_back", "rollback failed: " + process.stderr)
    require(tree(copy, skip_state=True) == original, "Rollback did not restore full original bytes/modes")
    before_repeat = tree(copy, mtimes=True)
    process, repeated_rollback = cli(package, "rollback", copy)
    require(process.returncode == 0 and repeated_rollback["result"] == "already_rolled_back", "Repeat rollback failed")
    require(tree(copy, mtimes=True) == before_repeat, "Repeat rollback modified files")
    return {"check": checked["result"], "apply": applied["result"], "repeat_apply": repeated["result"],
            "status_files": len(status["files"]), "later_edit_preserved": True,
            "rollback": rolled["result"], "repeat_rollback": repeated_rollback["result"],
            "restored_original_file_count": len(original), "copy": str(copy)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=REPO)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--exercise-copy", type=Path)
    args = parser.parse_args()
    result = {"result": "failed", "baseline_commit": u.BASELINE, "graphics_run": False,
              "windows_cmd_executed": False, "actual_base_exercise": None}
    try:
        original_baseline = verify_exact_baseline(args.source, args.baseline)
        inventory_path = args.report.with_suffix(".baseline_inventory.json")
        inventory_path.parent.mkdir(parents=True, exist_ok=True)
        inventory_path.write_text(json.dumps({"baseline_commit": u.BASELINE,
            "files": [{"path": p, "sha256": v["sha256"]} for p, v in sorted(original_baseline.items())]},
            ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        result["baseline_inventory"] = str(inventory_path)
        package = u.checked_path(args.package)
        names = ["update_source.py", "APPLY_SOURCE_UPDATE.cmd", "ROLLBACK_SOURCE_UPDATE.cmd"]
        if (package / "compact_source_update.py").exists() or (package / "compact_payload.json").exists():
            names.append("compact_source_update.py")
        for name in names:
            require(u.file_hash(package / name) == u.file_hash(args.source / "tools/reference_wing_delivery" / name),
                    "Package installer differs from reviewed source: " + name)
        if (package / "compact_payload.json").exists():
            process, preparation = cli(package, "check", args.baseline)
            require(process.returncode == 0, "Compact package preparation/check failed: " + process.stderr)
            result["compact_preparation_check"] = preparation["result"]
        package, manifest = u.load_package(package)
        result["exact_baseline_file_count"] = len(original_baseline)
        result["manifest_sha256"] = u.manifest_digest(manifest)
        result["files"] = len(manifest["files"])
        for item in manifest["files"]:
            require(u.file_hash(args.source / item["path"]) == item["new_sha256"],
                    "Source changed since final freeze: " + item["path"])
            require(u.file_hash(args.baseline / item["path"]) == item["old_sha256"],
                    "Manifest old hash disagrees with exact baseline: " + item["path"])
        require(u.file_hash(package / "README-SOURCE-UPDATE.md") ==
                u.file_hash(args.source / "docs/reference_wing/INSTALL-源码更新.md"),
                "Package installation guide differs from reviewed source")
        result["dependencies"] = dependencies(args.source, args.baseline, package, manifest)
        if args.exercise_copy:
            result["actual_base_exercise"] = exercise(package, args.baseline, args.exercise_copy, manifest)
        require(tree(args.baseline) == original_baseline, "Pristine baseline changed during review")
        result["pristine_baseline_unchanged"] = True
        result["result"] = "passed"
    except (OSError, ValueError, u.UpdateError) as exc:
        result["error"] = str(exc)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "dependencies"}, ensure_ascii=False, indent=2))
    return 0 if result["result"] == "passed" else 2


if __name__ == "__main__":
    sys.exit(main())
