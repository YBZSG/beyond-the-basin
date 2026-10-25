"""Build-time required-base closure. Reads merged payload/base; never changes either."""
from __future__ import annotations

import json
from pathlib import Path
import posixpath
import re
import struct
from urllib.parse import unquote, urlsplit

import update_source as core


FORMAT = "poolcore-base-prerequisites/v1"
FILENAME = "base_prerequisites.json"
OPTIONAL = {"assets/character_refinement/model_contract.json",
            "assets/character_refinement/natural_hand_finish/explorer_natural_hand.scn"}
TEXT = {".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres", ".json", ".glsl", ".glslinc", ".vert", ".frag", ".comp", ".gdextension", ".import"}
RES = re.compile(r'''res://([^"'\r\n]+)''')
BINARY_DEPENDENCIES = {
    "assets/water_motion/explorer_water_motion.scn": [],
    "assets/lighting/runtime_mainhall_candidate/native_indirect.lmbake": [
        "assets/lighting/runtime_mainhall_candidate/indirect_00.exr"],
}
BINARY_QUERY_HASHES = {
    "assets/water_motion/explorer_water_motion.scn": "66f674c5f95b7f9a945b1e6ade7acee612b0e0951ef415348598c3d61b8a8f67",
    "assets/lighting/runtime_mainhall_candidate/native_indirect.lmbake": "57d7fdc37f152eb046dfd673dd4e76878e6258ca89a55f502defdcc32a604b18",
}


def runtime_path(path):
    return path == "project.godot" or path == "default_bus_layout.tres" or path.startswith(
        ("scripts/", "scenes/", "shaders/", "assets/", "native/"))


def generate(stage, manifest, baseline, closure_report, baseline_inventory):
    baseline = core.project_root(baseline)
    core.check_anchors(baseline, manifest)
    payload = {e["path"]: core.member(stage / "payload", e["path"]) for e in manifest["files"]}
    for item in manifest["files"]:
        if core.file_hash(core.member(baseline, item["path"])) != item["old_sha256"]:
            raise core.UpdateError("Prerequisite baseline differs from manifest old value: " + item["path"])
    certificate = core.read_json(baseline_inventory)
    if not isinstance(certificate, dict) or set(certificate) != {"baseline_commit", "files"} or certificate["baseline_commit"] != core.BASELINE:
        raise core.UpdateError("An archive-derived exact 351f baseline inventory is required")
    expected_base = {}
    if not isinstance(certificate["files"], list):
        raise core.UpdateError("Invalid baseline inventory file list")
    for entry in certificate["files"]:
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256"} or not core.valid_hash(entry["sha256"]):
            raise core.UpdateError("Invalid baseline inventory entry")
        # This inventory describes the complete immutable archive, including old
        # optional caches that are deliberately forbidden in an update allowlist.
        path = entry["path"]
        if not isinstance(path, str) or not path or "\\" in path or path.startswith("/") or any(
                part in {"", ".", ".."} for part in path.split("/")):
            raise core.UpdateError("Unsafe baseline inventory path")
        if path in expected_base:
            raise core.UpdateError("Duplicate baseline inventory path")
        expected_base[path] = entry["sha256"]
    inventory = {p.relative_to(baseline).as_posix(): core.checked_path(p)
                 for p in baseline.rglob("*") if p.is_file()}
    inventory.update({p: path for p, path in payload.items() if runtime_path(p)})
    report = core.read_json(closure_report)
    closure = report.get("runtime_closure", {}) if isinstance(report, dict) else {}
    if closure.get("pass") is not True or closure.get("missing_required_inputs") != []:
        raise core.UpdateError("A passing final runtime closure report with no missing inputs is required")
    seeds = []
    for key in ("literal_references", "expanded_dynamic_references"):
        rows = closure.get(key)
        if not isinstance(rows, list):
            raise core.UpdateError("Missing runtime closure seed list: " + key)
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("path"), str):
                raise core.UpdateError("Invalid runtime closure seed")
            seeds.append(row["path"])
    queue = ["project.godot"] + [p for p in payload if runtime_path(p)]
    # Godot auto-discovers extension descriptors; include their declared binaries,
    # not unrelated native source/build docs or an external engine installation.
    queue += [p for p in inventory if p.endswith(".gdextension")]
    if "default_bus_layout.tres" in inventory:
        queue.append("default_bus_layout.tres")
    seen, unresolved, excluded, prefixes = set(), set(), set(), set()
    classes = {}
    for p, path in inventory.items():
        if p.endswith(".gd"):
            match = re.search(r"(?m)^\s*class_name\s+([A-Za-z_]\w*)", path.read_text(encoding="utf-8"))
            if match:
                if match.group(1) in classes and classes[match.group(1)] != p:
                    raise core.UpdateError("Duplicate Godot class_name: " + match.group(1))
                classes[match.group(1)] = p

    def reference(value):
        relative = value[6:] if value.startswith("res://") else value
        if relative.startswith(("output/", ".godot/", "tools/", "docs/", "tests/", "source_provenance/", "assets/cache/source_terrain/")) or relative in OPTIONAL:
            excluded.add(relative)
            return
        # Existing literal paths have precedence over prefix expansion.
        if relative in inventory:
            queue.append(relative)
            return
        if relative.endswith(".import") and not (baseline / relative).is_file() and relative not in payload:
            excluded.add(relative)
            return
        prefix = relative.split("%", 1)[0]
        matches = [p for p in inventory if p.startswith(prefix)]
        if (relative.endswith("/") or "%" in relative or Path(relative).suffix == "") and matches:
            prefixes.add(relative)
            queue.extend(matches)
        else:
            unresolved.add(relative)

    for value in seeds:
        reference(value)
    while queue:
        relative = queue.pop()
        if relative in seen:
            continue
        if relative not in inventory:
            unresolved.add(relative)
            continue
        seen.add(relative)
        path = inventory[relative]
        core.validate_relative(relative)
        for sidecar in (relative + ".import", relative + ".uid"):
            if sidecar in inventory:
                queue.append(sidecar)
        if relative == "project.godot" or path.suffix in TEXT:
            text = path.read_text(encoding="utf-8")
            for value in RES.findall(text):
                reference(value)
            if path.suffix == ".gd":
                for token in set(re.findall(r"\b[A-Za-z_]\w*\b", text)) & set(classes):
                    queue.append(classes[token])
        elif path.suffix in {".scn", ".res", ".lmbake"}:
            if relative not in BINARY_DEPENDENCIES:
                raise core.UpdateError("Binary Godot dependency closure needs explicit verified query: " + relative)
            if core.file_hash(path) != BINARY_QUERY_HASHES[relative]:
                raise core.UpdateError("Binary resource differs from verified dependency-query bytes: " + relative)
            for dependency in BINARY_DEPENDENCIES[relative]:
                reference(dependency)
        elif path.suffix in {".glb", ".gltf"}:
            if path.suffix == ".glb":
                with path.open("rb") as stream:
                    header = stream.read(20)
                    if len(header) != 20:
                        raise core.UpdateError("Truncated required GLB header: " + relative)
                    magic, version, length, size, kind = struct.unpack("<4sIIII", header)
                    if magic != b"glTF" or version != 2 or length != path.stat().st_size:
                        raise core.UpdateError("Invalid required GLB header: " + relative)
                    if kind != 0x4E4F534A or size > length - 20 or size > 64 * 1024 ** 2 or size % 4:
                        raise core.UpdateError("Invalid or excessive required GLB JSON chunk: " + relative)
                    try:
                        gltf = json.loads(stream.read(size))
                    except ValueError as exc:
                        raise core.UpdateError("Invalid required GLB JSON: " + relative) from exc
            else:
                gltf = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(gltf, dict):
                raise core.UpdateError("Required glTF JSON must be an object: " + relative)
            for group in ("buffers", "images"):
                entries = gltf.get(group, [])
                if not isinstance(entries, list):
                    raise core.UpdateError("Invalid required glTF resource list: " + relative)
                for entry in entries:
                    if not isinstance(entry, dict):
                        raise core.UpdateError("Invalid required glTF resource entry: " + relative)
                    uri = entry.get("uri")
                    if uri is not None and not isinstance(uri, str):
                        raise core.UpdateError("Invalid required glTF URI: " + relative)
                    if not uri or uri.startswith("data:"):
                        continue
                    parsed = urlsplit(uri)
                    decoded = unquote(parsed.path)
                    if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment or decoded.startswith("/") or "\\" in decoded:
                        raise core.UpdateError("Unsupported external GLB/glTF URI: " + relative + ": " + uri)
                    target = posixpath.normpath(posixpath.join(posixpath.dirname(relative), decoded))
                    core.validate_relative(target)
                    reference(target)
    if unresolved:
        raise core.UpdateError("Unresolved required runtime dependencies need explicit review: " + repr(sorted(unresolved)))
    files = []
    regenerated_metadata = []
    for p in sorted(seen - set(payload)):
        if p.endswith((".import", ".uid")):
            # Canonical metadata is read for dependency discovery, not hash-gated
            # on the user's editor version. New payload metadata remains strict.
            regenerated_metadata.append(p)
            continue
        expected = expected_base.get(p)
        if expected is None or core.file_hash(core.member(baseline, p)) != expected:
            raise core.UpdateError("Required base resource does not match immutable 351f inventory: " + p)
        files.append({"path": p, "sha256": expected})
    if not files or not any(e["path"] == "project.godot" for e in files):
        raise core.UpdateError("Required-base closure must include project.godot")
    return {"format": FORMAT, "baseline_commit": core.BASELINE,
            "manifest_sha256": core.manifest_digest(manifest), "files": files,
            "coverage": {"seed_report_sha256": core.file_hash(closure_report),
                         "baseline_inventory_sha256": core.file_hash(baseline_inventory),
                         "seed_count": len(seeds), "merged_runtime_files": len(seen),
                         "expanded_prefixes": sorted(prefixes), "documented_exclusions": sorted(excluded),
                         "regenerated_baseline_metadata_not_hash_gated": regenerated_metadata,
                         "binary_dependencies": {p: BINARY_DEPENDENCIES[p] for p in seen if p in BINARY_DEPENDENCIES},
                         "binary_query_sha256": {p: BINARY_QUERY_HASHES[p] for p in seen if p in BINARY_QUERY_HASHES},
                         "binary_query_evidence": "Official Godot 4.6.3 ResourceLoader.get_dependencies returned these exact dependencies; no rendering or GPU query.",
                         "method": "Final literal+expanded dynamic seeds, transitive text/class_name/GLB references, verified binary dependencies, discovered extension descriptors and existing sidecars; output/cache/authoring/unrelated files are excluded."}}
