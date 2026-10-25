"""Original Blender-authored dry descending gallery based on user reference 5.
Rebuild: blender -b -t 4 --python tools/blender/reference_wing/stair_gallery/build_stair_gallery.py
Optional -- --render enables an explicitly labeled CPU Cycles composition preview.
All authored coordinates and JSON contracts use Godot Y-up, metres. Blender stores Z-up.
The runtime owns ceramic texture/shader binding: exported UV0 is exactly 1 UV/metre.
"""
import bpy, bmesh, math, os, sys, json, random, hashlib
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from collections import Counter
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'))
SOURCE=os.path.join(ROOT,'tools/blender/reference_wing/stair_gallery/source')
OUT=os.path.join(ROOT,'assets/models/reference_wing')
QA=os.path.join(ROOT,'output/reference_wing/stair')
for d in [SOURCE,OUT,QA]:os.makedirs(d,exist_ok=True)
open(os.path.join(SOURCE,'.gdignore'),'w').write('')
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
random.seed(50074)
C={'schema':'poolcore-reference-geometry-v1','id':'stair_gallery','name':'Dry Descending Stair Gallery','reference':'reference-5/1000074570.jpg','generator':'tools/blender/reference_wing/stair_gallery/build_stair_gallery.py','editable_source':'tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend','glb':'assets/models/reference_wing/stair_gallery.glb','coordinate_system':'Godot Y-up metres; Blender glTF export_yup=True','cell_size':32.0,'deck_top':.52,'upper_floor_y':4.68,'ceiling':11.32,'interior_ceiling':11.32,'water_rects':[],'basin_rects':[],'water_meshes':[],'dry_only':True,'spawn_local':[1.4,4.76,10.8],'spawn_facing':[0,0,-1],'collision_boxes':[],'collision_convex':[],'support_contacts':[],'raycast_contract':[],'stairs':[],'fixtures':[],'plants':[],'boundaries':[],'uv_metres_per_unit':1.0,'tile_pitch_metres':.1,'materials_runtime':['ref_tile_pearl','ref_tile_pearl_ref5_crown','ref_tile_teal','ref_tile_dry','ref_grout','ref_dark_foliage','ref_fixture_metal','ref_fixture_emission'],'validation_limits':'Blender CPU geometry and optional Cycles composition preview only. Not a Godot, Windows, NVIDIA or player-controller visual validation.'}
F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
M={}; visible=[]; proxies=[]
def p(v):return(v[0],-v[2],v[1])
def g(v):return(v[0],v[2],-v[1])
def rnd(v):return[round(float(x),6) for x in v]
def role(name,color,rough,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 m['runtime_role']=name;m['uv_metres_per_unit']=1.0;m['tile_pitch_metres']=.1
 M[name]=m;return m,bs
for name,color,rough,metal in [('ref_tile_pearl',(.66,.72,.64),.19,0),('ref_tile_pearl_ref5_crown',(.66,.72,.64),.075,0),('ref_tile_teal',(.32,.49,.44),.18,0),('ref_tile_dry',(.66,.72,.64),.26,0),('ref_grout',(.09,.13,.10),.86,0),('ref_dark_foliage',(.018,.034,.018),.72,0),('ref_fixture_metal',(.30,.34,.30),.24,.82),('ref_fixture_emission',(.92,1,.83),.27,0)]:
 m,bs=role(name,color,rough,metal)
 if name.startswith('ref_tile'):
  nd=m.node_tree.nodes;lk=m.node_tree.links
  uv=nd.new('ShaderNodeTexCoord');br=nd.new('ShaderNodeTexBrick');br.offset=0;br.offset_frequency=1
  br.inputs['Color1'].default_value=(*color,1);br.inputs['Color2'].default_value=(*(x*.95 for x in color),1);br.inputs['Mortar'].default_value=(.17,.22,.18,1)
  br.inputs['Scale'].default_value=1;br.inputs['Mortar Size'].default_value=.00115;br.inputs['Mortar Smooth'].default_value=.0002;br.inputs['Brick Width'].default_value=.1;br.inputs['Row Height'].default_value=.1
  lk.new(uv.outputs['UV'],br.inputs['Vector']);lk.new(br.outputs['Color'],bs.inputs['Base Color'])
  bump=nd.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.55;bump.inputs['Distance'].default_value=.0012;bump.invert=True;lk.new(br.outputs['Fac'],bump.inputs['Height']);lk.new(bump.outputs['Normal'],bs.inputs['Normal'])
  bs.inputs['Coat Weight'].default_value=.32;bs.inputs['Coat Roughness'].default_value=.075
 if name=='ref_fixture_emission':bs.inputs['Emission Color'].default_value=(.89,1,.78,1);bs.inputs['Emission Strength'].default_value=2

def uv_metric(me):
 for old in list(me.uv_layers):me.uv_layers.remove(old)
 uv=me.uv_layers.new(name='UVMap')
 for face in me.polygons:
  n=face.normal.normalized()
  if abs(n.z)>.9:
   u=Vector((1,0,0));u=(u-n*u.dot(n)).normalized();v=n.cross(u)
   if v.y<0:v=-v
  else:
   u=Vector((0,0,1)).cross(n).normalized()
   if (abs(u.x)>=abs(u.y) and u.x<0) or (abs(u.x)<abs(u.y) and u.y<0):u=-u
   v=n.cross(u)
   if v.z<0:v=-v
  for li in face.loop_indices:
   co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co.dot(u),co.dot(v))

def mesh(name,verts,faces,mat='ref_tile_pearl',proxy=False,kind=None,bevel=0):
 me=bpy.data.meshes.new(name);me.from_pydata([p(v) for v in verts],[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
 ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);me.materials.append(M[mat]);ob['runtime_role']=mat
 if proxy:
  ob.hide_render=True;ob['collision_proxy']=kind;ob['proxy_kind']=kind;proxies.append(ob)
 else:
  visible.append(ob)
  if bevel:
   bpy.context.view_layer.objects.active=ob;mod=ob.modifiers.new('Ceramic edge radius 4 mm','BEVEL');mod.width=bevel;mod.segments=2;mod.limit_method='ANGLE';mod.angle_limit=.5;mod.affect='EDGES';mod.use_clamp_overlap=True
   bpy.ops.object.modifier_apply(modifier=mod.name)
   ob['ceramic_edge_bevel_metres']=bevel
 uv_metric(ob.data);ob['uv_metres_per_unit']=1.0
 return ob

def boxverts(lo,hi):
 x,y,z=lo;X,Y,Z=hi
 return[(x,y,z),(X,y,z),(X,Y,z),(x,Y,z),(x,y,Z),(X,y,Z),(X,Y,Z),(x,Y,Z)]
def proxy_box(name,lo,hi):
 ob=mesh('COLLISION_'+name,boxverts(lo,hi),F,proxy=True,kind='BOX')
 C['collision_boxes'].append({'name':ob.name,'proxy_kind':'BOX','position':rnd(lo),'size':rnd([hi[i]-lo[i] for i in range(3)]),'center':rnd([(hi[i]+lo[i])/2 for i in range(3)]),'rotation':[0,0,0]});return ob

def box(name,lo,hi,mat='ref_tile_pearl',col=True,bevel=0):
 ob=mesh(name,boxverts(lo,hi),F,mat,bevel=bevel)
 if col:proxy_box(name,lo,hi)
 return ob

def extrude_x(name,profile,x0,x1,mat='ref_tile_pearl',col=True,bevel=0):
 # profile is a closed polygon in Godot z/y; no repeated final point.
 verts=[(x,y,z) for x in [x0,x1] for z,y in profile];n=len(profile)
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 ob=mesh(name,verts,faces,mat,bevel=bevel)
 if col:proxy_convex(name,verts,faces,'CONVEX_WEDGE')
 return ob

def proxy_convex(name,verts,faces,kind):
 ob=mesh('COLLISION_'+name,verts,faces,proxy=True,kind=kind)
 C['collision_convex'].append({'name':ob.name,'proxy_kind':kind,'vertices_godot':[rnd(v) for v in verts],'faces':[list(f) for f in faces],'convex':True});return ob

def extrude_z(name,profile,z0,z1,mat='ref_tile_pearl',col=True,bevel=0,kind='CONVEX_WEDGE'):
 verts=[(x,y,z) for z in [z0,z1] for x,y in profile];n=len(profile)
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 ob=mesh(name,verts,faces,mat,bevel=bevel)
 if col:proxy_convex(name,verts,faces,kind)
 return ob

def extrude_y(name,profile,y0,y1,mat='ref_tile_pearl',col=True):
 verts=[(x,y,z) for y in [y0,y1] for x,z in profile];n=len(profile)
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 ob=mesh(name,verts,faces,mat)
 if col:proxy_convex(name,verts,faces,'CONVEX_WEDGE')
 return ob

def contact(above,below,point,direction=(0,-1,0),distance=.1):
 C['support_contacts'].append({'supported':above,'bearing':below,'contact_point_godot':rnd(point)})
 C['raycast_contract'].append({'id':'bearing_'+above,'origin':rnd([point[i]-direction[i]*.04 for i in range(3)]),'direction':list(direction),'max_distance':distance,'expected_position':rnd(point),'expected_surface_object':below,'tolerance_metres':.006})

def expected_ray(name,origin,direction,point,target,maxdist=20):
 C['raycast_contract'].append({'id':name,'origin':rnd(origin),'direction':list(direction),'max_distance':maxdist,'expected_position':rnd(point),'expected_surface_object':target,'tolerance_metres':.006})

# A continuous watertight stepped solid, not a stack with overlapping visible faces.
profile=[(.68,.12),(14.5,.12),(14.5,4.68),(9,4.68)]
for i in range(26):
 z0=9-i*.32;z1=z0-.32;y=4.68-(i+1)*.16
 profile.extend([(z0,y),(z1,y)])
stair=extrude_x('StairFlightAndUpperLanding',profile,-.1,2.9,mat='ref_tile_dry',col=False,bevel=.004)
proxy_box('UpperLanding',(-.1,.12,9),(2.9,4.68,14.5))
for i in range(26):
 z0=9-i*.32;z1=z0-.32;y=4.68-(i+1)*.16
 name='StairTread_%02d'%(i+1);proxy_box(name,(-.1,.12,z1),(2.9,y,z0))
 C['stairs'].append({'index':i+1,'riser_height':.16,'tread_depth':.32,'clear_width':3.,'z_min':round(z1,6),'z_max':round(z0,6),'top_y':round(y,6),'collision':'COLLISION_'+name,'visible_object':stair.name})
 expected_ray('tread_%02d'%(i+1),(1.4,y+.25,(z0+z1)/2),(0,-1,0),(1.4,y,(z0+z1)/2),stair.name,1)
box('LowerLanding',(-.1,.12,-3.6),(2.9,.52,.68),'ref_tile_dry',bevel=0)
expected_ray('spawn_support',(1.4,5.1,10.8),(0,-1,0),(1.4,4.68,10.8),stair.name,1)
expected_ray('lower_landing',(1.4,1,-2),(0,-1,0),(1.4,.52,-2),'LowerLanding',1)

# A truly supported sloping planter fill; parapet has no floating ramp or air gap.
def floorline(z):return .52 if z<=.68 else 4.68 if z>=9 else .52+(z-.68)*.5
parapet=extrude_x('ContinuousSlopingParapet',[(.68,.12),(14.5,.12),(14.5,5.66),(9,5.66),(.68,1.5)],-.38,-.1,col=False,bevel=.004)
planter_segments=[('Slope',.68,9,.52,4.68),('Upper',9,14.5,4.68,4.68)]
for suffix,z0,z1,y0,y1 in planter_segments:
 para=extrude_x('Parapet'+suffix,[(z0,.12),(z1,.12),(z1,y1+.98),(z0,y0+.98)],-.38,-.1,bevel=0)
 visible.remove(para);bpy.data.objects.remove(para,do_unlink=True)
 fill=extrude_x('PlanterStructure'+suffix,[(z0,.12),(z1,.12),(z1,y1+.62),(z0,y0+.62)],-4.2,-.38,'ref_tile_teal')
 soil=extrude_x('PlanterSoil'+suffix,[(z0,y0+.62),(z1,y1+.62),(z1,y1+.68),(z0,y0+.68)],-4.2,-.38,'ref_grout',col=False)
 zm=(z0+z1)/2;ym=floorline(zm)
 contact(soil.name,fill.name,(-1.8,ym+.62,zm),distance=.12)
 contact('ContinuousSlopingParapet','MainFoundation',(-.24,.12,zm))
 contact(fill.name,'MainFoundation',(-1.8,.12,zm))
# Shell slabs meet at exact structural planes, with sufficient physical thickness.
box('MainFoundation',(-4.5,-.18,-4),(3.2,.12,14.8),bevel=0)
contact('StairFlightAndUpperLanding','MainFoundation',(1.4,.12,5))
contact('LowerLanding','MainFoundation',(1.4,.12,-2))
box('EastWall',(2.9,.12,-4),(3.2,11.32,14.8))
box('WestRecessWall',(-4.5,.12,-4),(-4.2,11.32,14.8))
box('SouthClosedWall',(-4.2,.12,14.5),(2.9,11.32,14.8))
box('PlanterEndReturn',(-4.2,.12,.38),(-.1,11.32,.68))
box('LowerLandingWestWall',(-.4,.12,-3.6),(-.1,11.32,.38))
contact('PlanterEndReturn','MainFoundation',(-2,.12,.53))
contact('LowerLandingWestWall','MainFoundation',(-.25,.12,-2))
box('MainCeiling',(-4.5,11.32,-4),(3.2,11.62,14.8))
contact('MainCeiling','EastWall',(3.05,11.32,5))
contact('MainCeiling','WestRecessWall',(-4.35,11.32,5))
contact('EastWall','MainFoundation',(3.05,.12,5))
contact('WestRecessWall','MainFoundation',(-4.35,.12,5))
contact('SouthClosedWall','MainFoundation',(1.4,.12,14.65))

# Small 2.1 m arch, including supported jambs, annular voussoirs and real spandrels.
cx=1.4;spring=2.07;ri=.55;ro=.75;n=24;zfront=-3.6;zback=-4.0
box('NorthFarWallLeft',(-4.2,.12,zback),(cx-ro,11.32,zfront))
box('NorthFarWallRight',(cx+ro,.12,zback),(2.9,11.32,zfront))
box('NorthFarWallCrown',(cx-ro,spring+ro,zback),(cx+ro,11.32,zfront))
box('ArchLeftJamb',(cx-ro,.52,zback),(cx-ri,spring,zfront),'ref_tile_teal',bevel=0)
box('ArchRightJamb',(cx+ri,.52,zback),(cx+ro,spring,zfront),'ref_tile_teal',bevel=0)
# Full threshold beneath all arch and adjacent wall feet, terminating at lower landing.
box('ArchThreshold',(-4.2,.12,zback),(2.9,.52,zfront),'ref_tile_dry')
contact('ArchLeftJamb','ArchThreshold',(cx-(ri+ro)/2,.52,-3.8))
contact('ArchRightJamb','ArchThreshold',(cx+(ri+ro)/2,.52,-3.8))
rv=[]
for z in [zback,zfront]:
 for r in [ri,ro]:
  for i in range(n+1):
   a=math.pi*i/n;rv.append((cx+r*math.cos(a),spring+r*math.sin(a),z))
L=n+1;rf=[]
for i in range(n):
 rf.extend([(i,i+1,L+i+1,L+i),(2*L+i,3*L+i,3*L+i+1,2*L+i+1),(i,2*L+i,2*L+i+1,i+1),(L+i,L+i+1,3*L+i+1,3*L+i)])
rf.extend([(0,L,3*L,2*L),(n,2*L+n,3*L+n,L+n)])
mesh('ContinuousArchedReveal',rv,rf,'ref_tile_teal',bevel=.004)
for i in range(n):
 a=math.pi*i/n;b=math.pi*(i+1)/n
 poly=[(cx+ri*math.cos(a),spring+ri*math.sin(a)),(cx+ro*math.cos(a),spring+ro*math.sin(a)),(cx+ro*math.cos(b),spring+ro*math.sin(b)),(cx+ri*math.cos(b),spring+ri*math.sin(b))]
 vs=[(x,y,z) for z in [zback,zfront] for x,y in poly];fs=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
 proxy_convex('ArchVoussoir_%02d'%i,vs,fs,'CONVEX_ARCH_WEDGE')
 # Spandrel strips follow outer arch precisely, without a bounding box across the hole.
 x0,y0=poly[1];x1,y1=poly[2]
 pp=[(x0,y0),(x1,y1),(x1,spring+ro),(x0,spring+ro)]
 unique=[]
 for v in pp:
  if not unique or (Vector(v)-Vector(unique[-1])).length>1e-7:unique.append(v)
 if len(unique)>1 and (Vector(unique[0])-Vector(unique[-1])).length<1e-7:unique.pop()
 extrude_z('ArchSpandrel_%02d'%i,unique,zback,zfront,bevel=0)
contact('ContinuousArchedReveal','ArchLeftJamb',(cx-(ri+ro)/2,spring,-3.8))
contact('ContinuousArchedReveal','ArchRightJamb',(cx+(ri+ro)/2,spring,-3.8))
C['door']={'center_x':cx,'front_z':zfront,'back_z':zback,'floor_y':.52,'clear_width':1.1,'clear_height':2.1,'spring_y':spring,'crown_y':2.62,'facets':n,'continuous_ring_object':'ContinuousArchedReveal','collision_strategy':'Exact convex segmented annular wedges and exact spandrel wedges; never an AABB across the opening','clearance_samples':[]}
# Lower corridor reaches the north module boundary; other boundaries are closed.
# The hidden connector shifts physically from x=1.4 to the common grid centre x=0.
def route_center(z):return 1.4*(z+16)/12
extrude_y('ContinuationFoundation',[(-1.8,-16),(1.8,-16),(3.2,-4),(-.4,-4)],-.18,.12)
extrude_y('NorthContinuationFloor',[(-1.5,-16),(1.5,-16),(2.9,-4),(-.1,-4)],.12,.52,'ref_tile_dry')
extrude_y('NorthContinuationLeft',[(-1.8,-16),(-1.5,-16),(-.1,-4),(-.4,-4)],.12,3.32)
extrude_y('NorthContinuationRight',[(1.5,-16),(1.8,-16),(3.2,-4),(2.9,-4)],.12,3.32)
extrude_y('NorthContinuationRoof',[(-1.8,-16),(1.8,-16),(3.2,-4),(-.4,-4)],3.32,3.62)
for name,x in [('NorthContinuationFloor',.7),('NorthContinuationLeft',-.95),('NorthContinuationRight',2.35)]:contact(name,'ContinuationFoundation',(x,.12,-10))
contact('NorthContinuationRoof','NorthContinuationLeft',(-.95,3.32,-10))
contact('NorthContinuationRoof','NorthContinuationRight',(2.35,3.32,-10))
C['connector_clear_path']={'centerline':[[1.4,.52,-4],[.7,.52,-10],[0,.52,-16]],'north_portal_width':3.,'clear_height':2.8,'minimum_perpendicular_width':round(3/math.sqrt(1+(1.4/12)**2),6),'swept_player_radius':.34,'swept_player_height':1.8,'samples':[]}
for j in range(25):
 z=-4.1-j*11.8/24;x=route_center(z)
 expected_ray('connector_floor_%02d'%j,(x,1,z),(0,-1,0),(x,.52,z),'NorthContinuationFloor',1)
 for side in [-1,0,1]:
  for h in [.15,1.,1.8]:
   z2=max(-15.99,z-.45);sample={'from':[x+side*.34,.52+h,z],'to':[route_center(z2)+side*.34,.52+h,z2],'expected':'unobstructed'}
   C['connector_clear_path']['samples'].append(sample)
C['portals']=[{'side':'north','center':[0,.52,-16],'clear_width':3.0,'clear_height':2.8,'floor_y':.52,'normal':[0,0,-1],'connection_type':'dry'}]
C['boundaries']=[{'side':'north','state':'one dry portal only','portal_center':[0,.52,-16]},{'side':'south','state':'closed','wall_z':14.5},{'side':'west','state':'closed','wall_x':-4.2},{'side':'east','state':'closed','wall_x':2.9}]
expected_ray('north_route_floor',(route_center(-15.8),1,-15.8),(0,-1,0),(route_center(-15.8),.52,-15.8),'NorthContinuationFloor',1)
for y in [.72,1.2,1.8,2.2]:
 C['door']['clearance_samples'].append({'from':[1.4,y,-3.2],'to':[1.4,y,-4.4],'expected':'unobstructed'})
# Two parallel banks of slim fixtures physically fastened to the ceiling.
for row,x in enumerate([.62,2.14]):
 for j,z in enumerate([-2.15,-.05,2.05,4.15,6.25,8.35,10.45,12.55]):
  name='CeilingStrip_R%d_%02d'%(row,j)
  box(name+'_Housing',(x-.072,11.23,z-.81),(x+.072,11.32,z+.81),'ref_fixture_metal',col=False)
  box(name+'_Lens',(x-.049,11.205,z-.765),(x+.049,11.23,z+.765),'ref_fixture_emission',col=False)
  contact(name+'_Housing','MainCeiling',(x,11.32,z),direction=(0,1,0))
  contact(name+'_Lens',name+'_Housing',(x,11.23,z),direction=(0,1,0))
  C['fixtures'].append({'name':name,'position':[x,11.19,z],'direction':[0,-1,0],'color':[.89,1,.78],'color_space':'linear','native_type':'spot','emitter_radius':.005,'spot_angle_deg':80.,'energy':4.,'preview_area_watts':24.,'preview_emission_strength':2.,'range':12.,'size':[.098,1.53],'attachment_surface':'MainCeiling','attachment_y':11.32})
  li=bpy.data.lights.new('PREVIEW_'+name,'AREA');li.energy=24;li.color=(.89,1,.78);li.shape='RECTANGLE';li.size=.12;li.size_y=1.53
  ob=bpy.data.objects.new(li.name,li);bpy.context.collection.objects.link(ob);ob.location=p((x,11.18,z));ob.rotation_euler=(0,0,0)
# One dim continuation fixture, hidden by the small arch from the main camera.
box('ContinuationStrip_Housing',(.64,3.26,-10.6),(.76,3.32,-9.4),'ref_fixture_metal',col=False)
box('ContinuationStrip_Lens',(.66,3.24,-10.56),(.74,3.26,-9.44),'ref_fixture_emission',col=False)
C['fixtures'].append({'name':'ContinuationStrip','position':[.7,3.2,-10.0],'direction':[0,-1,0],'color':[.89,1,.78],'color_space':'linear','native_type':'spot','emitter_radius':.005,'spot_angle_deg':80.,'energy':2.,'range':5.,'size':[.08,1.12],'attachment_surface':'NorthContinuationRoof','attachment_y':3.32})
# Native light semantics are explicit; source preview areas remain unchanged.
C['lights']=C['fixtures']
li=bpy.data.lights.new('PREVIEW_Continuation','AREA');li.energy=15;li.color=(.89,1,.78);li.size=1
ob=bpy.data.objects.new(li.name,li);bpy.context.collection.objects.link(ob);ob.location=p((.7,3.2,-10))

# Original low-poly foliage: each closed stem enters the supported planter soil.
def branch_mesh(name,base,top,r):
 verts=[];axis=(Vector(top)-Vector(base)).normalized();u=axis.cross(Vector((0,0,1)))
 if u.length<.01:u=axis.cross(Vector((1,0,0)))
 u.normalize();v=axis.cross(u).normalized()
 for center in [Vector(base),Vector(top)]:
  for i in range(5):verts.append(tuple(center+r*(u*math.cos(i*2*math.pi/5)+v*math.sin(i*2*math.pi/5))))
 faces=[tuple(range(4,-1,-1)),tuple(range(5,10))]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
 return mesh(name,verts,faces,'ref_dark_foliage')
def leaf_mesh(name,base,tip,width):
 a=Vector(base);b=Vector(tip);axis=(b-a).normalized();u=axis.cross(Vector((0,1,0)))
 if u.length<.01:u=axis.cross(Vector((1,0,0)))
 u.normalize();mid=a.lerp(b,.49);normal=axis.cross(u).normalized()
 verts=[tuple(a),tuple(b),tuple(mid+u*width),tuple(mid-u*width),tuple(mid+normal*.0015),tuple(mid-normal*.0015)]
 faces=[(0,2,4),(2,1,4),(1,3,4),(3,0,4),(2,0,5),(1,2,5),(3,1,5),(0,3,5)]
 return mesh(name,verts,faces,'ref_dark_foliage')
for i in range(145):
 x=random.uniform(-3.95,-.60);z=random.uniform(.92,14.2);y=floorline(z)+.68
 h=random.uniform(.24,.57);top=(x+random.uniform(-.08,.08),y+h,z+random.uniform(-.08,.08));stem=branch_mesh('RootedPlant_%03d'%i,(x,y-.025,z),top,.009)
 for j in range(5):
  f=.24+j*.15;a=Vector((x,y,z)).lerp(Vector(top),f);ang=j*2.399+random.random();le=random.uniform(.16,.30)
  b=a+Vector((math.cos(ang)*le,random.uniform(.03,.11),math.sin(ang)*le));leaf_mesh('Plant_%03d_Leaf%d'%(i,j),a,b,le*.30)
 soilname='PlanterSoil'+('Lower' if z<=.68 else 'Upper' if z>=9 else 'Slope')
 expected_ray('plant_root_%03d'%i,(x,y+.1,z),(0,-1,0),(x,y,z),soilname,.2)
 C['plants'].append({'stem':stem.name,'root':[round(x,5),round(y-.025,5),round(z,5)],'soil_top_y':round(y,5),'root_penetration_metres':.025,'height':round(h,5)})
# Dense original leaf sprays. No polygonal ellipsoids or rock-like hedge crowns.
for i in range(104):
 z=1.0+(i%52)*.252;x=-.72-(i//52)*.51+random.uniform(-.07,.07);y=floorline(z)+.68
 h=random.uniform(.45,.64);top=(x+random.uniform(-.05,.05),y+h,z+random.uniform(-.05,.05))
 stem=branch_mesh('HedgeRoot_%03d'%i,(x,y-.025,z),top,.011)
 for j in range(13):
  f=.20+j*.058;root=Vector((x,y,z));a=root.lerp(Vector(top),f);ang=j*2.399+random.uniform(-.4,.4)+i*.39
  le=random.uniform(.19,.35);b=a+Vector((math.cos(ang)*le,random.uniform(.025,.11),math.sin(ang)*le))
  leaf_mesh('Hedge_%03d_Leaf%02d'%(i,j),a,b,le*random.uniform(.23,.33))
 soilname='PlanterSoil'+('Upper' if z>=9 else 'Slope')
 expected_ray('hedge_root_%03d'%i,(x,y+.1,z),(0,-1,0),(x,y,z),soilname,.2)
 C['plants'].append({'stem':stem.name,'root':[round(x,5),round(y-.025,5),round(z,5)],'soil_top_y':round(y,5),'root_penetration_metres':.025,'height':round(h+.11,5),'supported_leaf_count':13,'leaf_attachment':'Each leaf base intersects its own rooted stem; no detached crowns.'})
# Bind the shared reference glaze candidate, retaining exact runtime role names.
# Dedicated reviewed wall profile; no geometry/UV edit or dry/ceiling rebinding.
sys.path.insert(0,os.path.dirname(__file__))
from stair_crown_bindings import bind_ref5_crown_vertical_walls
C['ref5_crown_binding']=bind_ref5_crown_vertical_walls()
sys.path.insert(0,os.path.join(ROOT,'tools/materials/reference_wing'))
from blender_materials import attach_named_materials
C['blender_glaze_binding']=attach_named_materials()
C['blender_glaze_helper']='tools/materials/reference_wing/blender_materials.py'
for im in bpy.data.images:
 if im.filepath and os.path.isfile(bpy.path.abspath(im.filepath)):
  im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath),start=SOURCE)
# Useful reference camera, not a claim of final Godot rendering.
world=bpy.data.worlds.new('PreviewNeutralWorld');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.13,.17,.14,1);world.node_tree.nodes['Background'].inputs[1].default_value=.075;scene.world=world
camd=bpy.data.cameras.new('REFERENCE_5_Composition');cam=bpy.data.objects.new(camd.name,camd);bpy.context.collection.objects.link(cam)
cam.location=p((1.92,6.28,10.8));target=Vector(p((.95,4.55,-3.5)));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camd.lens=22.0;camd.sensor_width=36;scene.camera=cam
C['recommended_views']=[{'from':[1.92,6.28,10.8],'toward':[.95,4.55,-3.5],'blender_focal_length_mm':22.0}]
sys.path.insert(0,os.path.dirname(__file__))
from stair_diagnostic_camera import add_diagnostic_camera
_diagnostic_camera,_diagnostic_view=add_diagnostic_camera();C['diagnostic_views']=[_diagnostic_view]
scene['diagnostic_views']=json.dumps(C['diagnostic_views'])
scene['room_contract']=json.dumps({k:v for k,v in C.items() if k not in ['collision_boxes','collision_convex','raycast_contract','plants']})
scene['authoring']='Original Blender-authored reference-5 dry stair gallery. No pool, wet surfaces or circular lounge.'
scene['preview_scope']='CPU Cycles geometry/composition preview only. Runtime material binding and target NVIDIA validation are separate.'

# Real mesh-based CPU raycast checks; expected targets are checked independently to
# avoid a supported object occluding its own bearing ray.
def bvh(ob):
 verts=[ob.matrix_world@v.co for v in ob.data.vertices];faces=[list(f.vertices) for f in ob.data.polygons]
 return BVHTree.FromPolygons(verts,faces,all_triangles=False)
checks={'schema':'poolcore-blender-geometry-checks-v1','engine':'Blender 4.3.2 CPU bmesh/BVHTree','not_tested':['Godot renderer','Windows/NVIDIA','player controller walking'],'mesh_checks':[],'raycasts':[],'door_clearance':[],'connector_clearance':[],'failures':[]}
bvhs={ob.name:bvh(ob) for ob in visible}
for ob in visible+proxies:
 bm=bmesh.new();bm.from_mesh(ob.data)
 nonmanifold=sum(1 for e in bm.edges if not e.is_manifold);zeroarea=sum(1 for f in bm.faces if f.calc_area()<1e-10);volume=bm.calc_volume(signed=True);bm.free()
 uv=ob.data.uv_layers.active;uv_error=0
 for face in ob.data.polygons:
  lis=list(face.loop_indices)
  for a,b in zip(lis,lis[1:]+lis[:1]):
   la=ob.data.loops[a].vertex_index;lb=ob.data.loops[b].vertex_index
   dl=(ob.data.vertices[la].co-ob.data.vertices[lb].co).length;du=(uv.data[a].uv-uv.data[b].uv).length
   uv_error=max(uv_error,abs(dl-du))
 ck={'object':ob.name,'nonmanifold_edges':nonmanifold,'zero_area_faces':zeroarea,'signed_volume_m3':round(volume,8),'maximum_metric_uv_error_m':round(uv_error,7)}
 checks['mesh_checks'].append(ck)
 if nonmanifold or zeroarea or volume<=0 or uv_error>1e-4:checks['failures'].append(ck)
for rc in C['raycast_contract']:
 target=bvhs.get(rc['expected_surface_object']);hit=None
 if target:hit=target.ray_cast(Vector(p(rc['origin'])),Vector(p(rc['direction'])),rc['max_distance'])
 got=rnd(g(hit[0])) if hit and hit[0] is not None else None
 error=(Vector(g(hit[0]))-Vector(rc['expected_position'])).length if got else None
 record={'id':rc['id'],'target':rc['expected_surface_object'],'expected':rc['expected_position'],'actual':got,'error_m':round(error,7) if error is not None else None,'pass':error is not None and error<=rc['tolerance_metres']}
 checks['raycasts'].append(record)
 if not record['pass']:checks['failures'].append(record)
for sample in C['door']['clearance_samples']:
 origin=Vector(p(sample['from']));delta=Vector(p(sample['to']))-origin;blocked=[]
 for name,tree in bvhs.items():
  hit=tree.ray_cast(origin,delta.normalized(),delta.length)
  if hit[0] is not None:blocked.append(name)
 record={**sample,'blocking_objects':blocked,'pass':not blocked};checks['door_clearance'].append(record)
 if blocked:checks['failures'].append(record)
for sample in C['connector_clear_path']['samples']:
 origin=Vector(p(sample['from']));delta=Vector(p(sample['to']))-origin;blocked=[]
 for name,tree in bvhs.items():
  hit=tree.ray_cast(origin,delta.normalized(),delta.length)
  if hit[0] is not None:blocked.append(name)
 record={**sample,'blocking_objects':blocked,'pass':not blocked};checks['connector_clearance'].append(record)
 if blocked:checks['failures'].append(record)
for contact_record in C['support_contacts']:
 point=contact_record['contact_point_godot'];bearing=bvhs[contact_record['bearing']]
 hit=bearing.find_nearest(Vector(p(point)),.05)
 actual=rnd(g(hit[0])) if hit[0] is not None else None
 supported=bvhs[contact_record['supported']].find_nearest(Vector(p(point)),.05)
 supported_actual=rnd(g(supported[0])) if supported[0] is not None else None
 contact_record.update({'supported_contact_position':supported_actual,'bearing_contact_position':actual,'supported_surface_y':supported_actual[1] if supported_actual else None,'bearing_surface_y':actual[1] if actual else None,'measured_gap_metres':round((Vector(supported_actual)-Vector(actual)).length,7) if supported_actual and actual else None,'measurement':'Independent nearest-point BVH measurements on BOTH actual supported and bearing meshes; target ray also tested'})
# Convex proxy proof: every vertex lies on or behind every outward face plane.
checks['convex_proxy_checks']=[]
for ob in proxies:
 if ob['proxy_kind']=='BOX':continue
 maxoutside=0
 for face in ob.data.polygons:
  q=ob.data.vertices[face.vertices[0]].co;nrm=face.normal
  maxoutside=max(maxoutside,max(nrm.dot(v.co-q) for v in ob.data.vertices))
 rec={'object':ob.name,'maximum_outside_plane_m':round(maxoutside,8),'pass':maxoutside<1e-5};checks['convex_proxy_checks'].append(rec)
 if not rec['pass']:checks['failures'].append(rec)
coords=[g(v.co) for ob in visible for v in ob.data.vertices]
C['bounds_min']=rnd([min(v[a] for v in coords) for a in range(3)]);C['bounds_max']=rnd([max(v[a] for v in coords) for a in range(3)])
C['visible_triangles']=sum(sum(len(f.vertices)-2 for f in ob.data.polygons) for ob in visible)
C['visible_objects']=len(visible);C['proxy_count']=len(proxies);C['collision_proxy_kinds']=dict(Counter(o['proxy_kind'] for o in proxies))
checks['summary']={'visible_meshes':len(visible),'collision_proxies':len(proxies),'visible_triangles':C['visible_triangles'],'closed_positive_volume_meshes':sum(1 for m in checks['mesh_checks'] if m['nonmanifold_edges']==0 and m['signed_volume_m3']>0),'raycasts_passed':sum(r['pass'] for r in checks['raycasts']),'raycasts_total':len(checks['raycasts']),'door_rays_passed':sum(r['pass'] for r in checks['door_clearance']),'connector_clearance_passed':sum(r['pass'] for r in checks['connector_clearance']),'connector_clearance_total':len(checks['connector_clearance']),'failure_count':len(checks['failures'])}
json.dump(checks,open(os.path.join(QA,'stair_geometry_checks.json'),'w'),indent=2)
# Source saves original independently named editable objects, material preview nodes,
# exact collision proxies, camera and preview lighting.
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=64;scene.cycles.use_denoising=False
scene.render.resolution_x=750;scene.render.resolution_y=750;scene.render.resolution_percentage=100
scene.render.use_stamp=True;scene.render.use_stamp_note=True;scene.render.stamp_note_text='CPU CYCLES | SHARED GLAZE CANDIDATE | NOT GODOT / NVIDIA VALIDATION';scene.render.use_stamp_time=False;scene.render.use_stamp_date=False;scene.render.use_stamp_frame=False;scene.render.use_stamp_camera=False;scene.render.use_stamp_scene=False;scene.render.use_stamp_filename=False;scene.render.use_stamp_render_time=False;scene.render.stamp_font_size=13;scene.render.stamp_foreground=(1,1,1,1);scene.render.stamp_background=(0,0,0,1);scene.render.use_stamp_labels=False;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=-1.0
frame=cam.data.view_frame(scene=scene)
vertical_angles=[math.atan2(v.y,-v.z) for v in frame];horizontal_angles=[math.atan2(v.x,-v.z) for v in frame]
C['recommended_views'][0].update({'fov_degrees':math.degrees(max(vertical_angles)-min(vertical_angles)),'fov_axis':'vertical','horizontal_fov_degrees':math.degrees(max(horizontal_angles)-min(horizontal_angles)),'reference_resolution':[scene.render.resolution_x,scene.render.resolution_y],'reference_pixel_aspect':[scene.render.pixel_aspect_x,scene.render.pixel_aspect_y],'blender_sensor_fit':cam.data.sensor_fit,'blender_view_frame_local':[[float(a) for a in v] for v in frame],'fov_derivation':'atan2 extents of camera.data.view_frame(scene=scene) with actual saved render aspect; not a 16:9 assumption'})
scene['room_contract']=json.dumps({k:v for k,v in C.items() if k not in ['collision_boxes','collision_convex','raycast_contract','plants']})
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,'stair_gallery.blend'))
# Export untextured role placeholders. The source retains procedural ceramic previews;
# runtime supplies its approved, sharper .1 m ceramic shader and optional filters.
for m in M.values():
 bs=m.node_tree.nodes.get('Principled BSDF')
 for link in list(m.node_tree.links):
  if link.to_node==bs:m.node_tree.links.remove(link)
 if m.name.startswith('ref_tile_'):
  def linear(c):return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
  bs.inputs['Base Color'].default_value=tuple(linear(c) for c in m.diffuse_color[:3])+(1,)
  bs.inputs['Metallic'].default_value=0
  bs.inputs['Roughness'].default_value=.26 if m.name=='ref_tile_dry' else .075
# Runtime mesh batching by material, exact proxies left separately inspectable.
for name in M:
 group=[ob for ob in list(scene.objects) if ob.type=='MESH' and not ob.name.startswith('COLLISION_') and ob.data.materials[0].name==name]
 if len(group)>1:
  bpy.ops.object.select_all(action='DESELECT')
  for ob in group:ob.select_set(True)
  bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join();group[0].name='StairGallery_'+name
bpy.ops.object.select_all(action='DESELECT')
for ob in scene.objects:
 if ob.type=='MESH':
  bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update();uv_metric(ob.data)
  ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'stair_gallery.glb'),export_format='GLB',use_selection=True,export_yup=True,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False)
C['glb_bytes']=os.path.getsize(os.path.join(OUT,'stair_gallery.glb'));C['glb_sha256']=hashlib.sha256(open(os.path.join(OUT,'stair_gallery.glb'),'rb').read()).hexdigest();C['blender_geometry_check_summary']=checks['summary']
C['water_regions']=[]
C['steps']=[{**t,'footprint':{'x_min':-.1,'x_max':2.9,'z_min':t['z_min'],'z_max':t['z_max']}} for t in C['stairs']]
C['lights']=C['fixtures']
C['portal_contracts']=[{'side':'north','center':[0,.52,-16],'width':3.0,'clear_height':2.8,'threshold_y':.52,'normal':[0,0,-1]}]
identity={'origin':[0,0,0],'basis':[[1,0,0],[0,1,0],[0,0,1]]}
C['collision_proxies']=[{'name':b['name'],'type':'BOX','proxy_kind':'BOX','bounds_min':b['position'],'bounds_max':rnd([b['position'][i]+b['size'][i] for i in range(3)]),'center':b['center'],'size':b['size'],'transform':identity} for b in C['collision_boxes']]+[{'name':b['name'],'type':'CONVEX','proxy_kind':b['proxy_kind'],'vertices':b['vertices_godot'],'faces':b['faces'],'transform':identity} for b in C['collision_convex']]
json.dump(C,open(os.path.join(OUT,'stair_gallery.geometry.json'),'w'),indent=2)
print('STAIR_GALLERY_RESULT',json.dumps(checks['summary']),flush=True)
if checks['failures']:raise RuntimeError('Geometry verification failed; see output/reference_wing/stair/stair_geometry_checks.json')
if '--render' in sys.argv:
 bpy.ops.wm.open_mainfile(filepath=os.path.join(SOURCE,'stair_gallery.blend'))
 scene=bpy.context.scene;scene.render.filepath=os.path.join(QA,'stair_cycles_square_preview.png');bpy.ops.render.render(write_still=True)
