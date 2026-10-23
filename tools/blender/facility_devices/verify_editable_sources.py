"""Reopen delivered .blend sources and export, without generator or source saves.

No rendering. Run with Blender background / factory startup / two threads.
-- --output-root /empty/scratch/directory
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy

parser=argparse.ArgumentParser()
parser.add_argument("--output-root",type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
ROOT=Path(__file__).resolve().parents[3]
output=args.output_root.resolve()
output.mkdir(parents=True,exist_ok=True)
assert not any(output.iterdir()),"Round-trip destination must be empty"
records={}
for name in ["pool_return_valve","pool_return_fitting"]:
    source=ROOT/"tools/blender/facility_devices/source"/(name+".blend")
    production=ROOT/"assets/models/facility_devices"/(name+".glb")
    before=hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    assert bpy.context.scene.unit_settings.system=="METRIC"
    assert bpy.context.scene.unit_settings.scale_length==1.0
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=="MESH"]
    assert meshes
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:obj.select_set(True)
    target=output/(name+".glb")
    bpy.ops.export_scene.gltf(filepath=str(target),export_format="GLB",use_selection=True,
                             export_yup=True,export_apply=True,export_extras=True,
                             export_animations=False,export_cameras=False,export_lights=False,
                             export_texcoords=True,export_normals=True,export_materials="EXPORT")
    unchanged=before==hashlib.sha256(source.read_bytes()).hexdigest()
    identical=target.read_bytes()==production.read_bytes()
    records[name]={"source_unchanged":unchanged,"glb_byte_identical":identical,
                   "roundtrip_sha256":hashlib.sha256(target.read_bytes()).hexdigest(),
                   "source_sha256":before,"editable_mesh_objects":len(meshes)}
    assert unchanged and identical,records[name]
report={"pass":True,"blender_version":bpy.app.version_string,"generator_executed":False,"rendered":False,"assets":records}
(output/"editable_roundtrip.json").write_text(json.dumps(report,indent=2)+"\n")
print("FACILITY_EDITABLE_ROUNDTRIP",json.dumps(report,sort_keys=True))
