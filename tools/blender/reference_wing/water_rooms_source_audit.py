"""Reopen every editable source and validate images and proxy representation."""
import bpy,os,json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];out=[]
for n in ['colonnade','cyan_corridor','octagonal_bath']:
 p=ROOT/'tools/blender/reference_wing/water_sources'/f'{n}.blend';bpy.ops.wm.open_mainfile(filepath=str(p));missing=[]
 for im in bpy.data.images:
  if im.source=='FILE' and not im.packed_file and not os.path.exists(bpy.path.abspath(im.filepath)):missing.append(im.filepath)
 runtime=bpy.data.collections.get('RUNTIME_ARCHITECTURE');preview=bpy.data.collections.get('PREVIEW_ONLY_NOT_EXPORTED')
 scene=bpy.context.scene;matrix=scene.camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=scene.render.resolution_x,y=scene.render.resolution_y,scale_x=scene.render.pixel_aspect_x,scale_y=scene.render.pixel_aspect_y)
 rec={'vertical_fov_degrees':math.degrees(2*math.atan(1/matrix[1][1])),'resolution':[scene.render.resolution_x,scene.render.resolution_y],'room':n,'editable_source_exists':p.exists(),'runtime_collection_objects':len(runtime.objects)if runtime else 0,'preview_collection_objects':len(preview.objects)if preview else 0,'missing_images':missing,'camera':bpy.context.scene.camera.name if bpy.context.scene.camera else None,'render_engine':bpy.context.scene.render.engine,'cycles_device':bpy.context.scene.cycles.device,'metric_scale':bpy.context.scene.unit_settings.scale_length,'status':'PASS'if not missing and runtime and preview and len(preview.objects)>0 and len(runtime.objects)>100 else'FAIL'};out.append(rec)
(ROOT/'output/reference_wing/water_rooms/source_reopen_audit.json').write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2));assert all(r['status']=='PASS'for r in out)
