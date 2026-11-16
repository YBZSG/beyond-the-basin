extends RefCounted
const Gloss=preload("res://scripts/dreamcore/uncanny/crossing_inverted_ceramic_gloss.gd")
## Original finite architecture; reference-matched real construction, metres.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const Effects=preload("res://scripts/dreamcore/uncanny/inverted_pool_effects.gd")
const Clip=preload("res://scripts/dreamcore/uncanny/crossing_inverted_clip_material.gd")
const ClipShader=preload("res://shaders/dreamcore/uncanny/crossing_inverted_clip_base.gdshader")
const PREFIX="inverted_pool_"
const ASSETS="res://assets/dreamcore/uncanny/inverted_pool/"
static var _architecture:Array=[]
static func material_specs()->Dictionary:
 var out={}
 for key in ["concrete","tile","cyan","blue"]:out[PREFIX+key]={"albedo":ASSETS+key+"_albedo.png","normal":ASSETS+key+"_normal.png","orm":ASSETS+key+"_orm.png","period":3.2,"strength":.48 if key=="concrete" else .55,"tint":"ffffff","roughness_channel":"g"}
 for key in ["tile","blue"]:out[PREFIX+"shell_"+key]=out[PREFIX+key].duplicate()
 out[PREFIX+"shell_floor"]=out[PREFIX+"tile"].duplicate();out[PREFIX+"shell_floor"].tint="b5cbd0"
 var concrete:Dictionary=out[PREFIX+"concrete"]
 for role in ["albedo","normal","orm"]:concrete[role]=ASSETS+"concrete_v2_"+role+".png"
 out[PREFIX+"basin_tile"]=out[PREFIX+"tile"].duplicate();out[PREFIX+"basin_tile"].tint="a7cbd4"
 # Same ceramic stock, subtly darker full-height structural pilaster glaze.
 out[PREFIX+"pier_tile"]=out[PREFIX+"tile"].duplicate();out[PREFIX+"pier_tile"].tint="d2d9d5"
 return out
static func materials_ready()->void:
 if G._mats.has(PREFIX+"concrete"):return
 for key:String in material_specs():
  var spec:Dictionary=material_specs()[key];var m=StandardMaterial3D.new();m.resource_name=key;m.albedo_texture=load(spec.albedo);m.albedo_color=Color(spec.tint);m.normal_enabled=true;m.normal_texture=load(spec.normal);m.normal_scale=spec.strength;m.roughness_texture=load(spec.orm);m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN;m.roughness=1.;m.ao_enabled=true;m.ao_texture=m.roughness_texture;m.ao_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED;m.uv1_scale=Vector3.ONE/float(spec.period);m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC;m.set_meta("annex_pbr_spec",spec);G._mats[key]=m
 for row in [["joint","38403e",.92,0.],["steel","9baba7",.36,.82],["dark_steel","303b39",.48,.70],["rubber","242a27",.95,0.],["paint","8faaa6",.49,.15],["warm","ffe3b5",.45,0.],["cool","edf5f2",.5,0.]]:
  var m=StandardMaterial3D.new();m.resource_name=PREFIX+row[0];m.albedo_color=Color(row[1]);m.roughness=row[2];m.metallic=row[3]
  if row[0] in ["warm","cool"]:m.emission_enabled=true;m.emission=Color(row[1]);m.emission_energy_multiplier=2.0 if row[0]=="warm" else 1.4
  G._mats[PREFIX+row[0]]=m
static func _box(a:Array,p:Vector3,s:Vector3,key:String,collision:bool=true,bevel:float=0.0)->void:
 a.append(G.item(chamfer_mesh(s,bevel),p,PREFIX+key,collision) if bevel>0 else G.box(p,s,PREFIX+key,collision))
static func _tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,n:Vector3)->void:
 if (b-a).cross(c-a).dot(n)>0:
  var t=b;b=c;c=t
 st.set_normal(n.normalized())
 for p in [a,b,c]:st.add_vertex(p)
static func _quad(st:SurfaceTool,p:Array,n:Vector3)->void:
 _tri(st,p[0],p[1],p[2],n);_tri(st,p[0],p[2],p[3],n)
static func chamfer_mesh(size:Vector3,b:float)->Mesh:
 var h=size*.5;var k=h-Vector3.ONE*minf(b,minf(h.x,minf(h.y,h.z))*.45);var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for axis in 3:
  var u=(axis+1)%3;var v=(axis+2)%3
  for s in [-1.,1.]:
   var q:Array=[];var normal=Vector3.ZERO;normal[axis]=s
   for uv in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
    var p=Vector3.ZERO;p[axis]=s*h[axis];p[u]=uv.x*k[u];p[v]=uv.y*k[v];q.append(p)
   _quad(st,q,normal)
 for axis in 3:
  var u=(axis+1)%3;var v=(axis+2)%3
  for su in [-1.,1.]:
   for sv in [-1.,1.]:
    var q:Array=[];var n=Vector3.ZERO;n[u]=su;n[v]=sv
    for e in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
     var p=Vector3.ZERO;p[axis]=e.x*k[axis];p[u]=su*(h[u] if e.y==0 else k[u]);p[v]=sv*(k[v] if e.y==0 else h[v]);q.append(p)
    _quad(st,q,n.normalized())
 for x in [-1.,1.]:
  for y in [-1.,1.]:
   for z in [-1.,1.]:_tri(st,Vector3(x*h.x,y*k.y,z*k.z),Vector3(x*k.x,y*h.y,z*k.z),Vector3(x*k.x,y*k.y,z*h.z),Vector3(x,y,z).normalized())
 return st.commit()
static func rod(a:Vector3,b:Vector3,r:float,key:String,segments:int=16)->Dictionary:
 var mesh=CylinderMesh.new();mesh.top_radius=r;mesh.bottom_radius=r;mesh.height=a.distance_to(b);mesh.radial_segments=segments;mesh.rings=0
 var item=G.item(mesh,(a+b)*.5,PREFIX+key,false);item.transform.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()));return item
static func beam(a:Array,p:Vector3,q:Vector3,width:float,height:float,key:String,collision:bool=true)->void:
 var e=G.box((p+q)*.5,Vector3(width,height,p.distance_to(q)),PREFIX+key,collision)
 e.transform.basis=Basis.looking_at((q-p).normalized(),Vector3.UP);a.append(e)
static func ramp(a:Array,x:float,width:float,z0:float,z1:float,y0:float,y1:float,bottom0:float,bottom1:float,key:String)->void:
 var p=[Vector3(x-width*.5,bottom0,z0),Vector3(x+width*.5,bottom0,z0),Vector3(x+width*.5,bottom1,z1),Vector3(x-width*.5,bottom1,z1),Vector3(x-width*.5,y0,z0),Vector3(x+width*.5,y0,z0),Vector3(x+width*.5,y1,z1),Vector3(x-width*.5,y1,z1)]
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for face in [[0,3,2,1,Vector3.DOWN],[4,5,6,7,Vector3(0,1,(y1-y0)/(z0-z1)).normalized()],[0,4,7,3,Vector3.LEFT],[1,2,6,5,Vector3.RIGHT],[0,1,5,4,Vector3.BACK],[3,7,6,2,Vector3.FORWARD]]:_quad(st,[p[face[0]],p[face[1]],p[face[2]],p[face[3]]],face[4])
 a.append(G.item(st.commit(),Vector3.ZERO,PREFIX+key,true))
static func drain(a:Array,p:Vector3,length:float,axis_x:bool=true,width:float=.30)->void:
 var size=Vector3(length,.025,width) if axis_x else Vector3(width,.025,length)
 _box(a,p,size,"joint",false)
 for i in int(length/.15):
  var offset=-length*.5+.075+i*.15;var q=p+(Vector3(offset,.018,0) if axis_x else Vector3(0,.018,offset))
  _box(a,q,Vector3(.025,.035,width) if axis_x else Vector3(width,.035,.025),"steel",false,.004)
 for s in [-1.,1.]:_box(a,p+(Vector3(0,.025,s*width*.52) if axis_x else Vector3(s*width*.52,.025,0)),Vector3(length,.045,.022) if axis_x else Vector3(.022,.045,length),"steel",false,.005)
static func door(a:Array,p:Vector3,yaw:float=0.)->void:
 var b=Basis(Vector3.UP,yaw);var items:Array=[]
 _box(items,Vector3(0,1.1,0),Vector3(1.4,2.2,.09),"paint",true,.012)
 for x in [-.76,.76]:_box(items,Vector3(x,1.15,.02),Vector3(.09,2.3,.14),"steel",false,.012)
 _box(items,Vector3(0,2.3,.02),Vector3(1.61,.10,.14),"steel",false,.012)
 items.append(rod(Vector3(.46,1.00,.13),Vector3(.46,1.19,.13),.018,"steel",16))
 for y in [.35,1.85]:_box(items,Vector3(-.65,y,.08),Vector3(.08,.14,.07),"steel",false,.01)
 for e:Dictionary in items:e.transform=Transform3D(b,p)*e.transform;a.append(e)
const POOL=Rect2(-18,-28,36,56)
const YAW=0.2617993877991494
static func definition()->Dictionary:
 return {"id":"inverted_pool","title":"倒悬浴场","subtitle":"泳道在头顶，铅垂线仍然朝下。","goal":"沿侧岸找到卷线器，放下铅锤，看清倒过来的是建筑。","bounds":Rect2i(-1,-2,3,5),"retain_full_finite_scene":true,"spawn":Vector3(-4,.42,36),"look_at":Vector3(0,16,-4),"exit":Vector3(32,.4,-43.5),"exit_station":{"presentation":"authored","readout":false,"interaction_offset":Vector3(.46,1.09,.15),"interaction_pose":Vector3(32,.42,-41.8),"interaction_alternate_pose":Vector3(32.5,.42,-41.8),"label":"干燥耳廊门把手"},"stations":[{"id":"inverted_plumb","label":"铅垂线卷线器","kind":"plumb_winch","position":Vector3(29.45,.4,-20),"presentation":"authored","readout":false,"interaction_offset":Vector3(-.20,1.12,0),"interaction_pose":Vector3(27.65,.42,-20),"interaction_alternate_pose":Vector3(27.65,.42,-19.45),"state_count":2,"target":1,"latch_completion":true,"value_labels":["收起 / 高位","下放 / 垂直基准"],"action":"转动卷线手柄","clue":"铅锤只在封闭维修槽中下降。地面和水面不动，重力没有翻转。"}],"routes":[[Vector3(-4,.42,36),Vector3(0,.42,38),Vector3(-28,.42,38),Vector3(-28,.42,-38),Vector3(0,.42,-38),Vector3(28,.42,-38),Vector3(28,.42,-30),Vector3(28,.42,-20),Vector3(27.65,.42,-20),Vector3(28,.42,38),Vector3(0,.42,38),Vector3(-4,.42,36)],[Vector3(0,.42,31),Vector3(0,.42,28.4),Vector3(0,.24,27.6),Vector3(0,.06,26.8),Vector3(0,-.11,25.6),Vector3(0,-.11,-25.6),Vector3(0,.06,-26.8),Vector3(0,.24,-27.6),Vector3(0,.42,-28.4),Vector3(0,.42,-31)],[Vector3(28,.42,-30),Vector3(32,.42,-30),Vector3(32,.42,-41.8)],[Vector3(0,.42,38),Vector3(0,.42,31)],[Vector3(0,.42,-31),Vector3(0,.42,-38)]],"route_notes":"Wading route uses two 800mm treads at either end, with 180/180/170mm risers to the 450mm-deep bed. Waypoints are horizontal approach/landing locations, not vertical teleports. Both dry connectors share exact perimeter nodes; actual source-depth-bound unchanged PoolPlayer traversal is tested separately.","route_clearance_m":3.0,"pool_depth":.45,"inverted_shell":{"outer_width":36.0,"outer_length":56.0,"depth":18.0,"rim_y":18.0,"ceiling_y":36.0,"wall_thickness":1.2,"yaw_degrees":15.0,"dry":true,"grille_recess_m":.0625,"grille_span_m":.72},"cameras":[{"name":"entry_normal_eye","position":Vector3(-4,2.02,36),"target":Vector3(0,16,-4),"fov":62.0},{"name":"halfway_west_bank","position":Vector3(-28,2.02,2),"target":Vector3(0,26,-5),"fov":62.0},{"name":"winch_close","position":Vector3(28.25,2.02,-20),"target":Vector3(29.5,1.52,-20),"fov":62.0},{"name":"reference_corner","position":Vector3(-8,2.02,35),"target":Vector3(0,20,-4),"fov":62.0},{"name":"side_shell_truth","position":Vector3(28,2.02,-18),"target":Vector3(2,23,-4),"fov":62.0},{"name":"exit_lookback","position":Vector3(32,2.02,-31),"target":Vector3(-4,22,8),"fov":62.0},{"name":"near_pool_drain","position":Vector3(-19.1,2.02,24),"target":Vector3(-17.5,.4,23.5),"fov":62.0}],"sky_top":Color("71848c"),"sky_horizon":Color("c0ccc9"),"ambient":Color("d7dedd"),"ambient_energy":.14,"sun_color":Color("e0e9e5"),"sun_energy":0.,"sun_rotation":Vector3(-38,-110,0),"sky_shader":"res://shaders/dreamcore/annex_day_sky.gdshader","sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.0,"fog":.0003}
static func pool_steps()->Array[AABB]:
 # Same steps create actual mesh/collision/proxy plus compatibility layout.water_steps; layout.solids stays empty.
 return [AABB(Vector3(-2.5,-.13,27.2),Vector3(5,.35,.8)),AABB(Vector3(-2.5,-.13,26.4),Vector3(5,.17,.8)),AABB(Vector3(-2.5,-.13,-28),Vector3(5,.35,.8)),AABB(Vector3(-2.5,-.13,-27.2),Vector3(5,.17,.8))]
static func layout(coord:Vector2i)->Dictionary:
 var steps:Array[AABB]=[]
 for step:AABB in pool_steps():
  for rect:Rect2 in G.water_rects(coord,Rect2(Vector2(step.position.x,step.position.z),Vector2(step.size.x,step.size.z))):
   steps.append(AABB(Vector3(rect.position.x,step.position.y,rect.position.y),Vector3(rect.size.x,step.size.y,rect.size.y)))
 return {"coord":coord,"water_enabled":true,"water_floor_y":-.13,"water_steps":steps,"water_rects":G.water_rects(coord,POOL),"solids":[],"spawn_local":Vector3(-4,.42,36)}
static func _cove(a:Array,side:float,axis_x:bool)->void:
 # True 1m cove at dry inner wall/ceiling join; finite curved geometry, not shading decal.
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);var limit=15.8 if axis_x else 25.8;var span=51.6 if axis_x else 31.6
 for i in 16:
  var q:Array=[]
  for e in [[i,-1.],[i,1.],[i+1,1.],[i+1,-1.]]:
   var ang=float(e[0])*PI*.5/16.;var across=side*(limit+sin(ang));var y=35.+cos(ang);q.append(Vector3(across,y,e[1]*span*.5) if axis_x else Vector3(e[1]*span*.5,y,across))
  var mid=(i+.5)*PI*.5/16.;var n=Vector3(-side*sin(mid),-cos(mid),0) if axis_x else Vector3(0,-cos(mid),-side*sin(mid));_quad(st,q,n)
 a.append(G.item(st.commit(),Vector3.ZERO,PREFIX+"tile",false))
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 materials_ready();var a:Array=[]
 # Ground pool and real dry circulation. Water remains source Y=.32; bed is -.13 (45cm).
 _box(a,Vector3(0,-.325,0),Vector3(80,.39,96),"basin_tile")
 for r in [Rect2(-40,28,80,20),Rect2(-40,-48,80,20),Rect2(-40,-28,22,56),Rect2(18,-28,22,56)]:_box(a,Vector3(r.get_center().x,.135,r.get_center().y),Vector3(r.size.x,.53,r.size.y),"tile")
 for step:AABB in pool_steps():_box(a,step.get_center(),step.size,"tile")
 for x in [-12.,-6.,0.,6.,12.]:
  _box(a,Vector3(x,-.126,0),Vector3(.5,.008,49),"blue",false)
  for z in [-24.5,24.5]:_box(a,Vector3(x,-.125,z),Vector3(2.4,.009,.5),"blue",false)
 # Basin perimeter has real grilles and double ceramic coping, with two step openings.
 for x in [-18.17,18.17]:
  drain(a,Vector3(x,.407,0),56,false,.32)
  _box(a,Vector3(x+signf(x)*.33,.415,0),Vector3(.25,.03,56.6),"tile",false,.02)
 for z in [-28.17,28.17]:
  drain(a,Vector3(0,.407,z),36,true,.32)
  _box(a,Vector3(0,.415,z+signf(z)*.33),Vector3(36.6,.03,.25),"tile",false,.02)
 # Ordinary closed 80x96x58 hall; structural bays set the huge upper shell against negative space.
 for x in [-40.6,40.6]:_box(a,Vector3(x,29,0),Vector3(1.2,58,96),"tile")
 for z in [-48.59,48.59]:_box(a,Vector3(0,29,z),Vector3(80,58,1.2),"tile")
 _box(a,Vector3(0,58.6,0),Vector3(82,1.2,98),"concrete",false)
 for x in [-37.,37.]:
  for z in [-32.,-11.,11.,32.]:_box(a,Vector3(x,29,z),Vector3(4,58,2.4),"pier_tile",true,.06)
 for z in [-46.,46.]:
  for x in [-25.,0.,25.]:_box(a,Vector3(x,29,z),Vector3(2.4,58,4),"pier_tile",true,.06)
 # The entire overhead object is a real 36x56x18m inverted dry pool shell, yaw15deg.
 var upper:Array=[]
 _box(upper,Vector3(0,36.6,0),Vector3(36,1.2,56),"concrete",true,.10)
 _box(upper,Vector3(0,35.987,0),Vector3(33.6,.026,53.6),"shell_floor",false)
 for x in [-17.4,17.4]:_box(upper,Vector3(x,27,0),Vector3(1.2,18,56),"tile",true,.08)
 for z in [-27.4,27.4]:_box(upper,Vector3(0,27,z),Vector3(33.6,18,1.2),"tile",true,.08)
 for s in [-1.,1.]:_cove(upper,s,true);_cove(upper,s,false)
 # Five cobalt lane lines with substantial T ends on inner ceiling and down-facing end returns.
 for x in [-12.,-6.,0.,6.,12.]:
  _box(upper,Vector3(x,35.967,0),Vector3(.5,.014,48),"blue",false)
  for z in [-24.,24.]:_box(upper,Vector3(x,35.962,z),Vector3(2.8,.02,.5),"blue",false)
  for z in [-26.785,26.785]:
   _box(upper,Vector3(x,32.7,z),Vector3(.5,4.8,.028),"blue",false)
   _box(upper,Vector3(x,30.4,z),Vector3(2.8,.5,.032),"blue",false)
 # Inset double coping with regular dry scupper interruptions and fitted drainage grates.
 for x in [-17.6,17.6]:
  # Real recessed drain channel between two ceramic coping shoulders.
  for dx in [-.55,.55]:_box(upper,Vector3(x+dx,17.94,0),Vector3(.40,.24,56.6),"tile",false,.05)
  _box(upper,Vector3(x-signf(x)*.70,18.06,0),Vector3(.28,.28,54.4),"tile",false,.08)
  _box(upper,Vector3(x,17.9875,0),Vector3(.70,.025,55.7),"joint",false)
  for i in 370:
   var gz=-27.675+i*.15;var scupper=false
   for slot in range(-26,27,4):
    if absf(gz-float(slot))<.325:scupper=true;break
   if not scupper:_box(upper,Vector3(x,17.90,gz),Vector3(.72,.035,.026),"steel",false,.004)
  for z in range(-26,27,4):
   _box(upper,Vector3(x,17.965,z),Vector3(.70,.015,.65),"joint",false)
   for dz in [-.36,.36]:_box(upper,Vector3(x,17.88,z+dz),Vector3(.76,.07,.06),"steel",false,.01)
 for z in [-27.6,27.6]:
  for dz in [-.55,.55]:_box(upper,Vector3(0,17.94,z+dz),Vector3(35.8,.24,.40),"tile",false,.05)
  _box(upper,Vector3(0,18.06,z-signf(z)*.70),Vector3(33.6,.28,.28),"tile",false,.08)
  _box(upper,Vector3(0,17.9875,z),Vector3(34.7,.025,.70),"joint",false)
  for i in 230:_box(upper,Vector3(-17.175+i*.15,17.90,z),Vector3(.026,.035,.72),"steel",false,.004)
 # Genuine dry drain covers in the inner pool ceiling; normal construction orientation is inverted with shell.
 for z in [-18.,0.,18.]:
  _box(upper,Vector3(0,35.94,z),Vector3(1.0,.045,.75),"joint",false,.025)
  for i in 8:_box(upper,Vector3(-.42+i*.12,35.905,z),Vector3(.035,.035,.70),"steel",false,.006)
 # Sparse external ribs/diaphragms belong to the shell, not a hanging slab substitute.
 for x in [-18.6,18.6]:
  for z in [-18.,18.]:_box(upper,Vector3(x,27,z),Vector3(1.2,18,2.4),"concrete",false,.08)
 var rot=Transform3D(Basis(Vector3.UP,YAW),Vector3.ZERO)
 for e:Dictionary in upper:
  e.transform=rot*e.transform
  if e.material in [PREFIX+"tile",PREFIX+"blue"]:e.material=PREFIX+"shell_"+str(e.material).trim_prefix(PREFIX)
  a.append(e)
 # Four real lateral load paths connect side diaphragms into the hall; all stay above player routes.
 for side in [-1.,1.]:
  for z in [-18.,18.]:
   var inner:Vector3=rot*Vector3(side*18.6,19.2,z);var outer=Vector3(side*37,19.2,inner.z)
   beam(a,inner,outer,4.2,2.4,"concrete",true)
   var low=Vector3(side*35.8,12.0,inner.z);var high=inner+Vector3(0,.25,0)
   var mesh=BoxMesh.new();mesh.size=Vector3(2.0,1.8,low.distance_to(high));var e=G.item(mesh,(low+high)*.5,PREFIX+"concrete",true);e.transform.basis=Basis.looking_at((high-low).normalized(),Vector3.UP);a.append(e)
   _box(a,Vector3(side*37,9.14,inner.z),Vector3(4,17.48,4.2),"concrete",true,.08)
   _box(a,outer+Vector3(0,-1.26,0),Vector3(3.5,.12,3.7),"rubber",false,.025)
 # Human-height practical wall lights and thin metal fixtures, never a bright floating ceiling.
 for x in [-34.94,34.94]:
  for z in [-32.,11.,32.]:
   _box(a,Vector3(x,2.55,z),Vector3(.12,.48,.22),"dark_steel",false,.025)
   _box(a,Vector3(x-signf(x)*.075,2.55,z),Vector3(.07,.28,.14),"warm",false,.02)
 _box(a,Vector3(0,2.55,-43.94),Vector3(.22,.48,.12),"dark_steel",false,.025)
 _box(a,Vector3(0,2.55,-43.86),Vector3(.14,.28,.07),"warm",false,.02)
 # Visible low-rim maintenance luminaires wash upward into the dry cavity; no hidden photography lights.
 for x in [-11.,11.]:
  var p=rot*Vector3(x,18.36,25.70);_box(a,p,Vector3(2.4,.10,.24),"cool",false,.025)
 # Sealed plumb-line service groove. Weight/line never reach the walking path.
 _box(a,Vector3(31.6,9.7,-20),Vector3(.40,18.6,1.55),"concrete",true,.04)
 for z in [-20.77,-19.23]:_box(a,Vector3(31.15,9.7,z),Vector3(1.30,18.6,.12),"steel",true,.025)
 for y in [.48,18.92]:_box(a,Vector3(31.15,y,-20),Vector3(1.30,.16,1.55),"steel",true,.025)
 # A continuous visibly perforated guard with collision-only cell matching its bars.
 for i in 13:
  var z=-20.70+i*.1167;_box(a,Vector3(30.52,9.7,z),Vector3(.08,18.6,.025),"steel",true,.007)
 for y in range(1,19):_box(a,Vector3(30.48,y,-20),Vector3(.10,.026,1.48),"steel",false,.006)
 for i in 34:
  var y=1.0+i*.5;_box(a,Vector3(31.36,y,-19.40),Vector3(.03,.035,.22 if i%2==0 else .12),"blue",false)
 # Winch pedestal, spindle bearings and tension path are fixed visible construction.
 _box(a,Vector3(29.85,1.0,-20),Vector3(.62,1.2,.72),"concrete",true,.06)
 _box(a,Vector3(29.68,1.52,-20),Vector3(.22,.42,.45),"steel",false,.035)
 a.append(rod(Vector3(29.45,1.52,-20),Vector3(30.05,1.52,-20),.05,"steel",24))
 for y in [1.36,1.68]:
  for z in [-20.16,-19.84]:a.append(rod(Vector3(29.515,y,z),Vector3(29.58 if y>1.6 else 29.56,y,z),.025,"steel",6))
 # Enclosed offset transfer gears visibly join the crank spindle and vertical shaft.
 # Both fixed casings remain behind the reachable handle, never in the walking loop.
 _box(a,Vector3(30,1.52,-20.225),Vector3(.48,.48,.65),"dark_steel",true,.045)
 a.append(rod(Vector3(29.72,1.52,-20),Vector3(29.82,1.52,-20),.105,"steel",24))
 for y in [1.35,1.69]:
  for z in [-20.45,-20.02]:a.append(rod(Vector3(29.72,y,z),Vector3(29.77,y,z),.022,"steel",6))
 _box(a,Vector3(30.75,18.5,-20.225),Vector3(.40,.50,.70),"dark_steel",true,.04)
 a.append(rod(Vector3(30.93,18.5,-20),Vector3(31.03,18.5,-20),.095,"steel",24))
 a.append(rod(Vector3(30,1.52,-20.45),Vector3(30,18.5,-20.45),.035,"steel",16))
 a.append(rod(Vector3(30,18.5,-20.45),Vector3(30.75,18.5,-20.45),.035,"steel",16))
 for y in [2.,6.,10.,14.,18.]:_box(a,Vector3(30.255,y,-20.45),Vector3(.53,.14,.14),"steel",false,.015)
 # Modest normal-height side service opening and dry ear-corridor; no arbitrary ladder.
 for x in [29.5,34.5]:_box(a,Vector3(x,1.8,-38),Vector3(.22,2.8,12),"tile",true,.02)
 _box(a,Vector3(32,3.25,-38),Vector3(5.2,.1,12),"tile",true)
 for x in [30.4,33.6]:_box(a,Vector3(x,1.55,-32),Vector3(1.6,2.3,.18),"tile",true)
 _box(a,Vector3(32,2.95,-32),Vector3(5.2,.5,.18),"tile",true)
 for x in [31.2,32.8]:_box(a,Vector3(x,1.55,-31.86),Vector3(.09,2.3,.1),"steel",false,.012)
 for x in [30.4,33.6]:_box(a,Vector3(x,1.8,-43.62),Vector3(1.6,2.8,.22),"tile",true)
 _box(a,Vector3(32,2.95,-43.62),Vector3(1.6,.5,.22),"tile",true)
 door(a,Vector3(32,.4,-43.5))
 _box(a,Vector3(32,3.10,-37),Vector3(.8,.045,.10),"warm",false)
 _architecture=a;return a
static func _align_shell_uv(room:Node3D,data:Dictionary)->void:
 var offset=Vector3(data.coord.x*32.,0,data.coord.y*32.);var inv=Basis(Vector3.UP,-YAW)
 for node in room.get_children():
  if not node is MeshInstance3D or not str(node.name).begins_with("Annex_"+PREFIX+"shell_") or node.has_meta("shell_uv_aligned"):continue
  var arrays=node.mesh.surface_get_arrays(0);var uv=PackedVector2Array()
  for i in arrays[Mesh.ARRAY_VERTEX].size():uv.append(G.metric_uv(inv*(arrays[Mesh.ARRAY_VERTEX][i]+offset),inv*arrays[Mesh.ARRAY_NORMAL][i]))
  arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TANGENT]=null
  var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);var st=SurfaceTool.new();st.create_from(mesh,0);st.generate_tangents();node.mesh=st.commit();node.mesh.set_meta("source_static_arrays",{"vertices":arrays[Mesh.ARRAY_VERTEX],"indices":arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()});node.set_meta("shell_uv_aligned",true)
# The tall tiled pilasters are decorative finish at their shared bearing faces.
# Remove only coincident visible tile triangles where an actual concrete bearing
# front owns the face. Collision/load paths remain the original untouched shapes.
static func _outside_rectangle(poly:Array,rect:Rect2)->Array:
 var outside:Array=[];var inside:Array=poly
 for cut in [[1,rect.position.x,true],[1,rect.end.x,false],[2,rect.position.y,true],[2,rect.end.y,false]]:
  if inside.size()<3:break
  var piece:Array=G._clip(inside,int(cut[0]),float(cut[1]),not bool(cut[2]))
  if piece.size()>=3:outside.append(piece)
  inside=G._clip(inside,int(cut[0]),float(cut[1]),bool(cut[2]))
 return outside
static func _trim_bearing_veneer_faces(room:Node3D,data:Dictionary)->void:
 var offset=Vector3(data.coord.x*32.,0,data.coord.y*32.);var rot=Basis(Vector3.UP,YAW)
 for node in room.get_children():
  if not node is MeshInstance3D or str(node.name)!="Annex_"+PREFIX+"pier_tile" or node.has_meta("bearing_faces_owned"):continue
  var arrays=node.mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array();var count:int=indices.size() if not indices.is_empty() else vertices.size()
  var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
  for start in range(0,count,3):
   var points:Array=[];var normal=Vector3.ZERO
   for k in 3:
    var index:int=indices[start+k] if not indices.is_empty() else start+k;points.append(vertices[index]+offset);normal+=normals[index]
   normal=normal.normalized();var pieces:Array=[points];var side:float=signf(points[0].x)
   var shared_front:bool=absf(absf(points[0].x)-35.)<.00001 and absf(absf(points[1].x)-35.)<.00001 and absf(absf(points[2].x)-35.)<.00001 and normal.dot(Vector3(-side,0,0))>.9999
   if shared_front:
    for z in [-18.,18.]:
     var center:Vector3=rot*Vector3(side*18.6,19.2,z)
     # Exact flat portion of the real chamfered 4x17.48x4.2m bearing.
     var face=Rect2(Vector2(.48,center.z-2.02),Vector2(17.32,4.04));var next:Array=[]
     for piece:Array in pieces:next.append_array(_outside_rectangle(piece,face))
     pieces=next
   for piece:Array in pieces:
    for k in range(1,piece.size()-1):
     var triangle=[piece[0],piece[k],piece[k+1]]
     if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).length_squared()<.000000000001:continue
     for point:Vector3 in triangle:st.set_normal(normal);st.set_uv(G.metric_uv(point,normal));st.add_vertex(point-offset)
  st.generate_tangents();var mesh=st.commit();var result=mesh.surface_get_arrays(0)
  mesh.set_meta("source_static_arrays",{"vertices":result[Mesh.ARRAY_VERTEX],"indices":result[Mesh.ARRAY_INDEX] if result[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()});node.mesh=mesh;node.set_meta("bearing_faces_owned",true)

static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),true);_align_shell_uv(room,data);_trim_bearing_veneer_faces(room,data);Gloss.install(room,"inverted_pool",Gloss.resources());Clip.install(room,"inverted_pool",ClipShader)
# Two existing cavity-rim fixtures carry real shadows; no new light/fill nodes.
# Wrapper deliberately leaves shared G.lamp and all original scenes unchanged.
static func _mounted_lamp(room:Node3D,data:Dictionary,point:Vector3,color:Color,energy:float,reach:float,casts_shadow:bool=false)->void:
 var before:int=room.get_child_count()
 G.lamp(room,data,point,color,energy,reach)
 if casts_shadow and room.get_child_count()>before:
  var light:OmniLight3D=room.get_child(room.get_child_count()-1) as OmniLight3D
  if light!=null:light.shadow_enabled=true
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false);_align_shell_uv(room,data);Gloss.install(room,"inverted_pool",Gloss.resources());Clip.install(room,"inverted_pool",ClipShader)
 for x in [-34.7,34.7]:
  for z in [-32.,11.]:_mounted_lamp(room,data,Vector3(x,2.55,z),Color("ffe3b5"),1.5,32.)
 var rot=Basis(Vector3.UP,YAW)
 for x in [-11.,11.]:_mounted_lamp(room,data,rot*Vector3(x,18.65,25.45),Color("d6e5e7"),8.,72.,true)
 _mounted_lamp(room,data,Vector3(0,2.55,-43.72),Color("ffe3b5"),1.3,32.)
 _mounted_lamp(room,data,Vector3(32,2.95,-37),Color("ffe3b5"),.35,8.)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 materials_ready();var actor=Effects.new();actor.name="InvertedPlumbWinch";root.add_child(actor)
