import bpy,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3];OUT=ROOT/'tests/handmade_motion/previews';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/blender/handmade_motion/explorer_handmade_motion.blend'))
s=bpy.context.scene;r=next(o for o in bpy.data.objects if o.type=='ARMATURE')
for tr in r.animation_data.nla_tracks:tr.mute=True
s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=32;s.cycles.use_denoising=False
s.render.resolution_x=640;s.render.resolution_y=640;s.render.resolution_percentage=100
s.world=bpy.data.worlds.new('Preview world');s.world.color=(.18,.18,.18)
s.view_settings.view_transform='AgX'
def aim(ob,target):ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2.4,3.8,1.95));cam=bpy.context.object;aim(cam,(0,.04,1.05));cam.data.lens=60;s.camera=cam
for loc,power,size in [((1.2,2.4,3.1),450,2.4),((-2,1,2),250,2),((0,-2,2.8),400,2)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,1))
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));floor=bpy.context.object
mat=bpy.data.materials.new('Neutral preview floor');mat.diffuse_color=(.18,.21,.22,1);floor.data.materials.append(mat)
s.render.use_stamp=True;s.render.use_stamp_note=True;s.render.stamp_note_text='BLENDER POSE REVIEW - NOT GODOT GAMEPLAY'
for attr in ['use_stamp_date','use_stamp_time','use_stamp_render_time','use_stamp_frame','use_stamp_frame_range','use_stamp_memory','use_stamp_hostname','use_stamp_camera','use_stamp_lens','use_stamp_scene','use_stamp_marker','use_stamp_filename']:
 if hasattr(s.render,attr):setattr(s.render,attr,False)
for name,frame in [('Pickup',18),('SetDown',12),('WadeRest',42)]:
 r.animation_data.action=bpy.data.actions[name];s.frame_set(frame);s.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
