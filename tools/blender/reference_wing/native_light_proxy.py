"""Read-only native POINT/SPOT diagnostic, never an area-preview acceptance image.

blender -b room.blend -t 4 --python tools/blender/reference_wing/native_light_proxy.py -- \
    --geometry assets/models/reference_wing/octagonal_bath.geometry.json \
    --report output/reference_wing/native_bath_lights.json
Add --render output/reference_wing/native_bath.png only with the shared render slot.

The importable apply_native_proxy(scene, geometry, watts_per_energy=100.0) also
works on an unsaved authoring candidate. No .blend, GLB or sidecar is overwritten.
The fixed 100 W/native-energy scale is a diagnostic convention, NOT a physical
unit conversion. Source author-area watts are retained separately in the report.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

SCHEMA = 1
DEFAULT_WATTS_PER_ENERGY = 100.0
MAX_SHADOWS = 4
MAX_VISIBLE = 27


def _clamp(value, low, high):
    return max(low, min(high, value))


def binding(source):
    """Mirror reference_lighting.gd.binding; verified by the lighting contract."""
    raw = source.get("reference_light", source)
    position = list(raw.get("position", source.get("position", [0, 0, 0])))
    direction = list(raw.get("direction", raw.get("emission_direction", [0, 0, 0])))
    if sum(v * v for v in direction) < 1e-12 and "target" in raw:
        direction = [float(t) - float(p) for t, p in zip(raw["target"], position)]
    length = math.sqrt(sum(v * v for v in direction))
    kind = str(raw.get("native_type", "")).lower()
    if not kind:
        kind = "spot" if length > 1e-6 else str(raw.get("type", "omni")).lower()
    if kind not in ("spot", "omni", "point"):
        raise ValueError(f"Explicit native POINT/SPOT type required, got {kind}: {raw.get('name')}")
    if kind == "spot" and length < 1e-6:
        raise ValueError(f"Spot direction missing: {raw.get('name')}")
    energy = max(0, float(raw.get("native_energy", raw.get("energy", float(source.get("power", 1 / .07)) * .07))))
    color_space = str(raw.get("color_space", "srgb")).lower()
    if color_space not in ("srgb", "linear"):
        raise ValueError("Reference light color_space must be linear or srgb")
    color = list(raw.get("color", source.get("color", [1, 1, 1])))
    if color_space == "linear":
        color = [_linear_to_srgb(value) for value in color]
    return {
        "name": str(raw.get("name", "ReferenceFixture")),
        "fixture_object": str(raw.get("fixture_object", source.get("fixture_object", raw.get("name", "")))),
        "type": "spot" if kind == "spot" else "omni",
        "position": position,
        "direction": [v / length for v in direction] if length > 1e-6 else [0, 0, 0],
        "color": color,
        "authored_color_space": color_space,
        "energy": energy,
        "range": _clamp(float(raw.get("range", source.get("range", 6))), 1, 20),
        "radius": _clamp(float(raw.get("emitter_radius", .005)), 0, 1),
        "attenuation": _clamp(float(raw.get("attenuation", 2)), 0, 10),
        "spot_angle": _clamp(float(raw.get("spot_angle_deg", 80)), 1, 89),
        "spot_attenuation": max(.001, float(raw.get("spot_angle_attenuation", .25))),
        "shadow": bool(raw.get("shadow", source.get("shadow", True))),
        "specular": _clamp(float(raw.get("native_specular", 0)), 0, 1),
    }


def godot_to_blender(vector):
    return (float(vector[0]), -float(vector[2]), float(vector[1]))


def blender_to_godot(vector):
    return (float(vector[0]), float(vector[2]), -float(vector[1]))


def _srgb_to_linear(value):
    return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4


def _linear_to_srgb(value):
    return value * 12.92 if value < .0031308 else 1.055 * value ** (1 / 2.4) - .055


def apply_native_proxy(scene, geometry, watts_per_energy=DEFAULT_WATTS_PER_ENERGY):
    import bpy
    from mathutils import Vector

    if not math.isfinite(watts_per_energy) or watts_per_energy <= 0:
        raise ValueError("Diagnostic scale must be finite and positive")
    # Hide authored AREA/POINT fill, including the explicitly preview-only fills.
    # Keep emissive mesh material graphs, geometry, world and exposure untouched.
    hidden = []
    for ob in list(scene.objects):
        if ob.type == "LIGHT":
            if ob.get("reference_native_proxy", False):
                bpy.data.objects.remove(ob, do_unlink=True)
            else:
                hidden.append(ob.name)
                ob.hide_render = True
    raw_sources = [value for value in geometry.get("lights", []) if value.get("runtime_enabled", True)]
    if len(raw_sources) > MAX_VISIBLE:
        raise ValueError("One-room proxy exceeds the native visibility budget")
    camera = scene.camera
    if camera is None:
        raise ValueError("Use an authored camera before creating native proxies")
    specs = [binding(value) for value in raw_sources]

    # Match the raster property budget of one active room. PT always traces a
    # visibility ray for each sampled native light in the pinned target engine.
    shadowed = set()
    # Active-room order is authored and stable, not camera-dependent.
    for index in range(len(specs)):
        if len(shadowed) < MAX_SHADOWS and specs[index]["shadow"]:
            shadowed.add(index)
    reports = []
    for index, (raw, spec) in enumerate(zip(raw_sources, specs)):
        kind = "SPOT" if spec["type"] == "spot" else "POINT"
        name = "NATIVE_PROXY_" + spec["name"]
        data = bpy.data.lights.new(name, kind)
        data.energy = spec["energy"] * watts_per_energy
        # Native Light3D color is sRGB; Blender's light color is scene-linear.
        data.color = tuple(_srgb_to_linear(v) for v in spec["color"])
        data.shadow_soft_size = spec["radius"]
        data.use_shadow = index in shadowed
        data.specular_factor = spec["specular"]
        data.use_custom_distance = True
        data.cutoff_distance = spec["range"]
        if kind == "SPOT":
            # Blender uses full cone diameter, Godot uses half-angle.
            data.spot_size = math.radians(spec["spot_angle"] * 2)
            # This is a proxy only: Blender's blend curve is not the native
            # power-law cone attenuation. Never claim pixel/flux equivalence.
            data.spot_blend = _clamp(spec["spot_attenuation"], 0, 1)
        ob = bpy.data.objects.new(name, data)
        ob["reference_native_proxy"] = True
        scene.collection.objects.link(ob)
        ob.location = godot_to_blender(spec["position"])
        if kind == "SPOT":
            direction = Vector(godot_to_blender(spec["direction"]))
            ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        reports.append({
            "binding": spec, "blender_type": kind, "blender_position": list(ob.location),
            "blender_forward": list(ob.rotation_euler.to_quaternion() @ Vector((0, 0, -1))),
            "blender_color_linear": list(data.color), "diagnostic_watts": data.energy,
            "author_area_watts": raw.get("preview_area_watts", raw.get("source_watts", raw.get("power_watts"))),
            "native_energy_was_explicit": "native_energy" in raw or "energy" in raw,
            "native_energy_is_provisional": bool(raw.get("native_energy_provisional", "native_energy" not in raw and "energy" not in raw)),
            "raster_shadow_property": bool(data.use_shadow),
        })
    return {
        "schema": SCHEMA, "fixture_count": len(reports), "hidden_author_lights": hidden,
        "diagnostic_watts_per_native_energy": watts_per_energy, "fixtures": reports,
        "energy_convention": "One fixed diagnostic scale only; Blender Watts are not equivalent to Godot light_energy.",
        "limitations": [
            "Blender POINT/SPOT geometry and cone direction only, not a Godot or NVIDIA screenshot.",
            "Blender cone blend, inverse-square normalization, range falloff, tone mapping and indirect transport differ.",
            "Cycles can ignore viewport-only range/specular controls; verify native range and glints in Godot.",
            "Four shadow-enabled proxy properties model the raster budget, not target PT visibility-ray cost.",
            "The target PT always tests sampled light visibility; emitter meshes contribute hit/bounce radiance, not area-light NEE.",
            "Original source liquid/droplet/photon transport remains a point-input approximation without spot cones.",
        ],
        "changed": ["In-memory author lights hidden", "One native-shaped proxy per enabled fixture"],
        "unchanged": ["Source .blend/GLB/JSON on disk", "Geometry", "Materials and mesh emission", "World", "Exposure", "Water"],
    }


def main():
    import bpy
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--geometry", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--render", type=Path)
    parser.add_argument("--samples", type=int, default=24)
    parser.add_argument("--resolution", type=int, default=512)
    parser.add_argument("--watts-per-energy", type=float, default=DEFAULT_WATTS_PER_ENERGY)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    scene = bpy.context.scene
    report = apply_native_proxy(scene, json.loads(args.geometry.read_text()), args.watts_per_energy)
    report["geometry_contract"] = str(args.geometry)
    report["geometry_sha256"] = hashlib.sha256(args.geometry.read_bytes()).hexdigest()
    report["source_blend"] = bpy.data.filepath
    if bpy.data.filepath:
        report["source_blend_sha256"] = hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()
    report["rendered"] = bool(args.render)
    if args.render:
        args.render.parent.mkdir(parents=True, exist_ok=True)
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = args.samples
        scene.cycles.use_denoising = False
        scene.render.threads_mode = "FIXED"
        scene.render.threads = 4
        aspect = scene.render.resolution_y / scene.render.resolution_x
        scene.render.resolution_x = args.resolution
        scene.render.resolution_y = round(args.resolution * aspect)
        scene.render.resolution_percentage = 100
        scene.render.filepath = str(args.render.resolve())
        scene.render.use_stamp = True
        scene.render.use_stamp_note = True
        scene.render.stamp_note_text = "BLENDER POINT/SPOT PROXY | NOT GODOT/NVIDIA | ENERGY SCALE NOT PHOTOMETRIC"
        bpy.ops.render.render(write_still=True)
        report["render_path"] = str(args.render)
        report["samples"] = args.samples
        report["resolution"] = [scene.render.resolution_x, scene.render.resolution_y]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print("REFERENCE_NATIVE_PROXY", json.dumps({"fixtures": report["fixture_count"], "rendered": report["rendered"], "report": str(args.report)}))


if __name__ == "__main__":
    main()
