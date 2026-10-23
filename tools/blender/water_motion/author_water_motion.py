"""Editable animation authoring on the existing Explorer rig; CPU-only, no render.

Run with Blender 4.3.2:
  blender -b -t 2 --python tools/blender/water_motion/author_water_motion.py -- \
    --source-blend tools/blender/water_hands/pool_explorer_water_hands.blend \
    --base-glb assets/water_hands/pool_explorer_water_hands.glb --draft
Final source/GLB can instead be the compatible hand-rig revision. This does not
re-export geometry: only new animation arrays are appended to the baseline GLB.
The preserved Idle/Walk/Run/Hold/Climb records and binary data are byte-identical.
"""
from pathlib import Path
import argparse, copy, hashlib, json, math, sys
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]; OUT=ROOT/'assets/water_motion'
sys.path.insert(0,str(HERE))
from glb_io import GLB
args=argparse.ArgumentParser()
args.add_argument('--source-blend',default='tools/blender/water_hands/pool_explorer_water_hands.blend')
args.add_argument('--base-glb',default='assets/water_hands/pool_explorer_water_hands.glb')
args.add_argument('--draft',action='store_true')
args.add_argument('--no-save',action='store_true')
args=args.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
FPS=120
CLIPS={
 'Wade':dict(frames=168,loop=True,cycle_distance_m=1.05,stance_fraction=.62),
 'Swim':dict(frames=288,loop=True),
 'SwimIdle':dict(frames=264,loop=True),
 'JumpRise':dict(frames=30,loop=False),
 'JumpAir':dict(frames=72,loop=True),
 'Land':dict(frames=36,loop=False),
 'ThrowCharge':dict(frames=54,loop=False,upper_body_only=True),
 'ThrowRelease':dict(frames=30,loop=False,upper_body_only=True,release_seconds=0.0,release_frame=0),
 'ThrowRecover':dict(frames=42,loop=False,upper_body_only=True),
}
PRESERVED=['Idle','Walk','Run','Hold','Climb']
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/args.source_blend))
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;scene.render.fps=FPS;scene.render.fps_base=1
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
rig.animation_data_create();rig.animation_data.action=None
for track in rig.animation_data.nla_tracks: track.mute=True
bones={b.name:(b.head_local.copy(),b.tail_local.copy()) for b in rig.data.bones}
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
assert all(n in bones for n in ['Root','Hips','Spine','Chest','Hand_L','Hand_R','Foot_L','Foot_R'])
base=GLB(ROOT/args.base_glb)
base_raw=base.raw;base_binary=base.bin;base_json=copy.deepcopy(base.j)
node_ids={n['name']:i for i,n in enumerate(base.j['nodes']) if n.get('name')}
assert all(n in node_ids for n in bones), 'Editable rig contains bones missing from GLB'
C=Matrix.Rotation(-math.pi/2,4,'X')
# Existing exporter leaves bone-local coordinate systems unchanged. Only the
# root receives Blender Z-up -> glTF Y-up. Reject a mismatching rest skeleton.
rest_errors={}
for n,b in rig.data.bones.items():
 local=rest[b.parent.name].inverted()@rest[n] if b.parent else C@rest[n]
 nd=base.j['nodes'][node_ids[n]]
 q=nd.get('rotation',[0,0,0,1]);expected=Matrix.LocRotScale(Vector(nd.get('translation',[0,0,0])),Quaternion((q[3],q[0],q[1],q[2])),Vector(nd.get('scale',[1,1,1])))
 rest_errors[n]=max(abs(local[r][c]-expected[r][c]) for r in range(4) for c in range(4))
assert max(rest_errors.values())<2e-5, ('Source/GLB rest mismatch',max(rest_errors.items(),key=lambda p:p[1]))

def curve_hash(action):
 rows=[]
 for fc in action.fcurves:
  rows.append((fc.data_path,fc.array_index,[(list(k.co),k.interpolation,list(k.handle_left),list(k.handle_right)) for k in fc.keyframe_points]))
 return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()
old_curve_hash={n:curve_hash(bpy.data.actions[n]) for n in PRESERVED}
# Natural hand poses use anatomical flexion, not arbitrary local XYZ axes.
hand_pose_path=ROOT/'assets/water_hands/hand_pose_contract.json'
hand_pose_contract=json.loads(hand_pose_path.read_text()) if hand_pose_path.exists() and 'Index3_L' in bones else {}
hand_manifest=hand_pose_contract.get('hand_geometry') or json.loads((ROOT/'assets/models/avatar_v2/avatar_v2_manifest.json').read_text())['hand_geometry']
extra_contract_path=ROOT/'assets/water_hands/animation_contract.json'
extra_contract=json.loads(extra_contract_path.read_text()) if extra_contract_path.exists() else {}
hand_poses=hand_pose_contract.get('poses',{})


def ease(x):
 x=max(0.,min(1.,x));return x*x*(3-2*x)
def smoother(x):
 x=max(0.,min(1.,x));return x*x*x*(10+x*(-15+6*x))
def lerp(a,b,t):return a+(b-a)*t

def knots(t,points):
 for (a,av),(b,bv) in zip(points,points[1:]):
  if t<=b:
   u=ease((t-a)/(b-a));return np.asarray(av)*(1-u)+np.asarray(bv)*u
 return np.asarray(points[-1][1])

def reset():
 for pb in rig.pose.bones:
  pb.location=(0,0,0);pb.rotation_mode='QUATERNION';pb.rotation_quaternion=(1,0,0,0);pb.scale=(1,1,1)

def rot(name,angles):
 if name not in rig.pose.bones:return
 basis=rest[name].to_3x3().normalized().to_quaternion()
 q=Quaternion((1,0,0),float(angles[0]))@Quaternion((0,1,0),float(angles[1]))@Quaternion((0,0,1),float(angles[2]))
 rig.pose.bones[name].rotation_quaternion=basis.inverted()@q@basis

def shift_hips(delta):
 rig.pose.bones['Hips'].location=rest['Hips'].to_3x3().inverted()@Vector(delta)

def global_pose(name):
 pb=rig.pose.bones[name]
 return (global_pose(pb.parent.name)@rest[pb.parent.name].inverted()@rest[name] if pb.parent else rest[name])@pb.matrix_basis

def desired(name,head,tail):
 q=(bones[name][1]-bones[name][0]).rotation_difference(tail-head)
 return Matrix.Translation(head)@q.to_matrix().to_4x4()@rest[name].to_3x3().to_4x4()

def assign(name,matrix,parent):
 pb=rig.pose.bones[name]
 inherit=parent@rest[pb.parent.name].inverted()@rest[name] if pb.parent else rest[name]
 pb.rotation_quaternion=(inherit.inverted()@matrix).to_quaternion();pb.location=(0,0,0)
 return matrix

ik_records=[]
def two_bone(upper,lower,target,pole):
 parent=global_pose(rig.pose.bones[upper].parent.name)
 hip=parent@rest[rig.pose.bones[upper].parent.name].inverted()@bones[upper][0]
 a=(bones[upper][1]-bones[upper][0]).length;b=(bones[lower][1]-bones[lower][0]).length
 delta=target-hip;raw=delta.length;reach=min(a+b-.00002,max(abs(a-b)+.00002,raw));direction=delta.normalized()
 bend=(pole-direction*pole.dot(direction)).normalized()
 along=(a*a-b*b+reach*reach)/(2*reach)
 joint=hip+direction*along+bend*math.sqrt(max(0,a*a-along*along));end=hip+direction*reach
 um=assign(upper,desired(upper,hip,joint),parent)
 lm=assign(lower,desired(lower,joint,end),um)
 flex=math.pi-math.acos(max(-1,min(1,(a*a+b*b-reach*reach)/(2*a*b))))
 ik_records.append(dict(upper=upper,target_error=(end-target).length,reach_margin=a+b-raw,flex=flex))
 return lm,end

def leg(side,target,q):
 lm,end=two_bone('UpperLeg_'+side,'LowerLeg_'+side,target,Vector((0,1,0)))
 fm=Matrix.Translation(end)@q.to_matrix().to_4x4()@rest['Foot_'+side].to_3x3().to_4x4()
 assign('Foot_'+side,fm,lm)

def arm(side,anatomical_target,pole=(0,.8,-.15),hip_relative=False):
 if hip_relative:
  transform=global_pose('Hips')@rest['Hips'].inverted()
  target=transform@Vector(anatomical_target);pole=transform.to_3x3()@Vector(pole)
 else:target=Vector(anatomical_target);pole=Vector(pole)
 lm,end=two_bone('UpperArm_'+side,'Forearm_'+side,target,pole)
 return lm,end

def fingers(kind,t,closed=None):
 if hand_poses:
  selected='swim' if kind in ['Swim','SwimIdle'] else ('carry' if kind=='ThrowCharge' else 'relaxed')
  for n,cfg in hand_poses[selected].items():
   if n not in bones:continue
   q=Quaternion(cfg['quaternion_wxyz'])
   if kind=='ThrowRecover':q=Quaternion(hand_poses['release'][n]['quaternion_wxyz']).slerp(Quaternion(hand_poses['relaxed'][n]['quaternion_wxyz']),ease(t))
   elif closed is not None:q=Quaternion(hand_poses['release'][n]['quaternion_wxyz']).slerp(Quaternion(hand_poses['carry'][n]['quaternion_wxyz']),closed)
   rig.pose.bones[n].rotation_quaternion=q
  return
 # Modest natural flex and independent fingers, with no baked thumb-root pinch.
 # New distal joints, when supplied, take a proportion of PIP flexion.
 if closed is None:
  if kind in ['Swim','SwimIdle']: p,d,th=.055,.10,.045
  elif kind.startswith('Throw'): p,d,th=.20,.30,.12
  else:p,d,th=.13,.22,.07
 else:p,d,th=lerp(.035,.24,closed),lerp(.055,.35,closed),lerp(.015,.14,closed)
 for side in ['L','R']:
  D=Vector(hand_manifest[side]['dorsal_axis'])
  for fn in ['Index','Middle','Ring','Little','Thumb']:
   factor={'Index':.84,'Middle':1.,'Ring':1.08,'Little':1.13,'Thumb':1.}[fn]
   for seg in [1,2,3]:
    name=fn+str(seg)+'_'+side
    if name not in bones:continue
    direction=(bones[name][1]-bones[name][0]).normalized()
    axis=rest[name].to_3x3().inverted()@direction.cross(-D).normalized()
    angle=(0 if seg==1 else th*(1 if seg==2 else .45)) if fn=='Thumb' else factor*(p if seg==1 else d*(1 if seg==2 else .48))
    # Quiet asynchronous finger response rather than identical rigid fingers.
    if kind=='SwimIdle' and fn!='Thumb':angle+=.008*math.sin(t*2*math.pi+factor)
    rig.pose.bones[name].rotation_quaternion=Quaternion(axis,angle)
  # Optional hand-worker mapping: each entry defines axis_local and gain.
  for name,cfg in extra_contract.get('extra_pose_bones',{}).items():
   if name in bones and name.endswith('_'+side):
    rig.pose.bones[name].rotation_quaternion=Quaternion(Vector(cfg.get('axis_local',[1,0,0])),float(cfg.get('gain',0))*p)


def quintic(a,b,va,vb,u):
 delta=b-a
 return a+va*u+(10*delta-6*va-4*vb)*u**3+(-15*delta+8*va+7*vb)*u**4+(6*delta-3*va-3*vb)*u**5

def wade_foot(t,sign):
 p=t%1;stance=.62;distance=1.05;front=distance*stance*.5;rear=-front
 heel=.065;toe=-.24
 if p<=stance:
  y=front-distance*p;lift=0
  if p<stance*.18:pitch=heel*(1-ease(p/(stance*.18)));pivot=-.080
  elif p>stance*.76:pitch=toe*ease((p-stance*.76)/(stance*.24));pivot=.190
  else:pitch=0;pivot=0
 else:
  u=(p-stance)/(1-stance);edge=.12;velocity=-distance*(1-stance)*edge;overshoot=-velocity*.22
  if u<edge:y=quintic(rear,rear-overshoot,velocity,0,u/edge)
  elif u>1-edge:y=quintic(front+overshoot,front,0,velocity,(u-1+edge)/edge)
  else:y=rear-overshoot+(front-rear+2*overshoot)*smoother((u-edge)/(1-2*edge))
  # High knee recovery over water, restrained late extension against resistance.
  lift=.145*16*u*u*(1-u)*(1-u)
  pitch=lerp(toe,heel,ease(u));pivot=lerp(.190,-.080,ease(u))
 q=Quaternion((1,0,0),pitch);r=q@Vector((0,-pivot,.103))
 return Vector((sign*.108,y+pivot+r.y,.012+r.z+lift)),q


def wade(t):
 phase=t*2*math.pi
 shift_hips((.015*math.sin(phase),0,.815-.88-.010*math.cos(2*phase)))
 rot('Hips',(0,.017*math.sin(phase),.033*math.cos(phase)))
 rot('Spine',(-.055,-.012*math.sin(phase),-.025*math.cos(phase)))
 rot('Chest',(.015,0,-.032*math.cos(phase)))
 rot('Neck',(.025,0,.010*math.cos(phase)))
 for side,sign,offset in [('L',1,0),('R',-1,.5)]:
  p=phase+2*math.pi*offset
  rot('Shoulder_'+side,(.018*math.cos(p),0,sign*.014*math.sin(p)))
  rot('UpperArm_'+side,(-.19*math.cos(p),sign*.24,sign*.025*math.sin(p-.4)))
  rot('Forearm_'+side,(.38+.055*math.cos(p-.35),0,0));rot('Hand_'+side,(-.055+.025*math.sin(p-.5),0,0))
  target,q=wade_foot(t+offset,sign);leg(side,target,q)


def swim(t):
 # Quiet glide -> outsweep -> insweep -> reach, then coordinated frog kick.
 pitch=float(knots(t,[(0,-1.30),(.25,-1.26),(.44,-1.20),(.68,-1.28),(1,-1.30)]))
 rot('Hips',(pitch,0,.010*math.sin(2*math.pi*t)))
 shift_hips((0,0,.012*math.sin(2*math.pi*t)))
 rot('Spine',(.045,0,0));rot('Chest',(.025,0,0));rot('Neck',(.12,0,0))
 target=knots(t,[(0,[.145,.015,1.865]),(.19,[.36,.04,1.70]),(.38,[.34,.23,1.34]),(.53,[.14,.27,1.37]),(.73,[.14,.12,1.73]),(.86,[.145,.015,1.865]),(1,[.145,.015,1.865])])
 kick=knots(t,[(0,[.06,-.12,.025,-1.05]),(.35,[.06,-.12,.025,-1.05]),(.58,[.48,-1.38,.26,-.35]),(.72,[.36,-.82,.38,-.55]),(.86,[.06,-.12,.025,-1.05]),(1,[.06,-.12,.025,-1.05])])
 for side,sign in [('L',1),('R',-1)]:
  rot('Shoulder_'+side,(0,0,sign*.015))
  arm(side,(sign*target[0],target[1],target[2]),(sign*.9,.12,-.35),True)
  rot('Hand_'+side,(-.07+.035*math.sin(2*math.pi*t),sign*.07,0))
  rot('UpperLeg_'+side,(kick[0],-sign*kick[2],0));rot('LowerLeg_'+side,(kick[1],sign*kick[2]*.35,0))
  rot('Foot_'+side,(kick[3],0,sign*kick[2]*.35))


def swim_idle(t):
 phase=2*math.pi*t
 shift_hips((.006*math.sin(phase),0,.014*math.sin(phase*2)))
 rot('Hips',(.045,0,.015*math.sin(phase)));rot('Spine',(-.06,0,0));rot('Chest',(.025,0,0))
 for side,sign in [('L',1),('R',-1)]:
  p=phase+(0 if sign>0 else math.pi)
  arm(side,(sign*(.37+.075*math.sin(phase)),.15+.06*math.cos(phase),1.10+.035*math.sin(phase)),(sign*.25,1,.05))
  rot('Hand_'+side,(-.10+.10*math.cos(phase),sign*.12*math.sin(phase),0))
  rot('UpperLeg_'+side,(.24+.18*math.sin(p),-sign*(.10+.04*math.cos(p)),0))
  rot('LowerLeg_'+side,(-.54-.27*math.sin(p-.45),0,0));rot('Foot_'+side,(-.09+.11*math.sin(p+.2),0,sign*.05))


def jump(kind,t):
 phase=2*math.pi*t
 if kind=='Land':
  compress=float(knots(t,[(0,.025),(.27,.115),(.65,.05),(1,0)]))
  shift_hips((0,0,-compress));rot('Spine',(-.10*compress/.115,0,0));rot('Chest',(.035*compress/.115,0,0))
  for side,sign in [('L',1),('R',-1)]:
   leg(side,Vector((sign*.108,0,.115)),Quaternion())
   rot('UpperArm_'+side,(.40*(1-t),sign*.25,0));rot('Forearm_'+side,(.35*(1-t)+.18,0,0))
 elif kind=='JumpRise':
  u=ease(t);shift_hips((0,0,-.025*(1-u)))
  rot('Spine',(-.04*(1-u),0,0))
  for side,sign in [('L',1),('R',-1)]:
   rot('UpperLeg_'+side,(lerp(.10,.30 if side=='L' else .19,u),0,0))
   rot('LowerLeg_'+side,(lerp(-.22,-.54 if side=='L' else -.38,u),0,0))
   rot('Foot_'+side,(lerp(-.15,-.05,u),0,0))
   rot('UpperArm_'+side,(lerp(.15,.58,u),sign*.24,0));rot('Forearm_'+side,(lerp(.22,.42,u),0,0))
   # Lift off from actual planted soles, then blend into the authored airborne pose.
   fm=global_pose('Foot_'+side)
   target=Vector((sign*.108,0,.115)).lerp(fm.translation,u)
   fq=(fm.to_3x3()@rest['Foot_'+side].to_3x3().inverted()).to_quaternion()
   leg(side,target,Quaternion().slerp(fq,u))
 else:
  for side,sign in [('L',1),('R',-1)]:
   rot('UpperLeg_'+side,((.30 if side=='L' else .19)+.025*math.sin(phase),0,0))
   rot('LowerLeg_'+side,((-.54 if side=='L' else -.38)-.035*math.sin(phase),0,0));rot('Foot_'+side,(-.05,0,0))
   rot('UpperArm_'+side,(.58+.035*math.sin(phase),sign*.24,0));rot('Forearm_'+side,(.42,0,0))


def throw(kind,t):
 # Two-handed chest toss: held contact -> compact loaded chest -> extension.
 # Actual object attachment and physics release remain controller-owned.
 if kind=='ThrowCharge':
  v=knots(t,[(0,[.19,.33,1.19,0]),(1,[.18,.245,1.25,1])]);closed=1
 elif kind=='ThrowRelease':
  v=knots(t,[(0,[.18,.245,1.25,1]),(.25,[.21,.435,1.30,0]),(.65,[.25,.45,1.29,-.35]),(1,[.27,.43,1.26,-.30])]);closed=0.0
 else:
  v=knots(t,[(0,[.27,.43,1.26,-.30]),(.45,[.28,.23,1.12,-.10]),(1,[.34,.045,.97,0])]);closed=lerp(0,.55,ease(t))
 rot('Spine',(float(v[3])*.045,0,0));rot('Chest',(float(v[3])*.065,0,0))
 for side,sign in [('L',1),('R',-1)]:
  arm(side,(sign*v[0],v[1],v[2]),(sign*.65,.35,-.6))
  rot('Hand_'+side,(-.08+(.13*ease(t/.4) if kind=='ThrowRelease' else 0),sign*.03,0))
 fingers(kind,t,closed)


def pose(kind,t):
 reset();fingers(kind,t)
 if kind=='Wade':wade(t)
 elif kind=='Swim':swim(t)
 elif kind=='SwimIdle':swim_idle(t)
 elif kind in ['JumpRise','JumpAir','Land']:jump(kind,t)
 else:throw(kind,t)
 for side in ['L','R']:
  name='WristSupport_'+side
  if name in rig.pose.bones:
   rig.pose.bones[name].rotation_quaternion=Quaternion().slerp(rig.pose.bones['Hand_'+side].rotation_quaternion,.5)


def is_upper(n):
 return n not in ['Root','Hips'] and not any(n.startswith(p) for p in ['UpperLeg','LowerLeg','Foot','Toe'])

# Static mesh, proportional and sole sampling uses actual skinned evaluated mesh.
mesh_objects=[o for o in bpy.data.objects if o.type=='MESH' and any(m.type=='ARMATURE' and m.object==rig for m in o.modifiers)]
sole_ids={}
for o in mesh_objects:
 ids=[]
 for v in o.data.vertices:
  if v.co.z<.035:ids.append(v.index)
 sole_ids[o.name]=ids

report=dict(source_blend=args.source_blend,base_glb=args.base_glb,source_sha256=hashlib.sha256(base_raw).hexdigest(),
 rest_error_max=max(rest_errors.values()),bone_count=len(bones),clips={},
 coordinate_contract='Blender +Y front/Z up; glTF/Godot -Z front/Y up; Root fixed, Hips articulation only.',
 preserved_clips=PRESERVED,resource_policy='CPU only; no rendering, no editor-wide reimport, no geometry export.')
new_anims=[]
for kind,cfg in CLIPS.items():
 if kind in bpy.data.actions:bpy.data.actions.remove(bpy.data.actions[kind])
 action=bpy.data.actions.new(kind);action.use_fake_user=True;rig.animation_data.action=action
 action['loop']=cfg['loop'];action['authoring_description']='Water/action motion, original Explorer rig, in-place root.'
 if cfg.get('release_frame') is not None:
  marker=action.pose_markers.new('RELEASE');marker.frame=cfg['release_frame']
 names=[n for n in bones if (not cfg.get('upper_body_only') or is_upper(n))]
 samples={n:{'rotation':[],'translation':[]} for n in names}
 positions={n:[] for n in ['Hips','Head','Hand_L','Hand_R','Foot_L','Foot_R']}
 sole_samples=[];mesh_bounds=[];skeleton_samples=[];sampled_knees=[];ik_records.clear();bone_lengths=[]
 for frame in range(cfg['frames']+1):
  scene.frame_set(frame);pose(kind,frame/cfg['frames'])
  for n in names:
   pb=rig.pose.bones[n];pb.keyframe_insert('rotation_quaternion',frame=frame,group=n)
   if n=='Hips':pb.keyframe_insert('location',frame=frame,group=n)
  bpy.context.view_layer.update()
  for n in names:
   pb=rig.pose.bones[n]
   m=pb.parent.matrix.inverted()@pb.matrix if pb.parent else C@pb.matrix
   q=m.to_quaternion();q.normalize();value=[q.x,q.y,q.z,q.w]
   if samples[n]['rotation'] and np.dot(samples[n]['rotation'][-1],value)<0:value=[-x for x in value]
   samples[n]['rotation'].append(value);samples[n]['translation'].append(list(m.translation))
  if frame%max(1,cfg['frames']//24)==0 or frame==cfg['frames']:
   for n in positions:positions[n].append(list(rig.pose.bones[n].head))
   bone_lengths.append(max(abs(pb.length-pb.bone.length) for pb in rig.pose.bones))
   for side in ['L','R']:
    a=rig.pose.bones['UpperLeg_'+side].head;b=rig.pose.bones['LowerLeg_'+side].head;c=rig.pose.bones['Foot_'+side].head
    sampled_knees.append(math.pi-(a-b).angle(c-b))
   if frame%max(1,cfg['frames']//6)==0 or frame==cfg['frames']:
    skeleton_samples.append(dict(frame=frame,bones={pb.name:[list(pb.head),list(pb.tail)] for pb in rig.pose.bones}))
   deps=bpy.context.evaluated_depsgraph_get();lo=Vector((1e9,1e9,1e9));hi=-lo;sole=[]
   for o in mesh_objects:
    eo=o.evaluated_get(deps);me=eo.to_mesh()
    for corner in eo.bound_box:
     v=eo.matrix_world@Vector(corner)
     for j in range(3):lo[j]=min(lo[j],v[j]);hi[j]=max(hi[j],v[j])
    for idx in sole_ids[o.name]:sole.append((eo.matrix_world@me.vertices[idx].co).z)
    eo.to_mesh_clear()
   if sole:sole_samples.append(dict(frame=frame,min_z=min(sole),max_z=max(sole)))
   mesh_bounds.append(dict(frame=frame,min=list(lo),max=list(hi)))
 for fc in action.fcurves:
  for k in fc.keyframe_points:k.interpolation='LINEAR'
 action['duration_seconds']=cfg['frames']/FPS
 times=np.arange(cfg['frames']+1,dtype=np.float32)/FPS
 ti=base.append(times,'SCALAR',with_bounds=True)
 anim=dict(name=kind,channels=[],samplers=[],extras=dict(loop=cfg['loop'],**{k:v for k,v in cfg.items() if k!='loop'}))
 for n,data in samples.items():
  for path,typ in [('rotation','VEC4'),('translation','VEC3')]:
   if path=='translation' and n!='Hips':continue
   ai=base.append(data[path],typ)
   si=len(anim['samplers']);anim['samplers'].append(dict(input=ti,output=ai,interpolation='LINEAR'))
   anim['channels'].append(dict(sampler=si,target=dict(node=node_ids[n],path=path)))
 new_anims.append(anim)
 loop_error=max(min(np.linalg.norm(np.array(v['rotation'][0])-np.array(v['rotation'][-1])),np.linalg.norm(np.array(v['rotation'][0])+np.array(v['rotation'][-1]))) for v in samples.values())
 steps={}
 for n,v in samples.items():
  q=np.asarray(v['rotation'],dtype=float);q/=np.linalg.norm(q,axis=1)[:,None]
  steps[n]=float(np.degrees(2*np.arccos(np.clip(np.abs(np.sum(q[:-1]*q[1:],axis=1)),-1,1))).max())
 all_t=np.array(samples.get('Hips',{'translation':[[0,0,0]]})['translation'])
 report['clips'][kind]=dict(**cfg,duration_seconds=cfg['frames']/FPS,rotation_tracks=len(names),
  loop_quaternion_error=float(loop_error),hips_local_min=all_t.min(0).tolist(),hips_local_max=all_t.max(0).tolist(),
  max_bone_length_error_m=max(bone_lengths),max_adjacent_rotation_step_deg=steps,sampled_positions={n:dict(min=np.min(v,axis=0).tolist(),max=np.max(v,axis=0).tolist(),samples=v) for n,v in positions.items()},
  ik_target_error_max_m=max([r['target_error'] for r in ik_records] or [0]),
  ik_reach_margin_min_m=min([r['reach_margin'] for r in ik_records] or [0]),
  knee_flex_min_rad=min([r['flex'] for r in ik_records if r['upper'].startswith('UpperLeg')] or [0]),
  knee_flex_max_rad=max([r['flex'] for r in ik_records if r['upper'].startswith('UpperLeg')] or [0]),
  sampled_knee_flex_min_deg=math.degrees(min(sampled_knees)),sampled_knee_flex_max_deg=math.degrees(max(sampled_knees)),
  sole_samples=sole_samples,mesh_bounds=mesh_bounds,skeleton_samples=skeleton_samples)
 if cfg['loop']:assert loop_error<2e-5,(kind,'discontinuous loop',loop_error)
 if kind=='Swim':assert max(steps.values())<4.0,('Swim pole/rotation discontinuity',max(steps.items(),key=lambda p:p[1]))
 assert max(bone_lengths)<2e-5,(kind,'limb stretch')
 if kind in ['Wade','Land']:assert report['clips'][kind]['ik_target_error_max_m']<.0001,(kind,'unreachable feet')
 print('AUTHORED',kind,json.dumps({k:v for k,v in report['clips'][kind].items() if k not in ['sole_samples','mesh_bounds','sampled_positions','skeleton_samples','max_adjacent_rotation_step_deg']}),flush=True)
# Exact untouched records/accessors for the old clips and complete mesh/skin.
assert all(curve_hash(bpy.data.actions[n])==old_curve_hash[n] for n in PRESERVED)
base.j['animations']=[a for a in base_json['animations'] if a['name'] not in CLIPS]+new_anims
for key in ['nodes','meshes','skins','materials','textures','images','samplers']:
 assert base.j.get(key)==base_json.get(key), 'Unexpected asset edit: '+key
assert base.bin[:len(base_binary)]==base_binary
for name in PRESERVED:
 assert next(a for a in base.j['animations'] if a['name']==name)==next(a for a in base_json['animations'] if a['name']==name)
report['preserved_animation_curve_hashes']=old_curve_hash
report['all_baseline_binary_bytes_preserved']=True
report['mesh_skin_material_uv_tangent_records_identical']=True
rig.animation_data.action=None;reset()
rig.animation_data.action=bpy.data.actions['Idle'];scene.frame_set(0)
scene.frame_start=0;scene.frame_end=288
rig['water_motion_contract']='Controller owns translation; Wade 1.05 m; horizontal Swim; ThrowRelease marker 0.000 s, immediate physical launch.'
suffix='_draft' if args.draft else ''
if not args.no_save:
 glb_path=OUT/('explorer_water_motion'+suffix+'.glb');base.save(glb_path)
 blend_path=HERE/('explorer_water_motion'+suffix+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(blend_path),compress=True)
 report.update(glb=str(glb_path.relative_to(ROOT)),blend=str(blend_path.relative_to(ROOT)),glb_bytes=glb_path.stat().st_size,blend_bytes=blend_path.stat().st_size,
 glb_sha256=hashlib.sha256(glb_path.read_bytes()).hexdigest(),blend_sha256=hashlib.sha256(blend_path.read_bytes()).hexdigest())
report_path=OUT/('motion_validation'+suffix+'.json');report_path.write_text(json.dumps(report,separators=(',',':'))+'\n')
print('WATER_MOTION_RESULT '+json.dumps({k:v for k,v in report.items() if k!='clips'}))
