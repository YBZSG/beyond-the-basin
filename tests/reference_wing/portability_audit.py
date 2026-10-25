"""Audit NEW Reference Wing closure without Godot imports or production mutations.

Run: python tests/reference_wing/portability_audit.py --blender /usr/bin/blender
Copies only the five approved editable sources and ten new PNG maps to a clean
temporary hierarchy; Blender opens both original and copied sources without saves.
The unapproved colonnade pier candidate and .blend1 backups are never copied.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ROOMS = ("stair_gallery", "colonnade", "cyan_corridor", "octagonal_bath", "ball_lounge")
SOURCES = {
    "stair_gallery": "tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend",
    "colonnade": "tools/blender/reference_wing/water_sources/colonnade.blend",
    "cyan_corridor": "tools/blender/reference_wing/water_sources/cyan_corridor.blend",
    "octagonal_bath": "tools/blender/reference_wing/water_sources/octagonal_bath.blend",
    "ball_lounge": "tools/blender/reference_wing/lounge_sources/ball_lounge.blend",
}
ALLOWED_EDITS = ("scripts/main.gd", "scripts/app/world_restart.gd", "scripts/rendering/rt_material_refresh.gd")
TEXT_SUFFIXES = {".gd", ".gdshader", ".gdshaderinc", ".tres", ".tscn"}
RES_PATTERN = re.compile(r'''["'](res://[^"'\n]+)["']''')
LEGACY_OPTIONAL = "res://assets/character_refinement/model_contract.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_record(path):
    return {"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": digest(path)}


def glb_record(room):
    path = ROOT / "assets/models/reference_wing" / (room + ".glb")
    raw = path.read_bytes()
    magic, version, declared = struct.unpack_from("<4sII", raw)
    errors = []
    if magic != b"glTF" or version != 2 or declared != len(raw):
        errors.append("Invalid GLB 2.0 header/length")
    chunks, cursor = {}, 12
    while cursor < len(raw):
        size, kind = struct.unpack_from("<II", raw, cursor)
        cursor += 8
        chunks[kind] = raw[cursor:cursor + size]
        cursor += size
    if cursor != len(raw):
        errors.append("Invalid chunk boundary")
    data = json.loads(chunks[0x4e4f534a])
    binary = chunks.get(0x004e4942, b"")
    external = [{"kind": kind, "uri": item["uri"]} for kind in ("buffers", "images")
                for item in data.get(kind, []) if item.get("uri") and not item["uri"].startswith("data:")]
    for buffer in data.get("buffers", []):
        if "uri" not in buffer and not 0 <= len(binary) - buffer["byteLength"] <= 3:
            errors.append("Embedded buffer length mismatch")
    for index, view in enumerate(data.get("bufferViews", [])):
        if view.get("byteOffset", 0) + view["byteLength"] > data["buffers"][view["buffer"]]["byteLength"]:
            errors.append("bufferView %d exceeds buffer" % index)
    for kind in ("images", "accessors"):
        for index, item in enumerate(data.get(kind, [])):
            if "bufferView" in item and not 0 <= item["bufferView"] < len(data.get("bufferViews", [])):
                errors.append("%s %d has invalid bufferView" % (kind, index))
    primitives = sum(len(m["primitives"]) for m in data.get("meshes", []))
    if not primitives or not data.get("scenes") or not data.get("nodes"):
        errors.append("Missing populated scene/mesh graph")
    sidecar = path.with_suffix(".geometry.json")
    geometry = json.loads(sidecar.read_text())
    if not geometry.get("collision_proxies") or not geometry.get("portal_contracts"):
        errors.append("Missing geometry collision/portal contract")
    if not (geometry.get("camera_views") or geometry.get("recommended_views")):
        errors.append("Missing authored camera contract")
    source_links = {}
    for key in ("source", "editable_source", "source_blend", "generator", "rebuild_script", "glb"):
        value = geometry.get(key)
        if isinstance(value, str):
            target = ROOT / value.removeprefix("res://")
            source_links[key] = {"path": value, "exists": target.is_file()}
            if not target.is_file():
                errors.append("Missing geometry metadata path: " + value)
    return {"room": room, "glb": file_record(path), "geometry": file_record(sidecar),
            "editable_source": file_record(ROOT / SOURCES[room]),
            "meshes": len(data.get("meshes", [])), "primitives": primitives,
            "images": len(data.get("images", [])), "embedded_binary_bytes": len(binary),
            "external_uris": external, "metadata_paths": source_links, "errors": errors,
            "pass": not errors and not external}


def runtime_closure():
    seeds = sorted((ROOT / "scripts/reference_wing").glob("*.gd"))
    seeds += sorted(p for p in (ROOT / "shaders/reference_wing").iterdir() if p.suffix in TEXT_SUFFIXES)
    seeds += [ROOT / p for p in ALLOWED_EDITS]
    pending, seen, refs, missing, exceptions = list(seeds), set(), [], [], []
    while pending:
        source = pending.pop()
        if source in seen:
            continue
        seen.add(source)
        for value in RES_PATTERN.findall(source.read_text()):
            record = {"from": str(source.relative_to(ROOT)), "path": value}
            if value.startswith("res://output/"):
                exceptions.append({**record, "reason": "Output capture destination, not input dependency"})
                continue
            if "%s" in value:
                exceptions.append({**record, "reason": "Audio template expanded separately below"})
                continue
            target = ROOT / value.removeprefix("res://")
            if value == LEGACY_OPTIONAL and not target.exists():
                exceptions.append({**record, "reason": "Unmodified legacy optional hand contract; fallback model exists"})
                continue
            record["exists"] = target.exists()
            refs.append(record)
            if not target.exists():
                missing.append(record)
            if target.is_file() and target.suffix in TEXT_SUFFIXES:
                pending.append(target)
    # Enumerate runtime paths assembled from constants rather than full literals.
    dynamic = [f"assets/models/reference_wing/{r}{ext}" for r in ROOMS for ext in (".glb", ".geometry.json")]
    dynamic += ["assets/materials/reference_wing/" + p for p in (
        "ref_tile_pearl_albedo_2k.png", "ref_tile_teal_albedo_2k.png",
        "ref_tile_pink_albedo_2k.png", "ref_tile_dark_teal_albedo_2k.png",
        "bevel_slope_rg_2k.png", "glaze_orm_2k.png")]
    audio_source = (ROOT / "scripts/audio/pool_audio.gd").read_text()
    for name, prefix, suffix in (("CLIP_NAMES", "assets/sfx/", ".ogg"), ("GAIT_CLIPS", "assets/sfx/native_gait/", ".wav")):
        values = re.search(r"const " + name + r"\s*:=\s*(\[[^\]]*\])", audio_source).group(1)
        dynamic += [prefix + value + suffix for value in json.loads(values)]
    dynamic_records = [{"path": p, "exists": (ROOT / p).is_file()} for p in dynamic]
    missing += [r for r in dynamic_records if not r["exists"]]
    return {"text_files_scanned": len(seen), "literal_references": refs,
            "expanded_dynamic_references": dynamic_records, "documented_exceptions": exceptions,
            "missing_required_inputs": missing, "pass": not missing}


def tracked_scope():
    modified = subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).splitlines()
    imports = [p for p in modified if p.endswith(".import")]
    actual = [p for p in modified if not p.endswith(".import")]
    unexpected = [p for p in actual if p not in ALLOWED_EDITS]
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines()
    generated = [p for p in untracked if p.endswith((".uid", ".import")) or
                 p.startswith(("assets/water_hands/pool_explorer_water_hands_explorer_", "assets/water_motion/explorer_water_motion_explorer_"))]
    return {"baseline_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "allowed_changes": list(ALLOWED_EDITS), "tracked_non_import_changes": actual,
            "unexpected_changes": unexpected, "ignored_modified_imports": imports,
            "reported_generated_untracked_files": generated, "pass": not unexpected}


def delivery_manifest():
    runtime = []
    for folder in ("assets/models/reference_wing", "assets/materials/reference_wing", "scripts/reference_wing", "shaders/reference_wing"):
        runtime += [p for p in (ROOT / folder).rglob("*") if p.is_file()
                    and "candidate" not in p.name and "__pycache__" not in p.parts]
    authoring = []
    for folder in ("tools/blender/reference_wing", "tools/materials/reference_wing"):
        authoring += [p for p in (ROOT / folder).rglob("*") if p.is_file()
                      and "__pycache__" not in p.parts and "candidate" not in p.name
                      and (p.suffix in (".py", ".sh", ".md", ".blend") or p.name == ".gdignore")]
    # Explicit source allowlist prevents an unreviewed alternate .blend from
    # entering the suggested delivery merely because it shares a directory.
    authoring = [p for p in authoring if p.suffix != ".blend" or str(p.relative_to(ROOT)) in SOURCES.values()]
    # Required production join recipe, not a blanket inclusion of candidate or
    # QA JSON files that happen to share the authoring directory.
    authoring.append(ROOT / "tools/blender/reference_wing/water_rooms_joint_manifest.json")
    result = {
        "status": "Suggested source-project patch manifest; not target-machine acceptance",
        "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "apply_to": "Complete unchanged original Godot project at base_commit; this is not a standalone replacement project",
        "integration_edits": [file_record(ROOT / p) for p in ALLOWED_EDITS],
        "runtime_additions": [file_record(p) for p in sorted(runtime)],
        "editable_authoring_additions": [file_record(p) for p in sorted(authoring)],
        "retain_new_import_metadata": True,
        "exclude": [".godot/", "__pycache__/", "*.blend1", "unapproved *candidate* sources/scripts",
                    "incidental original-asset .import changes and extracted textures from central Godot import"],
        "note": "Preserve project-relative hierarchy. Include finalized docs/reference_wing and relevant tests separately as QA evidence."
    }
    (HERE / "portability_delivery_manifest.json").write_text(json.dumps(result, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", default="/usr/bin/blender")
    args = parser.parse_args()
    maps_dir = ROOT / "assets/materials/reference_wing"
    material = json.loads((maps_dir / "material_manifest.json").read_text())
    maps = [maps_dir / name for name in material["files"]]
    map_records = []
    for path in maps:
        record = file_record(path)
        expected = material["files"][path.name]
        record["pass"] = record["sha256"] == expected["sha256"] and record["bytes"] == expected["bytes"]
        map_records.append(record)
    report = {"audit_utc": datetime.now(timezone.utc).isoformat(), "scope": "Production Reference Wing only; read-only CPU audit",
              "rooms": [glb_record(room) for room in ROOMS], "material_maps": map_records,
              "runtime_closure": runtime_closure(), "tracked_scope": tracked_scope()}
    manifest = {"editable_sources": list(SOURCES.values()), "maps": [str(p.relative_to(ROOT)) for p in maps],
                "candidate_excluded": "tools/blender/reference_wing/water_sources/colonnade_pier_teal_candidate.blend",
                "required_hierarchy": "Preserve project-relative paths; do not flatten source or maps directories."}
    manifest_path = HERE / "portability_source_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    watched = [ROOT / p for p in SOURCES.values()] + maps
    watched += [ROOT / "assets/models/reference_wing" / (room + ext) for room in ROOMS for ext in (".glb", ".geometry.json")]
    before = {str(p.relative_to(ROOT)): digest(p) for p in watched}
    with tempfile.TemporaryDirectory(prefix="reference-wing-portability-") as folder:
        copied_root = Path(folder) / "independent_project"
        for rel in manifest["editable_sources"] + manifest["maps"]:
            copied = copied_root / rel
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, copied)
        for label, root in (("original", ROOT), ("copied", copied_root)):
            output = HERE / ("portability_blender_" + label + ".json")
            log = HERE / ("portability_blender_" + label + ".txt")
            command = [args.blender, "--factory-startup", "--background", "--disable-autoexec", "--threads", "1",
                       "--python-exit-code", "1", "--python", str(HERE / "portability_blender_probe.py"),
                       "--", str(root), str(manifest_path), str(output)]
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
            log.write_text(result.stdout)
            if result.returncode or not output.is_file():
                raise RuntimeError("Blender read-only probe failed; see " + str(log))
            report["blender_" + label] = json.loads(output.read_text())
    report["original_hashes_unchanged"] = all(digest(ROOT / p) == sha for p, sha in before.items())
    report["pass"] = (all(x["pass"] for x in report["rooms"] + map_records)
                      and report["runtime_closure"]["pass"] and report["tracked_scope"]["pass"]
                      and report["blender_original"]["pass"] and report["blender_copied"]["pass"]
                      and report["original_hashes_unchanged"])
    delivery_manifest()
    (HERE / "portability_report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"pass": report["pass"], "rooms": len(report["rooms"]), "maps": len(map_records),
                      "runtime_missing": report["runtime_closure"]["missing_required_inputs"],
                      "source_failures": [{"source": s["source"], "dependencies": [d for d in s["dependencies"] if not d["pass"]]} for s in report["blender_copied"]["sources"] if not s["pass"]],
                      "original_hashes_unchanged": report["original_hashes_unchanged"]}, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
