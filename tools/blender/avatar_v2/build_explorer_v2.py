"""Pool Explorer V2: original arm/hand anatomy candidate, never auto-integrated.
Blender 4.3.2. Reuses this project's original 42-bone source and seven clips.
Run: blender -b -t 4 --python tools/blender/avatar_v2/build_explorer_v2.py

Only this directory and assets/models/avatar_v2 are written. The first build
captures a compressed immutable source seed; subsequent builds use that seed.
The rest rig and every non-finger animation key are checked bit-for-bit.
"""
import bpy, bmesh, math, json, hashlib, struct
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'assets/models/avatar_v2'
AUDIT=HERE/'audit'
for d in [OUT,AUDIT]:d.mkdir(parents=True,exist_ok=True)
SEED=HERE/'pool_explorer_original_seed.blend'
ORIGINAL=ROOT/'tools/blender/avatar/pool_explorer.blend'
SOURCE=SEED if SEED.exists() else ORIGINAL
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
bpy.context.preferences.filepaths.save_version=0
if not SEED.exists():
 (AUDIT/'seed_provenance.json').write_text(json.dumps({'source':str(ORIGINAL.relative_to(ROOT)),'sha256':hashlib.sha256(ORIGINAL.read_bytes()).hexdigest(),'note':'Original project-authored source only; no third-party character assets.'},indent=2))
 bpy.ops.wm.save_as_mainfile(filepath=str(SEED),compress=True)
scene=bpy.context.scene
rig=bpy.data.objects['ExplorerRig'];body=bpy.data.objects['Body_Explorer'];head=bpy.data.objects['Head_Explorer']
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
scene.frame_set(0)
FINGERS=['Index','Middle','Ring','Little','Thumb']
FINGER_NAMES=[f+str(i)+'_'+s for s in ['L','R'] for f in FINGERS for i in [1,2]]
REQUIRED=['Idle','Walk','Run','Hold','Wade','Swim','Climb']

def bone_contract():
 return {b.name:{'parent':b.parent.name if b.parent else None,'connected':b.use_connect,'deform':b.use_deform,'matrix':[list(row) for row in b.matrix_local],'head':list(b.head_local),'tail':list(b.tail_local)} for b in rig.data.bones}

def curve_contract(include_fingers=False):
 result={}
 for a in bpy.data.actions:
  rows=[]
  for fc in a.fcurves:
   if not include_fingers and any('"'+n+'"' in fc.data_path for n in FINGER_NAMES):continue
   rows.append([fc.data_path,fc.array_index,[[float(k.co.x),float(k.co.y),k.interpolation] for k in fc.keyframe_points]])
  result[a.name]=hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()
 return result
BASE_BONES=bone_contract();BASE_NONFINGER=curve_contract();BASE_HEAD=hashlib.sha256(b''.join(struct.pack('<3f',*v.co) for v in head.data.vertices)).hexdigest()
assert len(BASE_BONES)==42
assert set(a.name for a in bpy.data.actions)==set(REQUIRED)

skin_original=bpy.data.materials['Explorer | neutral warm skin']
skin=skin_original.copy();skin.name='Explorer V2 | anatomical skin vertex color';skin.use_nodes=True
bs=skin.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.64
color_node=skin.node_tree.nodes.new('ShaderNodeVertexColor');color_node.layer_name='AnatomicalColor'
skin.node_tree.links.new(color_node.outputs['Color'],bs.inputs['Base Color'])
skin.diffuse_color=(.46,.285,.18,1)
nail=bpy.data.materials.new('Explorer V2 | natural short nails');nail.use_nodes=True;nail.diffuse_color=(.48,.33,.255,1)
nb=nail.node_tree.nodes.get('Principled BSDF');nb.inputs['Base Color'].default_value=nail.diffuse_color;nb.inputs['Roughness'].default_value=.48
shoe=bpy.data.materials['Explorer | dark nubuck shoes'];lace=bpy.data.materials['Explorer | textile shoelaces']

# Remove only original bare arms/hands/nails and shoelaces from the consolidated
# body. Do not touch topology or weights in legs, feet soles, torso or head.
bm=bmesh.new();bm.from_mesh(body.data);bm.verts.ensure_lookup_table()
skin_slots={i for i,m in enumerate(body.data.materials) if m==skin_original}
edge_slots={i for i,m in enumerate(body.data.materials) if m and 'stitched shirt edges' in m.name}
lace_slots={i for i,m in enumerate(body.data.materials) if m==lace}
delete=[]
for f in bm.faces:
 if f.material_index in skin_slots or f.material_index in lace_slots or (f.material_index in edge_slots and all(abs(v.co.x)>.38 and v.co.z<.97 for v in f.verts)):
  delete.append(f)
bmesh.ops.delete(bm,geom=delete,context='FACES')
loose=[v for v in bm.verts if not v.link_faces]
if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
bm.to_mesh(body.data);bm.free();body.data.update()

# Subtle cloth relaxation: geometric changes stay below 2 mm and do not enlarge
# the shoulder silhouette or alter the camera/arm joint contract.
shirt_slots={i for i,m in enumerate(body.data.materials) if m and 'warm ivory' in m.name}
shirt_vertices=set(v for p in body.data.polygons if p.material_index in shirt_slots for v in p.vertices)
for vi in shirt_vertices:
 v=body.data.vertices[vi];p=v.co
 # Small forearm-side sleeve compression folds, tapering to zero at shoulder.
 zone=math.exp(-((p.z-1.19)/.045)**2)*max(0,min(1,(abs(p.x)-.24)/.055))
 depth_sign=1 if p.y>=0 else -1
 p.y+=depth_sign*.0011*zone*math.sin((p.z-1.15)*210+abs(p.x)*25)
# Restrained shoe toe taper; the contact sole and floor height remain unchanged.
shoe_slots={i for i,m in enumerate(body.data.materials) if m==shoe}
shoe_vertices=set(v for p in body.data.polygons if p.material_index in shoe_slots for v in p.vertices)
for vi in shoe_vertices:
 v=body.data.vertices[vi];p=v.co;sg=1 if p.x>0 else -1
 t=max(0,min(1,(p.y-.07)/.12));t=t*t*(3-2*t)
 p.x=sg*.108+(p.x-sg*.108)*(1-.055*t)
 p.z+=.0018*t*max(0,min(1,(p.z-.036)/.025))

PARTS=[]

def mesh_object(name,verts,faces,material):
 me=bpy.data.meshes.new(name+'Mesh');me.from_pydata(verts,[],faces);me.update()
 ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob);ob.data.materials.append(material)
 for p in me.polygons:p.use_smooth=True
 return ob

def recalc(ob):
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()

def smoothstep(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3.-2.*t)

def blend(a,b,t):
 return {k:a.get(k,0.)*(1-t)+b.get(k,0.)*t for k in set(a)|set(b)}

def tube_mesh(name,points,radii,material,n=16,normal_hint=Vector((1,0,0)),flat=1.,palm_factor=1.):
 # Authored longitudinal quad rings, with smaller rings defining knuckles/pads.
 vv=[];ff=[]
 for i,(p,r) in enumerate(zip(points,radii)):
  p=Vector(p);prev=Vector(points[max(0,i-1)]);nxt=Vector(points[min(len(points)-1,i+1)])
  d=(nxt-prev).normalized();a=(normal_hint-d*normal_hint.dot(d)).normalized();b=d.cross(a).normalized()
  for j in range(n):
   t=math.tau*j/n;cs=math.cos(t);sn=math.sin(t)
   depth=r*flat*(palm_factor if cs<0 else 1)
   vv.append(tuple(p+a*depth*cs+b*r*sn))
 for i in range(len(points)-1):
  for j in range(n):ff.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
 ff.extend([tuple(reversed(range(n))),tuple((len(points)-1)*n+j for j in range(n))])
 ob=mesh_object(name,vv,ff,material);recalc(ob);return ob

def ellipsoid(name,center,radii,axes,material,segments=24,rings=14):
 vv=[];ff=[];c=Vector(center);a,b,d=axes
 for i in range(rings+1):
  t=math.pi*i/rings
  for j in range(segments):
   p=math.tau*j/segments
   vv.append(tuple(c+a*(radii[0]*math.sin(t)*math.cos(p))+b*(radii[1]*math.sin(t)*math.sin(p))+d*(radii[2]*math.cos(t))))
 for i in range(rings):
  for j in range(segments):ff.append((i*segments+j,i*segments+(j+1)%segments,(i+1)*segments+(j+1)%segments,(i+1)*segments+j))
 ob=mesh_object(name,vv,ff,material);recalc(ob);return ob

def join_objects(obs,name):
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();ob=obs[0];ob.name=name;return ob

def segment_distance(p,a,b):
 t=max(0,min(1,(p-a).dot(b-a)/(b-a).length_squared));return (p-a-(b-a)*t).length

def skin_object(ob,weight_function):
 groups={}
 for v in ob.data.vertices:
  ws={k:w for k,w in weight_function(v.co).items() if w>.00001};total=sum(ws.values());assert total>0
  for n,w in ws.items():
   if n not in groups:groups[n]=ob.vertex_groups.new(name=n)
   groups[n].add([v.index],w/total,'REPLACE')
 ob.parent=rig;mod=ob.modifiers.new('Explorer skeletal deformation','ARMATURE');mod.object=rig
 uv=ob.data.uv_layers.new(name='UVMap')
 for loop in ob.data.loops:
  p=ob.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(p.y*4+.5,p.z*4)
 PARTS.append(ob)

HAND_DATA={}
for side,sg in [('L',1),('R',-1)]:
 W=rig.data.bones['Hand_'+side].head_local.copy()
 K=rig.data.bones['Middle1_'+side].head_local.copy()
 L=(K-W).normalized();D=Vector((sg,0,0));D=(D-L*D.dot(L)).normalized();R=D.cross(L).normalized()
 if R.y<0:R=-R
 axes=(D,R,L)
 def pos(u,v,w):return W+R*u+L*v+D*w
 def local(p):
  d=p-W;return Vector((d.dot(R),d.dot(L),d.dot(D)))
 chains={}
 for fn in FINGERS:
  b1=rig.data.bones[fn+'1_'+side];b2=rig.data.bones[fn+'2_'+side]
  chains[fn]=(b1.head_local.copy(),b1.tail_local.copy(),b2.tail_local.copy())
 pieces=[]
 # Forearm muscle belly, wrist styloid flare and palm share ONE manifold union.
 # The proximal edge is concealed under the unchanged rolled cloth cuff.
 elbow=rig.data.bones['Forearm_'+side].head_local.copy()
 fore_centers=[elbow.lerp(W,t) for t in [-.025,.05,.18,.35,.53,.72,.87,.96,1.055]]
 for i,t in enumerate([-.025,.05,.18,.35,.53,.72,.87,.96,1.055]):
  fore_centers[i]+=R*(.0025*math.sin(max(0,min(1,t))*math.pi))
 fore_radii=[.043,.0435,.041,.037,.0315,.026,.0242,.0237,.024]
 fore=tube_mesh('V2 Forearm '+side,fore_centers,fore_radii,skin,n=36,normal_hint=D,flat=.77,palm_factor=1.08);pieces.append(fore)
 # Palm is a flattened asymmetric volume, not an inflated mitten: broad MCP
 # heads, cupped central palm, and separate thenar/hypothenar pads below.
 palm_sections=[(-.009,.025,.019,.021),(.006,.028,.017,.022),(.024,.036,.016,.024),(.044,.042,.014,.027),(.062,.043,.013,.027),(.077,.0415,.012,.023),(.085,.039,.010,.015),(.088,.034,.006,.009)]
 vv=[];ff=[];N=48
 for v,width,dorsal,palmar in palm_sections:
  for j in range(N):
   theta=math.tau*j/N;u=width*math.sin(theta)-(.002+.010*smoothstep(.014,.075,v))
   c=math.cos(theta);w=(dorsal if c>=0 else palmar)*math.copysign(abs(c)**.72,c)
   # A slight transverse arch, dorsal metacarpal ridges and a palm cup.
   if c>0:
    ridge=sum(math.exp(-((u-x)/.0045)**2) for x in [.028,.005,-.019,-.039])
    w+=.0007*ridge*math.sin(math.pi*max(0,min(1,v/.09)))
   else:w+=.0012*math.exp(-(u/.024)**2-((v-.049)/.021)**2)
   vv.append(tuple(pos(u,v+.22*u*smoothstep(.020,.075,v),w)))
 for i in range(len(palm_sections)-1):
  for j in range(N):ff.append((i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j))
 ff.extend([tuple(reversed(range(N))),tuple((len(palm_sections)-1)*N+j for j in range(N))])
 palm=mesh_object('V2 Shaped palm '+side,vv,ff,skin);recalc(palm);pieces.append(palm)
 # Thenar and hypothenar pads are blended into the surface, not separate balls.
 pieces.append(ellipsoid('V2 Thenar '+side,pos(.023,.036,-.013),(.014,.018,.027),axes,skin))
 pieces.append(ellipsoid('V2 Hypothenar '+side,pos(-.027,.047,-.012),(.013,.016,.029),axes,skin))
 # Retain the existing 28 mm contact patch at Hand→Middle1 78% interpolation.
 anchor=W.lerp(K,.78)-D*.028
 pieces.append(ellipsoid('V2 Contact pad '+side,anchor+D*.011,(.0115,.025,.026),axes,skin))
 finger_meta={}
 for fn,width in [('Index',.0098),('Middle',.0105),('Ring',.0098),('Little',.0082),('Thumb',.0123)]:
  h,j,t=chains[fn];d1=(j-h).normalized();d2=(t-j).normalized()
  if fn=='Thumb':
   params=[(-.20,.93),(.0,1.),(.18,1.04),(.52,.99),(.84,.90),(1.,.96),(1.14,.88),(1.43,.82),(1.65,.81),(1.82,.70),(1.96,.42),(2.02,.06)]
  else:
   params=[(-.19,.98),(.0,1.02),(.13,1.04),(.39,.92),(.69,.86),(.89,.93),(1.,.97),(1.10,.87),(1.32,.76),(1.55,.78),(1.66,.82),(1.77,.73),(1.91,.52),(2.01,.11)]
  pts=[];rads=[]
  for u,radius in params:
   p=h+(j-h)*u if u<=1 else j+(t-j)*(u-1)
   # Visible distal pads have gentle rest curvature but bones stay untouched.
   if fn!='Thumb' and u>1.7:p-=D*(.0012*smoothstep(1.7,2.01,u))
   if fn=='Thumb':p+=(R*.011-D*.004)*smoothstep(.0,1.7,u)
   pts.append(p);rads.append(width*radius)
  digit=tube_mesh('V2 '+fn+' '+side,pts,rads,skin,n=20,normal_hint=D,flat=.83,palm_factor=1.12);pieces.append(digit)
  # Sculpted dorsal MCP/PIP relief, never oversized spherical knuckles.
  if fn!='Thumb':
   pieces.append(ellipsoid('V2 '+fn+' MCP '+side,h+D*.005,(.0048,width*.86,.0105),axes,skin,20,10))
   pieces.append(ellipsoid('V2 '+fn+' PIP '+side,j+D*.0055,(.0038,width*.78,.006),axes,skin,20,10))
  finger_meta[fn]={'base':list(h),'joint':list(j),'tip':list(t),'width_m':width*2}
 # A watertight union is sculpted at 1.8 mm, then reduced only after weighting
 # zones have been retained analytically. Four separate fingers remain distinct.
 arm=join_objects(pieces,'V2 Anatomical arm '+side)
 re=arm.modifiers.new('Continuous wrist and hand union','REMESH');re.mode='VOXEL';re.voxel_size=.0018;re.use_smooth_shade=True
 bpy.ops.object.modifier_apply(modifier=re.name)
 sm=arm.modifiers.new('Subtle tissue relaxation','SMOOTH');sm.factor=.55;sm.iterations=3;bpy.ops.object.modifier_apply(modifier=sm.name)
 de=arm.modifiers.new('Bounded game topology','DECIMATE');de.ratio=.075;bpy.ops.object.modifier_apply(modifier=de.name)
 recalc(arm)
 def weights(p):
  q=local(p)
  # Single forearm→hand transition, no disconnected wrist cuff/rim.
  fore_to_hand=smoothstep(-.026,.023,q.y)
  palm_w={'Forearm_'+side:1-fore_to_hand,'Hand_'+side:fore_to_hand}
  if q.y<.012:return palm_w
  scores=[]
  for fn,(h,j,t) in chains.items():
   if fn=='Thumb':
    shift=R*.011-D*.004;j=j+shift*smoothstep(0.,1.7,1.);t=t+shift
   scores.append((min(segment_distance(p,h,j),segment_distance(p,j,t)),fn))
  dist,fn=min(scores);h,j,t=chains[fn]
  if fn=='Thumb':
   shift=R*.011-D*.004;j=j+shift*smoothstep(0.,1.7,1.);t=t+shift
  d1=(j-h).normalized()
  along=(p-h).dot(d1);length=(j-h).length
  # Only this digit's own two bones are used; adjacent digits cannot pull it.
  root_blend=smoothstep(-.003,.014,along)
  if fn=='Thumb':root_blend=smoothstep(.005,.026,along)
  if dist>.024:root_blend*=1-smoothstep(.024,.038,dist)
  joint_blend=smoothstep(length-.007,length+.007,along)
  digit_w={fn+'1_'+side:1-joint_blend,fn+'2_'+side:joint_blend}
  return blend(palm_w,digit_w,root_blend)
 skin_object(arm,weights)
 region=arm.data.attributes.new(name='V2_SurfaceRegion',type='INT',domain='POINT')
 for value in region.data:value.value=1
 # Export-safe vertex colors: slight palm warmth, knuckle flush and creases.
 attr=arm.data.color_attributes.new(name='AnatomicalColor',type='FLOAT_COLOR',domain='POINT')
 for v in arm.data.vertices:
  p=v.co;q=local(p);palm_side=1-smoothstep(-.004,.009,q.z)
  hand_amount=smoothstep(-.006,.025,q.y)
  color=Vector((.46,.285,.18)).lerp(Vector((.49,.300,.212)),palm_side*hand_amount*.7)
  crease=0.
  if q.y>.018 and q.y<.085:
   for yy in [.042+.20*q.x,.069-.14*q.x]:crease+=math.exp(-((q.y-yy)/.0017)**2)
  color*=1-.035*min(1,crease)*palm_side
  redness=0.
  for fn,(h,j,t) in chains.items():redness+=math.exp(-((p-j).length/.012)**2)
  color.x+=.008*min(1,redness);color.y-=.002*min(1,redness)
  attr.data[v.index].color=(*color,1)
 # Nails are tiny curved dorsal patches, attached exclusively to the distal
 # phalanx instead of being dragged around by nearest-palm weights.
 for fn,width in [('Index',.0098),('Middle',.0105),('Ring',.0098),('Little',.0082),('Thumb',.0123)]:
  h,j,t=chains[fn];d=(t-j).normalized();a=(D-d*D.dot(d)).normalized();b=d.cross(a).normalized()
  center=j.lerp(t,.72)
  if fn=='Thumb':center+=R*.011-D*.004
  # Rounded nail plate is shrink-wrapped onto the actual reduced finger mesh,
  # eliminating the floating oval stickers of the earlier source.
  verts=[];faces=[];segments=16
  nail_half_width=width*.49;nail_half_length=(t-j).length*.195
  for ring in [0.,.56,1.]:
   for index in range(segments):
    ang=math.tau*index/segments
    bx=math.copysign(abs(math.sin(ang))**.64,math.sin(ang))*nail_half_width*ring
    dz=math.copysign(abs(math.cos(ang))**.64,math.cos(ang))*nail_half_length*ring
    start=center+b*bx+d*dz+a*.03
    hit,point,normal,_=arm.ray_cast(start,-a)
    assert hit,('Nail missed finger surface',side,fn)
    verts.append(tuple(point+a*(.00012+.00010*(1-ring))))
  for index in range(segments):faces.append((0,segments+index,segments+(index+1)%segments))
  for index in range(segments):faces.append((segments+index,segments+(index+1)%segments,2*segments+(index+1)%segments,2*segments+index))
  # Remove duplicate unused center vertices from the authored plate.
  used=sorted(set(v for face in faces for v in face));index_map={v:i for i,v in enumerate(used)}
  verts=[verts[v] for v in used];faces=[tuple(index_map[v] for v in face) for face in faces]
  ob=mesh_object('V2 '+fn+' nail '+side,verts,faces,skin);recalc(ob)
  skin_object(ob,lambda p,fn=fn:{fn+'2_'+side:1.})
  # Share one surface with skin; nail tint lives in the same glTF color channel.
  color=ob.data.color_attributes.new(name='AnatomicalColor',type='FLOAT_COLOR',domain='POINT')
  for value in color.data:value.color=(.48,.33,.255,1.)
  region=ob.data.attributes.new(name='V2_SurfaceRegion',type='INT',domain='POINT')
  for value in region.data:value.value=2
 HAND_DATA[side]={'wrist':list(W),'long_axis':list(L),'dorsal_axis':list(D),'radial_axis':list(R),'palm_contact':list(anchor),'fingers':finger_meta}

# Functional looking cross-laces and restrained eyelet loops. Foot skin/sole and
# all contact points remain the original source, avoiding gait/ground regressions.
for side,sg in [('L',1),('R',-1)]:
 x=sg*.108
 for i in range(4):
  y=.054+i*.016;z=.121-i*.005
  for cross in [-1,1]:
   points=[Vector((x-cross*.023,y,z)),Vector((x,y+.006,z+.0012)),Vector((x+cross*.021,y+.013,z-.003))]
   ob=tube_mesh('V2 crossed lace '+side+str(i)+str(cross),points,[.00135]*3,lace,n=6,normal_hint=Vector((0,0,1)))
   skin_object(ob,lambda p,side=side:{'Foot_'+side:1.})

# Source-space raycasts verify the unchanged hand-IK palm anchor on the actual
# reduced skin, rather than assuming a radius from construction parameters.
CONTACT_AUDIT={}
for side in ['L','R']:
 arm=next(o for o in PARTS if o.name=='V2 Anatomical arm '+side)
 D=Vector(HAND_DATA[side]['dorsal_axis']);target=Vector(HAND_DATA[side]['palm_contact'])
 hit,p,n,_=arm.ray_cast(target-D*.035,D)
 assert hit,('Missing palmar contact surface',side)
 error=(p-target).length
 assert error<.004,('Palmar contact changed beyond tolerance',side,error)
 CONTACT_AUDIT[side]={'surface_error_m':error,'expected':list(target),'actual':list(p)}

# Original material surfaces receive white values so the imported vertex color
# channel never inadvertently darkens pre-existing clothes/skin in another mesh.
def fill_white(ob):
 attr=ob.data.color_attributes.get('AnatomicalColor')
 if not attr:
  attr=ob.data.color_attributes.new(name='AnatomicalColor',type='FLOAT_COLOR',domain='POINT')
  for d in attr.data:d.color=(1,1,1,1)
fill_white(body)
for ob in PARTS:fill_white(ob)
body=join_objects([body]+PARTS,'Body_Explorer');recalc(body)
bpy.ops.object.material_slot_remove_unused()
# Consolidation must retain exactly one skin modifier and old object contract.
for m in list(body.modifiers):
 if m.type=='ARMATURE' and m!=next(x for x in body.modifiers if x.type=='ARMATURE'):body.modifiers.remove(m)

# Diagnostic isolation found Thumb1 rotation pinched the thin index web even
# at small angles. Supported poses preserve this already-opposed root at rest
# and flex only Thumb2. This is a deliberate bounded pose, not a full thumb rig.
# Grip library uses existing finger bones and rotations relative to their native
# rest frames. It is data, not a runtime dependency or locomotion rewrite.
GRIP_LEVELS={
 'open':{'proximal':0.,'distal':0.,'thumb':0.},
 'relaxed':{'proximal':.10,'distal':.20,'thumb':.07},
 'carry_large':{'proximal':.19,'distal':.30,'thumb':.17},
 'cupped_grip':{'proximal':.36,'distal':.52,'thumb':.22},
}
GRIP_LIBRARY={}
for pose,cfg in GRIP_LEVELS.items():
 rotations={}
 for side,sg in [('L',1),('R',-1)]:
  D=Vector(HAND_DATA[side]['dorsal_axis'])
  for fn in FINGERS:
   for segment in [1,2]:
    name=fn+str(segment)+'_'+side;b=rig.data.bones[name];direction=(b.tail_local-b.head_local).normalized()
    axis=direction.cross(-D).normalized();local_axis=b.matrix_local.to_3x3().inverted()@axis
    angle=(0. if segment==1 else cfg['thumb']*1.3) if fn=='Thumb' else cfg['proximal' if segment==1 else 'distal']
    if fn!='Thumb':angle*= {'Index':.84,'Middle':1.,'Ring':1.08,'Little':1.14}[fn]
    q=Quaternion(local_axis,angle)
    rotations[name]={'quaternion_wxyz':list(q),'axis_local':list(local_axis),'angle_radians':angle}
 GRIP_LIBRARY[pose]=rotations
(OUT/'grip_poses.json').write_text(json.dumps({'format':'existing-bone local rest-relative quaternion wxyz','bones_added':0,'poses':GRIP_LIBRARY,'notes':['Optional targets, not runtime logic.','Blend existing finger bone rotations after arm IK; do not use persistent skeleton overrides.','Supported poses keep Thumb1 at rest: root opposition was rejected for thumb-web pinching; Thumb2 remains articulated.','Cupped grip is an artist pose capability, not proven object-specific contact. Full closed fist is deliberately not included.']},indent=2))
# Replace ONLY the existing finger quaternion samples. All gait/upper-arm/wrist
# tracks remain bit-for-bit. Large-carry is shallow enough for 0.15-0.25 m props.
clip_pose={'Idle':'relaxed','Walk':'relaxed','Run':'relaxed','Hold':'carry_large','Wade':'relaxed','Swim':'open','Climb':'carry_large'}
for a in bpy.data.actions:
 targets=GRIP_LIBRARY[clip_pose[a.name]]
 for fc in a.fcurves:
  for name in FINGER_NAMES:
   if fc.data_path=='pose.bones["'+name+'"].rotation_quaternion':
    value=targets[name]['quaternion_wxyz'][fc.array_index]
    for kp in fc.keyframe_points:kp.co.y=value;kp.handle_left.y=value;kp.handle_right.y=value
    break
 a['v2_finger_pose']=clip_pose[a.name]
assert bone_contract()==BASE_BONES,'Rest skeleton changed'
assert curve_contract()==BASE_NONFINGER,'Non-finger animation changed'
assert hashlib.sha256(b''.join(struct.pack('<3f',*v.co) for v in head.data.vertices)).hexdigest()==BASE_HEAD,'Head geometry changed'
# Every mesh vertex is normalized; influence limit never exceeds four.
for ob in [body,head]:
 for v in ob.data.vertices:
  ws=sorted([(g.group,g.weight) for g in v.groups],key=lambda q:-q[1]);keep=ws[:4];total=sum(w for _,w in keep)
  assert total>.999,'Unweighted vertex'
  for group,weight in ws[4:]:ob.vertex_groups[group].remove([v.index])
  for group,weight in keep:ob.vertex_groups[group].add([v.index],weight/total,'REPLACE')
rig['v2_candidate']='Arm and hand anatomy candidate; not auto-integrated.'
rig['v2_contract']='42 original rest bones; seven original clip names/timings; only finger tracks revised.'
rig['v2_grip_library']='assets/models/avatar_v2/grip_poses.json'
rig.animation_data.action=bpy.data.actions['Idle'];scene.frame_set(0)
scene.render.fps=120;scene.frame_start=0;scene.frame_end=288
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'pool_explorer_v2.blend'),compress=True)
bpy.ops.object.select_all(action='DESELECT')
for ob in [rig,body,head]:ob.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'pool_explorer_v2.glb'),export_format='GLB',use_selection=True,
 export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False,
 export_skins=True,export_all_influences=False,export_def_bones=False,export_yup=True,
 export_apply=False,export_materials='EXPORT',export_texcoords=True,export_normals=True,
 export_cameras=False,export_lights=False,export_extras=True,export_anim_single_armature=True)
manifest={'candidate':'Pool Explorer V2 original anatomical hand/forearm pass','generator':'Blender '+bpy.app.version_string,'integrated':False,
 'source_seed':SEED.name,'bone_count':len(rig.data.bones),'bone_contract_unchanged':bone_contract()==BASE_BONES,
 'nonfinger_animation_contract_unchanged':curve_contract()==BASE_NONFINGER,'head_geometry_unchanged':True,
 'nonfinger_curve_hashes':BASE_NONFINGER,'animations':{a.name:{'frames':list(a.frame_range),'duration_seconds':(a.frame_range[1]-a.frame_range[0])/120,'finger_pose':clip_pose[a.name]} for a in bpy.data.actions},
 'hand_geometry':HAND_DATA,'palm_contact_audit':CONTACT_AUDIT,'meshes':{},'limitations':['Original procedural face and main clothing remain; not a photoreal character.','Static CPU studio renders are not gameplay or GPU performance evidence.','Optional cupped grip has no object-specific collision/contact solver; extreme closed-fist pose is not supported.','Owner must verify V2 in the actual player and remeasure hand surface contact before integration.']}
for ob in [body,head]:
 ob.data.calc_loop_triangles();sums=[sum(g.weight for g in v.groups) for v in ob.data.vertices]
 manifest['meshes'][ob.name]={'vertices':len(ob.data.vertices),'triangles':len(ob.data.loop_triangles),'materials':len(ob.data.materials),'weight_min':min(sums),'weight_max':max(sums),'max_influences':max(len(v.groups) for v in ob.data.vertices)}
for file in [OUT/'pool_explorer_v2.glb',HERE/'pool_explorer_v2.blend']:
 manifest[file.suffix[1:]+'_sha256']=hashlib.sha256(file.read_bytes()).hexdigest()
(OUT/'avatar_v2_manifest.json').write_text(json.dumps(manifest,indent=2))
(AUDIT/'preserved_bone_contract.json').write_text(json.dumps(BASE_BONES,indent=2))
print('AVATAR_V2_BUILD '+json.dumps(manifest))
