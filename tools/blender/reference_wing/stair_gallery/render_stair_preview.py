"""Render only the saved, shared-glaze source. CPU Cycles, no display required."""
import bpy,os,json
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'))
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend'))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.use_denoising=False
scene.cycles.samples=96;scene.render.use_border=False;scene.render.use_crop_to_border=False
scene.render.stamp_note_text='CPU CYCLES | DRY FLOOR / LEAF REVISION | SHARED GLAZE CANDIDATE | NOT GODOT / NVIDIA'
scene.render.filepath=os.path.join(ROOT,'output/reference_wing/stair/stair_cycles_square_preview.png')
bpy.ops.render.render(write_still=True)

contract=json.load(open(os.path.join(ROOT,'assets/models/reference_wing/stair_gallery.geometry.json')))
json.dump({'image':'stair_cycles_square_preview.png','revision':'square-framing-correction-preserved-vertical-field','source':contract['editable_source'],'glb_sha256':contract['glb_sha256'],'renderer':'Blender 4.3.2 Cycles CPU','samples':scene.cycles.samples,'denoising':False,'resolution':[scene.render.resolution_x,scene.render.resolution_y],'camera':contract['recommended_views'][0],'wall_material':{'role':'ref_tile_pearl_ref5_crown','face_roughness':.075,'profile':'reviewed C2 localized crown','crown_metres':.00030,'radius_metres':.04},'ceiling_base_pearl_shape_strength':1,'dry_floor_roughness':.26,'local_ceiling_area_watts':24,'local_lens_emission_strength':2,'preview_exposure':scene.view_settings.exposure,'user_runtime_exposure_changed':False,'visual_acceptance':False,'limits':'CPU composition/material evidence only. Not Godot, Windows/NVIDIA, performance or CharacterBody3D walking validation.'},open(os.path.join(ROOT,'output/reference_wing/stair/stair_final_square_metadata.json'),'w'),indent=2)
