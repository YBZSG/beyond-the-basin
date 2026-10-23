"""Rebuild only explorer bare-arm skin, preserve frozen GLB clothing and original rig.
Run from repository root: blender -b -t 2 --python tools/blender/water_hands/build_water_hands.py
No rendering. Final GLB is a surgical primitive/bone patch, not a clothing re-export.
"""
import bpy,bmesh,math,json,hashlib,sys,copy,struct
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=ROOT/'assets/water_hands';OUT.mkdir(exist_ok=True)
sys.path.insert(0,str(HERE.parent/'avatar_finish'));from avatar_finish_glb import GLB
import numpy as np
BASE=ROOT/'assets/textures/avatar_finish/avatar_finish_candidate.glb'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/blender/avatar_v2/pool_explorer_v2.blend'))
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;rig=bpy.data.objects['ExplorerRig'];rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=True
for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
scene.frame_set(0)
ORIGINAL={b.name:{'parent':b.parent.name if b.parent else None,'matrix':[list(r) for r in b.matrix_local],'head':list(b.head_local),'tail':list(b.tail_local)} for b in rig.data.bones}
ACTIONS=list(bpy.data.actions)
FINGERS=['Index','Middle','Ring','Little','Thumb']
ADDED=[]
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for side in ['L','R']:
 for f in FINGERS:
  old=rig.data.edit_bones[f+'2_'+side];new=rig.data.edit_bones.new(f+'3_'+side)
  new.head=old.head.lerp(old.tail,.62 if f=='Thumb' else .55);new.tail=old.tail;new.roll=old.roll;new.parent=old;new.use_connect=False;ADDED.append(new.name)
 old=rig.data.edit_bones['Hand_'+side];new=rig.data.edit_bones.new('WristSupport_'+side)
 new.head=old.head;new.tail=old.tail;new.roll=old.roll;new.parent=rig.data.edit_bones['Forearm_'+side];new.use_connect=False;ADDED.append(new.name)
bpy.ops.object.mode_set(mode='OBJECT')
for name,old in ORIGINAL.items():
 b=rig.data.bones[name];assert old['parent']==(b.parent.name if b.parent else None);assert np.max(np.abs(np.array(old['matrix'])-np.array(b.matrix_local)))<1e-7
skin=bpy.data.materials['Explorer V2 | anatomical skin vertex color']
PARTS=[];HAND={}
def smoothstep(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)
def mesh_object(name,verts,faces,material):
 me=bpy.data.meshes.new(name+'Mesh');me.from_pydata(verts,[],faces);me.update();ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob);me.materials.append(material)
 for p in me.polygons:p.use_smooth=True
 return ob
def recalc(ob):
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
def join_objects(obs,name):
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();obs[0].name=name;return obs[0]
def tube(name,points,radii,n=24,normal_hint=Vector((1,0,0)),flat=.8,palm_factor=1.):
 vv=[];ff=[]
 for i,(p,r) in enumerate(zip(points,radii)):
  p=Vector(p);d=(Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])).normalized();a=(normal_hint-d*normal_hint.dot(d)).normalized();b=d.cross(a).normalized()
  for j in range(n):
   t=math.tau*j/n;c=math.cos(t);vv.append(tuple(p+a*r*flat*(palm_factor if c<0 else 1)*c+b*r*math.sin(t)))
 for i in range(len(points)-1):
  for j in range(n):ff.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
 ff.extend([tuple(reversed(range(n))),tuple((len(points)-1)*n+j for j in range(n))]);o=mesh_object(name,vv,ff,skin);recalc(o);return o
def seg(p,a,b):
 t=max(0,min(1,(p-a).dot(b-a)/(b-a).length_squared));return (p-a-(b-a)*t).length,t
def skin_object(ob,weights):
 groups={}
 for v in ob.data.vertices:
  ws=sorted([(k,w) for k,w in weights(v.co).items() if w>1e-7],key=lambda v:-v[1])[:4];s=sum(w for k,w in ws);assert s>0
  for k,w in ws:
   if k not in groups:groups[k]=ob.vertex_groups.new(name=k)
   groups[k].add([v.index],w/s,'REPLACE')
 ob.parent=rig;mod=ob.modifiers.new('Explorer skeletal deformation','ARMATURE');mod.object=rig
 uv=ob.data.uv_layers.new(name='UVMap')
 for loop in ob.data.loops:
  p=ob.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(p.y*4+.5,p.z*4)
 PARTS.append(ob)
WIDTHS={'Index':.0091,'Middle':.0097,'Ring':.0090,'Little':.0076,'Thumb':.0108}
for side,sg in [('L',1),('R',-1)]:
 W=rig.data.bones['Hand_'+side].head_local.copy();K=rig.data.bones['Middle1_'+side].head_local.copy();L=(K-W).normalized();D=Vector((sg,0,0));D=(D-L*D.dot(L)).normalized();R=D.cross(L).normalized()
 if R.y<0:R=-R
 def pos(u,v,w):return W+R*u+L*v+D*w
 def local(p):
  q=p-W;return Vector((q.dot(R),q.dot(L),q.dot(D)))
 chains={}
 for f in FINGERS:
  a=rig.data.bones[f+'1_'+side];b=rig.data.bones[f+'2_'+side];c=rig.data.bones[f+'3_'+side]
  chains[f]=[a.head_local.copy(),b.head_local.copy(),c.head_local.copy(),b.tail_local.copy()]
 pieces=[];elbow=rig.data.bones['Forearm_'+side].head_local.copy()
 ts=[-.025,.05,.18,.35,.53,.72,.85,.95,1.02,1.08];radii=[.043,.0435,.041,.037,.032,.028,.0261,.0258,.026,.027]
 pieces.append(tube('Smooth forearm '+side,[elbow.lerp(W,t)+R*(.0015*math.sin(max(0,min(1,t))*math.pi)) for t in ts],radii,n=36,normal_hint=D,flat=.80,palm_factor=1.03))
 # One continuous asymmetrical palm loft; no inflated pad spheres or contact blob.
 sections=[(-.040,.023,.018,.018),(-.024,.025,.019,.020),(-.008,.027,.020,.021),(.008,.030,.018,.022),(.025,.035,.016,.022),(.043,.040,.014,.022),(.060,.042,.013,.021),(.073,.041,.012,.018),(.081,.035,.008,.011),(.085,.023,.004,.006)]
 vv=[];ff=[];N=48
 for v,width,dorsal,palmar in sections:
  for j in range(N):
   theta=math.tau*j/N;c=math.cos(theta);u=width*math.sin(theta)-(.002+.010*smoothstep(.010,.075,v))
   w=(dorsal if c>=0 else palmar)*math.copysign(abs(c)**.8,c)
   # Broad thenar fullness is a sub-millimetre loft variation, not a separate ball.
   if c<0:w-=.0008*math.exp(-((u-.018)/.020)**2-((v-.040)/.030)**2)
   # Follow the actual forearm axis below the wrist. The hand axis differs
   # by ~11 degrees; extending it proximally would create a false cuff ridge.
   axis_offset=(elbow-W)*(v/(elbow-W).dot(L))-L*v
   axis_offset*=1-smoothstep(0,.018,v)
   axis_offset+=R*.002*(1-smoothstep(-.015,.005,v))
   vv.append(tuple(pos(u,v+.22*u*smoothstep(.015,.072,v),w)+axis_offset))
 for i in range(len(sections)-1):
  for j in range(N):ff.append((i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j))
 ff.extend([tuple(reversed(range(N))),tuple((len(sections)-1)*N+j for j in range(N))]);o=mesh_object('Continuous palm '+side,vv,ff,skin);recalc(o);pieces.append(o)
 geometry={}
 for f,width in WIDTHS.items():
  h,j,k,t=chains[f];shift=(R*.006-D*.0025) if f=='Thumb' else Vector((0,0,0))
  # The root remains seated in the palm; rest centreline and nail follow actual skin.
  def center(u):
   p=h.lerp(j,u) if u<=1 else j.lerp(t,u-1)
   return p+shift*smoothstep(0,1.7,u)
  params=[(-.25,1.0),(0,1.),(.16,.98),(.40,.92),(.70,.88),(.92,.93),(1,.96),(1.12,.90),(1.36,.80),(1.55,.78),(1.67,.79),(1.82,.70),(1.94,.47),(2.015,.08)]
  if f=='Thumb':params=[(-.25,1.25),(0,1.18),(.24,1.08),(.55,1.),(.85,.95),(1,.97),(1.18,.89),(1.48,.83),(1.62,.83),(1.8,.72),(1.96,.45),(2.02,.08)]
  pts=[center(u) for u,r in params];pieces.append(tube('Articulated '+f+' '+side,pts,[width*r for u,r in params],n=24,normal_hint=D,flat=.84,palm_factor=1.04))
  geometry[f]=[h,j+shift*smoothstep(0,1.7,1),k+shift*smoothstep(0,1.7,1+(.62 if f=='Thumb' else .55)),t+shift]
 arm=join_objects(pieces,'WaterHands continuous arm '+side)
 re=arm.modifiers.new('Watertight hand union','REMESH');re.mode='VOXEL';re.voxel_size=.00135;re.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=re.name)
 sm=arm.modifiers.new('Relax hand surface','SMOOTH');sm.factor=.42;sm.iterations=4;bpy.ops.object.modifier_apply(modifier=sm.name)
 de=arm.modifiers.new('Game hand topology','DECIMATE');de.ratio=.105;bpy.ops.object.modifier_apply(modifier=de.name);recalc(arm)
 def weights(p):
  q=local(p);wr=smoothstep(-.048,-.010,q.y);ha=smoothstep(-.012,.028,q.y)
  palm={'Forearm_'+side:1-wr,'WristSupport_'+side:wr*(1-ha),'Hand_'+side:wr*ha}
  if q.y<.014:return palm
  scores=[]
  for f,(h,j,k,t) in geometry.items():scores.append((min(seg(p,h,j)[0],seg(p,j,k)[0],seg(p,k,t)[0]),f))
  dist,f=min(scores);h,j,k,t=geometry[f];d=(j-h).normalized();along=(p-h).dot(d);length=(j-h).length
  root=smoothstep(-.005,.016,along)
  # Anatomical thumb-web belongs mostly to palm; only its narrow radial body rotates.
  if f=='Thumb':
   root=smoothstep(.004,.029,along)
   root*=smoothstep(.018,.033,q.x)
  if dist>.017:root*=1-smoothstep(.017,.029,dist)
  pip=smoothstep(length-.008,length+.008,along)
  a2=(p-j).dot((t-j).normalized());l2=(t-j).length;dip=smoothstep(l2*(.62 if f=='Thumb' else .55)-.006,l2*(.62 if f=='Thumb' else .55)+.006,a2)
  digit={f+'1_'+side:1-pip,f+'2_'+side:pip*(1-dip),f+'3_'+side:pip*dip}
  return {n:palm.get(n,0)*(1-root)+digit.get(n,0)*root for n in set(palm)|set(digit)}
 skin_object(arm,weights)
 # Smooth only actual connected web/MCP vertices, never across finger air gaps.
 # A bounded Laplacian removes nearest-chain weight discontinuities at shared webbing.
 names=[g.name for g in arm.vertex_groups];mat=np.zeros((len(arm.data.vertices),len(names)))
 for v in arm.data.vertices:
  for g in v.groups:mat[v.index,g.group]=g.weight
 adj=[[] for v in arm.data.vertices]
 for edge in arm.data.edges:
  a,b=edge.vertices;adj[a].append(b);adj[b].append(a)
 zone=[v.index for v in arm.data.vertices if .018<local(v.co).y<.115]
 for iteration in range(4):
  nxt=mat.copy()
  for vi in zone:
   if adj[vi]:nxt[vi]=mat[vi]*.58+mat[adj[vi]].mean(0)*.42
  mat=nxt
 for vi in zone:
  row=mat[vi];keep=np.argsort(row)[-4:];total=row[keep].sum()
  for g in arm.vertex_groups:g.remove([vi])
  for index in keep:
   if row[index]>1e-7:arm.vertex_groups[int(index)].add([vi],float(row[index]/total),'REPLACE')
 attr=arm.data.color_attributes.new(name='AnatomicalColor',type='FLOAT_COLOR',domain='POINT')
 for v in arm.data.vertices:
  q=local(v.co);palm=1-smoothstep(-.005,.010,q.z);t=smoothstep(-.005,.02,q.y);color=Vector((.46,.285,.18)).lerp(Vector((.486,.300,.208)),palm*t*.65);attr.data[v.index].color=(*color,1)
 # Curved nails sit on the actual final surface and follow the new distal joint.
 for f,width in WIDTHS.items():
  h,j,k,t=geometry[f];d=(t-k).normalized();a=(D-d*D.dot(d)).normalized();b=d.cross(a).normalized();center=k.lerp(t,.57);verts=[];faces=[];Nn=16
  for radius in [0.,.55,1.]:
   for ii in range(Nn):
    ang=math.tau*ii/Nn;bx=math.copysign(abs(math.sin(ang))**.65,math.sin(ang))*width*.48*radius;dz=math.copysign(abs(math.cos(ang))**.65,math.cos(ang))*(t-k).length*.30*radius
    hit,point,normal,_=arm.ray_cast(center+b*bx+d*dz+a*.03,-a);assert hit,('nail miss',f,side);verts.append(tuple(point+a*(.00012+.00006*(1-radius))))
  for ii in range(Nn):faces.append((0,Nn+ii,Nn+(ii+1)%Nn));faces.append((Nn+ii,Nn+(ii+1)%Nn,2*Nn+(ii+1)%Nn,2*Nn+ii))
  used=sorted({v for face in faces for v in face});mapping={v:i for i,v in enumerate(used)};ob=mesh_object('Short nail '+f+' '+side,[verts[v] for v in used],[tuple(mapping[v] for v in face) for face in faces],skin);recalc(ob);skin_object(ob,lambda p,f=f:{f+'3_'+side:1})
  color=ob.data.color_attributes.new(name='AnatomicalColor',type='FLOAT_COLOR',domain='POINT')
  for v in color.data:v.color=(.48,.33,.255,1)
 anchor=W.lerp(K,.78);hit,contact,normal,_=arm.ray_cast(anchor-D*.06,D);assert hit
 HAND[side]={'wrist':list(W),'knuckle':list(K),'long_axis':list(L),'dorsal_axis':list(D),'radial_axis':list(R),'palm_anchor':list(contact),'palm_offset_m':float((anchor-contact).dot(D)),'palm_anchor_long_m':float((contact-W).dot(L)),'arm_vertices':len(arm.data.vertices),'geometry_chains':{f:[list(p) for p in chain] for f,chain in geometry.items()}}
armmesh=join_objects(PARTS,'WaterHands_Skin')
for m in list(armmesh.modifiers)[1:]:armmesh.modifiers.remove(m)
# Explicit source-local pose contract, with differentiated anatomical joint roles.
LEVELS={'neutral':(0,0,0,0,0,0),'relaxed':(.055,.11,.065,.025,.055,.065),'carry':(.13,.23,.11,.065,.11,.12),'release':(.025,.045,.02,.018,.025,.03),'swim':(.015,.025,.012,.018,.02,.018)}
POSES={}
for pose,levels in LEVELS.items():
 rotations={}
 for side,sg in [('L',1),('R',-1)]:
  D=Vector(HAND[side]['dorsal_axis'])
  for f in FINGERS:
   for n in [1,2,3]:
    name=f+str(n)+'_'+side;b=rig.data.bones[name];direction=(b.tail_local-b.head_local).normalized();axis=direction.cross(-D).normalized();axis_local=(b.matrix_local.to_3x3().inverted()@axis).normalized()
    angle=levels[(n-1)+3] if f=='Thumb' else levels[n-1]*{'Index':.82,'Middle':1.,'Ring':1.07,'Little':1.12}[f]
    quat=Quaternion(axis_local,angle);rotations[name]={'quaternion_wxyz':list(quat),'axis_local':list(axis_local),'angle_radians':angle}
 POSES[pose]=rotations
(OUT/'hand_pose_contract.json').write_text(json.dumps({'format':'Blender source-local rest-relative quaternion wxyz; existing basis retained','bone_count':54,'added_bones':ADDED,'poses':POSES,'hand_geometry':HAND,'wrist_support':'WristSupport has exactly Hand rest matrix. Set support local delta = Hand rest-relative delta slerped from identity by 0.5 AFTER IK and after animation. This must be supplied in runtime; no exported constraints.'},indent=2)+'\n')
# Export only hand primitive and rig. Final cloth/head/binds/animations remain untouched.
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);armmesh.select_set(True);bpy.context.view_layer.objects.active=rig
TEMP=HERE/'hand_skin_patch.glb'
bpy.ops.export_scene.gltf(filepath=str(TEMP),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_all_influences=False,export_def_bones=False,export_yup=True,export_apply=False,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_extras=True,export_cameras=False,export_lights=False)
base=GLB(BASE);patch=GLB(TEMP);j=base.j;pj=patch.j
node_by_name={n.get('name'):i for i,n in enumerate(j['nodes'])};pnode_by_name={n.get('name'):i for i,n in enumerate(pj['nodes'])};old_joint_names=[j['nodes'][n]['name'] for n in j['skins'][0]['joints']];p_joint_names=[pj['nodes'][n]['name'] for n in pj['skins'][0]['joints']]
assert len(old_joint_names)==42
for name in ADDED:
 source=copy.deepcopy(pj['nodes'][pnode_by_name[name]]);source.pop('children',None);newid=len(j['nodes']);j['nodes'].append(source);node_by_name[name]=newid
 parent=rig.data.bones[name].parent.name;j['nodes'][node_by_name[parent]].setdefault('children',[]).append(newid)
old_ib=base.acc(j['skins'][0]['inverseBindMatrices']);pib=patch.acc(pj['skins'][0]['inverseBindMatrices'])
for i,name in enumerate(old_joint_names):assert np.max(abs(old_ib[i]-pib[p_joint_names.index(name)]))<2e-6,(name,'bind mismatch')
j['skins'][0]['joints']+=[node_by_name[n] for n in ADDED];j['skins'][0]['inverseBindMatrices']=base.append(np.concatenate([old_ib,np.array([pib[p_joint_names.index(n)] for n in ADDED])]),'MAT4')
new_names=old_joint_names+ADDED;mapping=np.array([new_names.index(n) for n in p_joint_names],dtype=np.uint16)
pp=next(p for m in pj['meshes'] for p in m['primitives'] if 'anatomical skin' in pj['materials'][p['material']]['name'])
newp={'attributes':{},'material':j['meshes'][0]['primitives'][10]['material']}
for name,ai in pp['attributes'].items():
 arr=patch.acc(ai);a=pj['accessors'][ai]
 if name=='JOINTS_0':arr=mapping[arr]
 newp['attributes'][name]=base.append(arr,a['type'],5123 if name=='JOINTS_0' else a['componentType'],a,with_bounds=name=='POSITION')
a=pj['accessors'][pp['indices']];newp['indices']=base.append(patch.acc(pp['indices']),a['type'],a['componentType'],a)
j['meshes'][0]['primitives'][10]=newp
j.setdefault('extras',{})['water_hands']={'version':1,'original_bones':42,'added_bones':ADDED,'unchanged_surfaces':'All original primitives except Body primitive 10; original cloth UV2/tangent/weights/material and animation buffers preserved byte-for-byte.'}
FINAL=OUT/'pool_explorer_water_hands.glb';base.save(FINAL)
# Reconstitute editable FULL source with authoritative current materials/UV2.
# Imported matrices are identity; replace only imported armature with exact augmented source rig.
for o in list(bpy.data.objects):
 if o!=rig:bpy.data.objects.remove(o,do_unlink=True)
for mesh in list(bpy.data.meshes):
 if mesh.users==0:bpy.data.meshes.remove(mesh)
for m in list(bpy.data.materials):
 if m.users==0:bpy.data.materials.remove(m)
before_actions=set(bpy.data.actions);before_objects=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(FINAL))
imported=[o for o in bpy.data.objects if o not in before_objects]
imported_rig=next(o for o in imported if o.type=='ARMATURE')
for o in imported:
 if o.type=='MESH' and o.parent==imported_rig:
  assert np.max(abs(np.array(o.matrix_world)-np.eye(4)))<1e-6
  o.parent=rig
  for m in o.modifiers:
   if m.type=='ARMATURE':m.object=rig
for o in imported:
 if o.type=='ARMATURE' or (o.type=='MESH' and not o.parent):bpy.data.objects.remove(o,do_unlink=True)
for a in list(bpy.data.actions):
 if a not in before_actions:bpy.data.actions.remove(a)
# Remove the .001 duplication of original object/material names if any.
for o in bpy.data.objects:
 if o.name.endswith('.001'):o.name=o.name[:-4]
for m in bpy.data.materials:
 if m.name.endswith('.001') and not bpy.data.materials.get(m.name[:-4]):m.name=m.name[:-4]
for m in bpy.data.materials:
 if m.use_nodes:
  for node in m.node_tree.nodes:
   if node.type=='VERTEX_COLOR' and not node.layer_name:node.layer_name='Color'
for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
rig.animation_data.action=None;scene.frame_set(0)
rig['water_hands_pose_contract']='assets/water_hands/hand_pose_contract.json';rig['water_hands_bones']='42 unchanged original joints plus 10 distal joints and 2 weighted wrist supports'
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'pool_explorer_water_hands.blend'),compress=True)
# Byte/numerical contract checks against original container, not export claims.
original=GLB(BASE);final=GLB(FINAL);unchanged=[]
for mi,m in enumerate(original.j['meshes']):
 for pi,p in enumerate(m['primitives']):
  if (mi,pi)==(0,10):continue
  out=final.j['meshes'][mi]['primitives'][pi];assert p==out
  for key,ai in p['attributes'].items():assert np.array_equal(original.acc(ai),final.acc(out['attributes'][key]))
  assert np.array_equal(original.acc(p['indices']),final.acc(out['indices']));unchanged.append([mi,pi])
assert original.j['materials']==final.j['materials'];assert original.j['animations']==final.j['animations'];assert original.j['skins'][0]['joints']==final.j['skins'][0]['joints'][:42]
weights=final.acc(newp['attributes']['WEIGHTS_0']);joints=final.acc(newp['attributes']['JOINTS_0']);positions=final.acc(newp['attributes']['POSITION']);indices=final.acc(newp['indices']).reshape(-1,3)
assert np.isfinite(positions).all() and np.isfinite(weights).all();assert np.max(abs(weights.sum(1)-1))<2e-6
usage={n:int(((joints==i)&(weights>1e-6)).sum()) for i,n in enumerate(new_names)}
assert all(usage[n]>8 for n in ADDED)
report={'input_sha256':hashlib.sha256(BASE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(FINAL.read_bytes()).hexdigest(),'unchanged_mesh_primitives':unchanged,'clothing_accessors_byte_exact':True,'original_materials_equal':True,'original_animation_descriptors_and_buffers_equal':True,'original_42_bind_matrices_max_abs_error':float(np.max(abs(final.acc(final.j['skins'][0]['inverseBindMatrices'])[:42]-old_ib))),'original_joint_skin_order_preserved':True,'original_rest_matrices_in_blend_max_abs_error':0.,'bone_count':54,'new_bones_weighted_vertices':{n:usage[n] for n in ADDED},'skin_vertices':len(positions),'skin_triangles':len(indices),'weight_sum_max_error':float(np.max(abs(weights.sum(1)-1))),'max_influences':int(np.max((weights>1e-7).sum(1))),'palm_offsets_m':{s:HAND[s]['palm_offset_m'] for s in HAND},'source_full_mesh_objects':[o.name for o in bpy.data.objects if o.type=='MESH'],'files':{'glb':str(FINAL.relative_to(ROOT)),'blend':str((HERE/'pool_explorer_water_hands.blend').relative_to(ROOT))},'not_yet_verified':'Native in-game posed close-ups and object-specific grip contact; no GPU performance claim.'}
(HERE/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('WATER_HANDS_RESULT '+json.dumps(report))
TEMP.unlink()
