"""Original PoolCore facility modules, Blender 4.3.2. All dimensions are metres.
Run: blender -b --python tools/blender/expansion/build_expansion.py [-- --only shower_changing]
Editable .blend files are saved before material batching. GLBs contain separate
simple convex COLLISION_ proxies. Runtime supplies water and formal materials.
Reference: assets/models/expansion/reference/poolcore_ai_architecture_reference.png
"""
import bpy, math, os, sys, json, argparse
from mathutils import Vector
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../..'))
OUT=os.path.join(ROOT,'assets/models/expansion'); SOURCE=os.path.join(ROOT,'tools/blender/expansion/source')
os.makedirs(OUT,exist_ok=True);os.makedirs(SOURCE,exist_ok=True);open(os.path.join(SOURCE,'.gdignore'),'a').close()
P=argparse.ArgumentParser();P.add_argument('--only');args=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
M={};MANIFEST={}; current=''; serial=0
F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
PALETTE=[('formal_dry_deck',(.76,.83,.82,1),.52,0),('formal_basin',(.49,.72,.79,1),.3,0),('formal_wainscot',(.45,.68,.72,1),.3,0),('formal_plaster',(.89,.89,.86,1),.84,0),('formal_coping',(.84,.86,.82,1),.4,0),('brushed stainless',(.57,.65,.65,1),.28,.95),('black',(.04,.06,.065,1),.45,.3),('service',(.43,.54,.53,1),.42,.12),('dark sign board',(.06,.13,.17,1),.65,0),('lamp',(.94,.91,.80,1),.3,0),('formal_glazing',(.7,.85,.9,1),.15,0),('collision',(1,0,1,1),1,0)]
def reset(name):
 global M,current,serial
 current=name;serial=0;bpy.context.preferences.filepaths.save_version=0
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for d in list(bpy.data.materials):bpy.data.materials.remove(d)
 M={}
 for role,color,rough,metal in PALETTE:
  m=bpy.data.materials.new(role);m.diffuse_color=color;m.use_nodes=True
  p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=color;p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;M[role]=m
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
 bpy.context.scene['authoring']='Original procedural Blender facility design; not downloaded.'
 bpy.context.scene['reference']='AI architecture reference, not runtime footage.'
 bpy.context.scene['grid_metres']=32.0;bpy.context.scene['ceramic_pitch_metres']=.1

def p(v):return (v[0],-v[2],v[1])
def mesh(name,verts,faces,role='formal_plaster',bevel=0,proxy=False):
 me=bpy.data.meshes.new(name);me.from_pydata([p(v) for v in verts],[],faces);me.update()
 ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);me.materials.append(M['collision' if proxy else role])
 bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
 uv=me.uv_layers.new(name='UVMap')
 for face in me.polygons:
  axis=max(range(3),key=lambda a:abs(face.normal[a]));axes=[a for a in range(3) if a!=axis]
  for li in face.loop_indices:
   co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
 if bevel and not proxy:
  mod=ob.modifiers.new('Real scale edge easing','BEVEL');mod.width=bevel;mod.segments=1
  bpy.ops.object.modifier_apply(modifier=mod.name)
  mod=ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=mod.name)
 ob['units']='metres';ob['uv_density']='1 UV unit / metre; ceramic pitch 0.1m';ob['source_role']=role
 if proxy:ob['collision_proxy']=True;ob.hide_render=True
 ob.select_set(False);return ob

def box(name,c,s,role='formal_plaster',bevel=.008,col=True):
 x,y,z=c;a,b,d=[v/2 for v in s]
 v=[(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
 ob=mesh(name,v,F,role,bevel)
 if col:mesh('COLLISION_'+name,v,F,role,0,True)
 return ob

def collision_box(name,c,s):
 x,y,z=c;a,b,d=[v/2 for v in s]
 v=[(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
 return mesh('COLLISION_'+name,v,F,'brushed stainless',0,True)

def rod(name,a,b,r=.025,role='brushed stainless',n=10):
 aa=Vector(a);bb=Vector(b);axis=(bb-aa).normalized();u=axis.cross(Vector((0,1,0)))
 if u.length<.1:u=axis.cross(Vector((1,0,0)))
 u.normalize();v=axis.cross(u).normalized();verts=[]
 for q in [aa,bb]:
  for i in range(n):verts.append(tuple(q+r*(math.cos(i*math.tau/n)*u+math.sin(i*math.tau/n)*v)))
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 return mesh(name,verts,faces,role)

def transformed(fn,at=(0,0,0),yaw=0,prefix=''):
 before=set(bpy.context.scene.objects);fn()
 for ob in set(bpy.context.scene.objects)-before:
  for vert in ob.data.vertices:
   x,y,z=vert.co.x,vert.co.z,-vert.co.y
   xx=x*math.cos(yaw)+z*math.sin(yaw);zz=-x*math.sin(yaw)+z*math.cos(yaw)
   vert.co=p((xx+at[0],y+at[1],zz+at[2]))
  ob.name=prefix+ob.name if not ob.name.startswith('COLLISION_') else 'COLLISION_'+prefix+ob.name[10:]

def bench():
 box('Bench_CeramicSeat',(0,.42,0),(2.4,.12,.6),'formal_coping',.012)
 for x in [-.88,.88]:box('Bench_TiledPedestal',(x,.18,0),(.24,.36,.46),'formal_wainscot')
 # Deliberate physical end-reveal, not a tessellated tile surface.
 for z in [-.29,.29]:box('Bench_EdgeReveal',(0,.41,z),(2.36,.025,.018),'brushed stainless',.003,False)

def shower():
 box('Shower_TileBack',(0,1.2,0),(.42,2.4,.16),'formal_wainscot',.01)
 rod('Shower_Riser',(0,.8,.11),(0,2.12,.11),.022)
 rod('Shower_Arm',(0,2.12,.11),(0,2.12,.44),.022)
 box('Shower_RainHead',(0,2.09,.44),(.23,.035,.18),'brushed stainless',.008,False)
 rod('Shower_Mixer',(-.11,1.02,.13),(.11,1.02,.13),.035)
 for x in [-.09,.09]:rod('Shower_Tap',(x,1.02,.13),(x,1.02,.2),.035)

def drain():
 box('Drain_Channel',(0,-.027,0),(1.2,.054,.18),'black',.001,False)
 for z in [-.085,.085]:box('Drain_OuterLip',(0,.002,z),(1.2,.012,.015),'brushed stainless',.001,False)
 for i in range(16):box('Drain_GrateBar',(-.5625+i*.075,.004,0),(.032,.012,.15),'brushed stainless',0,False)

def rail():
 for x in [-1.05,1.05]:
  rod('Rail_Post',(x,0,0),(x,.85,0),.026)
  box('Rail_Foot',(x,.018,0),(.13,.036,.13),'brushed stainless',.004,False)
 rod('Rail_Top',(-1.05,.85,0),(1.05,.85,0),.03)
 # Two thin post proxies and the top bar, not a solid wall across the rail.
 for x in [-1.05,1.05]:collision_box('Rail_Post',(x,.43,0),(.06,.86,.06))
 collision_box('Rail_Top',(0,.85,0),(2.1,.06,.06))

def portal():
 for x in [-2.35,2.35]:box('Portal_Jamb',(x,1.75,0),(.3,3.5,.48),'formal_plaster',.012)
 box('Portal_Lintel',(0,3.35,0),(4.4,.3,.48),'formal_plaster',.012)
 for x in [-2.35,2.35]:box('Portal_TileFoot',(x,.6,.005),(.32,1.2,.5),'formal_wainscot',.008,False)

def plaque():
 box('Plaque_Board',(0,0,0),(.8,.42,.045),'dark sign board',.012,False)
 # Quiet physical arrow, text is a runtime Label3D with no copied font assets.
 mesh('Plaque_Arrow',[(-.27,.015,.028),(-.10,.015,.028),(-.10,.07,.028),(-.01,0,.028),(-.10,-.07,.028),(-.10,-.015,.028),(-.27,-.015,.028)],[(0,1,2,3,4,5,6)],'formal_coping')

def service_door():
 box('Service_OuterFrame',(0,1.25,0),(1.38,2.5,.22),'brushed stainless',.012)
 box('Service_RecessedLeaf',(0,1.21,.13),(1.18,2.36,.09),'service',.01,False)
 for i in range(7):box('Service_VentSlot',(0,.35+i*.065,.181),(.66,.025,.009),'black',.002,False)
 rod('Service_Handle',(.39,1.03,.2),(.39,1.2,.2),.019)
 for y in [.5,1.9]:box('Service_Hinge',(-.59,y,.19),(.04,.14,.04),'brushed stainless',.003,False)

def lamp(at,prefix):
 box(prefix+'_Housing',at,(.25,.6,.16),'brushed stainless',.008,False)
 box(prefix+'_Diffuser',(at[0],at[1],at[2]+.09),(.16,.48,.03),'lamp',.008,False)

def arch(name,z,spring=3.6,rise=1.7,span=20.2):
 n=28;v=[]
 for i in range(n+1):
  a=math.pi*i/n
  for r,h in [(span/2,rise),(span/2+.34,rise+.34)]:
   for dep in [-.32,.32]:v.append((r*math.cos(a),spring+h*math.sin(a),z+dep))
 faces=[]
 for i in range(n):
  a=i*4;b=a+4;faces += [(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)]
 faces += [(0,1,3,2),(n*4,n*4+2,n*4+3,n*4+1)]
 mesh(name,v,faces,'formal_plaster',.005)
 for x in [-(span/2+.17),span/2+.17]:box(name+'_Pier',(x,(spring+.52)/2,z),(.34,spring-.52,.64),'formal_plaster')
 # Arch underside is >3.6m; no costly trimesh needed for a 1.64m player.

def floor_deck(wet):
 box('Foundation',(0,-.995,0),(32,.55,32),'formal_basin',0)
 if wet:
  edges=[-12,-10,-3,3,10,12]
  for i in range(5):
   for j in range(5):
    if i in [1,3] and j in [1,3]:continue
    x0,x1=edges[i:i+2];z0,z1=edges[j:j+2]
    box('DryDeck_%s_%s'%(i,j),((x0+x1)/2,-.10,(z0+z1)/2),(x1-x0,1.24,z1-z0),'formal_dry_deck',0)
  for sx in [-1,1]:
   for sz in [-1,1]:
    # Recessed pool stairs: six 20.7cm risers, no geometry crossing central route.
    for i in range(5):
     top=.52-(i+1)*(1.24/6);x=sx*(3+(i+.5)*.4)
     box('BasinStair_%s_%s_%s'%(sx,sz,i),(x,(-.72+top)/2,sz*6.4),(.4,top+.72,1.8),'formal_basin',0)
    transformed(rail,(sx*4.2,.52,sz*7.48),0,'Basin_')
 else:box('DryDeck',(0,-.10,0),(24,1.24,24),'formal_dry_deck',0)
 # Dry technical apron at corners. Four entry stairs preserve source floor at +/-16m.
 for sx in [-1,1]:
  for sz in [-1,1]:
   box('Apron_NorthSouth',(sx*10,-.10,sz*14),(12,1.24,4),'formal_dry_deck',0)
   box('Apron_EastWest',(sx*14,-.10,sz*8),(4,1.24,8),'formal_dry_deck',0)
 for side in range(4):
  for i in range(7):
   top=.52-(i+1)*.155;d=12+(i+.5)*.5
   c=(0,(-.72+top)/2,d) if side%2==0 else (d,(-.72+top)/2,0)
   c=tuple(-a if k in [0,2] and side>=2 else a for k,a in enumerate(c))
   s=(8,top+.72,.5) if side%2==0 else (.5,top+.72,8)
   box('EntryStep_%s_%s'%(side,i),c,s,'formal_dry_deck',0)

def shell(kind,height,inner,wet=False):
 floor_deck(wet)
 # Boundary ownership matches the original: only north and west own shared walls.
 for offset in [-10,10]:
  box('Outer_North',(offset,(height-.78)/2,-16),(12,height+.78,.6),'formal_plaster',0)
  box('Outer_West',(-16,(height-.78)/2,offset),(.6,height+.78,12),'formal_plaster',0)
 for west in [False,True]:box('Outer_Header',(-16 if west else 0,(height+5.4)/2,0 if west else -16),(.6 if west else 8,height-5.4,8 if west else .6),'formal_plaster',0)
 # Human-scale inner enclosure, connected through all four cardinal portals.
 for side in range(4):
  def wall():
   for x in [-7,7]:
    box('Room_Dado',(x,1.26,-11.6),(9.6,1.48,.4),'formal_wainscot',.008)
    box('Room_Plaster',(x,(inner+2)/2,-11.6),(9.6,inner-2,.44),'formal_plaster',.008)
   box('Room_DoorHeader',(0,(inner+3.72)/2,-11.6),(4.4,inner-3.72,.44),'formal_plaster',.008)
   transformed(portal,(0,.52,-11.6),0,'Room_')
   transformed(plaque,(3.05,2.42,-11.36),0,'Wayfinding_')
  transformed(wall,yaw=side*math.pi/2,prefix='%s_'%side)
 # Full outer roof ring, no unintentional sky leaks around the inner enclosure.
 for x in [-14,14]:box('Roof_Apron',(x,height,0),(4,.36,32),'formal_plaster',0)
 for z in [-14,14]:box('Roof_Apron',(0,height,z),(24,.36,4),'formal_plaster',0)
 if kind=='skylight_gallery':
  # Two real 4m x 16m roof openings over basins, not emissive ceiling cards.
  for x,w in [(-11,2),(0,6),(11,2)]:box('Gallery_Roof',(x,inner,0),(w,.42,24),'formal_plaster',0)
  for x in [-6.5,6.5]:
   for z in [-10,10]:box('Gallery_RoofEnd',(x,inner,z),(7,.42,4),'formal_plaster',0)
   for z in [-8,8]:box('Skylight_Reveal',(x,inner+.32,z),(7,.64,.2),'formal_plaster',.01)
   for xx in [x-3.5,x+3.5]:box('Skylight_Reveal',(xx,inner+.32,0),(.2,.64,16),'formal_plaster',.01)
   for z in [-8,-4,0,4,8]:box('Skylight_Mullion',(x,inner+.68,z),(7,.1,.08),'brushed stainless',.002,False)
 elif kind=='service_transition':
  for x in [-7,7]:box('Service_Roof',(x,inner,0),(10,.38,24),'formal_plaster',0)
  for z in [-8,8]:box('Service_Roof',(0,inner,z),(4,.38,8),'formal_plaster',0)
  for x in [-2,2]:box('Service_Lightwell',(x,inner+.5,0),(.18,1,8),'formal_plaster',.008)
  for z in [-4,4]:box('Service_Lightwell',(0,inner+.5,z),(4,1,.18),'formal_plaster',.008)
 else:box('Interior_Ceiling',(0,inner,0),(24,.4,24),'formal_plaster',0)
 # Occupied vestibules must be enclosed overhead even when inner roof is lower.
 for side in range(4):
  if inner<height:
   transformed(lambda:box('Vestibule_Reveal',(0,(height+inner)/2,-12),(8,height-inner,.3),'formal_plaster',0),yaw=side*math.pi/2)

def room(kind):
 wet=kind in ['low_arched_bath','skylight_gallery']
 heights={'shower_changing':(6.2,4.5),'low_arched_bath':(6.4,5.8),'skylight_gallery':(7.2,6.5),'service_transition':(6.,4.3)}
 shell(kind,*heights[kind],wet)
 if kind=='shower_changing':
  for sx in [-1,1]:
   for z in [-7.5,-4.8,4.8,7.5]:
    transformed(shower,(sx*10.6,.52,z),-sx*math.pi/2,'ShowerBay_')
    transformed(drain,(sx*9.8,.53,z),math.pi/2,'ShowerBay_')
   for z in [-8.85,-6.15,-4.25,4.25,6.15,8.85]:box('Shower_PrivacyFin',(sx*9.5,1.7,z),(2.5,2.36,.12),'formal_wainscot',.006)
  # Four paired changing islands, kept outside an8.3m clear cardinal cross.
  # Existing ceramic benches flank low locker-like storage, not random clutter.
  for sx in [-1,1]:
   for sz in [-1,1]:
    center_x=sx*5.15;center_z=sz*5.95
    for dx in [-.65,.65]:transformed(bench,(center_x+dx,.52,center_z),math.pi/2,'ChangingIsland_')
    box('ChangingIsland_Core',(center_x,1.10,center_z),(.54,1.16,3.5),'formal_wainscot',.008)
    box('ChangingIsland_Cap',(center_x,1.70,center_z),(.60,.08,3.56),'formal_coping',.008,False)
    for side in [-1,1]:
     for dz in [-1.12,0,1.12]:
      box('ChangingIsland_StorageLeaf',(center_x+side*.285,1.32,center_z+dz),(.026,.62,1.08),'service',.004,False)
      box('ChangingIsland_FingerPull',(center_x+side*.307,1.40,center_z+dz+.39),(.018,.055,.16),'brushed stainless',.002,False)
  # Two shallow structural ribs are seated into the underside of the ceiling.
  # z=+/-6 aligns with existing suspended fixture/cable locations, no new lamps.
  for z in [-6,6]:box('Changing_CeilingRib',(0,4.21,z),(23.2,.24,.36),'formal_plaster',.008)


 elif kind=='low_arched_bath':
  for z in [-8,-4,4,8]:arch('Bath_LowArch',z)
  for sx in [-1,1]:
   for z in [-7.5,7.5]:transformed(bench,(sx*10.8,.52,z),math.pi/2,'Bath_')

 elif kind=='skylight_gallery':
  for sx in [-1,1]:
   for z in [-7,7]:transformed(bench,(sx*10.8,.52,z),math.pi/2,'Gallery_')
  for z in [-8,0,8]:box('Gallery_RoofBeam',(0,6.1,z),(24,.45,.24),'formal_plaster',.008)
 else:
  for sx in [-1,1]:
   for z in [-7,7]:transformed(service_door,(sx*11.27,.52,z),-sx*math.pi/2,'Service_')
   for z in [-7,7]:transformed(bench,(sx*6,.52,z),0,'Service_')
  for x in [-8,8]:
   for z in [-8,8]:
    box('Service_Pilaster',(x,2.25,z),(.42,3.46,.42),'formal_plaster',.008)

 # Large plumbing/service clutter is deliberately not added to playable paths.

def save(name):
 bpy.ops.object.select_all(action='DESELECT')
 scene=bpy.context.scene
 scene['module']=name
 source=os.path.join(SOURCE,name+'.blend');bpy.ops.wm.save_as_mainfile(filepath=source)
 visible=[o for o in scene.objects if o.type=='MESH' and not o.name.startswith('COLLISION_')]
 proxies=[o for o in scene.objects if o.type=='MESH' and o.name.startswith('COLLISION_')]
 tri_count=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in visible)
 # Only export batches are joined. Saved source retains each named editable component.
 groups={}
 for o in visible:groups.setdefault(o.data.materials[0].name,[]).append(o)
 for role,objects in groups.items():
  bpy.ops.object.select_all(action='DESELECT')
  for o in objects:o.select_set(True)
  bpy.context.view_layer.objects.active=objects[0]
  if len(objects)>1:bpy.ops.object.join()
  bpy.context.object.name='VIS_'+role.replace(' ','_')
 bpy.ops.object.select_all(action='SELECT')
 bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False)
 MANIFEST[name]={'visual_triangles':tri_count,'visual_material_batches':len(groups),'collision_proxies':len(proxies),'source_blend':'tools/blender/expansion/source/'+name+'.blend','glb':'assets/models/expansion/'+name+'.glb','source':'original procedural Blender geometry','uv_metres_per_unit':1.0}
 print('EXPANSION_ASSET',name,json.dumps(MANIFEST[name]))

ASSETS={'facility_bench':bench,'facility_shower':shower,'facility_drain':drain,'facility_rail':rail,'facility_portal':portal,'facility_wayfinding':plaque,'facility_service_door':service_door}
for name,fn in ASSETS.items():
 if args.only and name!=args.only:continue
 reset(name);fn();save(name)
for name in ['shower_changing','low_arched_bath','skylight_gallery','service_transition']:
 if args.only and name!=args.only:continue
 reset(name);room(name);save(name)
manifest_path=os.path.join(OUT,'manifest.json')
if args.only and os.path.exists(manifest_path):old=json.load(open(manifest_path));old.update(MANIFEST);MANIFEST=old
json.dump(MANIFEST,open(manifest_path,'w'),indent=2,sort_keys=True)
