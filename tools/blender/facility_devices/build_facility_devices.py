"""Original meter-scale utility fittings. CPU authoring/export only, never render.

blender --background --factory-startup --threads 2 --python <this file>
Optional: -- --output-root /absolute/isolated/project/root
The generated .blend files remain editable and export without this generator.
Coordinates passed to helpers are Godot Y-up; front is local +Z, wall is Z=0.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument("--output-root", type=Path)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
ROOT = args.output_root or Path(__file__).resolve().parents[3]
OUT = ROOT / "assets/models/facility_devices"
SOURCE = ROOT / "tools/blender/facility_devices/source"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").touch()
MATERIALS = {}
REPORT = {}


def point(v):
    return (v[0], -v[2], v[1])


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 2
    bpy.context.preferences.filepaths.save_version = 0
    MATERIALS.clear()
    for name, color, metallic, roughness in [
        ("Facility_Stainless", (.41, .46, .47, 1), .88, .31),
        ("Facility_SatinSteel", (.24, .29, .30, 1), .78, .44),
        ("Facility_BlueEnamel", (.045, .105, .13, 1), .25, .32),
        ("Facility_Label", (.77, .79, .74, 1), .12, .46),
        ("Facility_Engraving", (.025, .037, .039, 1), .0, .61),
        ("Facility_Gasket", (.018, .021, .022, 1), .0, .82),
    ]:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        mat.diffuse_color = color
        shader = mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = color
        shader.inputs["Metallic"].default_value = metallic
        shader.inputs["Roughness"].default_value = roughness
        MATERIALS[name.removeprefix("Facility_")] = mat


def mesh(name, vertices, faces, material, bevel=0.0, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(v) for v in vertices], [], faces)
    data.update()
    ob = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(MATERIALS[material])
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    if bevel:
        modifier = ob.modifiers.new("Machined edge radius (metres)", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in ob.data.polygons:
        polygon.use_smooth = smooth
    # Every exported vertex has a genuine metric UV. No arbitrary tiled noise.
    uv = ob.data.uv_layers.new(name="UVMap")
    for polygon in ob.data.polygons:
        axis = max(range(3), key=lambda i: abs(polygon.normal[i]))
        axes = [i for i in range(3) if i != axis]
        for loop_index in polygon.loop_indices:
            co = ob.data.vertices[ob.data.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = co[axes[0]], co[axes[1]]
    ob["units"] = "metres"
    ob["authorship"] = "Original project-authored utility fitting, no external mesh or texture"
    ob.select_set(False)
    return ob


def box(name, center, dimensions, material, bevel=.001):
    x, y, z = center
    a, b, c = [v / 2 for v in dimensions]
    vertices = [(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y+b,z-c),(x-a,y+b,z-c),
                (x-a,y-b,z+c),(x+a,y-b,z+c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
    faces = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    return mesh(name, vertices, faces, material, bevel)


def lathe(name, profile, material, segments=48, center=(0,0,0), smooth=True):
    """Closed radial profile around +Z. Actual bore/annulus, not a dark decal."""
    x, y, z = center
    vertices = [(x+r*math.cos(i*math.tau/segments), y+r*math.sin(i*math.tau/segments), z+d)
                for r, d in profile for i in range(segments)]
    faces = []
    for ring in range(len(profile)):
        following = (ring + 1) % len(profile)
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((ring*segments+i, ring*segments+j, following*segments+j, following*segments+i))
    return mesh(name, vertices, faces, material, smooth=smooth)


def screw(name, x, y, z, radius=.005):
    # Six-sided fastener and a real separate dark drive slot. Kept subdued.
    head = lathe(name, [(radius*.8,0),(radius,.001),(radius,.0035),(radius*.8,.004),(.001,.004),(.001,0)],
                 "Stainless", segments=6, center=(x,y,z), smooth=False)
    slot = box(name+"_Drive", (x,y,z+.0041), (radius*1.1,.0011,.00035), "Engraving", .0001)
    return [head, slot]


def lettering(name, text, position, size=.014):
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = text
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = .00018
    curve.resolution_u = 3
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.location = point(position)
    obj.rotation_euler.x = math.pi / 2
    obj.data.materials.append(MATERIALS["Engraving"])
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj["label_text"] = text
    obj["font_source"] = "Blender bundled Bfont"
    obj["units"] = "metres"
    obj.select_set(False)
    return obj


def merge(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.select_set(False)
    return obj


def move_origin(obj, location):
    # Preserve geometry but give the handle an actual, editable stem pivot.
    pivot = Vector(point(location))
    for vert in obj.data.vertices:
        vert.co -= pivot
    obj.location = pivot


def valve():
    reset()
    steel = [
        box("WallMount", (0,0,.006), (.118,.19,.012), "SatinSteel", .004),
        lathe("ValveBody", [(.033,.014),(.036,.019),(.036,.049),(.030,.057),(.009,.057),(.009,.014)], "Stainless"),
        lathe("StemCollar", [(.015,.055),(.018,.059),(.018,.073),(.012,.077),(.006,.077),(.006,.055)], "SatinSteel", 32),
        lathe("Stem", [(.007,.061),(.008,.063),(.008,.096),(.005,.098),(.004,.098),(.004,.061)], "Stainless", 24),
        box("LabelBacking", (0,.145,.007), (.182,.043,.014), "SatinSteel", .002),
    ]
    fasteners = []
    for x,y in [(-.043,-.072),(.043,-.072),(-.043,.072),(.043,.072),(-.077,.145),(.077,.145)]:
        fasteners += screw("MountFastener",x,y,.013,.0043)
    merge("ValveMountAndHousing", steel)
    merge("ValveFasteners", fasteners)
    box("ValveLabel", (0,.145,.0145), (.151,.034,.0015), "Label", .0006)
    lettering("ValveLabelText", "RETURN", (0,.145,.0155), .019)
    # 90-degree manual control: closed horizontal, open vertical. It is not a
    # multi-turn gate valve whose animation would imply unsupported travel.
    handle = [
        lathe("HandleHub", [(.017,.077),(.020,.081),(.020,.091),(.016,.095),(.005,.095),(.005,.077)], "BlueEnamel",32),
        box("HandlePaddle", (.043,0,.087), (.096,.022,.014), "BlueEnamel", .008),
        box("HandleCounterweight", (-.032,0,.087), (.046,.017,.012), "BlueEnamel", .005),
    ]
    handle_obj = merge("ValveHandle", handle)
    move_origin(handle_obj,(0,0,.087))
    handle_obj["pivot_axis_godot"] = "Z"
    handle_obj["closed_angle_radians"] = 0.0
    handle_obj["open_angle_radians"] = math.pi / 2
    handle_obj["purpose"] = "Quarter-turn return control; never detach or grab"
    screw_objects = screw("HandleCap",0,0,.095,.007)
    for obj in screw_objects:
        obj.parent = handle_obj
        obj.matrix_parent_inverse = handle_obj.matrix_world.inverted()
    # Open/closed stops are static and no emissive indicator is used.
    lettering("ValveClosedMark", "0", (.043,-.038,.0125), .010)
    lettering("ValveOpenMark", "1", (0,.070,.0125), .010)
    export("pool_return_valve", "Wall-mounted quarter-turn valve with label and fasteners")


def return_fitting():
    reset()
    lathe("ReturnGasket", [(.050,0),(.052,.001),(.052,.003),(.044,.003),(.044,0)], "Gasket")
    lathe("ReturnFlange", [(.047,.002),(.052,.006),(.052,.011),(.049,.014),(.031,.014),(.028,.009),(.028,.002)], "Stainless",64)
    lathe("ReturnNozzle", [(.028,.006),(.032,.012),(.029,.024),(.023,.032),(.017,.032),(.015,.029),(.015,.004),(.025,.004)], "Stainless",48)
    # The recess is closed 22 mm behind the outlet, not a hole through the room.
    lathe("ReturnRecess", [(.014,.003),(.016,.004),(.016,.010),(.001,.010),(.001,.003)], "Engraving",32)
    fasteners=[]
    for angle in [0,math.pi]:
        fasteners += screw("ReturnFastener",.041*math.cos(angle),.041*math.sin(angle),.012,.0032)
    merge("ReturnFasteners",fasteners)
    export("pool_return_fitting", "105 mm stainless return with genuine recessed 30 mm outlet")


def export(name, description):
    bpy.context.view_layer.update()
    objects=[obj for obj in bpy.context.scene.objects if obj.type=="MESH"]
    # Mesh positions and bounds are recorded from evaluated source objects.
    coords=[obj.matrix_world @ v.co for obj in objects for v in obj.data.vertices]
    godot=[(v.x,v.z,-v.y) for v in coords]
    triangles=sum(sum(len(p.vertices)-2 for p in obj.data.polygons) for obj in objects)
    low=[min(v[i] for v in godot) for i in range(3)]
    high=[max(v[i] for v in godot) for i in range(3)]
    for obj in objects:
        obj["asset_description"]=description
    bpy.context.scene["facility_asset"]=name
    bpy.context.scene["coordinate_contract"]="1 unit = 1 metre. Front local +Z in Godot, wall/back at Z=0. No water, lighting, audio or simulation meshes."
    bpy.context.scene["provenance"]="Original project-authored geometry. Existing owner project license applies; no external mesh, scan, texture or audio."
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:obj.select_set(True)
    blend=SOURCE/(name+".blend")
    glb=OUT/(name+".glb")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),compress=True)
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format="GLB",use_selection=True,
                              export_yup=True,export_apply=True,export_extras=True,
                              export_animations=False,export_cameras=False,export_lights=False,
                              export_texcoords=True,export_normals=True,export_materials="EXPORT")
    REPORT[name]={"description":description,"bounds_min":low,"bounds_max":high,
                  "dimensions":[high[i]-low[i] for i in range(3)],"mesh_objects":len(objects),
                  "triangles":triangles,"bytes":glb.stat().st_size,
                  "glb_sha256":hashlib.sha256(glb.read_bytes()).hexdigest(),
                  "blend_sha256":hashlib.sha256(blend.read_bytes()).hexdigest()}
    print("FACILITY_ASSET",name,json.dumps(REPORT[name],sort_keys=True))


valve()
return_fitting()
manifest={"schema":1,"units":"metres","front":"Godot local +Z","wall_plane":0.0,
          "blender_version":bpy.app.version_string,"assets":REPORT,
          "authorship":"Original project-authored utility fittings; existing project license retained.",
          "limits":"No rendering was performed. No audio, water surface, jet mesh, light, collider, or simulator is embedded in these GLBs. Candidate runtime supplies bounded collision and explicit integration."}
(OUT/"facility_devices_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
print("FACILITY_BUILD_COMPLETE")
