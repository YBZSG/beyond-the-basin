"""Original supplemental actions on the shipped 54-joint skin. No geometry edits.
Blender 4.3+: blender -b -t 2 --python tools/blender/handmade_motion/author_handmade_motion.py
Creates editable source and GLB, preserving the existing character/physics assets.
"""
import bpy, math, json, hashlib
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/character_refinement/handmade_motion'; OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'assets/character_refinement/natural_hand_finish/explorer_natural_hand.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
scene=bpy.context.scene; rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
scene.render.fps=60; bpy.context.preferences.filepaths.save_version=0
rig.animation_data_create()
for tr in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(tr)
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}; bones={b.name:(b.head_local.copy(),b.tail_local.copy()) for b in rig.data.bones}
upper=[n for n in bones if n not in ['Root','Hips'] and not any(n.startswith(x) for x in ['UpperLeg','LowerLeg','Foot','Toe'])]
# Imported source actions were authored at 24 FPS. Frame zero is independent of rate.
def capture(name):
 rig.animation_data.action=bpy.data.actions[name+'_ExplorerRig'];scene.frame_set(0);bpy.context.view_layer.update()
 return {n:rig.pose.bones[n].rotation_quaternion.copy() for n in bones}
idle=capture('Idle');hold=capture('Hold')
rig.animation_data.action=None
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
contract=json.loads((ROOT/'assets/character_refinement/natural_hand_finish/model_contract.json').read_text())
poses=contract['poses']
def smooth(t):
 t=max(0,min(1,t));return t*t*t*(10+t*(-15+6*t))
def reset():
 for p in rig.pose.bones:
  p.location=(0,0,0);p.scale=(1,1,1);p.rotation_mode='QUATERNION';p.rotation_quaternion=idle[p.name]
def global_pose(n):
 p=rig.pose.bones[n]
 return (global_pose(p.parent.name)@rest[p.parent.name].inverted()@rest[n] if p.parent else rest[n])@p.matrix_basis
def rotate(n,xyz):
 b=rest[n].to_quaternion();q=Quaternion((1,0,0),xyz[0])@Quaternion((0,1,0),xyz[1])@Quaternion((0,0,1),xyz[2]);rig.pose.bones[n].rotation_quaternion=b.inverted()@q@b

def two_bone(side,target):
 un='UpperArm_'+side;ln='Forearm_'+side
 parent=global_pose(rig.pose.bones[un].parent.name);hip=parent@rest[rig.pose.bones[un].parent.name].inverted()@bones[un][0]
 a=(bones[un][1]-bones[un][0]).length;b=(bones[ln][1]-bones[ln][0]).length
 d=target-hip;reach=min(a+b-.008,max(abs(a-b)+.008,d.length));v=d.normalized();sg=1 if side=='L' else -1
 pole=Vector((sg*.65,.35,-.6));pole=(pole-v*pole.dot(v)).normalized();along=(a*a-b*b+reach*reach)/(2*reach)
 joint=hip+v*along+pole*math.sqrt(max(0,a*a-along*along));end=hip+v*reach
 for n,h,t in [(un,hip,joint),(ln,joint,end)]:
  q=(bones[n][1]-bones[n][0]).rotation_difference(t-h)
  desired=Matrix.Translation(h)@q.to_matrix().to_4x4()@rest[n].to_3x3().to_4x4()
  p=rig.pose.bones[n];inherit=global_pose(p.parent.name)@rest[p.parent.name].inverted()@rest[n]
  p.rotation_quaternion=(inherit.inverted()@desired).to_quaternion()
 return (end-target).length

def hand_frame(side,weight):
 cfg=contract['hand_contact'][side];sg=1 if side=='L' else -1
 def frame(long,normal):
  y=Vector(long).normalized();z=Vector(normal);z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized()
  return Matrix((x,y,z)).transposed()
 desired=frame((0,1,0),(-sg,0,0))@frame(cfg['long_local_godot'],cfg['inward_local_godot']).inverted()
 n='Hand_'+side;p=rig.pose.bones[n];inherit=global_pose(p.parent.name)@rest[p.parent.name].inverted()@rest[n]
 q=(inherit.to_3x3().inverted()@desired).to_quaternion()
 p.rotation_quaternion=p.rotation_quaternion.slerp(q,weight)

def fingers(a,b,w):
 for n,cfg in poses[a].items():
  if n in rig.pose.bones:
   rig.pose.bones[n].rotation_quaternion=Quaternion(cfg['quaternion_wxyz']).slerp(Quaternion(poses[b][n]['quaternion_wxyz']),w)

def pose(kind,t):
 reset();phase=t*math.tau
 if kind=='WadeRest':
  # Planted lower body stays owned by locomotion/foot placement. Upper limbs
  # balance softly at rest rather than snapping into the dry arms-down pose.
  rotate('Spine',(-.025,.008*math.sin(phase),.008*math.sin(phase)))
  rotate('Chest',(.012,-.008*math.sin(phase),-.010*math.sin(phase)))
  for side,sg in [('L',1),('R',-1)]:
   rotate('Shoulder_'+side,(.010*math.sin(phase+sg*.3),0,sg*.012))
   rotate('UpperArm_'+side,(-.075+.02*math.sin(phase+sg*.4),sg*.18,0))
   rotate('Forearm_'+side,(.30+.025*math.sin(phase+sg*.55),0,0))
   rotate('Hand_'+side,(-.035+.02*math.sin(phase+sg*.8),0,sg*.015))
  fingers('relaxed','swim',.2+.07*math.sin(phase))
 elif kind=='Pickup':
  # Reach then draw toward the chest. Contact IK determines the true prop
  # position; this upper-body gesture never teleports or delays the prop.
  lift=smooth(t/.62);settle=smooth((t-.62)/.38)
  for side,sg in [('L',1),('R',-1)]:
   start=bones['Hand_'+side][0];reach=Vector((sg*.22,.355,1.13));finish=Vector((sg*.19,.30,1.23))
   target=start.lerp(reach,lift).lerp(finish,settle)
   two_bone(side,target)
   hand_frame(side,lift)
   rotate('Shoulder_'+side,(.025*math.sin(math.pi*t),0,sg*.014*math.sin(math.pi*t)))
  rotate('Spine',(-.025*math.sin(math.pi*t),0,0));rotate('Chest',(-.035*math.sin(math.pi*t),0,0))
  fingers('release','carry',smooth((t-.30)/.62))
 else:
  # Drop/open hands, then ease back to idle. Physical release stays immediate.
  lower=smooth(t/.48);recover=smooth((t-.48)/.52)
  for side,sg in [('L',1),('R',-1)]:
   target=Vector((sg*.19,.30,1.23)).lerp(Vector((sg*.28,.26,1.02)),lower)
   two_bone(side,target)
   hand_frame(side,1.0)
   for n in ['Shoulder_','UpperArm_','Forearm_','Hand_']:
    name=n+side;rig.pose.bones[name].rotation_quaternion=rig.pose.bones[name].rotation_quaternion.slerp(idle[name],recover)
  fingers('carry','release',smooth(t/.25))
  if t>.45:
   fingers('release','relaxed',smooth((t-.45)/.55))
 for side in ['L','R']:
  rig.pose.bones['WristSupport_'+side].rotation_quaternion=Quaternion().slerp(rig.pose.bones['Hand_'+side].rotation_quaternion,.5)

report={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'rig_bones':len(bones),'policy':'Original Blender-authored upper-body rotations only; no physics or root-motion tracks. Existing 14 locomotion/action clips unchanged.','clips':{}}
for kind,seconds,loop in [('Pickup',.48,False),('SetDown',.46,False),('WadeRest',2.8,True)]:
 frames=round(seconds*60);action=bpy.data.actions.new(kind);action.use_fake_user=True;rig.animation_data.action=action
 samples=[]
 for frame in range(frames+1):
  scene.frame_set(frame);pose(kind,frame/frames);bpy.context.view_layer.update()
  row={}
  for n in upper:
   p=rig.pose.bones[n];p.keyframe_insert('rotation_quaternion',frame=frame,group=n);row[n]=list(p.rotation_quaternion)
  samples.append(row)
 for fc in action.fcurves:
  for k in fc.keyframe_points:k.interpolation='LINEAR'
 action['duration_seconds']=frames/60;action['loop']=loop
 if kind=='Pickup':action.pose_markers.new('REACH').frame=round(frames*.62)
 if kind=='SetDown':action.pose_markers.new('PHYSICS_ALREADY_RELEASED').frame=0
 seam=max(Quaternion(samples[0][n]).rotation_difference(Quaternion(samples[-1][n])).angle for n in upper)
 # Normalize shortest-arc comparison for quaternions with opposite signs.
 seam=min(seam,math.tau-seam)
 if loop:assert seam<1e-4,(kind,seam)
 report['clips'][kind]={'duration_seconds':frames/60,'rotation_bones':len(upper),'keys_per_bone':frames+1,'loop':loop,'loop_seam_radians':seam,'source_keyframes':len(action.fcurves)*(frames+1)}
 rig.animation_data.action=None
 track=rig.animation_data.nla_tracks.new();track.name=kind;strip=track.strips.new(kind,0,action);strip.name=kind
# Editable scene retains source mesh, skin and textures for pose review.
for tr in rig.animation_data.nla_tracks:tr.mute=True
rig.animation_data.action=bpy.data.actions['Pickup'];scene.frame_set(18)
scene.frame_start=0;scene.frame_end=29
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'tools/blender/handmade_motion/explorer_handmade_motion.blend'))
rig.animation_data.action=None
for tr in rig.animation_data.nla_tracks:tr.mute=False
bpy.ops.export_scene.gltf(filepath=str(OUT/'explorer_handmade_motion.glb'),export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_force_sampling=True,export_def_bones=False,export_yup=True,export_cameras=False,export_lights=False)
(OUT/'authoring_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('HANDMADE_MOTION_OK',report['clips'])
