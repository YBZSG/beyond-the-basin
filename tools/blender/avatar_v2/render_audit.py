"""Bounded Cycles CPU studio evidence. Not gameplay/performance evidence."""
import bpy,bmesh,json,math,sys
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=HERE/'audit/renders';OUT.mkdir(parents=True,exist_ok=True)
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
which=args[0] if args else 'all'
def setup(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));s=bpy.context.scene
 s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=20;s.cycles.use_denoising=False
 s.render.resolution_x=600;s.render.resolution_y=800;s.render.resolution_percentage=100
 s.render.image_settings.file_format='PNG';s.view_settings.view_transform='AgX'
 s.world.use_nodes=True;bg=s.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.25,.29,.32,1);bg.inputs['Strength'].default_value=.65
 for o in list(bpy.data.objects):
  if o.type in ['LIGHT','CAMERA']:bpy.data.objects.remove(o,do_unlink=True)
 for name,loc,power,size in [('Key',(1.5,2.5,2.8),150,2.0),('Fill',(-1,1,1.6),90,2),('Rim',(1,-2,1.5),180,1.5)]:
  data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
  o=bpy.data.objects.new(name,data);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((.4,0,.90))-o.location).to_track_quat('-Z','Y').to_euler()
 data=bpy.data.cameras.new('Audit camera');c=bpy.data.objects.new('Audit camera',data);s.collection.objects.link(c);s.camera=c;data.type='ORTHO'
 r=bpy.data.objects['ExplorerRig'];r.animation_data.action=None
 for p in r.pose.bones:p.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update()
 return s,r,c

def shoot(s,c,label,loc,target,scale,up='Y',horizontal=600,vertical=800):
 c.location=loc;c.rotation_euler=(Vector(target)-c.location).to_track_quat('-Z',up).to_euler();c.data.ortho_scale=scale
 s.render.resolution_x=horizontal;s.render.resolution_y=vertical;s.render.filepath=str(OUT/(label+'.png'));bpy.ops.render.render(write_still=True)

for candidate,path in [('baseline',HERE/'pool_explorer_original_seed.blend'),('v2',HERE/'pool_explorer_v2.blend')]:
 if which not in ['all',candidate]:continue
 s,r,c=setup(path)
 W=r.data.bones['Hand_L'].head_local;K=r.data.bones['Middle1_L'].head_local;L=(K-W).normalized();D=Vector((1,0,0));D=(D-L*D.dot(L)).normalized();R=D.cross(L).normalized()
 center=W+L*.075
 # Isolate the actual left-arm mesh for unobstructed anatomy review. This is
 # only a render copy; original source and exported mesh remain untouched.
 original=bpy.data.objects['Body_Explorer'];arm=original.copy();arm.data=original.data.copy();s.collection.objects.link(arm)
 bm=bmesh.new();bm.from_mesh(arm.data)
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if not(v.co.x>.27 and v.co.z<1.18)],context='VERTS')
 bm.to_mesh(arm.data);bm.free();original.hide_render=True;bpy.data.objects['Head_Explorer'].hide_render=True
 shoot(s,c,candidate+'_hand_dorsal',center+D*.70+R*.07,center,.265)
 shoot(s,c,candidate+'_hand_palm',center-D*.70+R*.10,center,.265)
 if candidate=='v2':
  library=json.loads((ROOT/'assets/models/avatar_v2/grip_poses.json').read_text())
  for pose in ['relaxed','carry_large','cupped_grip']:
   for p in r.pose.bones:p.matrix_basis=Matrix.Identity(4)
   for name,row in library['poses'][pose].items():
    p=r.pose.bones[name];p.rotation_mode='QUATERNION';p.rotation_quaternion=Quaternion(row['quaternion_wxyz'])
   bpy.context.view_layer.update()
   shoot(s,c,'v2_'+pose,center+D*.65+R*.45,center,.265)
  for p in r.pose.bones:p.matrix_basis=Matrix.Identity(4)
  arm.hide_render=True;original.hide_render=False;bpy.data.objects['Head_Explorer'].hide_render=False
  shoot(s,c,'v2_full_front',(0,4,1.02),(0,0,.87),1.96,horizontal=700,vertical=1000)
  shoot(s,c,'v2_full_three_quarter',(2.5,4,1.7),(0,0,.87),1.96,horizontal=700,vertical=1000)
  r.animation_data.action=bpy.data.actions['Hold'];s.frame_set(0);bpy.context.view_layer.update()
  # Authored clip view only, NOT the runtime object's hand IK.
  shoot(s,c,'v2_hold_clip',(1.8,3.2,1.4),(0,.25,1.10),1.25,horizontal=900,vertical=700)
