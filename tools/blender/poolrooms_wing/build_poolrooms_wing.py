"""Three integrated PoolCore rooms using selected Cenji FREE architectural meshes.
Blender 4.3.2 CPU authoring; no raw kit is copied into this project.
Usage: blender -b -t 2 --python tools/blender/poolrooms_wing/build_poolrooms_wing.py -- --source-dir /path/to/Cenji/GLB
Editable assembled .blend files retain named component objects and existing project
PBR texture links. Runtime exports batch visible meshes by material, retaining exact
BOX-only COLLISION_ proxies. Source water geometry is never imported.
"""
import bpy, bmesh, math, os, sys, json, hashlib, argparse
from mathutils import Vector, Matrix
from collections import Counter
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../..'))
OUT=os.path.join(ROOT,'assets/models/poolrooms_wing')
SRC=os.path.join(ROOT,'tools/blender/poolrooms_wing/source')
PROV=os.path.join(ROOT,'source_provenance/poolrooms_wing/geometry.json')
P=argparse.ArgumentParser();P.add_argument('--source-dir',default=os.path.join(os.path.dirname(ROOT),'pool-assets-acquisition/Cenji_BackroomsLevel37_Poolrooms_FREE/GLB'));P.add_argument('--only');args=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
for d in [OUT,SRC,os.path.dirname(PROV)]:os.makedirs(d,exist_ok=True)
open(os.path.join(SRC,'.gdignore'),'a').close()
F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
DECK=.52;BOTTOM=-.22;SOURCE_FLOOR=-.72;WATER=.32
TEX=os.path.join(ROOT,'assets/materials/art_pass/textures')
ROLES={
'art_pass_tile_pearl':('tile_pearl_albedo_2k.png','tile_normal_gl_2k.png','tile_pearl_orm_2k.png',.8,(.78,.83,.79,1),.56),
'art_pass_tile_blue':('tile_blue_albedo_2k.png','tile_normal_gl_2k.png','tile_blue_orm_2k.png',.8,(.43,.66,.71,1),.38),
'art_pass_plaster_oyster':('plaster_oyster_albedo_2k.png','plaster_normal_gl_2k.png','plaster_orm_2k.png',2.,(.86,.87,.81,1),.85),
'art_pass_coping_ivory':('coping_ivory_albedo_1k.png','coping_normal_gl_1k.png','coping_orm_1k.png',1.,(.82,.84,.77,1),.45),
'art_pass_steel_brushed':('steel_brushed_albedo_512.png','steel_normal_gl_512.png','steel_orm_512.png',.25,(.45,.53,.53,1),.3),
'art_pass_joint':(None,None,None,1,(.16,.20,.18,1),.85),
'art_pass_inlet_dark':(None,None,None,1,(.035,.05,.045,1),.72),
'lamp':(None,None,None,1,(.86,.88,.72,1),.4),
'collision':(None,None,None,1,(1,0,1,1),1)}
M={};DATA={};G={};COUNTS=Counter();CACHE={};serial=0

def p(v):return (v[0],-v[2],v[1])
def g(v):return (v[0],v[2],-v[1])
def rnd(v):return [round(float(x),6) for x in v]
def reset(name):
 global M,G,COUNTS,CACHE,serial
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for c in list(bpy.data.collections):
  if c.users==0:bpy.data.collections.remove(c)
 for m in list(bpy.data.materials):bpy.data.materials.remove(m)
 M={};CACHE={};COUNTS=Counter();serial=0
 G={'name':name,'source_instances':[],'collision_boxes':[],'water_steps':[],'basin_steps':[],'fixtures':[], 'omitted_high_collisions':[],
    'architecture_bearings':[], 'architecture_connections':[], 'water_obstacles':[], 'portal_jamb_bearings':[]}
 for role,(al,nor,orm,repeat,color,rough) in ROLES.items():
  m=bpy.data.materials.new(role);m.use_nodes=True;m.diffuse_color=color
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=color;bs.inputs['Roughness'].default_value=rough
  if role=='art_pass_steel_brushed':bs.inputs['Metallic'].default_value=.85
  if al:
   nd=m.node_tree.nodes;lk=m.node_tree.links
   uv=nd.new('ShaderNodeTexCoord');sc=nd.new('ShaderNodeVectorMath');sc.operation='SCALE';sc.inputs['Scale'].default_value=1/repeat;lk.new(uv.outputs['UV'],sc.inputs[0])
   im=[]
   for i,fn in enumerate([al,nor,orm]):
    t=nd.new('ShaderNodeTexImage');t.image=bpy.data.images.load(os.path.join(TEX,fn),check_existing=True)
    if i:t.image.colorspace_settings.name='Non-Color'
    lk.new(sc.outputs[0],t.inputs['Vector']);im.append(t)
   lk.new(im[0].outputs['Color'],bs.inputs['Base Color'])
   nm=nd.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.85;lk.new(im[1].outputs['Color'],nm.inputs['Color']);lk.new(nm.outputs[0],bs.inputs['Normal'])
   sep=nd.new('ShaderNodeSeparateColor');lk.new(im[2].outputs['Color'],sep.inputs[0]);lk.new(sep.outputs[1],bs.inputs['Roughness']);lk.new(sep.outputs[2],bs.inputs['Metallic'])
  M[role]=m
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
 bpy.context.preferences.filepaths.save_version=0
 bpy.context.scene['authoring']='Original integrated PoolCore composition incorporating selected Cenji FREE modular geometry; not an asset-pack redistribution.'
 bpy.context.scene['uv_contract']='UV0 = 1 unit/metre; existing art_pass ceramic texture repeats .8m with eight 10cm tiles.'

def uv_metric(me):
 # An orthonormal tangent frame on every flat polygon gives exact 1 UV/metre,
 # including the imported curved-wall facets and arch intrados. Coplanar faces
 # use the same projected world basis, so tile phase is continuous on planes.
 for layer in list(me.uv_layers):me.uv_layers.remove(layer)
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

def mesh(name,verts,faces,role='art_pass_plaster_oyster',proxy=False,weld=False):
 me=bpy.data.meshes.new(name);me.from_pydata([p(v) for v in verts],[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me)
 if weld:bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
 bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(me);bm.free();me.update()
 ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);me.materials.append(M['collision' if proxy else role]);uv_metric(me)
 ob['uv_metres_per_unit']=1.;ob['source_role']=role
 if proxy:ob.hide_render=True;ob['collision_proxy']='BOX'
 return ob

def box(name,c,s,role='art_pass_plaster_oyster',col=True,water=False):
 global serial
 serial+=1;name=f'{name}_{serial:03d}';x,y,z=c;a,b,d=[v/2 for v in s]
 v=[(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
 ob=mesh(name,v,F,role)
 if col:proxy(name,c,s)
 if water:G['water_steps'].append({'position':rnd([c[i]-s[i]/2 for i in range(3)]),'size':rnd(s),'name':name})
 return ob

def proxy(name,c,s):
 x,y,z=c;a,b,d=[v/2 for v in s]
 v=[(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
 mesh('COLLISION_'+name,v,F,proxy=True)
 G['collision_boxes'].append({'name':'COLLISION_'+name,'position':rnd([c[i]-s[i]/2 for i in range(3)]),'size':rnd(s)})

def at_transform(v,at,yaw=0):
 x,y,z=v;c=math.cos(yaw);s=math.sin(yaw);return (at[0]+x*c+z*s,at[1]+y,at[2]-x*s+z*c)

def tbox(name,c,s,at,yaw=0,role='art_pass_plaster_oyster',col=True):
 cc=at_transform(c,at,yaw);ss=(s[2],s[1],s[0]) if abs(math.sin(yaw))>.5 else s
 return box(name,cc,ss,role,col)

def imported(name,fn,mapfn,role='art_pass_tile_pearl',clip_floor=False):
 path=os.path.join(args.source_dir,fn)
 if fn not in CACHE:
  before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=path)
  obs=list(set(bpy.context.scene.objects)-before);arr=[]
  for ob in obs:
   if ob.type=='MESH':
    coords=[g(ob.matrix_world@v.co) for v in ob.data.vertices]
    faces=[tuple(f.vertices) for f in ob.data.polygons]
    matidx=[f.material_index for f in ob.data.polygons];names=[m.name for m in ob.data.materials]
    arr.append((coords,faces,matidx,names))
  for ob in obs:bpy.data.objects.remove(ob,do_unlink=True)
  CACHE[fn]=arr
 result=[]
 for j,(coords,faces,mi,matnames) in enumerate(CACHE[fn]):
  ob=mesh(name+(f'_{j}' if j else ''),[mapfn(v) for v in coords],faces,role,weld=True)
  if clip_floor:
   bm=bmesh.new();bm.from_mesh(ob.data)
   bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
   geom=list(bm.verts)+list(bm.edges)+list(bm.faces)
   bmesh.ops.bisect_plane(bm,geom=geom,dist=0.00001,plane_co=Vector((0,0,DECK)),plane_no=Vector((0,0,1)),clear_inner=True,clear_outer=False)
   boundary=[e for e in bm.edges if e.is_boundary and all(abs(v.co.z-DECK)<.0001 for v in e.verts)]
   if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=0)
   bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update();uv_metric(ob.data)
  if 'Light' in fn:
   ob.data.materials.clear();ob.data.materials.append(M['art_pass_steel_brushed']);ob.data.materials.append(M['lamp'])
   for poly,idx in zip(ob.data.polygons,mi):poly.material_index=1 if 'Diffused' in matnames[idx] else 0
  ob['licensed_component']=fn;ob['source_author']='Cenji';ob['integration']='Transformed, re-UVd and rematerialed within complete original room.'
  result.append(ob)
 COUNTS[fn]+=1;G['source_instances'].append({'object':name,'source_file':fn,'vertices':sum(len(o.data.vertices) for o in result)})
 return result

def arch(name,center,yaw=0,width=6,spring=3.3,crown=4.65,depth=.42,
         bearing_y=DECK,cap_y=None,basin_footings=False):
 # Each support uses its real receiving surface, not the global dry-deck datum.
 # Source arch09 opening: x .5..3.5, spring1.2, crown2.7, top3.0.
 # Separate lower-shaft and upper-spandrel maps preserve the clear opening.
 sx=width/4;sy=(crown-spring)/1.5;top=cap_y if cap_y is not None else spring+1.8*sy
 def mapper(v):
  x,y,z=v
  if y<=1.2:y2=bearing_y+(y+1.5)/2.7*(spring-bearing_y)
  elif cap_y is not None and y>2.7:y2=crown+(y-2.7)/.3*(top-crown)
  else:y2=spring+(y-1.2)*sy
  return at_transform(((x-2)*sx,y2,(z+.1)*depth/.2),center,yaw)
 imported(name,'MOD_09_Archway_Wide.glb',mapper)
 for side in [-1,1]:
  footing=None
  if basin_footings:
   # A narrow concrete bearing embedded 10cm into the actual basin slab.
   # Project outwards only: the 4m central dry route remains untouched.
   fc=at_transform((side*(1.75*sx+.07),(BOTTOM-.10+bearing_y)/2,0),center,yaw)
   fs=(.5*sx+.14,bearing_y-(BOTTOM-.10),depth+.28)
   if abs(math.sin(yaw))>.5:fs=(fs[2],fs[1],fs[0])
   footing=box(name+'_SubmergedFooting_'+str(side),fc,fs,'art_pass_tile_blue',water=True)
   G['water_obstacles'].append({'object':footing.name,'collision':'COLLISION_'+footing.name,
    'position':rnd([fc[i]-fs[i]/2 for i in range(3)]),'size':rnd(fs),
    'role':'submerged structural footing; bathymetric ledge, not water surface'})
  cc=at_transform((side*1.75*sx,(top+bearing_y)/2,0),center,yaw)
  ss=(depth,top-bearing_y,.5*sx) if abs(math.sin(yaw))>.5 else (.5*sx,top-bearing_y,depth)
  pn=name+'_Pier_'+str(side);proxy(pn,cc,ss)
  if basin_footings:
   # The same exact shaft envelope drives physics and source-water occupancy.
   record={'name':'COLLISION_'+pn,'position':rnd([cc[i]-ss[i]/2 for i in range(3)]),'size':rnd(ss)}
   G['water_steps'].append(record)
   G['water_obstacles'].append(dict(record,object=name,collision='COLLISION_'+pn,role='solid pier crossing waterline'))
  G['architecture_bearings'].append({'object':name,'side':side,'pier_collision':'COLLISION_'+pn,
   'bearing_y':round(center[1]+bearing_y,6),'receiving_floor_y':round(center[1]+(BOTTOM if basin_footings else DECK),6),
   'receiving_surface':footing.name if footing else 'DryPerimeterDeck',
   'footing_embedded_metres':.10 if basin_footings else 0.0,
   'pier_foot_center':rnd(at_transform((side*1.75*sx,bearing_y,0),center,yaw)),
   'roof_bearing_y':round(center[1]+top,6)})
 cc=at_transform((0,(top+crown+.03)/2,0),center,yaw);ss=(depth,top-crown-.03,width) if abs(math.sin(yaw))>.5 else (width,top-crown-.03,depth)
 proxy(name+'_HighLintel',cc,ss)
 G['omitted_high_collisions'].append({'object':name,'minimum_curved_underside_y':spring,'reason':'Curved intrados above player jump/head envelope; box piers and high lintel retained, no trimesh.'})
 return top

def floor(wet):
 box('CommonFoundation',(0,-.97,0),(32,.50,32),'art_pass_tile_blue')
 xs=sorted(set([-12,12]+[v for r in wet for v in [r[0],r[0]+r[2]]]))
 zs=sorted(set([-12,12]+[v for r in wet for v in [r[1],r[1]+r[3]]]))
 for i in range(len(xs)-1):
  for j in range(len(zs)-1):
   x0,x1=xs[i:i+2];z0,z1=zs[j:j+2];x=(x0+x1)/2;z=(z0+z1)/2
   if any(r[0]<x<r[0]+r[2] and r[1]<z<r[1]+r[3] for r in wet):continue
   box('DryPerimeterDeck',(x,-.10,z),(x1-x0,1.24,z1-z0),'art_pass_tile_pearl')
 for i,(x,z,w,d) in enumerate(wet):box('BasinBottom'+str(i),(x+w/2,-.47,z+d/2),(w,.50,d),'art_pass_tile_blue',water=True)
 for sx in [-1,1]:
  for sz in [-1,1]:
   box('OuterApronNS',(sx*10,-.10,sz*14),(12,1.24,4),'art_pass_tile_pearl')
   box('OuterApronEW',(sx*14,-.10,sz*8),(4,1.24,8),'art_pass_tile_pearl')
 for side in range(4):
  for i in range(7):
   top=DECK-(i+1)*.155;d=12+(i+.5)*.5
   c=(0,(-.72+top)/2,d) if side%2==0 else (d,(-.72+top)/2,0)
   c=tuple(-a if k in [0,2] and side>=2 else a for k,a in enumerate(c));s=(8,top+.72,.5) if side%2==0 else (.5,top+.72,8)
   box('CommonEntryStep',c,s,'art_pass_tile_pearl',water=True)


def subtract_intervals(a,b,gap):
 if gap is None:return [(a,b)]
 lo,hi=gap;return [(l,r) for l,r in [(a,min(b,lo)),(max(a,hi),b)] if r-l>.001]

def basin_details(rect,stairs_end,stairs_x):
 x,z,w,d=rect;width=2.;gap=(stairs_x-width/2,stairs_x+width/2)
 for zz,label in [(z,'north'),(z+d,'south')]:
  for lo,hi in subtract_intervals(x-.14,x+w+.14,gap if label==stairs_end else None):
   box('PoolCoping',( (lo+hi)/2,.532,zz),(hi-lo,.024,.28),'art_pass_coping_ivory')
 for xx in [x,x+w]:box('PoolCoping',(xx,.532,z+d/2),(.28,.024,d-.28),'art_pass_coping_ivory')
 # Four treads and the basin floor produce five equal 14.8cm rises.
 for i in range(4):
  top=DECK-(i+1)*.148;zz=z+(i+.5)*.5 if stairs_end=='north' else z+d-(i+.5)*.5
  c=(stairs_x,(BOTTOM+top)/2,zz);s=(width,top-BOTTOM,.5)
  ob=box('ShallowBasinStair',c,s,'art_pass_tile_blue',water=True)
  G['basin_steps'].append({'name':ob.name,'position':rnd([c[k]-s[k]/2 for k in range(3)]),'size':rnd(s),'riser':.148,'tread':.5,'width':2.})
 # Restrained submerged return inlets, not water meshes or glowing panels.
 for frac in [.25,.75]:box('BasinReturnInlet',(x+w-.009,.02,z+d*frac),(.018,.12,.32),'art_pass_inlet_dark',False)


def shell(height):
 # Boundary ownership matches Expanded: north and west own the shared wall.
 for ofs in [-10,10]:
  box('OuterNorth',(ofs,2.44,-16),(12,6.32,.60))
  box('OuterWest',(-16,2.44,ofs),(.60,6.32,12))
 box('OuterNorthHeader',(0,5.50,-16),(8,.20,.60))
 box('OuterWestHeader',(-16,5.50,0),(.60,.20,8))
 for side in range(4):
  yaw=side*math.pi/2
  for sx in [-1,1]:
   tbox('InnerPearlDado',(sx*7,1.25,-11.8),(9.6,1.46,.40),(0,0,0),yaw,'art_pass_tile_pearl')
   tbox('InnerOysterPlaster',(sx*7,(height+1.98)/2,-11.8),(9.6,height-1.98,.40),(0,0,0),yaw)
   # The rear 75mm lip crosses the deck edge onto the first entry tread.
   # Seat the entire jamb at that tread; its dry-side base embeds into deck.
   jamb_bottom=DECK-.155;jamb_top=3.72
   jamb=tbox('PortalJamb',(sx*2.3,(jamb_top+jamb_bottom)/2,-11.8),(.20,jamb_top-jamb_bottom,.55),(0,0,0),yaw,'art_pass_coping_ivory')
   G['portal_jamb_bearings'].append({'object':jamb.name,'collision':'COLLISION_'+jamb.name,
    'side':side,'jamb_side':sx,'bottom_y':jamb_bottom,'top_y':jamb_top,
    'first_tread_y':jamb_bottom,'dry_deck_embed_metres':.155,
    'outboard_lip_metres':.075,'tread_contact_probe':rnd(at_transform((sx*2.3,jamb_bottom,-12.04),(0,0,0),yaw))})
  tbox('InnerPortalHeader',(0,(height+3.72)/2,-11.8),(4.4,height-3.72,.40),(0,0,0),yaw)
  # Transverse vestibule soffit closes the height transition without a light card.
  tbox('VestibuleTransition',(0,(5.40+height)/2,-12.1),(8,5.40-height,.40),(0,0,0),yaw)
  G['architecture_connections'].append({'role':'vestibule soffit to inner header and apron roof',
   'side':side,'header_overlap_metres':.10,'bottom_y':height,'top_y':5.40})
 for x in [-14,14]:box('ApronRoof',(x,5.50,0),(4,.20,32))
 for z in [-14,14]:box('ApronRoof',(0,5.50,z),(24,.20,4))


def roof_with_openings(height,holes):
 xs=sorted(set([-12,12]+[v for r in holes for v in [r[0],r[0]+r[2]]]))
 zs=sorted(set([-12,12]+[v for r in holes for v in [r[1],r[1]+r[3]]]))
 for a,b in zip(xs,xs[1:]):
  for c,d in zip(zs,zs[1:]):
   x=(a+b)/2;z=(c+d)/2
   if any(r[0]<x<r[0]+r[2] and r[1]<z<r[1]+r[3] for r in holes):continue
   box('SolidRoofNotLightPanel',(x,height+.11,z),(b-a,.22,d-c))
 for x,z,w,d in holes:
  for zz in [z,z+d]:box('RealSkylightReveal',(x+w/2,height+.16,zz),(w,.32,.14),'art_pass_coping_ivory')
  for xx in [x,x+w]:box('RealSkylightReveal',(xx,height+.16,z+d/2),(.14,.32,d),'art_pass_coping_ivory')
  if w>3:
   for t in [.33,.67]:box('SkylightSlenderMullion',(x+w*t,height+.30,z+d/2),(.055,.06,d),'art_pass_steel_brushed',False)
 G['skylight_openings']=[{'rect':r,'underside_y':height,'open_to_sky':True} for r in holes]


def wall_lamp(name,at,yaw=0,width=.7,power=38.0,range_m=None):
 def mapper(v):return at_transform(((v[0]-.25)*(width/.5),v[1]-.125,v[2]+.025),at,yaw)
 imported(name,'PRP_06_WallLight.glb',mapper,'art_pass_steel_brushed')
 # Godot fixture receiver is 10cm in front of the physical diffuser.
 pos=at_transform((0,0,.18),at,yaw)
 record={'position':rnd(pos),'color':'edf0df','power':power,'power_scale':1.0,'alive':True,'flicker':False}
 if range_m is not None:record['range']=float(range_m)
 G['fixtures'].append(record)


def bench(name,at,yaw=0):
 imported(name,'PRP_08_TiledBench.glb',lambda v:at_transform((v[0]-1,v[1]*.75,-v[2]-.45),at,yaw),'art_pass_tile_pearl')
 # Seat and two pedestals, rather than a single invisible cuboid to the floor.
 c=at_transform((0,.43,0),at,yaw);s=(.9,.11,2) if abs(math.sin(yaw))>.5 else (2,.11,.9);proxy(name+'Seat',c,s)
 for x in [-.7,.7]:
  c=at_transform((x,.20,0),at,yaw);s=(.60,.40,.24) if abs(math.sin(yaw))>.5 else (.24,.40,.60);proxy(name+'Foot'+str(x),c,s)


def curved_alcove():
 # Actual imported Cenji half-circle wall forms a seated south alcove.
 imported('CenjiHalfCurveRestAlcove','MOD_49_Wall_CurvedHalf_4m.glb',lambda v:at_transform((v[0]-2,v[1]+DECK,v[2]),(-5,0,9.05),math.pi),clip_floor=True)
 # Small exact axis-aligned boxes approximate its circular centreline. The
 # maximum corner excess is <7cm; this alcove is away from required dry routes.
 for i in range(32):
  a=math.pi*i/32;b=math.pi*(i+1)/32
  pts=[(-5+2*math.cos(t),9.05+2*math.sin(t)) for t in [a,b]]
  x0=min(v[0] for v in pts)-.095;x1=max(v[0] for v in pts)+.095;z0=min(v[1] for v in pts)-.095;z1=max(v[1] for v in pts)+.095
  proxy('AlcoveCurveBand'+str(i),((x0+x1)/2,2.02,(z0+z1)/2),(x1-x0,3,z1-z0))
 bench('CenjiAlcoveBench',(-5,DECK,9.75),0)


def vault_surface():
 # Original continuous shallow barrel joins imported Cenji ribs into one gallery.
 n=40;verts=[]
 for i in range(n+1):
  a=math.pi*i/n
  for thick in [0,.20]:
   for z in [-11.8,11.8]:verts.append(((2+thick)*math.cos(a),3.50+(.95+thick)*math.sin(a),z))
 faces=[]
 for i in range(n):
  a=i*4;b=a+4;faces.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)])
 faces.extend([(0,1,3,2),(n*4,n*4+2,n*4+3,n*4+1)])
 mesh('OriginalContinuousShallowBarrelVault',verts,faces)
 G['architecture_connections'].append({'object':'OriginalContinuousShallowBarrelVault',
  'role':'barrel carried by four transverse ribs and seated into existing portal headers',
  'ends_z':[-11.8,11.8],'header_engagement_metres':.20,'spring_y':3.50,'intrados_crown_y':4.45})
 G['omitted_high_collisions'].append({'object':'OriginalContinuousShallowBarrelVault','minimum_curved_underside_y':3.50,'reason':'Above player jump/head envelope; no complex collision.'})


def circular_gateway():
 # Enlarged source circle remains round: centre(0,2.15), radius2.16m.
 # Upper wall infill is compressed above the opening to fit the 5.2m ceiling.
 def mapper(v):
  x,y,z=v;yy=y*1.6+1.03
  if y>2.05:yy=4.31+(y-2.05)*(.89/.95)
  return at_transform(((x-2)*1.6,yy,(z+.1)*2),(2.1,0,0),math.pi/2)
 imported('CenjiCircularGateway','MOD_51_Portal_Circular_Flooded.glb',mapper,clip_floor=True)
 # Box bands lie inside the wall, never across the hole. Max opening extent
 # over each band is used to guarantee no collision lips enter the passage.
 radius=2.16;cy=2.15;top=5.2;lo=DECK;i=0
 while lo<top-1e-6:
  hi=min(top,lo+.12);nearest=max(lo,min(cy,hi));half=math.sqrt(max(0,radius*radius-(nearest-cy)**2)) if abs(nearest-cy)<radius else 0
  for sign in [-1,1]:
   width=3.2-half
   c=(2.1,(lo+hi)/2,sign*(half+width/2));proxy('CircularGatewayBand%02d_%s'%(i,sign),c,(.4,hi-lo,width))
  lo=hi;i+=1
 for sign in [-1,1]:box('RestNicheDividerWing',(2.1,(5.2+DECK)/2,sign*5.7),(.4,5.2-DECK,5.0),'art_pass_plaster_oyster')
 G['gateway']={'center':[2.1,2.15,0],'opening_radius':2.16,'dry_floor_clear_width':round(2*math.sqrt(radius**2-(DECK-cy)**2),4),'orientation':'east-west','source_file':'MOD_51_Portal_Circular_Flooded.glb','collision_strategy':'horizontal BOX-only bands outside exact circular opening'}


def room(name):
 if name=='crescent_court':
  wet=[[-8,-7,12,10]];height=5.2;floor(wet);shell(height);roof_with_openings(height,[[-7,-6,8,7]])
  basin_details(wet[0],'south',2.4)
  for z in [-6,0,6]:
   top=arch('CenjiCourtArcade'+str(z),(5.25,0,z),math.pi/2,width=6,spring=3.3,crown=4.65)
   box('ArcadeRoofConnection',(5.25,(top+height)/2,z),(.42,height-top,6))
  curved_alcove();bench('CenjiEastBench',(10.4,DECK,6.2),math.pi/2)
  for x,z,yaw in [(-11.55,-5,math.pi/2),(-11.55,5,math.pi/2),(11.55,-6,-math.pi/2),(11.55,6,-math.pi/2)]:wall_lamp('CourtPoolFixture',(x,3.1,z),yaw)
  G.update({'spawn_local':[7,.60,8],'interior_ceiling':height,'daylight':True,'dry_route_ring':[[-10,.52,-9.5],[9,.52,-9.5],[9,.52,8],[-10,.52,6]],'recommended_views':[{'from':[8,2.1,8],'toward':[-3,1.5,-3]}]})
 elif name=='vaulted_lanes':
  wet=[[-6,-9,4,18],[2,-9,4,18]];height=4.7;floor(wet);shell(height)
  roof_with_openings(height,[[-4.65,-7,1.3,14],[3.35,-7,1.3,14]])
  for r in wet:basin_details(r,'north',r[0]+r[2]/2)
  for z in [-7.5,-2.5,2.5,7.5]:
   arch('CenjiLaneRib'+str(z),(0,0,z),width=16/3,spring=3.35,crown=4.45,depth=.44,
        bearing_y=BOTTOM+.18,cap_y=height,basin_footings=True)
  vault_surface()
  for x in [-10.8,10.8]:
   for z in [-6,6]:bench('CenjiGalleryBench',(x,DECK,z),math.pi/2 if x>0 else -math.pi/2)
  for x in [-1.945,1.945]:
   for z in [-2.5,2.5]:wall_lamp('GalleryInnerPierFixture',(x,2.7,z),math.pi/2 if x<0 else -math.pi/2,width=.35,power=14.0,range_m=6.5)
  G.update({'spawn_local':[0,.60,9.8],'interior_ceiling':height,'daylight':True,'central_dry_width':4.0,'dry_route_ring':[[-9,.52,-10],[9,.52,-10],[9,.52,10],[-9,.52,10]],'recommended_views':[{'from':[0,2.1,10.5],'toward':[0,2,-8]}]})
 elif name=='circular_bath':
  wet=[[-8,-6,8,12]];height=5.2;floor(wet);shell(height);roof_with_openings(height,[[-6,-4,4,8]])
  basin_details(wet[0],'south',-1.5);circular_gateway()
  for z in [-5,5]:bench('CenjiRestNicheBench',(9.9,DECK,z),math.pi/2)
  # A modest imported rounded divider curves one corner of the east rest niche.
  imported('CenjiNicheRoundedDivider','MOD_52_Divider_RoundedCapsule.glb',lambda v:at_transform(((v[0]-2)*.7,v[1]*.48+DECK,(v[2]+.5)*.7),(7,0,-7.4)),clip_floor=True)
  # Deliberately conservative box below the low rounded seating-wall silhouette.
  proxy('NicheLowDivider',(7,.72,-7.4),(2.7,.40,.60))
  for x,z,yaw in [(-11.55,-4,math.pi/2),(-11.55,4,math.pi/2),(11.55,-5,-math.pi/2),(11.55,5,-math.pi/2)]:wall_lamp('BathPoolFixture',(x,3.1,z),yaw)
  G.update({'spawn_local':[7,.60,0],'interior_ceiling':height,'daylight':True,'dry_route_ring':[[-10,.52,-9.5],[9,.52,-9.5],[9,.52,9.5],[-10,.52,9.5]],'recommended_views':[{'from':[9.3,2.15,0],'toward':[-5,1.7,0]}]})
 G['basin_rects']=wet;G['entry_water_rects']=[[-4,-16,8,3.5],[-4,12.5,8,3.5],[-16,-4,3.5,8],[12.5,-4,3.5,8]]
 G['water_rects']=G['entry_water_rects']+wet;G['water_floor_y']=SOURCE_FLOOR;G['basin_floor_y']=BOTTOM;G['water_level']=WATER;G['basin_depth_metres']=.54;G['deck_top']=DECK;G['outer_portal_width']=8.;G['inner_portal_width']=4.4;G['cell_size']=32;G['outer_portal_top']=5.4;G['ceiling']=5.6


def save(name):
 for ob in bpy.context.scene.objects:
  if ob.type=='MESH' and not ob.name.startswith('COLLISION_'):
   bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update();uv_metric(ob.data)
 bpy.context.scene['room_contract']=json.dumps({k:v for k,v in G.items() if k not in ['collision_boxes','source_instances']})
 # Preview-only neutral sunlight/world. No luminant architectural ceiling cards.
 world=bpy.data.worlds.new('PoolroomsPreviewSky');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.75,.82,1);world.node_tree.nodes['Background'].inputs[1].default_value=.35;bpy.context.scene.world=world
 sun=bpy.data.lights.new('PreviewOnlySun','SUN');sun.energy=2.5;sun.angle=.16;ob=bpy.data.objects.new('PreviewOnlySun',sun);bpy.context.collection.objects.link(ob);ob.rotation_euler=(.35,-.45,-.3)
 for i,f in enumerate(G['fixtures']):
  li=bpy.data.lights.new('PreviewFixture'+str(i),'POINT');li.energy=100;li.color=(.93,.95,.84);li.shadow_soft_size=.3;ob=bpy.data.objects.new(li.name,li);bpy.context.collection.objects.link(ob);ob.location=p(f['position'])
 # All textures are existing project files, linked relatively, not source-kit maps.
 for im in bpy.data.images:
  if im.filepath and os.path.isfile(bpy.path.abspath(im.filepath)):
   im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath),start=SRC)
 bpy.data.orphans_purge(do_recursive=True)
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC,name+'.blend'))
 G['editable_source']='tools/blender/poolrooms_wing/source/'+name+'.blend'
 G['glb']='assets/models/poolrooms_wing/'+name+'.glb'
 G['source_asset_counts']=dict(COUNTS)
 G['source_asset_sha256']={fn:hashlib.sha256(open(os.path.join(args.source_dir,fn),'rb').read()).hexdigest() for fn in COUNTS}
 G['proxy_count']=len(G['collision_boxes'])
 visible=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.name.startswith('COLLISION_')]
 coords=[g(o.matrix_world@v.co) for o in visible for v in o.data.vertices]
 G['bounds_min']=rnd([min(v[a] for v in coords) for a in range(3)]);G['bounds_max']=rnd([max(v[a] for v in coords) for a in range(3)])
 G['visible_triangles']=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in visible)
 G['materials']=sorted(set(m.name for o in visible for m in o.data.materials))
 # Batch only runtime visuals. Editable .blend retains independently named parts.
 for ob in list(bpy.context.scene.objects):
  if ob.type not in ['MESH']:bpy.data.objects.remove(ob,do_unlink=True)
 for role in G['materials']:
  group=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.name.startswith('COLLISION_') and len(o.data.materials)==1 and o.data.materials[0].name==role]
  if len(group)>1:
   bpy.ops.object.select_all(action='DESELECT')
   for ob in group:ob.select_set(True)
   bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join();group[0].name='IntegratedRoom_'+role
 # Runtime supplies existing art_pass maps by exact material name. Avoid duplicate
 # texture payloads in the GLBs while retaining coloured fallback materials.
 for role in M:
  m=bpy.data.materials.get(role)
  if m is None:continue
  bs=m.node_tree.nodes.get('Principled BSDF')
  for li in list(m.node_tree.links):
   if li.to_node==bs:m.node_tree.links.remove(li)
  bs.inputs['Base Color'].default_value=ROLES[role][4];bs.inputs['Roughness'].default_value=ROLES[role][5]
 for ob in bpy.context.scene.objects:
  if ob.type=='MESH' and not ob.name.startswith('COLLISION_'):
   bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
 bpy.ops.object.select_all(action='SELECT')
 bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),export_format='GLB',use_selection=True,export_yup=True,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False)
 G['glb_bytes']=os.path.getsize(os.path.join(OUT,name+'.glb'));G['glb_sha256']=hashlib.sha256(open(os.path.join(OUT,name+'.glb'),'rb').read()).hexdigest()
 DATA[name]=G.copy()
 print('ROOM_DONE',name,G['visible_triangles'],G['proxy_count'],G['glb_bytes'])

for name in ['crescent_court','vaulted_lanes','circular_bath']:
 if args.only and args.only!=name:continue
 reset(name);room(name);save(name)
manifest={'schema':'poolrooms-wing-geometry-v1','generator':'tools/blender/poolrooms_wing/build_poolrooms_wing.py','source_assets_external':True,'standalone_asset_pack_included':False,'source_water_mesh_imported':False,'physics':'Every COLLISION_ mesh is an exact axis-aligned BOX, eight vertices and six quad faces before glTF triangulation. No concave/trimesh shapes.','uv':'UV0 one unit/metre using orthonormal per-face world frames; shared existing art_pass ceramic maps use .8m repeat with eight 10cm tiles.','materials_runtime':'Existing art_pass roles and project-owned PBR maps. Source Cenji 25cm textures deliberately not exported.','rooms':DATA}
if args.only and os.path.exists(PROV):
 old=json.load(open(PROV));old['rooms'].update(DATA);manifest=old
with open(PROV,'w') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
