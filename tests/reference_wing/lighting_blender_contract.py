"""Run Blender factory startup without rendering or importing a room.

blender -b --factory-startup --threads 2 --python tests/reference_wing/lighting_blender_contract.py
"""
import importlib.util
import json
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("native_proxy", ROOT / "tools/blender/reference_wing/native_light_proxy.py")
proxy = importlib.util.module_from_spec(spec); spec.loader.exec_module(proxy)
errors = []
checks = 0


def check(condition, detail):
    global checks
    checks += 1
    if not condition: errors.append(detail)


scene = bpy.context.scene
original = {
    "world": scene.world.as_pointer(), "exposure": scene.view_settings.exposure,
    "look": scene.view_settings.look, "camera": list(scene.camera.matrix_world),
    "materials": [(m.name, m.as_pointer()) for m in bpy.data.materials],
    "geometry": [(o.name, len(o.data.vertices), len(o.data.polygons)) for o in scene.objects if o.type == "MESH"],
}
rooms = []
for path in sorted((ROOT / "assets/models/reference_wing").glob("*.geometry.json")):
    data = json.loads(path.read_text())
    report = proxy.apply_native_proxy(scene, data)
    bpy.context.view_layer.update()
    native = [o for o in scene.objects if o.get("reference_native_proxy", False)]
    check(len(native) == len(report["fixtures"]), f"{path.stem}: exactly one proxy per native fixture")
    check(sum(o.data.use_shadow for o in native) <= 4, f"{path.stem}: raster shadow property budget")
    check(all(o.hide_render for o in scene.objects if o.type == "LIGHT" and not o.get("reference_native_proxy", False)), "Every old area/fill light excluded")
    for entry in report["fixtures"]:
        binding = entry["binding"]
        ob = scene.objects["NATIVE_PROXY_" + binding["name"]]
        check(ob.data.type == ("SPOT" if binding["type"] == "spot" else "POINT"), "Supported proxy shape")
        check((ob.location - Vector(proxy.godot_to_blender(binding["position"]))).length < 2e-6, "Position axis convention")
        check(math.isclose(ob.data.energy, binding["energy"] * 100, rel_tol=1e-6), "One fixed diagnostic energy convention")
        check(math.isclose(ob.data.shadow_soft_size, binding["radius"], abs_tol=1e-7), "Native emitter radius")
        check(math.isclose(ob.data.cutoff_distance, binding["range"], rel_tol=1e-6), "Range property")
        raw = next(value for value in data["lights"] if value["name"] == binding["name"])
        if raw.get("color_space", "srgb") == "linear":
            check(all(math.isclose(actual, expected, abs_tol=2e-6) for actual, expected in zip(ob.data.color, raw["color"])), "Native proxy restores actual author-linear hue")
        if ob.data.type == "SPOT":
            actual = ob.matrix_world.to_quaternion() @ Vector((0, 0, -1))
            expected = Vector(proxy.godot_to_blender(binding["direction"]))
            check((actual - expected).length < 2e-6, "Up/down/side spots preserve physical direction")
            check(math.isclose(ob.data.spot_size, math.radians(2 * binding["spot_angle"]), rel_tol=1e-6), "Full versus half cone angle")
    rooms.append({"id": path.stem, "fixtures": len(native), "shadow_properties": sum(o.data.use_shadow for o in native)})
    # Replacing an existing preview is idempotent, not accumulating energy.
    proxy.apply_native_proxy(scene, data)
    check(len([o for o in scene.objects if o.get("reference_native_proxy", False)]) == len(native), "Repeat application has no duplicate lights")
check(original["world"] == scene.world.as_pointer() and original["exposure"] == scene.view_settings.exposure and original["look"] == scene.view_settings.look, "No world/exposure changes")
check(original["camera"] == list(scene.camera.matrix_world), "No camera changes")
check(original["materials"] == [(m.name, m.as_pointer()) for m in bpy.data.materials], "No material/emission changes")
check(original["geometry"] == [(o.name, len(o.data.vertices), len(o.data.polygons)) for o in scene.objects if o.type == "MESH"], "No mesh changes")
result = {"passed": not errors, "checks": checks, "errors": errors, "rooms": rooms, "blender": bpy.app.version_string, "rendered": False, "gpu_run": False, "scope": "Real Blender POINT/SPOT object construction and binding only, not image validation."}
(ROOT / "tests/reference_wing/lighting_blender_report.json").write_text(json.dumps(result, indent=2) + "\n")
print("REFERENCE_LIGHTING_BLENDER", json.dumps(result))
if errors: raise RuntimeError("Native proxy contract failed")
