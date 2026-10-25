"""One bounded near-wall CPU material shot. No variant, filter, or saved changes."""
import bpy,os,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4];QA=ROOT/'output/reference_wing/stair';C=json.load(open(ROOT/'assets/models/reference_wing/stair_gallery.geometry.json'));view=C['diagnostic_views'][0]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/C['editable_source']));s=bpy.context.scene;s.camera=bpy.data.objects[view['camera_name']]
s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.use_denoising=False;s.cycles.samples=256;s.cycles.seed=5074;s.cycles.use_adaptive_sampling=False
s.render.resolution_x=640;s.render.resolution_y=640;s.render.resolution_percentage=100;s.render.use_border=False;s.render.use_crop_to_border=False
s.render.stamp_note_text='CPU DIAGNOSTIC | 10cm TILE GRID | NO OPTIONAL FILTER | NOT GODOT/NVIDIA';s.render.stamp_font_size=11
s.render.filepath=str(QA/'stair_nearwall_diagnostic.png');bpy.ops.render.render(write_still=True)
view=json.load(open(ROOT/'assets/models/reference_wing/stair_gallery.geometry.json'))['diagnostic_views'][0]
json.dump({'image':'stair_nearwall_diagnostic.png','camera':view,'samples':256,'renderer':'Blender4.3.2 Cycles CPU','denoising':False,'display_transform':s.view_settings.view_transform,'preview_exposure_unchanged':s.view_settings.exposure,'new_lights':False,'changed_materials':False,'runtime_glb_unchanged':True,'reference_camera_and_normal_spawn_unchanged':True,'native_godot_or_nvidia_validation':False},open(QA/'stair_nearwall_diagnostic_metadata.json','w'),indent=2)
