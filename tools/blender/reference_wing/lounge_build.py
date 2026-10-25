"""Reference 4: original salmon ball-pit lounge. Blender 4.3.2, metres.

Rebuild:
  blender -b -t 4 --python tools/blender/reference_wing/lounge_build.py
Preview, only after coordinating the shared render slot:
  blender -b -t 4 tools/blender/reference_wing/lounge_sources/ball_lounge.blend \
    --python tools/blender/reference_wing/lounge_render.py

Godot coordinates are used in authoring functions and converted to Blender Z-up.
Every ball is statically supported by a floor/bench or a previously settled ball.
No individual ball physics is claimed or exported. The architectural pit floor,
not the visible ball tops, is the player collider. See the geometry sidecar.
"""
import bpy, math, json, os, random, sys, hashlib
from mathutils import Vector
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../..'))
SRC=os.environ.get('LOUNGE_SOURCE_DIR',os.path.join(ROOT,'tools/blender/reference_wing/lounge_sources'))
OUT=os.environ.get('LOUNGE_OUTPUT_DIR',os.path.join(ROOT,'assets/models/reference_wing'))
AUDIT=os.environ.get('LOUNGE_AUDIT_DIR',os.path.join(ROOT,'output/reference_wing/lounge'))
for directory in [SRC,OUT,AUDIT]:os.makedirs(directory,exist_ok=True)
open(os.path.join(SRC,'.gdignore'),'a').close()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for mat in list(bpy.data.materials):bpy.data.materials.remove(mat)
SCENE=bpy.context.scene; SCENE.unit_settings.system='METRIC';SCENE.unit_settings.scale_length=1
SCENE['reference_image']='reference-4/1000074569.jpg'
SCENE['description']='Low salmon lounge, supported curved bench, coral pillows, pale blue and ivory static ball pit, five closed deep cyan portholes. No water.'
SCENE['uv_convention']='UV0 metric metres, 1 UV unit / metre; sphere UVs use physical arc length.'
SCENE['coordinates']='Blender Z-up; GLB export Godot Y-up. Module 32 m, center origin.'
SEED=4569; random.seed(SEED)
MAT={};COLLISIONS=[];SUPPORT=[];STEPS=[];LIGHTS=[];PORTS=[];WINDOWS=[];BALLS=[];CAMERAS=[]
PALETTE={
'ref_lounge_plaster':((.43,.245,.245,1),.84),
'ref_lounge_fabric':((.50,.265,.265,1),.90),
'ref_cushion_coral':((.67,.085,.072,1),.86),
'ref_ball_blue':((.39,.68,.76,1),.52),
'ref_ball_ivory':((.79,.84,.79,1),.55),
'ref_glazing_cyan':((.37,.75,.88,1),.48),
'ref_fixture_metal':((.29,.34,.34,1),.4),
}
for role,(rgba,rough) in PALETTE.items():
 m=bpy.data.materials.new(role);m.diffuse_color=rgba;m.use_nodes=True
 bsdf=m.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=rgba;bsdf.inputs['Roughness'].default_value=rough
 if role=='ref_fixture_metal':bsdf.inputs['Metallic'].default_value=.55
 if role=='ref_glazing_cyan':
  bsdf.inputs['Emission Color'].default_value=(.43,.78,.87,1);bsdf.inputs['Emission Strength'].default_value=.25
 if role in ['ref_lounge_plaster','ref_lounge_fabric','ref_cushion_coral']:
  tex=m.node_tree.nodes.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=120 if role=='ref_lounge_plaster' else 240;tex.inputs['Detail'].default_value=2
  coord=m.node_tree.nodes.new('ShaderNodeTexCoord');m.node_tree.links.new(coord.outputs['Object'],tex.inputs['Vector'])
  bump=m.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.15;bump.inputs['Distance'].default_value=.007 if role=='ref_lounge_plaster' else .002
  m.node_tree.links.new(tex.outputs['Fac'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
 MAT[role]=m

def p(v):return (v[0],-v[2],v[1])
def g(v):return (v[0],v[2],-v[1])
IDENTITY=[1,0,0,0,1,0,0,0,1]
FACES=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]

def metric_uv(mesh):
 uv=mesh.uv_layers.new(name='UV0')
 for f in mesh.polygons:
  axis=max(range(3),key=lambda a:abs(f.normal[a]));axes=[a for a in range(3) if a!=axis]
  for li in f.loop_indices:
   co=mesh.vertices[mesh.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
 return uv

def mesh(name,verts,faces,role='ref_lounge_plaster',bevel=0,smooth=False):
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata([p(v) for v in verts],[],faces);me.update()
 ob=bpy.data.objects.new(name,me);SCENE.collection.objects.link(ob);me.materials.append(MAT[role])
 bpy.context.view_layer.objects.active=ob;ob.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
 metric_uv(me)
 if bevel:
  b=ob.modifiers.new('Soft physical edge contour','BEVEL');b.width=bevel;b.segments=4;b.limit_method='ANGLE';b.angle_limit=.35
  bpy.ops.object.modifier_apply(modifier=b.name)
  n=ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');n.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=n.name)
  # Generated bevel strips need real metric UV area, not inherited zero-area edge UVs.
  for layer in list(ob.data.uv_layers):ob.data.uv_layers.remove(layer)
  metric_uv(ob.data)
 if smooth:
  for face in ob.data.polygons:face.use_smooth=True
 ob['units']='metres';ob['material_role']=role;ob['uv_density']='1 UV / metre';ob.select_set(False)
 return ob

def proxy_box(name,center,size,purpose='structural'):
 COLLISIONS.append({'name':name,'type':'BOX','center':list(center),'size':list(size),'transform':{'origin':[0,0,0],'basis':IDENTITY},'bounds':{'min':[center[i]-size[i]/2 for i in range(3)],'max':[center[i]+size[i]/2 for i in range(3)]},'purpose':purpose})

def proxy_convex(name,verts,faces,purpose='structural'):
 COLLISIONS.append({'name':name,'type':'CONVEX','vertices':[list(v) for v in verts],'faces':[list(f) for f in faces],'transform':{'origin':[0,0,0],'basis':IDENTITY},'bounds':{'min':[min(v[i] for v in verts) for i in range(3)],'max':[max(v[i] for v in verts) for i in range(3)]},'purpose':purpose})

# Exact structural terminations at eleven independently observed same-facing
# wall contacts. Seven connector boxes stop at their retained neighbour's real
# solid boundary; the removed volumes are fully owned by those neighbours.
# These are architectural dimensions, never epsilon offsets or scene booleans.
CONTACT_END_TRIMS={
 'Connector_boundary_0_3_2':{'axis':0,'old':[-16.,-8.],'new':[-15.8,-8.18],'retained':['Sealed_module_x_minus','Connector_boundary_1_2_0']},
 'Connector_boundary_0_3_3':{'axis':0,'old':[-16.,-8.],'new':[-15.8,-8.18],'retained':['Sealed_module_x_minus.001','Connector_boundary_1_4_0']},
 'Connector_boundary_4_0_0':{'axis':2,'old':[-16.,-12.],'new':[-15.8,-12.18],'retained':['Sealed_module_z_minus','Connector_boundary_3_1_2']},
 'Connector_boundary_4_0_1':{'axis':2,'old':[-16.,-12.],'new':[-15.8,-12.],'retained':['Sealed_module_z_minus.001']},
 'Connector_boundary_2_1_3':{'axis':0,'old':[-5.,-3.4],'new':[-4.82,-3.4],'retained':['Connector_boundary_1_2_1']},
 'Connector_boundary_2_5_2':{'axis':0,'old':[-5.,-3.4],'new':[-4.82,-3.76],'retained':['Connector_boundary_1_4_1','Room_left_wall']},
 'Connector_boundary_2_5_3':{'axis':0,'old':[-5.,-3.4],'new':[-5.,-3.76],'retained':['Room_left_south_jamb']},
}

def contact_box_dimensions(name,center,size):
 if name not in CONTACT_END_TRIMS:return center,size
 spec=CONTACT_END_TRIMS[name];axis=spec['axis']
 before=[center[axis]-size[axis]/2,center[axis]+size[axis]/2]
 if any(abs(a-b)>1e-9 for a,b in zip(before,spec['old'])):
  raise ValueError('Contact dimensions changed; revalidate exact solid coverage: '+name)
 center=list(center);size=list(size);low,high=spec['new']
 center[axis]=(low+high)/2;size[axis]=high-low
 return center,size

def box(name,c,s,role='ref_lounge_plaster',bevel=0,col=True):
 if name in CONTACT_END_TRIMS and bevel:
  raise ValueError('A bevel requires fresh visible contact coverage proof: '+name)
 c,s=contact_box_dimensions(name,c,s)
 x,y,z=c;a,b,d=[v/2 for v in s]
 vv=[(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
 ob=mesh(name,vv,FACES,role,min(bevel,min(s)*.24))
 if col:proxy_box(name,c,s)
 return ob

# Real structural slab, room pit, supported access apron. No implied floating floor.
box('Module_foundation',(0,-.23,0),(32,.30,32))
box('Pit_structural_floor',(0,-.015,0),(6.8,.19,16)) # top .08
box('Dry_entry_apron',(0,.30,6.4),(6.8,.44,3.2),'ref_lounge_plaster',.025)
SUPPORT.append({'object':'Dry_entry_apron','support':'Pit_structural_floor','object_bottom_y':.08,'support_top_y':.08,'gap_m':0.0,'contact_region_xz':[-3.4,3.4,4.8,8.0]})
# Shallow, wide, dry access into the cosmetic ball fill.
for i in range(3):
 top=.52-(i+1)*(.44/3);z=4.8-(i+.5)*.38
 name='Pit_access_step_%02d'%(i+1)
 thickness=max(.018,top-.08)
 if i<2:box(name,(-1.65,top-thickness/2,z),(1.45,thickness,.38),'ref_lounge_plaster',.012)
 # The third tread is the existing structural floor, not a coplanar duplicate mesh.
 STEPS.append({'name':name,'center':[-1.65,top,z],'width':1.45,'tread':.38,'riser':.44/3,'top_y':top,'approach':'from dry apron z=4.8 toward negative z','collision_proxy':name if i<2 else 'Pit_structural_floor'})
# Low retaining lip, continuous front edge except deliberate stair opening.
for xa,xb in [(-3.4,-2.375),(-.925,1.1)]:
 box('Pit_front_retaining_wall',((xa+xb)/2,.295,4.77),(xb-xa,.43,.11),'ref_lounge_plaster',.025)
# Room left and south boundaries; exact 3 m-wide west door opens onto dry apron.
box('Room_left_wall',(-3.58,1.80,-1.6),(.36,3.44,12.8)) # z -8..4.8
box('Room_left_south_jamb',(-3.58,1.80,7.90),(.36,3.44,.20))
box('Room_west_door_header',(-3.58,3.42,6.3),(.36,.20,3.0))
box('Room_south_wall',(0,1.80,8.18),(7.52,3.44,.36))
box('Room_continuous_low_roof',(0,3.68,0),(7.52,.32,16.72),'ref_lounge_plaster',.025)

# Deep circle apertures cut into thick wall panels, with solid opaque external closures.
def porthole_panel(name,plane,offset,u0,u1,uc,r=.86,cy=2.0):
 # u is Godot z on right wall, Godot x on rear wall. Plane normal points outward.
 def xyz(u,y,d):return (offset+d,y,u) if plane=='right' else (u,y,offset-d)
 ymin,ymax=.08,3.52
 angles=[i*math.tau/64 for i in range(64)]
 angles += [math.atan2(y-cy,u-uc)%math.tau for u,y in [(u0,ymin),(u1,ymin),(u1,ymax),(u0,ymax)]]
 angles=sorted(set(round(a,9) for a in angles));count=len(angles)
 outer=[];inner=[]
 for a in angles:
  dx,dy=math.cos(a),math.sin(a)
  hits=[]
  if dx>1e-9:hits.append((u1-uc)/dx)
  elif dx< -1e-9:hits.append((u0-uc)/dx)
  if dy>1e-9:hits.append((ymax-cy)/dy)
  elif dy< -1e-9:hits.append((ymin-cy)/dy)
  t=min(v for v in hits if v>0)
  outer.append((uc+dx*t,cy+dy*t));inner.append((uc+dx*r,cy+dy*r))
 verts=[]
 for d in [0,.36]:
  verts += [xyz(u,y,d) for u,y in outer]+[xyz(u,y,d) for u,y in inner]
 faces=[]
 for i in range(count):
  j=(i+1)%count;faces.extend([(i,j,count+j,count+i),(2*count+i,3*count+i,3*count+j,2*count+j),(i,2*count+i,2*count+j,j),(count+i,count+j,3*count+j,3*count+i)])
  pv=[xyz(*outer[i],d) for d in [0,.36]]+[xyz(*outer[j],d) for d in [0,.36]]+[xyz(*inner[j],d) for d in [0,.36]]+[xyz(*inner[i],d) for d in [0,.36]]
  proxy_convex(name+'_wall_sector_%02d'%i,pv,[(0,2,4,6),(1,7,5,3),(0,1,3,2),(2,3,5,4),(4,5,7,6),(6,7,1,0)],'Actual thick porthole wall sector')
 mesh(name+'_thick_wall',verts,faces,'ref_lounge_plaster')
 # Closed recess extends 0.74 m beyond the room face, never opens into the void.
 vv=[]
 for d,rad in [(.36,r),(.74,r*.96),(.36,r+.025),(.82,r+.025)]:
  for a in angles:vv.append(xyz(uc+rad*math.cos(a),cy+rad*math.sin(a),d))
 ff=[]
 for i in range(count):
  j=(i+1)%count;ff.extend([(i,j,count+j,count+i),(2*count+i,3*count+i,3*count+j,2*count+j),(count+i,count+j,3*count+j,3*count+i),(i,2*count+i,2*count+j,j)])
 mesh(name+'_deep_reveal',vv,ff,'ref_lounge_plaster',0,True)
 # A closed 16-sector collision sleeve prevents escaping sideways after entering
 # the recess from the bench. Its conservative chord intrudes < 18 mm inward.
 for section in range(16):
  a=section*math.tau/16;b=(section+1)*math.tau/16;pv=[]
  for depth,inner_radius in [(.36,r),(.82,r*.96)]:
   for radius,theta in [(inner_radius,a),(inner_radius,b),(r+.025,b),(r+.025,a)]:pv.append(xyz(uc+radius*math.cos(theta),cy+radius*math.sin(theta),depth))
  proxy_convex(name+'_closed_recess_sleeve_%02d'%section,pv,FACES,'Closed light-well side collision, conservative 16-sector approximation; inward tolerance below 0.018 m')
 # Separate thick cyan glazing disk and truly closed backing, not an open paper hole.
 for suffix,depth,thickness,rad in [('cyan_glazing',.70,.035,r*.962),('opaque_sky_backing',.78,.06,r+.025)]:
  v=[]
  for d in [depth,depth+thickness]:
   for a in angles:v.append(xyz(uc+rad*math.cos(a),cy+rad*math.sin(a),d))
  f=[tuple(range(count-1,-1,-1)),tuple(range(count,2*count))]+[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
  mesh(name+'_'+suffix,v,f,'ref_glazing_cyan')
  if suffix=='opaque_sky_backing':proxy_convex(name+'_closed_backing',v,f,'Opaque closed end of deep cyan light well')
 WINDOWS.append({'name':name,'center':list(xyz(uc,cy,0)),'radius':r,'wall_thickness':.36,'reveal_depth':.74,'backing_far_depth':.84,'closed':True,'orientation':plane,'front_ring_extrusion_m':0.0,'reveal_material_role':'ref_lounge_plaster','sleeve_thickness_m':.025,'collision_sleeve_segments':16,'collision_sleeve_radial_tolerance_m':.018,'daylight_source_depth_m':.06,'glazing_depth_m':.70})
 # Preview area light outside the inner surface, preserving actual thick recess shadows.
 loc=xyz(uc,cy,.06);target=xyz(uc,cy,-3)
 add_area_light(name+'_soft_daylight',loc,target,160,(.64,.86,1),1.5)

def add_area_light(name,at,target,power,color,size):
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size
 ob=bpy.data.objects.new(name,data);SCENE.collection.objects.link(ob);ob.location=p(at);direction=Vector(p(target))-ob.location;ob.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
 fixture=name.replace('_soft_daylight','_cyan_glazing') if name.endswith('_soft_daylight') else name.replace('Connector_practical_','Connector_flush_light_') if name.startswith('Connector_practical_') else 'Room_continuous_low_roof'
 LIGHTS.append({'name':name,'fixture_object':fixture,'runtime_enabled':name.endswith('_soft_daylight') or name.startswith('Connector_practical_'),'type':'area_preview','native_type':'spot','color_space':'linear','native_energy':1.0,'native_energy_provisional':True,'emitter_radius':.005,'spot_angle_deg':80.0,'position':list(at),'target':list(target),'power_watts':power,'color':list(color),'size':size,'runtime_recommendation':'soft omni or baked light; do not treat Watts as Godot energy'})
 if not LIGHTS[-1]['runtime_enabled']:ob.hide_render=True
 return ob

window_centers=[-6.5,-3.1,.3,3.7];window_boundaries=[-8,-4.8,-1.4,2.0,8]
for j in range(4):porthole_panel('Right_porthole_%02d'%(j+1),'right',3.4,window_boundaries[j],window_boundaries[j+1],window_centers[j])
porthole_panel('Rear_porthole_05','rear',-8,-3.4,3.4,-1.15,.86,2.0)

# Continuous supported right-hand bench: convex strips follow a gently bowed front edge.
# Body occupies the same plan as the seat, with 10 cm physical rounded edge.
def inner_bench(z):return 1.05+.24*math.sin((z+7.65)/15.30*math.pi)
zs=[-7.65+i*(15.30/40) for i in range(41)]
outline=[(inner_bench(z),z) for z in zs]+[(3.4,7.65),(3.4,-7.65)]
v=[(x,y,z) for y in [.08,1.10] for x,z in outline];n=len(outline)
f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
bench=mesh('Continuous_curved_supported_bench',v,f,'ref_lounge_fabric',.10)
for j in range(len(zs)-1):
 a,b=zs[j:j+2];vv=[(x,y,z) for y in [.08,1.10] for x,z in [(inner_bench(a),a),(inner_bench(b),b),(3.4,b),(3.4,a)]]
 proxy_convex('Bench_supported_convex_%02d'%j,vv,FACES,'Supported bench volume; soft rendered edge differs by at most 0.10 m')
SUPPORT.append({'object':'Continuous_curved_supported_bench','support':'Pit_structural_floor','object_bottom_y':.08,'support_top_y':.08,'gap_m':0,'contact_region_xz':[1.05,3.4,-7.65,7.65],'top_y':1.10})
# Deliberately restrained fabric edge seam on the soft front rim, not tiled grout.
# Seam is modeled as an inset piping contour attached to the bench's edge.
def tube_polyline(name,points,r,role,sides=8):
 vv=[]
 for i,pt in enumerate(points):
  direction=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
  direction.normalize();u=direction.cross(Vector((0,1,0))).normalized();w=direction.cross(u).normalized()
  for j in range(sides):vv.append(tuple(Vector(pt)+r*(u*math.cos(j*math.tau/sides)+w*math.sin(j*math.tau/sides))))
 ff=[]
 for i in range(len(points)-1):
  for j in range(sides):ff.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
 ff += [tuple(range(sides-1,-1,-1)),tuple(range((len(points)-1)*sides,len(points)*sides))]
 return mesh(name,vv,ff,role,0,True)
tube_polyline('Bench_attached_soft_edge_piping',[(inner_bench(z)+.065,1.055,z) for z in zs],.009,'ref_lounge_fabric')

# Enclosed orthogonal corridor union. Building its boundary from occupied cells avoids
# closed walls at intersections and avoids doubled coplanar wall/floor seams.
RECTS=[(-1.5,1.5,-16,-9),(-8,1.5,-12,-9),(-8,-5,-12,7.8),(-16,-5,-1.5,1.5),(-8,-3.4,4.8,7.8)]
xs=sorted(set([r[k] for r in RECTS for k in [0,1]]));zz=sorted(set([r[k] for r in RECTS for k in [2,3]]))
occupied=set()
for ix in range(len(xs)-1):
 for iz in range(len(zz)-1):
  cx=(xs[ix]+xs[ix+1])/2;cz=(zz[iz]+zz[iz+1])/2
  if any(a<=cx<=b and c<=cz<=d for a,b,c,d in RECTS):occupied.add((ix,iz))
# Merge cell rectangles for floor and roof surfaces without duplicate coplanar faces.
cv=[];cf=[]
for ix,iz in sorted(occupied):
 a,b=xs[ix:ix+2];c,d=zz[iz:iz+2]
 for y,reverse in [(.52,False),(-.08,True),(3.52,True),(3.78,False)]:
  k=len(cv);cv.extend([(a,y,c),(b,y,c),(b,y,d),(a,y,d)]);cf.append(tuple(k+j for j in ([3,2,1,0] if reverse else [0,1,2,3])))
 proxy_box('Connector_floor_%s_%s'%(ix,iz),((a+b)/2,.22,(c+d)/2),(b-a,.60,d-c),'Continuous dry connector floor supported by foundation')
 proxy_box('Connector_roof_%s_%s'%(ix,iz),((a+b)/2,3.65,(c+d)/2),(b-a,.26,d-c),'Closed connector roof')
# Boundary edges (floor and roof close with actual 0.18 m exterior walls).
for ix,iz in sorted(occupied):
 a,b=xs[ix:ix+2];c,d=zz[iz:iz+2]
 edges=[((ix-1,iz),(a,c),(a,d)),((ix+1,iz),(b,c),(b,d)),((ix,iz-1),(a,c),(b,c)),((ix,iz+1),(a,d),(b,d))]
 for ei,(neighbor,start,end) in enumerate(edges):
  if neighbor in occupied:continue
  x1,z1=start;x2,z2=end
  # Real closed floor/roof thickness, including portal edges, not disconnected sheets.
  for low,high in [(-.08,.52),(3.52,3.78)]:
   k=len(cv);cv.extend([(x1,low,z1),(x2,low,z2),(x2,high,z2),(x1,high,z1)]);cf.append((k,k+1,k+2,k+3))
  north=abs(z1+16)<1e-5 and abs(z2+16)<1e-5
  west=abs(x1+16)<1e-5 and abs(x2+16)<1e-5
  room=abs(x1+3.4)<1e-5 and abs(x2+3.4)<1e-5 and z1>=4.8 and z2<=7.8
  if room:continue
  if north or west:
   box('Connector_portal_header_%s_%s_%s'%(ix,iz,ei),((x1+x2)/2+(.09 if west else 0),3.42,(z1+z2)/2+(.09 if north else 0)),(max(.18,abs(x2-x1)),.20,max(.18,abs(z2-z1))))
   continue
  outward=[(-.09,0),(.09,0),(0,-.09),(0,.09)][ei]
  box('Connector_boundary_%s_%s_%s'%(ix,iz,ei),((x1+x2)/2+outward[0],1.80,(z1+z2)/2+outward[1]),(max(.18,abs(x2-x1)),3.44,max(.18,abs(z2-z1))))
# Weld cell edges into two closed structural solids before UV/normals generation.
unique=[];lookup={};remap={}
for i,v in enumerate(cv):
 key=tuple(round(c,9) for c in v)
 if key not in lookup:lookup[key]=len(unique);unique.append(v)
 remap[i]=lookup[key]
cf=[tuple(remap[i] for i in face) for face in cf]
mesh('Closed_connector_floor_and_roof',unique,cf,'ref_lounge_plaster')
SUPPORT.append({'object':'Closed_connector_floor_and_roof','support':'Module_foundation','object_bottom_y':-.08,'support_top_y':-.08,'gap_m':0.0,'method':'The closed 0.60 m connector floor slab bears directly on the foundation; boundary walls support the closed 0.26 m roof.'})
# Outer inaccessible module limits sealed except the exact two agreed portals.
for axis,side in [('x',1),('z',1)]:
 box('Sealed_module_%s_plus'%axis,(side*15.9 if axis=='x' else 0,1.75,side*15.9 if axis=='z' else 0),(.2 if axis=='x' else 32,3.7,32 if axis=='x' else .2))
for axis in ['x','z']:
 for a,b in [(-16,-1.5),(1.5,16)]:
  box('Sealed_module_%s_minus'%axis,(-15.9 if axis=='x' else (a+b)/2,1.75,-15.9 if axis=='z' else (a+b)/2),(.2 if axis=='x' else b-a,3.7,b-a if axis=='x' else .2))
for side,center,normal in [('north',[0,.52,-16],[0,0,-1]),('west',[-16,.52,0],[-1,0,0])]:
 PORTS.append({'side':side,'center':center,'width':3.0,'height':2.8,'floor_y':.52,'opening_top_y':3.32,'normal':normal,'connected':True,'corridor_width_min':3.0,'corridor_floor_y':.52,'corridor_ceiling_y':3.52})

# Deterministic layered sphere settlement. Grid hashing keeps the contact test exact
# and bounded, not a rigid-body simulation. Three layers supply a deep visual fill.
GRID={};PIT_FLOOR=.08;pitch=.221

def cell(x,z):return (math.floor(x/.27),math.floor(z/.27))
def nearby(x,z):
 c=cell(x,z)
 for i in range(c[0]-1,c[0]+2):
  for j in range(c[1]-1,c[1]+2):
   for k in GRID.get((i,j),[]):yield BALLS[k]

def allowed_ball(x,z,r):
 if not (-3.29+r<=x<=inner_bench(z)-r-.015 and -7.63+r<=z<=4.67-r):return False
 # Safe, ball-free stair footprint and landing at the structural floor.
 if -2.53-r<x<-.77+r and z>3.37-r:return False
 return True
for layer in range(3):
 row=0;z=-7.50+layer*.045
 while z<4.55:
  x=-3.13+(row%2)*pitch/2+(pitch/2 if layer%2 else 0)
  while x<1.15:
   r=random.uniform(.096,.112);xx=x+random.uniform(-.008,.008);zzb=z+random.uniform(-.008,.008)
   if allowed_ball(xx,zzb,r):
    y=PIT_FLOOR+r;support_id='Pit_structural_floor';support_xyz=[xx,PIT_FLOOR,zzb]
    for other in nearby(xx,zzb):
     dx=xx-other['center'][0];dz=zzb-other['center'][2];rr=r+other['radius'];horizontal=dx*dx+dz*dz
     if horizontal<rr*rr:
      sy=other['center'][1]+math.sqrt(rr*rr-horizontal)
      if sy>y:
       y=sy;support_id=other['id'];dist=math.sqrt(horizontal+(y-other['center'][1])**2);t=r/dist
       support_xyz=[xx+(other['center'][0]-xx)*t,y+(other['center'][1]-y)*t,zzb+(other['center'][2]-zzb)*t]
    bid='ball_%04d'%len(BALLS)
    ball={'id':bid,'center':[xx,y,zzb],'radius':r,'material':'ref_ball_blue' if random.random()<.70 else 'ref_ball_ivory','layer':layer,'support':support_id,'support_contact':support_xyz,'support_gap_m':0.0}
    GRID.setdefault(cell(xx,zzb),[]).append(len(BALLS));BALLS.append(ball)
   x+=pitch
  row+=1;z+=pitch*math.sqrt(3)/2

# Bench-top balls are fixed accents, seated exactly on the actual cushion-free bench.
for x,z,r in [(1.50,-6.8,.108),(1.48,-2.3,.102),(2.73,1.48,.110),(1.50,4.8,.105),(2.86,6.75,.104),(1.70,-.92,.098)]:
 BALLS.append({'id':'bench_ball_%02d'%len(BALLS),'center':[x,1.10+r,z],'radius':r,'material':'ref_ball_ivory' if z>0 else 'ref_ball_blue','layer':'bench','support':'Continuous_curved_supported_bench','support_contact':[x,1.10,z],'support_gap_m':0.0})

# Pillows have a physically flat underside, softly bowed sides/top, and perimeter piping.
def rounded_rect(w,d,r,segments=10):
 pts=[]
 for cx,cz,start in [(w/2-r,d/2-r,0),(-w/2+r,d/2-r,90),(-w/2+r,-d/2+r,180),(w/2-r,-d/2+r,270)]:
  for j in range(segments):
   a=math.radians(start+j*90/segments);pts.append((cx+r*math.cos(a),cz+r*math.sin(a)))
 return pts

def pillow(name,x,z,w,d,bottom,yaw=0,support='bench',height=.29):
 pts=rounded_rect(w,d,min(.26,d*.45),12);count=len(pts);ca,sa=math.cos(yaw),math.sin(yaw)
 def rotate(px,pz):return (x+px*ca+pz*sa,z-px*sa+pz*ca)
 rings=[(0,.83),(.045,.97),(height*.48,1.0),(height*.82,.98),(height,.80)]
 verts=[]
 for h,s in rings:
  for px,pz in pts:
   xx,zz=rotate(px*s,pz*s);verts.append((xx,bottom+h,zz))
 faces=[tuple(range(count-1,-1,-1))]
 for j in range(len(rings)-1):
  for i in range(count):faces.append((j*count+i,j*count+(i+1)%count,(j+1)*count+(i+1)%count,(j+1)*count+i))
 verts.append((x,bottom+height+.018,z));apex=len(verts)-1
 for i in range(count):faces.append(((len(rings)-1)*count+i,(len(rings)-1)*count+(i+1)%count,apex))
 ob=mesh(name,verts,faces,'ref_cushion_coral',0,True)
 # Keep the underside flat even though the cushion surfaces are soft-shaded.
 ob.data.polygons[0].use_smooth=False
 seam=[]
 for px,pz in pts+[pts[0]]:
  xx,zz=rotate(px*.99,pz*.99);seam.append((xx,bottom+height*.48,zz))
 tube_polyline(name+'_attached_fabric_piping',seam,.006,'ref_cushion_coral')
 SUPPORT.append({'object':name,'support':support,'object_bottom_y':bottom,'support_top_y':bottom,'gap_m':0,'contact_point':[x,bottom,z],'method':'flat cushion underside rests on bench or measured maximum supporting ball top','static_decorative':True})
 return ob

for i,(x,z,w,d,yaw) in enumerate([(2.12,3.6,1.64,.82,.06),(2.16,2.75,1.35,.78,-.08),(2.2,.3,1.48,.77,-.05),(2.1,-3.5,1.46,.78,.10),(2.1,-6.3,1.52,.72,-.04)]):
 pillow('Bench_coral_cushion_%02d'%(i+1),x,z,w,d,1.10,yaw,'Continuous_curved_supported_bench',.30)
for i,(x,z,w,d,yaw) in enumerate([(-1.70,1.6,1.38,.78,-.13),(-2.25,-2.2,1.23,.70,.07),(-.28,-4.1,1.32,.73,-.08),(-2.12,-6.5,1.18,.72,.14)]):
 ca,sa=math.cos(yaw),math.sin(yaw)
 # Move at most to the local pile summit so the flat underside has a real central
 # contact and no neighboring sphere intersects the pillow's outer envelope.
 for iteration in range(8):
  candidates=[]
  for ball in BALLS:
   dx=ball['center'][0]-x;dz=ball['center'][2]-z
   xx=dx*ca-dz*sa;zzb=dx*sa+dz*ca
   if abs(xx)<w/2+ball['radius'] and abs(zzb)<d/2+ball['radius']:candidates.append(ball)
  supporting=max(candidates,key=lambda b:b['center'][1]+b['radius'])
  dx=supporting['center'][0]-x;dz=supporting['center'][2]-z
  xx=dx*ca-dz*sa;zzb=dx*sa+dz*ca
  if abs(xx)<w*.30 and abs(zzb)<d*.28:break
  x=supporting['center'][0];z=supporting['center'][2]
 bottom=supporting['center'][1]+supporting['radius']
 pillow('Pit_coral_cushion_%02d'%(i+1),x,z,w,d,bottom,yaw,supporting['id'],.24)
 SUPPORT[-1]['contact_point']=[supporting['center'][0],bottom,supporting['center'][2]]

# Two batched sphere meshes. Geometry is built once per material rather than thousands
# of live rigid bodies or object draw calls. Full instance metadata remains editable.
# UV spheres have metric arc-length UV0 and split seam UVs, with smooth normals.
def batch_balls(role):
 items=[b for b in BALLS if b['material']==role];vertices=[];faces=[];face_uvs=[];seg=12;rings=8
 for ball in items:
  cx,cy,cz=ball['center'];r=ball['radius'];base=len(vertices)
  vertices.append((cx,cy+r,cz))
  for j in range(1,rings):
   phi=math.pi*j/rings
   for i in range(seg):
    theta=math.tau*i/seg;vertices.append((cx+r*math.sin(phi)*math.cos(theta),cy+r*math.cos(phi),cz+r*math.sin(phi)*math.sin(theta)))
  south=len(vertices);vertices.append((cx,cy-r,cz))
  for i in range(seg):
   a=base+1+i;b=base+1+(i+1)%seg
   faces.append((base,a,b));face_uvs.append((((i+.5)/seg*math.tau*r,0),(i/seg*math.tau*r,math.pi*r/rings),((i+1)/seg*math.tau*r,math.pi*r/rings)))
  for j in range(rings-2):
   for i in range(seg):
    a=base+1+j*seg+i;b=base+1+j*seg+(i+1)%seg;c=b+seg;d=a+seg
    faces.append((a,d,c,b));face_uvs.append(((i/seg*math.tau*r,(j+1)/rings*math.pi*r),(i/seg*math.tau*r,(j+2)/rings*math.pi*r),((i+1)/seg*math.tau*r,(j+2)/rings*math.pi*r),((i+1)/seg*math.tau*r,(j+1)/rings*math.pi*r)))
  for i in range(seg):
   a=base+1+(rings-2)*seg+i;b=base+1+(rings-2)*seg+(i+1)%seg
   faces.append((a,south,b));face_uvs.append(((i/seg*math.tau*r,(rings-1)/rings*math.pi*r),((i+.5)/seg*math.tau*r,math.pi*r),((i+1)/seg*math.tau*r,(rings-1)/rings*math.pi*r)))
 ob=mesh('Static_ball_batch_'+role,vertices,faces,role,0,True)
 uv=ob.data.uv_layers.active
 # Normal-consistency may reverse face-loop order; derive spherical UV per loop instead.
 for poly in ob.data.polygons:
  vi=poly.vertices[0];idx=vi//(2+(rings-1)*seg);ball=items[idx];r=ball['radius'];center=Vector(p(ball['center']));us=[]
  for li in poly.loop_indices:
   co=ob.data.vertices[ob.data.loops[li].vertex_index].co-center
   xyz=g(co);u=(math.atan2(xyz[2],xyz[0])%math.tau)*r;v=math.acos(max(-1,min(1,xyz[1]/r)))*r;us.append([li,u,v])
  if max(a[1] for a in us)-min(a[1] for a in us)>math.pi*r:
   for a in us:
    if a[1]<math.pi*r:a[1]+=math.tau*r
  for li,u,v in us:uv.data[li].uv=(u,v)
 ob['ball_count']=len(items);ob['physics']='Static decorative spheres; structural pit floor collider only';ob['instance_metadata']='ball_lounge.geometry.json: ball_instances'
 return ob
for role in ['ref_ball_blue','ref_ball_ivory']:batch_balls(role)

# Corridor practical fixtures and a warm, indirect entrance fill.
# Mount tops meet the actual 3.52m ceiling. The entrance fixture is inside
# the room, clear of the 0.36m-thick west doorway header, not buried in it.
for i,at in enumerate([(-12,3.46,0),(-6.5,3.46,3.4),(-6.5,3.46,-6),(0,3.46,-13),(-2.8,3.46,6.3)]):
 box('Connector_light_mount_%02d'%i,(at[0],at[1]+.04,at[2]),(.49,.04,.49),'ref_fixture_metal',.025,False)
 box('Connector_flush_light_%02d'%i,at,(.42,.07,.42),'ref_glazing_cyan',.035,False)
 add_area_light('Connector_practical_%02d'%i,(at[0],at[1]-.05,at[2]),(at[0],.52,at[2]),70,(1,.78,.68),.6)
add_area_light('Warm_entrance_bounce',(-2,3.38,6.3),(-1,.4,-2),160,(1,.69,.59),2.3)
add_area_light('Soft_camera_fill',(-2.8,2.8,7.4),(0,1,-2),75,(.79,.88,1),2)

# Readable reference camera: long low composition, near balls at left, bench at right.
def camera(name,at,target,lens):
 data=bpy.data.cameras.new(name);data.lens=lens;data.sensor_width=36;data.clip_start=.06;data.clip_end=150
 ob=bpy.data.objects.new(name,data);SCENE.collection.objects.link(ob);ob.location=p(at);ob.rotation_euler=(Vector(p(target))-ob.location).to_track_quat('-Z','Y').to_euler()
 CAMERAS.append({'name':name,'position':list(at),'target':list(target),'fov_degrees':math.degrees(2*math.atan(36*(680/1000)/(2*lens))),'fov_axis':'vertical','lens_mm':lens,'reference_resolution':[1000,680]})
 return ob
SCENE.camera=camera('Reference4_composition',(-1.9,1.65,6.6),(1.6,1.35,-4.0),21.5)
camera('Dry_connector_inspection',(-6.5,1.9,6.15),(1,1.6,6.2),24)
world=bpy.data.worlds.new('Soft neutral exterior') if not bpy.data.worlds else bpy.data.worlds[0];SCENE.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.45,.58,.67,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.22
SCENE.render.engine='CYCLES';SCENE.cycles.samples=24;SCENE.cycles.use_denoising=False;SCENE.cycles.max_bounces=6;SCENE.cycles.diffuse_bounces=4
SCENE.render.resolution_x=1000;SCENE.render.resolution_y=680;SCENE.render.resolution_percentage=100;SCENE.render.image_settings.file_format='PNG'
SCENE.view_settings.view_transform='AgX';SCENE.view_settings.look='AgX - Medium High Contrast';SCENE.view_settings.exposure=.25

# Numerically audited support graph and non-overlap. Contacts are geometric, not a
# claim of dynamic stability. All balls are immobile decorative assets.
max_support_gap=0;min_clearance=1e9;violations=[];by_id={b['id']:b for b in BALLS}
for ball in BALLS:
 if ball['support'] in by_id:
  a=Vector(ball['center']);other=by_id[ball['support']];gap=(a-Vector(other['center'])).length-ball['radius']-other['radius']
 else:
  floor=1.10 if ball['layer']=='bench' else .08;gap=ball['center'][1]-ball['radius']-floor
 ball['support_gap_m']=round(gap,9);max_support_gap=max(max_support_gap,abs(gap))
 if abs(gap)>.00001:violations.append({'ball':ball['id'],'gap':gap})
# All overlapping horizontal neighbors are checked in the spatial index.
for b in BALLS:
 if b['layer']=='bench':continue
 for other in nearby(b['center'][0],b['center'][2]):
  if other['id']>=b['id']:continue
  clearance=(Vector(b['center'])-Vector(other['center'])).length-b['radius']-other['radius'];min_clearance=min(min_clearance,clearance)
  if clearance<-.00001:violations.append({'pair':[b['id'],other['id']],'penetration':-clearance})
# Triangulate closed caps explicitly so the saved source and GLB both carry valid tangents.
for ob in SCENE.objects:
 if ob.type=='MESH' and any(len(poly.vertices)>4 for poly in ob.data.polygons):
  bpy.context.view_layer.objects.active=ob
  mod=ob.modifiers.new('Deterministic cap triangulation','TRIANGULATE');mod.quad_method='FIXED';mod.ngon_method='BEAUTY'
  bpy.ops.object.modifier_apply(modifier=mod.name)

# UV/tangent availability audit is executed on the actual export meshes.
uv_audit={'meshes':0,'missing_uv':[],'nonfinite_uv':[],'tangent_failures':[]}
tris=0
for ob in SCENE.objects:
 if ob.type!='MESH':continue
 uv_audit['meshes']+=1;me=ob.data;me.calc_loop_triangles();tris+=len(me.loop_triangles)
 if not me.uv_layers:uv_audit['missing_uv'].append(ob.name);continue
 if any(not math.isfinite(c) for loop in me.uv_layers.active.data for c in loop.uv):uv_audit['nonfinite_uv'].append(ob.name)
 try:me.calc_tangents(uvmap=me.uv_layers.active.name);me.free_tangents()
 except Exception as exc:uv_audit['tangent_failures'].append({'mesh':ob.name,'error':str(exc)})
# Actual architectural support evidence kept separate from thousands of ball records.
summary={'seed':SEED,'sphere_count':len(BALLS),'pit_sphere_count':sum(b['layer']!='bench' for b in BALLS),'static_mesh_batches':2,'max_ball_support_gap_m':max_support_gap,'min_ball_pair_clearance_m':min_clearance,'support_violation_count':len(violations),'violations':violations[:20],'triangle_count':tris,'uv_tangent_audit':uv_audit,'visual_test':'Blender camera preview only after render; custom Godot visual test is reserved to the user.'}
DATA={'schema_version':1,'asset':'ball_lounge','units':'metres','coordinate_system':'Godot XYZ Y-up','source_blend':'res://tools/blender/reference_wing/lounge_sources/ball_lounge.blend','rebuild_script':'res://tools/blender/reference_wing/lounge_build.py','reference':'reference-4/1000074569.jpg','module_bounds':{'min':[-16,-.38,-16],'max':[16,3.84,16]},'bounds':{'min':[-16,-.38,-16],'max':[16,3.84,16]},'datums':{'doorway_floor_y':.52,'pit_floor_y':.08,'bench_top_y':1.10,'ceiling_y':3.52,'portal_clear_top_y':3.32},'spawn_local':[-1.65,.52,6.3],'camera_views':CAMERAS,'collision_coordinate_contract':'World-baked Godot XYZ; BOX center is absolute and local transform is identity; CONVEX vertices are absolute and local transform is identity. Do not apply center twice.','room_bounds':{'min':[-3.4,.08,-8],'max':[3.4,3.52,8]},'collision_proxies':COLLISIONS,'portal_contracts':PORTS,'steps':STEPS,'support_contacts':SUPPORT,'lights':LIGHTS,'water_regions':[],'material_roles':[{'name':role,'base_color':list(rgba),'roughness':rough,'metallic':.55 if role=='ref_fixture_metal' else 0.0,'emission_color':[.43,.78,.87] if role=='ref_glazing_cyan' else [0,0,0],'emission_strength':.25 if role=='ref_glazing_cyan' else 0.0} for role,(rgba,rough) in PALETTE.items()],'portholes':WINDOWS,'ball_instances':BALLS,'static_collision_policy':{'individual_ball_rigid_bodies':False,'ball_collision':False,'pit_floor_y':.08,'visual_surface_top_range':[min(b['center'][1]+b['radius'] for b in BALLS if b['layer']==2),max(b['center'][1]+b['radius'] for b in BALLS if b['layer']==2)],'player_behavior':'The player walks on the actual structural pit floor; decorative balls can visually surround feet/lower legs. No simulated ball movement, buoyancy, or sphere-top walking is claimed. Mandatory route remains on the dry apron and connectors.','bench_collision':'40 adjacent convex volume strips; rounded render edges within 0.10 m of conservative collider.'},'walkable_routes':[{'name':'north_to_lounge','floor_y':.52,'centerline':[[0,.52,-16],[0,.52,-10.5],[-6.5,.52,-10.5],[-6.5,.52,6.3],[-1.65,.52,6.3]],'minimum_clear_width':3.0,'clear_headroom':2.8},{'name':'west_to_lounge','floor_y':.52,'centerline':[[-16,.52,0],[-6.5,.52,0],[-6.5,.52,6.3],[-1.65,.52,6.3]],'minimum_clear_width':3.0,'clear_headroom':2.8}],'audit':summary}
DATA['fixture_mounts']=[{'fixture':'Connector_light_mount_%02d'%i,'diffuser':'Connector_flush_light_%02d'%i,'light':'Connector_practical_%02d'%i,'ceiling_underside_y':3.52,'mount_top_y':3.52,'point_to_diffuser_clearance_m':.015,'mounting':'Flush-supported underside; no floating bracket or point inside west doorway header'}for i in range(5)]
DATA['contact_boundary_repairs']={'method':'Exact local solid end termination; retained peers cover every removed volume. No epsilon offsets or broad Boolean operations.','targets':CONTACT_END_TRIMS,'hidden_porthole_contacts':'Unchanged: no authored-camera or known-route exposure in independent audit.'}
with open(os.path.join(OUT,'ball_lounge.geometry.json'),'w') as f:json.dump(DATA,f,indent=2)
with open(os.path.join(AUDIT,'geometry_audit.json'),'w') as f:json.dump(summary,f,indent=2)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC,'ball_lounge.blend'))
# Export only meshes: cameras and authoring light energy stay in the source .blend,
# runtime lighting is set by the integrating scene using the explicit sidecar.
bpy.ops.object.select_all(action='DESELECT')
for ob in SCENE.objects:
 if ob.type=='MESH':ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'ball_lounge.glb'),export_format='GLB',use_selection=True,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_yup=True,export_extras=True,export_cameras=False,export_lights=False,export_apply=True)
print('LOUNGE_BUILD_COMPLETE',json.dumps(summary))
if violations or uv_audit['missing_uv'] or uv_audit['nonfinite_uv'] or uv_audit['tangent_failures']:raise RuntimeError('Geometry support or UV/tangent audit failed')
