"""Reference-matched PoolCore rooms, authored from metric solids in Blender 4.3.
Reproduce: blender -b -t 4 --python tools/blender/reference_wing/water_rooms_build.py
Optional: -- --only colonnade|cyan_corridor|octagonal_bath --render
All authoring coordinates in this generator and JSON are Godot XYZ. Blender conversion
is (x, -z, y); glTF's official Y-up conversion restores the contract coordinates.
No water mesh is exported. Preview water is a separate render-only collection.
"""
import bpy, bmesh, json, math, os, sys, argparse
from mathutils import Vector, Matrix
from collections import Counter
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../..'))
OUT=os.path.join(ROOT,'assets/models/reference_wing')
SRC=os.path.join(ROOT,'tools/blender/reference_wing/water_sources')
QA=os.path.join(ROOT,'output/reference_wing/water_rooms')
for d in (OUT,SRC,QA):os.makedirs(d,exist_ok=True)
open(os.path.join(SRC,'.gdignore'),'a').close()
P=argparse.ArgumentParser();P.add_argument('--only',choices=['colonnade','cyan_corridor','octagonal_bath']);P.add_argument('--render',action='store_true');P.add_argument('--samples',type=int,default=32)
args=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
DECK=.52;WATER=.32;BOTTOM=-.22;FOUNDATION=-.60;WALL=.24
CUBE_FACES=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
M={};G={};OB={};runtime=None;preview=None

def p(v):return (v[0],-v[2],v[1])
def g(v):return (v[0],v[2],-v[1])
def rr(v):return [round(float(x),6) for x in v]
def poly_rect(x0,x1,z0,z1):return [[x0,z0],[x1,z0],[x1,z1],[x0,z1]]
def oct_poly(a):
 q=a*(math.sqrt(2)-1)
 return [[-q,-a],[q,-a],[a,-q],[a,q],[q,a],[-q,a],[-a,q],[-a,-q]]

def reset(name):
 global M,G,OB,runtime,preview
 for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
 for c in list(bpy.data.collections):bpy.data.collections.remove(c)
 for m in list(bpy.data.materials):bpy.data.materials.remove(m)
 runtime=bpy.data.collections.new('RUNTIME_ARCHITECTURE');bpy.context.scene.collection.children.link(runtime)
 preview=bpy.data.collections.new('PREVIEW_ONLY_NOT_EXPORTED');bpy.context.scene.collection.children.link(preview)
 M={};OB={}
 G={'schema_version':2,'name':name,'coordinate_system':'Godot XYZ metres; Y up','module_bounds':{'min':[-16,FOUNDATION,-16],'max':[16,6.2,16]},'datums':{'deck_y':DECK,'water_y':WATER,'basin_bottom_y':BOTTOM},'source':f'tools/blender/reference_wing/water_sources/{name}.blend','generator':'tools/blender/reference_wing/water_rooms_build.py','uv0_units_per_metre':1,'tile_pitch_m':.1,'collision_proxies':[],'portal_contracts':[],'water_regions':[],'water_exclusions':[],'steps':[],'support_contacts':[],'lights':[],'camera_views':[],'composition':{}}
 colors={'ref_tile_pearl':(.50,.60,.56,1),'ref_tile_teal':(.20,.63,.60,1),'ref_tile_pink':(.76,.52,.52,1),'ref_grout':(.015,.025,.025,1),'ref_recess_black':(.002,.004,.004,1),'ref_fixture_metal':(.18,.24,.23,1),'ref_fixture_emission':(.8,1,1,1),'ref_sign_red':(.58,.015,.018,1),'ref_sign_white':(.88,.92,.88,1)}
 colors.update({'ref_tile_dark_teal':(.051,.138,.125,1),'ref_tile_dark_teal_dry':(.051,.138,.125,1),'ref_tile_teal_satin':colors['ref_tile_teal'],'ref_tile_teal_satin_dry':colors['ref_tile_teal'],'ref_tile_pink_satin':colors['ref_tile_pink'],'ref_tile_pink_satin_dry':colors['ref_tile_pink'],'ref_tile_dry':colors['ref_tile_pearl'],'ref_tile_teal_dry':colors['ref_tile_teal'],'ref_tile_pink_dry':colors['ref_tile_pink']})
 for n,c in colors.items():
  m=bpy.data.materials.new(n);m.diffuse_color=c;m.use_nodes=True
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=c;bs.inputs['Roughness'].default_value=.17 if 'tile' in n else .48
  if n=='ref_fixture_metal':bs.inputs['Metallic'].default_value=.7
  if n=='ref_fixture_emission':bs.inputs['Emission Color'].default_value=c;bs.inputs['Emission Strength'].default_value=7
  if 'tile' in n:
   # Native metric tile preview, never baked over or substituted for runtime materials.
   nd=m.node_tree.nodes;lk=m.node_tree.links
   uv=nd.new('ShaderNodeTexCoord');sep=nd.new('ShaderNodeSeparateXYZ');lk.new(uv.outputs['UV'],sep.inputs[0])
   pairs=[]
   for axis in ('X','Y'):
    mul=nd.new('ShaderNodeMath');mul.operation='MULTIPLY';mul.inputs[1].default_value=10;lk.new(sep.outputs[axis],mul.inputs[0])
    fract=nd.new('ShaderNodeMath');fract.operation='FRACT';lk.new(mul.outputs[0],fract.inputs[0])
    low=nd.new('ShaderNodeMath');low.operation='LESS_THAN';low.inputs[1].default_value=.023;lk.new(fract.outputs[0],low.inputs[0])
    high=nd.new('ShaderNodeMath');high.operation='GREATER_THAN';high.inputs[1].default_value=.977;lk.new(fract.outputs[0],high.inputs[0])
    mx=nd.new('ShaderNodeMath');mx.operation='MAXIMUM';lk.new(low.outputs[0],mx.inputs[0]);lk.new(high.outputs[0],mx.inputs[1]);pairs.append(mx)
   mx=nd.new('ShaderNodeMath');mx.operation='MAXIMUM';lk.new(pairs[0].outputs[0],mx.inputs[0]);lk.new(pairs[1].outputs[0],mx.inputs[1])
   mix=nd.new('ShaderNodeMixRGB');mix.blend_type='MIX';mix.inputs[1].default_value=c;mix.inputs[2].default_value=tuple(v*.48 for v in c[:3])+(1,);lk.new(mx.outputs[0],mix.inputs[0]);lk.new(mix.outputs[0],bs.inputs['Base Color'])
   inv=nd.new('ShaderNodeMath');inv.operation='SUBTRACT';inv.inputs[0].default_value=1;lk.new(mx.outputs[0],inv.inputs[1])
   bump=nd.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.32;bump.inputs['Distance'].default_value=.0015;lk.new(inv.outputs[0],bump.inputs['Height']);lk.new(bump.outputs[0],bs.inputs['Normal'])
  M[n]=m
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
 bpy.context.preferences.filepaths.save_version=0
 bpy.context.scene['composition_source']='Individually authored from user reference; no third-party asset kit.'
 bpy.context.scene['runtime_water']='Original PoolCore runtime water retained. Preview-only planes are explicitly excluded from GLB.'
 bpy.context.scene['uv_contract']='UV0 1 UV/m, 10cm physical tiles; world-projected plane phases; tangents exported.'

def uv_metric(me):
 if me.uv_layers:
  for l in list(me.uv_layers):me.uv_layers.remove(l)
 uv=me.uv_layers.new(name='UVMap')
 for f in me.polygons:
  n=f.normal.normalized()
  if abs(n.z)>.9:
   u=Vector((1,0,0));u=(u-n*u.dot(n)).normalized();v=n.cross(u)
   if v.y<0:v=-v
  else:
   u=Vector((0,0,1)).cross(n).normalized()
   if (abs(u.x)>=abs(u.y) and u.x<0) or (abs(u.x)<abs(u.y) and u.y<0):u=-u
   v=n.cross(u)
   if v.z<0:v=-v
  for li in f.loop_indices:
   c=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(c.dot(u),c.dot(v))

def mesh(name,verts,faces,mat='ref_tile_pearl',proxy=False,bevel=0):
 me=bpy.data.meshes.new(name);me.from_pydata([p(v) for v in verts],[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(me);bm.free();me.update()
 ob=bpy.data.objects.new(name,me);runtime.objects.link(ob);me.materials.append(M[mat]);OB[name]=ob
 uv_metric(me);ob['uv_metres_per_unit']=1.0
 if proxy:ob.hide_render=True;ob.display_type='WIRE';ob['collision_proxy']=True
 if bevel:
  mod=ob.modifiers.new('Metric ceramic edge bevel','BEVEL');mod.width=bevel;mod.segments=2;mod.limit_method='ANGLE';mod.angle_limit=.4
  bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False);uv_metric(me)
 bm=bmesh.new();bm.from_mesh(me);ngons=[f for f in bm.faces if len(f.verts)>4]
 if ngons:bmesh.ops.triangulate(bm,faces=ngons)
 bm.to_mesh(me);bm.free();me.update();uv_metric(me)
 return ob

def bbox(ob):
 vs=[g(ob.matrix_world@v.co) for v in ob.data.vertices]
 return [[min(v[i] for v in vs) for i in range(3)],[max(v[i] for v in vs) for i in range(3)]]
def support(name,base,kind='bearing'):
 ob=OB[name];sup=OB[base];a,b=bbox(ob),bbox(sup)
 # Vertical support contacts are accepted only if footprints intersect.
 overlap=[min(a[1][i],b[1][i])-max(a[0][i],b[0][i]) for i in (0,2)]
 G['support_contacts'].append({'object':name,'support':base,'kind':kind,'object_bottom_y':round(a[0][1],6),'support_top_y':round(b[1][1],6),'gap':round(a[0][1]-b[1][1],6),'footprint_overlap_xz':rr(overlap),'measured_from':'evaluated mesh vertices'})

def box(name,c,s,mat='ref_tile_pearl',collision=True,bevel=.004):
 x,y,z=c;a,b,d=[q/2 for q in s]
 verts=[(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
 ob=mesh(name,verts,CUBE_FACES,mat,bevel=min(bevel,min(s)/4))
 if collision:
  cn='COLLISION_'+name;pr=mesh(cn,verts,CUBE_FACES,mat,proxy=True);pr['proxy_type']='BOX'
  G['collision_proxies'].append({'name':cn,'source_object':name,'type':'BOX','center':rr(c),'size':rr(s),'basis':[[1,0,0],[0,1,0],[0,0,1]],'position':rr([c[i]-s[i]/2 for i in range(3)]),'transform':{'origin':[0,0,0],'basis':[[1,0,0],[0,1,0],[0,0,1]]}})
 return ob

def prism(name,poly,y0,y1,mat='ref_tile_pearl',collision=True,bevel=.004):
 n=len(poly);verts=[(x,y0,z) for x,z in poly]+[(x,y1,z) for x,z in poly];faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 ob=mesh(name,verts,faces,mat,bevel=bevel)
 if collision:
  cn='COLLISION_'+name;pr=mesh(cn,verts,faces,mat,proxy=True);pr['proxy_type']='CONVEX'
  G['collision_proxies'].append({'name':cn,'source_object':name,'type':'CONVEX','vertices':[rr(v) for v in verts],'faces':[list(f) for f in faces],'transform':{'origin':[0,0,0],'basis':[[1,0,0],[0,1,0],[0,0,1]]},'convex_parts':1})
 return ob

def slab(name,x0,x1,z0,z1,top=DECK,mat='ref_tile_pearl'):
 return box(name,((x0+x1)/2,(FOUNDATION+top)/2,(z0+z1)/2),(x1-x0,top-FOUNDATION,z1-z0),mat,bevel=0)

def water(poly,name='Basin'):
 G['water_regions'].append({'name':name,'polygon_xz':poly,'surface_y':WATER,'bottom_y':BOTTOM})
 xs=[p[0] for p in poly];zs=[p[1] for p in poly]
 G.setdefault('water_rectangles',[]).append({'name':name,'position':[min(xs),WATER,min(zs)],'size':[max(xs)-min(xs),0,max(zs)-min(zs)],'clip_polygon_xz':poly,'surface_y':WATER,'bottom_y':BOTTOM,'note':'Derived bounding rectangle; clip to polygon before subtracting solid exclusions.'})

def exclude(poly,name,reason='solid support at water line'):
 G['water_exclusions'].append({'object':name,'polygon_xz':poly,'reason':reason})

def dry_role(mat):return {'ref_tile_pearl':'ref_tile_dry','ref_tile_teal':'ref_tile_teal_dry','ref_tile_pink':'ref_tile_pink_dry','ref_tile_dark_teal':'ref_tile_dark_teal_dry','ref_tile_teal_satin':'ref_tile_teal_satin_dry','ref_tile_pink_satin':'ref_tile_pink_satin_dry'}.get(mat,mat)

def steps(name,base,axis,start,end,across,width,mat='ref_tile_pearl'):
 # Four .185m real risers, not a ramp. Each solid touches basin slab directly.
 levels=[-.035,.15,.335,.52];length=(end-start)/4
 for i,h in enumerate(levels):
  a=start+i*length;b=a+length
  if axis=='z':x0,x1,z0,z1=across-width/2,across+width/2,min(a,b),max(a,b)
  else:x0,x1,z0,z1=min(a,b),max(a,b),across-width/2,across+width/2
  nn=f'{name}_Tread_{i+1:02d}';box(nn,((x0+x1)/2,(BOTTOM+h)/2,(z0+z1)/2),(x1-x0,h-BOTTOM,z1-z0),dry_role(mat) if h>.4 else mat,bevel=.003);support(nn,base,'solid stair bearing')
  bnd=bbox(OB[nn]);G['steps'].append({'object':nn,'top_y':round(bnd[1][1],6),'bottom_y':round(bnd[0][1],6),'rise_m':.185,'tread_depth_m':abs(length),'footprint_xz':poly_rect(bnd[0][0],bnd[1][0],bnd[0][2],bnd[1][2]),'collision':'COLLISION_'+nn})
  if h>WATER:exclude(poly_rect(x0,x1,z0,z1),nn,'tread above water surface')

def light(name,pos,color,energy,rng=6,size=1.0,kind='AREA',rotation=None):
 G['lights'].append({'name':name,'position':rr(pos),'color':list(color),'energy':energy/100,'range':rng,'source_watts':energy,'type':'omni','shadow':True,'color_space':'linear','native_type':'spot','direction':[0,-1,0],'spot_angle_deg':85,'spot_angle_attenuation':.15,'emitter_radius':.005,'native_energy_provisional':True})
 d=bpy.data.lights.new('PREVIEW_'+name,kind);d.energy=energy;d.color=color
 if kind=='AREA':d.shape='DISK';d.size=size
 elif kind=='POINT':d.shadow_soft_size=size
 ob=bpy.data.objects.new('PREVIEW_'+name,d);preview.objects.link(ob);ob.location=p(pos)
 if rotation:ob.rotation_euler=rotation
 return ob

def fixture(name,x,z,ceiling,w=.75,l=1.2,watts=200,color=(.7,.95,1)):
 box(name+'_MetalHousing',(x,ceiling-.055,z),(w+.09,.11,l+.09),'ref_fixture_metal',False,.012)
 box(name+'_Diffuser',(x,ceiling-.115,z),(w,.018,l),'ref_fixture_emission',False,.012)
 light(name,(x,ceiling-.16,z),color,watts,5.8,max(w,l));G['lights'][-1]['fixture_object']=name+'_Diffuser'

def opening_match(axis,value,start,end,opens):
 for a,v,s,e in opens:
  if a==axis and abs(v-value)<.00001 and start>=s-.00001 and end<=e+.00001:return True
 return False

def network(name,rects,openings,mat='ref_tile_pearl',ceiling=3.32):
 """Exact union of rectangular corridors: no internal partitions or overlap floors."""
 xs=sorted(set([x for r in rects for x in r[:2]]+[v for a,v,s,e in openings if a=='x']+[t for a,v,s,e in openings if a=='z' for t in (s,e)]))
 zs=sorted(set([z for r in rects for z in r[2:]]+[v for a,v,s,e in openings if a=='z']+[t for a,v,s,e in openings if a=='x' for t in (s,e)]))
 cells=set()
 for i in range(len(xs)-1):
  for j in range(len(zs)-1):
   x=(xs[i]+xs[i+1])/2;z=(zs[j]+zs[j+1])/2
   if any(r[0]-1e-6<x<r[1]+1e-6 and r[2]-1e-6<z<r[3]+1e-6 for r in rects):cells.add((i,j))
 edges=[]
 for k,(i,j) in enumerate(sorted(cells)):
  x0,x1=xs[i:i+2];z0,z1=zs[j:j+2]
  floor=slab(f'{name}_Floor_{k:03d}',x0,x1,z0,z1,DECK,dry_role(mat))
  box(f'{name}_Roof_{k:03d}',((x0+x1)/2,ceiling+.12,(z0+z1)/2),(x1-x0,.24,z1-z0),mat,True,0)
  # dry threshold's top is derived from the exported floor geometry.
  if k==0:G.setdefault('dry_surfaces',[]).append({'object':floor.name,'top_y':round(bbox(floor)[1][1],6)})
  for di,dj,axis,value,start,end,sign in [(-1,0,'x',x0,z0,z1,-1),(1,0,'x',x1,z0,z1,1),(0,-1,'z',z0,x0,x1,-1),(0,1,'z',z1,x0,x1,1)]:
   if (i+di,j+dj) not in cells and not opening_match(axis,value,start,end,openings):edges.append((axis,value,start,end,sign))
 # Join collinear exposed edges to eliminate unnecessary face splits.
 groups={}
 for a,v,s,e,sg in edges:groups.setdefault((a,v,sg),[]).append((s,e))
 idx=0
 for (a,v,sg),segments in groups.items():
  merged=[]
  for s,e in sorted(segments):
   if merged and abs(merged[-1][1]-s)<1e-6:merged[-1]=(merged[-1][0],e)
   else:merged.append((s,e))
  for s,e in merged:
   idx+=1
   if a=='x':c=(v+sg*WALL/2,(BOTTOM+ceiling+.24)/2,(s+e)/2);sz=(WALL,ceiling+.24-BOTTOM,e-s)
   else:c=((s+e)/2,(BOTTOM+ceiling+.24)/2,v+sg*WALL/2);sz=(e-s,ceiling+.24-BOTTOM,WALL)
   fn=f'{name}_WallFooting_{idx:03d}';box(fn,(c[0],(FOUNDATION+BOTTOM)/2,c[2]),(sz[0],BOTTOM-FOUNDATION,sz[2]),mat,True,0)
   wn=f'{name}_Wall_{idx:03d}';box(wn,c,sz,mat,True,.004);support(wn,fn,'connector wall footing')
 G.setdefault('connector_networks',[]).append({'name':name,'union_rectangles_xz':rects,'floor_y':DECK,'ceiling_y':ceiling,'open_boundaries':[{'axis':a,'value':v,'start':s,'end':e} for a,v,s,e in openings]})

def portals(sides):
 for side in ('south','north','east','west'):
  center={'south':[0,DECK,16],'north':[0,DECK,-16],'east':[16,DECK,0],'west':[-16,DECK,0]}[side]
  G['portal_contracts'].append({'side':side,'open':side in sides,'center':center,'width':3 if side in sides else 0,'clear_height':2.8 if side in sides else 0,'threshold_y':DECK})

def room_wall(name,axis,coord,start,end,y0,y1,mat,base):
 if end-start<1e-6:return
 c=(coord,(y0+y1)/2,(start+end)/2) if axis=='x' else ((start+end)/2,(y0+y1)/2,coord)
 sz=(WALL,y1-y0,end-start) if axis=='x' else (end-start,y1-y0,WALL)
 box(name,c,sz,mat)
 if abs(y0-BOTTOM)<1e-6:support(name,base,'room wall on basin slab')

def colonnade():
 reset('colonnade');mat='ref_tile_dark_teal';H=3.55
 G['composition']={'reference':1,'interior_width_m':10.4,'interior_length_m':25.6,'ceiling_y':H,'pier_pairs':7,'central_clear_water_aisle_m':3.35,'intent':'Dark paired square piers, strong axial rectangular light rhythm, shadowed side aisles.'}
 base=slab('Colonnade_BasinSlab',-5.44,5.44,-13.04,13.04,BOTTOM,mat).name
 room_wall('West_ClosedWall','x',-5.32,-13.04,13.04,BOTTOM,H,mat,base)
 for s,e in [(-13.04,-1.5),(1.5,13.04)]:room_wall('East_Wall_'+str(s),'x',5.32,s,e,BOTTOM,H,mat,base)
 room_wall('East_PortalLintel','x',5.32,-1.5,1.5,3.32,H,mat,base)
 for z,label in [(-12.92,'North'),(12.92,'South')]:
  for s,e in [(-5.2,-1.5),(1.5,5.2)]:room_wall(label+'_Wall_'+str(s),'z',z,s,e,BOTTOM,H,mat,base)
  room_wall(label+'_PortalLintel','z',z,-1.5,1.5,3.32,H,mat,base)
 box('Colonnade_ThickRoof',(0,H+.14,0),(10.88,.28,26.08),mat,True,.006)
 for i,z in enumerate([-9.3,-6.2,-3.1,0,3.1,6.2,9.3]):
  for x,label in [(-2.25,'Left'),(2.25,'Right')]:
   name=f'{label}_SquarePier_{i+1:02d}';pier=box(name,(x,(BOTTOM+H)/2,z),(1.15,H-BOTTOM,1.15),mat,True,.008);pier.data.materials[0]=M['ref_tile_teal'];support(name,base,'pier bears on submerged basin floor');exclude(poly_rect(x-.575,x+.575,z-.575,z+.575),name)
  fixture(f'AxialFixture_{i+1:02d}',0,z,H,.85,1.15,75 if i<5 else 58,(.78,.92,.88))
 fixture('EntranceCeilingFixture',0,12.05,H,.70,.85,42,(.82,.94,.90))
 steps('South_Entry',base,'z',11.2,12.8,0,3,mat);steps('North_Entry',base,'z',-11.2,-12.8,0,3,mat);steps('East_Entry',base,'x',3.6,5.2,0,3,mat)
 network('South_Connector',[[-1.5,1.5,12.8,16]],[('z',12.8,-1.5,1.5),('z',16,-1.5,1.5)],mat)
 network('North_Connector',[[-1.5,1.5,-16,-12.8]],[('z',-12.8,-1.5,1.5),('z',-16,-1.5,1.5)],mat)
 network('East_Connector',[[5.2,16,-1.5,1.5]],[('x',5.2,-1.5,1.5),('x',16,-1.5,1.5)],mat)
 fixture('EastConnector_Light',10.5,0,3.32,.35,.8,30,(.72,.87,.82));water(poly_rect(-5.2,5.2,-12.8,12.8));portals(['south','north','east'])
 G['camera_views'].append({'name':'Reference1_Axial','position':[0,1.5,11.0],'target':[0,1.35,-8.8],'lens_mm':23})
 finish()

def disc(name,center,radius,depth,mat,collision=False):
 # Disc faces +/-Godot Z; floor pole therefore faces the entrance camera.
 x,y,z=center;n=64;verts=[]
 for zz in [z-depth/2,z+depth/2]:
  verts.extend([(x+radius*math.cos(2*math.pi*i/n),y+radius*math.sin(2*math.pi*i/n),zz) for i in range(n)])
 faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 ob=mesh(name,verts,faces,mat,bevel=.003)
 if collision:
  cn='COLLISION_'+name;pr=mesh(cn,verts,faces,mat,proxy=True);pr['proxy_type']='CONVEX'
  G['collision_proxies'].append({'name':cn,'source_object':name,'type':'CONVEX','vertices':[rr(v) for v in verts],'faces':[list(f) for f in faces],'transform':{'origin':[0,0,0],'basis':[[1,0,0],[0,1,0],[0,0,1]]},'convex_parts':1})
 return ob

def cyan_corridor():
 reset('cyan_corridor');mat='ref_tile_teal_satin';H=3.4
 G['tile_pitch_m']=.15;G['material_contract']={'structure':mat,'dry_surfaces':dry_role(mat),'tile_pitch_m':.15,'face_roughness':.34,'dry_face_roughness':.40,'uv0_units_per_metre':1,'scope':'Reference2 only; shared colonnade/ref5 glaze unchanged.'}
 G['composition']={'reference':2,'interior_width_m':3.6,'interior_length_m':24,'ceiling_y':H,'recessed_left_windows':4,'intent':'Narrow turquoise tube, true black recessed rectangular windows, thin luminous jambs, anchored red no-entry sign, dark far end.'}
 base=slab('Cyan_BasinSlab',-2.64,2.04,-12.24,12.24,BOTTOM,mat).name
 # Four actual holes in the left wall, each backed by a deep sealed dark recess.
 windows=[(-8.1,-6.7),(-3.4,-1.8),(2.0,3.8),(6.6,8.8)];cursor=-12.24
 for i,(a,b) in enumerate(windows):
  room_wall(f'Left_SolidBay_{i:02d}','x',-1.92,cursor,a,BOTTOM,H,mat,base)
  room_wall(f'Window_{i+1}_LowerWall','x',-1.92,a,b,BOTTOM,.9,mat,base)
  room_wall(f'Window_{i+1}_UpperWall','x',-1.92,a,b,2.45,H,mat,base)
  box(f'Window_{i+1}_BlackRecessBack',(-2.57,1.675,(a+b)/2),(.14,1.55,b-a),'ref_recess_black')
  box(f'Window_{i+1}_RecessSill',(-2.22,.84,(a+b)/2),(.8,.12,b-a),mat)
  box(f'Window_{i+1}_RecessHead',(-2.22,2.51,(a+b)/2),(.8,.12,b-a),mat)
  for j,z in enumerate([a+.025,b-.025]):
   box(f'Window_{i+1}_SideReturn_{j}',(-2.22,1.675,z),(.8,1.55,.05),mat)
   box(f'Window_{i+1}_LuminousJamb_{j}',(-1.785,1.675,z),(.027,1.49,.035),'ref_fixture_emission',False,.004)
  cursor=b
 room_wall('Left_FinalBay','x',-1.92,cursor,12.24,BOTTOM,H,mat,base)
 for a,b in [(-12.24,-11.3),(-8.3,12.24)]:room_wall('Right_SolidWall_'+str(a),'x',1.92,a,b,BOTTOM,H,mat,base)
 room_wall('East_InteriorLintel','x',1.92,-11.3,-8.3,3.32,H,mat,base)
 room_wall('North_DarkEnd','z',-12.12,-1.8,1.8,BOTTOM,H,mat,base)
 for a,b in [(-1.8,-1.5),(1.5,1.8)]:room_wall('South_PortalPier_'+str(a),'z',12.12,a,b,BOTTOM,H,mat,base)
 room_wall('South_Lintel','z',12.12,-1.5,1.5,3.32,H,mat,base)
 box('Cyan_ThickCeiling',(0,H+.13,0),(4.08,.26,24.48),mat,True,.004)
 for i,z in enumerate([9,5.5,2,-1.5,-5,-8.5]):fixture(f'CyanStrip_{i+1:02d}',-.78,z,H,.055,.8,42 if i<4 else 16,(.65,1,.94))
 # A pole, flange and fasteners are seated on the actual -.22m basin floor.
 x=.93;z=5.15
 plate=box('NoEntry_PoleBasePlate',(x,BOTTOM+.025,z),(.24,.05,.24),'ref_fixture_metal',True,.008);support(plate.name,base,'sign base bolted to basin floor')
 polepoly=[[x+.027*math.cos(i*math.tau/12),z+.027*math.sin(i*math.tau/12)] for i in range(12)]
 pole=prism('NoEntry_AnchoredPole',polepoly,BOTTOM+.05,2.05,'ref_fixture_metal',True,.002);support(pole.name,plate.name,'pole seated on base flange')
 disc('NoEntry_RedDisc',(x,1.95,z+.008),.30,.035,'ref_sign_red',True)
 box('NoEntry_WhiteBar',(x,1.95,z+.030),(.40,.075,.009),'ref_sign_white',False,.006)
 for i,(dx,dz) in enumerate([(-.075,-.075),(.075,-.075),(-.075,.075),(.075,.075)]):
  bolt=box(f'NoEntry_AnchorBolt_{i}',(x+dx,BOTTOM+.058,z+dz),(.025,.016,.025),'ref_fixture_metal',False,.003);support(bolt.name,plate.name,'anchor bolt seated on flange')
 exclude(polepoly,pole.name,'only pole intersects water surface; submerged flange remains under water')
 steps('Cyan_SouthEntry',base,'z',10.4,12,0,3,mat);steps('Cyan_EastEntry',base,'x',.2,1.8,-9.8,3,mat)
 network('Cyan_SouthConnector',[[-1.5,1.5,12,16]],[('z',12,-1.5,1.5),('z',16,-1.5,1.5)],mat)
 network('Cyan_EastDogleg',[[1.8,5.4,-11.3,-8.3],[3.9,6.9,-9.8,1.5],[5.4,16,-1.5,1.5]],[('x',1.8,-11.3,-8.3),('x',16,-1.5,1.5)],mat)
 fixture('Cyan_ConnectorFixture',10,0,3.32,.08,1,28,(.55,.85,.8));water(poly_rect(-1.8,1.8,-12,12));portals(['south','east'])
 G['camera_views'].append({'name':'Reference2_Corridor','position':[-.15,1.45,10.25],'target':[0,1.3,-9.5],'lens_mm':22})
 finish()

def ring(name,a_outer,a_inner,y0,y1,mat,base=None,step=False):
 outer=oct_poly(a_outer);inner=oct_poly(a_inner)
 for i in range(8):
  j=(i+1)%8;poly=[outer[i],outer[j],inner[j],inner[i]];n=f'{name}_Facet_{i+1:02d}';ob=prism(n,poly,y0,y1,mat,True,.003)
  if base:support(n,base,'concentric step/rim bears on basin slab')
  if step:
   b=bbox(ob);G['steps'].append({'object':n,'top_y':round(b[1][1],6),'bottom_y':round(b[0][1],6),'rise_m':.185,'tread_depth_m':a_outer-a_inner,'footprint_xz':poly,'collision':'COLLISION_'+n})
 return outer

def octagonal_bath():
 reset('octagonal_bath');mat='ref_tile_pink_satin';A=6.5;H=3.5;outline=oct_poly(A)
 G['tile_pitch_m']=.20;G['material_contract']={'structure':mat,'dry_surfaces':dry_role(mat),'tile_pitch_m':.20,'face_roughness':.40,'dry_face_roughness':.40,'uv0_units_per_metre':1,'portal_reveals':mat,'scope':'Reference3 only; shared colonnade/ref5 glaze unchanged.'}
 G['composition']={'reference':3,'room_across_flats_m':13,'basin_across_flats_m':9,'continuous_rim_width_m':2,'rear_portals':2,'rear_portal_width_m':1.3,'rear_portal_clear_height_m':2.3,'ceiling_rings':8,'intent':'Human-scale blush octagonal stepped bath, two dark rear portals, asymmetric amber left portal, complete concentric stepped coffer.'}
 base=prism('Octagonal_BasinFoundation',oct_poly(A+.24),FOUNDATION,BOTTOM,mat,True,0).name
 ring('Octagonal_DryRim',A,4.5,BOTTOM,DECK,dry_role(mat),base)
 ring('Octagonal_Step_01',4.5,4.15,BOTTOM,.335,mat,base,True)
 ring('Octagonal_Step_02',4.15,3.8,BOTTOM,.15,mat,base,True)
 ring('Octagonal_Step_03',3.8,3.45,BOTTOM,-.035,mat,base,True)
 # Remaining center is the exposed foundation top at -.22m, not a floating insert.
 outer=oct_poly(A+WALL)
 for i in range(1,8):
  j=(i+1)%8;poly=[outline[i],outline[j],outer[j],outer[i]];n=f'Octagonal_WallFacet_{i+1:02d}';prism(n,poly,BOTTOM,H,mat,True,.004);support(n,base,'octagonal wall supported by foundation')
 q=A*(math.sqrt(2)-1)
 for idx,(a,b) in enumerate([(-q,-2.1),(-.8,.8),(2.1,q)]):room_wall(f'Rear_PortalPier_{idx}','z',-A-WALL/2,a,b,BOTTOM,H,mat,base)
 for i,(a,b) in enumerate([(-2.1,-.8),(.8,2.1)]):room_wall(f'Rear_PortalLintel_{i}','z',-A-WALL/2,a,b,2.82,H,mat,base)
 # Eight complete rings: contiguous faces, rising inward. Roof mass is real.
 outer_a=A+WALL
 for i in range(8):
  inner_a=outer_a-.53;underside=H+i*.22
  ring(f'CeilingCoffer_Ring_{i+1:02d}',outer_a,inner_a,underside,5.55,mat)
  outer_a=inner_a
 prism('CeilingCoffer_CenterCap',oct_poly(outer_a),5.26,5.55,mat,True,.003)
 # Both visual rear openings are real passages, routed to required W/S portals.
 left=[[-2.1,-.8,-9,-6.5],[-10.5,-.8,-10.5,-7.5],[-12,-9,-9,1.5],[-16,-10.5,-1.5,1.5]]
 right=[[.8,2.1,-9,-6.5],[.8,10.5,-10.5,-7.5],[9,12,-9,12],[-1.5,10.5,10.5,13.5],[-1.5,1.5,12,16]]
 network('Bath_WestRoute',left,[('z',-6.5,-2.1,-.8),('x',-16,-1.5,1.5)],mat)
 network('Bath_SouthRoute',right,[('z',-6.5,.8,2.1),('z',16,-1.5,1.5)],mat)
 # Narrow portal surrounds remain flat and un-overlapped; light sources are recessed.
 fixture('Bath_LeftPortalHiddenLamp',-1.45,-7.15,3.32,.1,.45,220,(1,.30,.07))
 # Recessed ceiling cove is real authored geometry; every light sample is
 # seated above actual diffuser geometry, never a floating room-center fill.
 # Final cavity-light recipe disables these direct samples and dims their mesh emission.
 outer_cove=oct_poly(5.13);inner_cove=oct_poly(5.08)
 housing_outer=oct_poly(5.15);housing_inner=oct_poly(5.06)
 ledge_outer=oct_poly(5.23);ledge_inner=oct_poly(5.05)
 lip_outer=oct_poly(5.05);lip_inner=oct_poly(5.01)
 G['fixture_mounts']=[]
 for i in range(8):
  j=(i+1)%8
  poly=[outer_cove[i],outer_cove[j],inner_cove[j],inner_cove[i]]
  housingpoly=[housing_outer[i],housing_outer[j],housing_inner[j],housing_inner[i]]
  ledgepoly=[ledge_outer[i],ledge_outer[j],ledge_inner[j],ledge_inner[i]]
  lippoly=[lip_outer[i],lip_outer[j],lip_inner[j],lip_inner[i]]
  ln=f'Bath_CoveCantileverLedge_{i+1:02d}';hn=f'Bath_CoveHousing_{i+1:02d}';dn=f'Bath_CoveDiffuser_{i+1:02d}'
  prism(ln,ledgepoly,3.900,3.940,mat,False,.002)
  prism(f'Bath_CoveConcealingLip_{i+1:02d}',lippoly,3.900,3.980,mat,False,.002)
  prism(hn,housingpoly,3.940,3.952,'ref_fixture_metal',False,.001)
  prism(dn,poly,3.952,3.960,'ref_fixture_emission',False,.001)
  x=sum(v[0] for v in poly)/4;z=sum(v[1] for v in poly)/4
  lamp=light(f'Bath_CoveSample_{i+1:02d}',[x,3.972,z],(1,.85,.82),140,5.2,1.8)
  # Match the physical 50mm strip instead of a 1.8m disc that generated
  # giant semicircle reflections and protruded beyond its concealed housing.
  tangent=Vector((poly[1][0]-poly[0][0],0,poly[1][1]-poly[0][1])).normalized()
  bx=Vector(p(tangent));bz=Vector((0,0,-1));by=bz.cross(bx).normalized()
  lamp.rotation_euler=Matrix((bx,by,bz)).transposed().to_euler()
  lamp.data.shape='RECTANGLE';lamp.data.size=min(math.dist(poly[0],poly[1]),math.dist(poly[2],poly[3]))-.02;lamp.data.size_y=.035
  G['lights'][-1]['fixture_object']=dn;G['lights'][-1]['position_note']='12mm above upward-facing diffuser, behind80mm concealing lip.'
  G['lights'][-1]['direction']=[0,1,0];G['lights'][-1]['emission_direction']=[0,1,0];G['lights'][-1]['preview_emitter_shape']='RECTANGLE';G['lights'][-1]['preview_emitter_size_m']=[round(lamp.data.size,6),.035]
  G['fixture_mounts'].append({'fixture':hn,'support_object':ln,'fixture_bottom_y':round(bbox(OB[hn])[0][1],6),'support_top_y':round(bbox(OB[ln])[1][1],6),'mount_gap':round(bbox(OB[hn])[0][1]-bbox(OB[ln])[1][1],6),'measured_from':'actual mesh vertices'})
 fixture('Bath_WestConnectorFixture',-13,0,3.32,.3,.7,35,(1,.57,.39))
 fixture('Bath_SouthConnectorFixture',0,14,3.32,.3,.7,35,(.65,.73,.87))
 water(oct_poly(4.15),'Octagonal_SteppedBasin');portals(['west','south'])
 G['interior_portals']=[{'name':'WarmLeftRearPortal','center':[-1.45,DECK,-A],'width':1.3,'clear_height':2.3,'leads_to':'west'},{'name':'DarkRightRearPortal','center':[1.45,DECK,-A],'width':1.3,'clear_height':2.3,'leads_to':'south'}]
 G['camera_views'].append({'name':'Reference3_OctagonalBath','position':[0,2.35,5.9],'target':[0,1.65,-2.9],'lens_mm':18})
 finish()

def preview_water():
 m=bpy.data.materials.new('PREVIEW_ONLY_WATER_NOT_EXPORTED');m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.012,.23,.26,1);bs.inputs['Roughness'].default_value=.12;bs.inputs['Metallic'].default_value=.0;bs.inputs['Transmission Weight'].default_value=.80;bs.inputs['IOR'].default_value=1.333
 if G['name']=='colonnade':bs.inputs['Base Color'].default_value=(.015,.045,.042,1);bs.inputs['Roughness'].default_value=.065;bs.inputs['Transmission Weight'].default_value=.65
 if G['name']=='octagonal_bath':bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.035;bs.inputs['Transmission Weight'].default_value=1;bs.inputs['IOR'].default_value=1.333
 nd=m.node_tree.nodes;lk=m.node_tree.links;tc=nd.new('ShaderNodeTexCoord');noise=nd.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=14;noise.inputs['Detail'].default_value=2;noise.inputs['Roughness'].default_value=.65;lk.new(tc.outputs['Generated'],noise.inputs['Vector']);bu=nd.new('ShaderNodeBump');bu.inputs['Strength'].default_value=.18;bu.inputs['Distance'].default_value=.022;lk.new(noise.outputs['Fac'],bu.inputs['Height']);lk.new(bu.outputs[0],bs.inputs['Normal'])
 for k,reg in enumerate(G['water_regions']):
  poly=reg['polygon_xz'];me=bpy.data.meshes.new('PreviewWater');me.from_pydata([p((x,WATER,z)) for x,z in poly],[],[tuple(reversed(range(len(poly))))]);me.update();ob=bpy.data.objects.new(f'PREVIEW_ONLY_Water_{k}',me);preview.objects.link(ob);me.materials.append(m)

def threshold_evidence():
 G['threshold_measurements']=[]
 for portal in G['portal_contracts']+G.get('interior_portals',[]):
  if not portal.get('open',True):continue
  x,y,z=portal['center'];floors=[];roofs=[]
  for ob in runtime.objects:
   if ob.type!='MESH' or ob.name.startswith('COLLISION_'):continue
   b=bbox(ob)
   if b[0][0]-1e-5<=x<=b[1][0]+1e-5 and b[0][2]-1e-5<=z<=b[1][2]+1e-5:
    if abs(b[1][1]-DECK)<1e-4:floors.append((ob,b))
    if b[0][1]>DECK+1:roofs.append((ob,b))
  if not floors or not roofs:raise RuntimeError('Missing enclosed threshold '+str(portal))
  floor,fb=min(floors,key=lambda t:t[1][0][1]);roof,rb=min(roofs,key=lambda t:t[1][0][1])
  G['threshold_measurements'].append({'portal':portal.get('side',portal.get('name')),'threshold_object':floor.name,'threshold_top_y':round(fb[1][1],6),'threshold_bottom_y':round(fb[0][1],6),'overhead_object':roof.name,'overhead_bottom_y':round(rb[0][1],6),'measured_clear_height_m':round(rb[0][1]-fb[1][1],6),'support':'Integral solid threshold extends to structural foundation; no floating threshold skin.','measured_from':'exported mesh vertices at doorway center'})


def audit():
 issues=[];counts=Counter();uv_errors=[];tangent_failures=[];bounds=[]
 for ob in runtime.objects:
  if ob.type!='MESH':continue
  bm=bmesh.new();bm.from_mesh(ob.data)
  non=sum(1 for e in bm.edges if not e.is_manifold);bm.free()
  if non:issues.append({'object':ob.name,'nonmanifold_edges':non})
  if not ob.name.startswith('COLLISION_'):
   counts['visual_meshes']+=1;counts['vertices']+=len(ob.data.vertices);counts['polygons']+=len(ob.data.polygons)
   if not ob.data.uv_layers:uv_errors.append(ob.name)
   else:
    try:ob.data.calc_tangents(uvmap='UVMap')
    except Exception as e:tangent_failures.append({'object':ob.name,'error':str(e)})
  b=bbox(ob);bounds.append(b)
 for c in G['support_contacts']:
  if abs(c['gap'])>1e-4:issues.append({'support_gap':c})
  if min(c['footprint_overlap_xz'])<=0:issues.append({'missing_support_overlap':c})
 for mount in G.get('fixture_mounts',[]):
  if abs(mount['mount_gap'])>1e-5:issues.append({'fixture_mount_gap':mount})
 metrics={'mesh_audit':'PASS' if not (issues or uv_errors or tangent_failures) else 'FAIL','issues':issues,'missing_uv':uv_errors,'tangent_failures':tangent_failures,'counts':dict(counts),'proxy_count':len(G['collision_proxies']),'measured_support_contacts':len(G['support_contacts']),'bounds':{'min':rr([min(b[0][i] for b in bounds) for i in range(3)]),'max':rr([max(b[1][i] for b in bounds) for i in range(3)])},'validation_scope':'Blender CPU mesh, tangent and contact validation only. No Godot/NVIDIA visual validation.'}
 G['audit']=metrics
 with open(os.path.join(QA,G['name']+'_audit.json'),'w') as f:json.dump(metrics,f,indent=2)
 if issues or uv_errors or tangent_failures:raise RuntimeError(json.dumps(metrics))

def route_waypoints():
 n=G['name'];routes={}
 if n=='colonnade':
  routes={'south_to_water':[[0,.52,16],[0,.52,13.4],[0,.52,12.6],[0,.335,12.2],[0,.15,11.8],[0,-.035,11.4],[0,-.22,10.8]],'north_to_water':[[0,.52,-16],[0,.52,-13.4],[0,.52,-12.6],[0,.335,-12.2],[0,.15,-11.8],[0,-.035,-11.4],[0,-.22,-10.8]],'east_to_water_around_pier':[[16,.52,0],[6,.52,0],[5,.52,0],[4.6,.335,0],[4.2,.15,0],[3.8,-.035,0],[3.35,-.22,1.1],[0,-.22,1.1]]}
 elif n=='cyan_corridor':
  routes={'south_to_water':[[0,.52,16],[0,.52,13],[0,.52,11.8],[0,.335,11.4],[0,.15,11],[0,-.035,10.6],[0,-.22,10]],'east_dogleg_to_water':[[16,.52,0],[5.4,.52,0],[5.4,.52,-8.8],[4.5,.52,-8.8],[4.5,.52,-9.8],[2.6,.52,-9.8],[1.6,.52,-9.8],[1.2,.335,-9.8],[.8,.15,-9.8],[.4,-.035,-9.8],[-.3,-.22,-9.8]]}
 else:
  routes={'west_to_warm_left_portal':[[-16,.52,0],[-10.5,.52,0],[-10.5,.52,-8],[-9.7,.52,-8],[-9.7,.52,-9],[-1.45,.52,-9],[-1.45,.52,-6],[-1.45,.52,-5]],'south_to_dark_right_portal':[[0,.52,16],[0,.52,12],[9.8,.52,12],[9.8,.52,11.2],[10.5,.52,11.2],[10.5,.52,-8.2],[9.8,.52,-8.2],[9.8,.52,-9],[1.45,.52,-9],[1.45,.52,-6],[1.45,.52,-5]]}
 G['connector_route_waypoints']=[{'name':key,'coordinates':'Godot local feet positions','waypoints':value,'status':'geometric route witness; existing-controller traversal is separately tested by integration owner'}for key,value in routes.items()]

def export_texture_free():
 # GLB uses lightweight named role placeholders. The editable .blend keeps the
 # real shared glaze nodes/maps, and runtime binds these same exact role names.
 used={m for ob in runtime.objects for m in ob.data.materials if m}
 replacements={};original_names={};slots=[]
 for mat in used:
  name=mat.name
  if not(name.startswith('ref_tile_') or name=='ref_grout'):continue
  original_names[mat]=name;mat.name=name+'__SOURCE_PREVIEW'
  flat=bpy.data.materials.new(name);flat.use_nodes=True
  bs=flat.node_tree.nodes.get('Principled BSDF')
  srgb=mat.diffuse_color[:3];linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in srgb]
  bs.inputs['Base Color'].default_value=tuple(linear)+(1,)
  bs.inputs['Metallic'].default_value=0
  bs.inputs['Roughness'].default_value=.82 if name=='ref_grout' else ((.40 if name.endswith('_dry') or 'pink' in name else .34) if '_satin' in name else (.26 if name.endswith('_dry') else .075))
  flat.diffuse_color=tuple(srgb)+(1,);replacements[mat]=flat
 for ob in runtime.objects:
  for index,mat in enumerate(ob.data.materials):
   if mat in replacements:slots.append((ob,index,mat));ob.data.materials[index]=replacements[mat]
 try:
  bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,G['name']+'.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
 finally:
  for ob,index,mat in slots:ob.data.materials[index]=mat
  for flat in replacements.values():bpy.data.materials.remove(flat)
  for mat,name in original_names.items():mat.name=name

def finish():
 sys.path.insert(0,os.path.dirname(__file__))
 from water_rooms_joint_helpers import apply_manifest
 apply_manifest(G,OB,runtime,box,uv_metric,bbox)
 from water_rooms_lighting_helpers import apply_final_lighting
 apply_final_lighting(G,OB,M,runtime,preview,box,light,bbox)
 threshold_evidence()
 audit()
 sys.path.insert(0,os.path.join(ROOT,'tools/materials/reference_wing'))
 from blender_materials import attach_named_materials
 attach_named_materials()
 # Include a source-preserving camera and labeled render-only water, never in GLB.
 preview_water();v=G['camera_views'][0]
 cd=bpy.data.cameras.new('REFERENCE_CAMERA');cam=bpy.data.objects.new('REFERENCE_CAMERA',cd);preview.objects.link(cam);cam.location=p(v['position']);target=Vector(p(v['target']));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cd.lens=v['lens_mm'];cd.clip_start=.05;cd.clip_end=120;bpy.context.scene.camera=cam
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=args.samples;scene.cycles.use_denoising=False;scene.render.resolution_x=700;scene.render.resolution_y={'colonnade':700,'cyan_corridor':688,'octagonal_bath':875}[G['name']];scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.025,.04,.04,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.12;scene.view_settings.view_transform='AgX';scene.render.film_transparent=False
 scene.render.use_stamp=True;scene.render.use_stamp_note=True;scene.render.stamp_note_text='BLENDER CPU COMPOSITION PREVIEW | NOT GODOT / NVIDIA VALIDATION';scene.render.stamp_font_size=12
 for flag in ('use_stamp_date','use_stamp_time','use_stamp_render_time','use_stamp_frame','use_stamp_frame_range','use_stamp_memory','use_stamp_hostname','use_stamp_camera','use_stamp_lens','use_stamp_scene','use_stamp_marker','use_stamp_filename','use_stamp_sequencer_strip'):
  if hasattr(scene.render,flag):setattr(scene.render,flag,False)
 if G['name']!='colonnade':cd.sensor_fit='HORIZONTAL'
 projection=cam.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=scene.render.resolution_x,y=scene.render.resolution_y,scale_x=scene.render.pixel_aspect_x,scale_y=scene.render.pixel_aspect_y)
 v['fov_degrees']=round(math.degrees(2*math.atan(1/projection[1][1])),6);v['fov_axis']='vertical';v['reference_resolution']=[scene.render.resolution_x,scene.render.resolution_y];v['sensor_fit']=cd.sensor_fit;v['sensor_width_mm']=cd.sensor_width;v['sensor_height_mm']=cd.sensor_height
 if G['name']!='colonnade':
  frame=cd.view_frame(scene=scene);v['fov_degrees']=round(math.degrees(math.atan(max(q.y/-q.z for q in frame))-math.atan(min(q.y/-q.z for q in frame))),6);v['original_reference_resolution']={'cyan_corridor':[400,393],'octagonal_bath':[400,500]}[G['name']]
 route_waypoints()
 scene['uv_contract']=f"UV0 1 UV/m; physical tile pitch {G['tile_pitch_m']}m; no mesh UV rescaling."
 scene['preview_label']='BLENDER CPU COMPOSITION PREVIEW ONLY; runtime water and GPU visuals not validated.'
 # Hide proxies in authoring viewport while keeping them inspectable and exportable.
 for ob in runtime.objects:
  if ob.name.startswith('COLLISION_'):ob.hide_render=True;ob.hide_set(True)
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC,G['name']+'.blend'))
 bpy.ops.file.make_paths_relative();bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC,G['name']+'.blend'))
 for ob in list(bpy.context.selected_objects):ob.select_set(False)
 for ob in runtime.objects:ob.hide_set(False);ob.select_set(True)
 export_texture_free()
 for ob in runtime.objects:
  ob.select_set(False)
  if ob.name.startswith('COLLISION_'):ob.hide_set(True)
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC,G['name']+'.blend'))
 # Compatibility alias: exact boxes only, never bounding-box substitutes for wedges.
 G['collision_boxes']=[{'name':c['name'],'position':c['position'],'size':c['size'],'type':'BOX'} for c in G['collision_proxies'] if c['type']=='BOX']
 G['water_steps']=[{'name':s['object'],'top_y':s['top_y'],'footprint_xz':s['footprint_xz']} for s in G['steps']]
 # Profile real submerged support tops too, without calling them stair treads.
 step_objects={s['object']for s in G['steps']}
 for proxy in G['collision_proxies']:
  if proxy['type']!='BOX' or proxy['source_object'] in step_objects:continue
  center,size=proxy['center'],proxy['size'];top=center[1]+size[1]/2
  if BOTTOM+1e-6<top<WATER-1e-6:
   b=bbox(OB[proxy['source_object']]);poly=poly_rect(b[0][0],b[1][0],b[0][2],b[1][2])
   G['water_steps'].append({'name':proxy['source_object'],'top_y':round(b[1][1],6),'footprint_xz':poly,'profile_kind':'submerged support top, not stair','collision':proxy['name'],'measured_from':'actual exported collision envelope and visual mesh vertices'})
 with open(os.path.join(OUT,G['name']+'.geometry.json'),'w') as f:json.dump(G,f,indent=2)
 if args.render:
  scene.render.filepath=os.path.join(QA,G['name']+'_blender_cpu.png');bpy.ops.render.render(write_still=True)
 print('ROOM_COMPLETE',G['name'],json.dumps(G['audit']))

for name,fn in [('colonnade',colonnade),('cyan_corridor',cyan_corridor),('octagonal_bath',octagonal_bath)]:
 if not args.only or args.only==name:fn()
