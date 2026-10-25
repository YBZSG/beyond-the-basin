"""Read-only Blender dependency probe. Never save, render, export, or modify a source."""
import json
import os
import sys
from pathlib import Path

import bpy


def dependency(block, kind, root):
    raw = block.filepath
    packed = bool(getattr(block, "packed_file", None)) or bool(getattr(block, "packed_files", ()))
    if not raw or raw == "<builtin>" or (kind == "images" and block.source not in ("FILE", "MOVIE", "SEQUENCE", "TILED")):
        return None
    resolved = Path(bpy.path.abspath(raw, library=getattr(block, "library", None))).resolve()
    inside = resolved.is_relative_to(root)
    return {
        "kind": kind, "name": block.name, "path": raw, "packed": packed,
        "relative": raw.startswith("//"), "exists": resolved.exists(),
        "resolved_within_copy": inside,
        "resolved_relative": str(resolved.relative_to(root)) if inside else str(resolved),
        "pass": packed or (raw.startswith("//") and inside and resolved.is_file()),
    }


args = sys.argv[sys.argv.index("--") + 1:]
root, manifest_path, output_path = (Path(x).resolve() for x in args)
manifest = json.loads(manifest_path.read_text())
records = []
for relative in manifest["editable_sources"]:
    path = root / relative
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    deps = []
    for kind in ("images", "libraries", "fonts", "sounds", "movieclips", "volumes", "cache_files"):
        for block in getattr(bpy.data, kind, ()):
            if hasattr(block, "filepath"):
                record = dependency(block, kind, root)
                if record:
                    deps.append(record)
    records.append({
        "source": relative, "dependencies": deps, "objects": len(bpy.data.objects),
        "meshes": len(bpy.data.meshes), "materials": len(bpy.data.materials),
        "external_libraries": len(bpy.data.libraries),
        "camera": bpy.context.scene.camera.name if bpy.context.scene.camera else None,
        "pass": bool(bpy.data.meshes) and all(d["pass"] for d in deps),
    })
    print("PORTABILITY_SOURCE", relative, "PASS" if records[-1]["pass"] else "FAIL", flush=True)
result = {"blender_version": bpy.app.version_string, "read_only": True, "sources": records,
          "pass": all(x["pass"] for x in records)}
output_path.write_text(json.dumps(result, indent=2) + "\n")
