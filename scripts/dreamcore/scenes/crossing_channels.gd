extends RefCounted
const Gloss=preload("res://scripts/dreamcore/uncanny/crossing_inverted_ceramic_gloss.gd")
## Original finite architecture; reference-matched real construction, metres.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const Effects=preload("res://scripts/dreamcore/uncanny/crossing_channels_effects.gd")
const Clip=preload("res://scripts/dreamcore/uncanny/crossing_inverted_clip_material.gd")
const ClipShader=preload("res://shaders/dreamcore/uncanny/crossing_inverted_clip_base.gdshader")
const PREFIX="crossing_channels_"
const ASSETS="res://assets/dreamcore/uncanny/crossing_channels/"
static var _architecture:Array=[]
static func material_specs()->Dictionary:
 var out={}
 for key in ["concrete","tile","cyan","blue"]:out[PREFIX+key]={"albedo":ASSETS+key+"_albedo.png","normal":ASSETS+key+"_normal.png","orm":ASSETS+key+"_orm.png","period":3.2,"strength":.48 if key=="concrete" else .55,"tint":"ffffff","roughness_channel":"g"}
 var concrete:Dictionary=out[PREFIX+"concrete"]
 for role in ["albedo","normal","orm"]:concrete[role]=ASSETS+"concrete_v2_"+role+".png"
 out[PREFIX+"basin_tile"]=out[PREFIX+"tile"].duplicate();out[PREFIX+"basin_tile"].tint="bbd6d2"
 out[PREFIX+"bearing_concrete"]=out[PREFIX+"concrete"].duplicate();out[PREFIX+"bearing_concrete"].tint="c2cbc5"
 out[PREFIX+"ramp_tile"]=out[PREFIX+"tile"].duplicate();out[PREFIX+"ramp_tile"].period=9.6;out[PREFIX+"ramp_tile"].tint="c2ccc7"
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
static func _smooth_tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,na:Vector3,nb:Vector3,nc:Vector3)->void:
 var cross=(b-a).cross(c-a)
 if cross.length_squared()<.000000000001:return
 if cross.dot(na+nb+nc)>0:
  var q=b;b=c;c=q;var nn=nb;nb=nc;nc=nn
 for pair in [[a,na],[b,nb],[c,nc]]:st.set_normal(pair[1]);st.add_vertex(pair[0])
static func rounded_mesh(size:Vector3,radius:float,steps:int=6)->Mesh:
 var h=size*.5;var r=minf(radius,minf(h.x,minf(h.y,h.z))*.9);var k=h-Vector3.ONE*r;var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for axis in 3:
  var u=(axis+1)%3;var v=(axis+2)%3
  for sign in [-1.,1.]:
   var q:Array=[];var n=Vector3.ZERO;n[axis]=sign
   for uv in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
    var point=Vector3.ZERO;point[axis]=sign*h[axis];point[u]=uv.x*k[u];point[v]=uv.y*k[v];q.append(point)
   _quad(st,q,n)
 for axis in 3:
  var u=(axis+1)%3;var v=(axis+2)%3
  for su in [-1.,1.]:
   for sv in [-1.,1.]:
    for i in steps:
     var q:Array=[];var normals:Array=[]
     for e in [[i,-1.],[i,1.],[i+1,1.],[i+1,-1.]]:
      var angle=float(e[0])*PI*.5/steps;var n=Vector3.ZERO;n[u]=su*cos(angle);n[v]=sv*sin(angle)
      var point=Vector3.ZERO;point[axis]=float(e[1])*k[axis];point[u]=su*k[u]+r*n[u];point[v]=sv*k[v]+r*n[v];q.append(point);normals.append(n)
     _smooth_tri(st,q[0],q[1],q[2],normals[0],normals[1],normals[2]);_smooth_tri(st,q[0],q[2],q[3],normals[0],normals[2],normals[3])
 for sx in [-1.,1.]:
  for sy in [-1.,1.]:
   for sz in [-1.,1.]:
    var center=Vector3(sx*k.x,sy*k.y,sz*k.z)
    for i in steps:
     for j in steps:
      var q:Array=[];var normals:Array=[]
      for uv in [Vector2(i,j),Vector2(i+1,j),Vector2(i+1,j+1),Vector2(i,j+1)]:
       var theta=uv.x*PI*.5/steps;var phi=uv.y*PI*.5/steps;var n=Vector3(sx*cos(theta)*cos(phi),sy*cos(theta)*sin(phi),sz*sin(theta));q.append(center+n*r);normals.append(n)
      _smooth_tri(st,q[0],q[1],q[2],normals[0],normals[1],normals[2]);_smooth_tri(st,q[0],q[2],q[3],normals[0],normals[2],normals[3])
 return st.commit()
static func _round_box(a:Array,p:Vector3,size:Vector3,key:String,radius:float,collision:bool=true)->void:a.append(G.item(rounded_mesh(size,radius),p,PREFIX+key,collision))
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
const POOL=Rect2(-28,-28,56,44)
static func definition()->Dictionary:
 return {"id":"crossing_channels","title":"交错旱渠","subtitle":"水早已离开，回声仍在上面交叉。","goal":"沿缓坡走进旱渠，转动声学挡板，再从侧面看清两渠的实空。","bounds":Rect2i(-2,-2,5,5),"retain_full_finite_scene":true,"spawn":Vector3(-32,.42,38),"look_at":Vector3(0,12,-14),"exit":Vector3(-45.1,4.4,-18),"exit_station":{"presentation":"authored","readout":false,"interaction_offset":Vector3(.15,1.09,-.46),"interaction_pose":Vector3(-43.3,4.42,-18),"interaction_alternate_pose":Vector3(-43.3,4.42,-17.5),"label":"声闸检修门把手"},"stations":[{"id":"channel_resonator","label":"旱渠声学挡板","kind":"resonator","position":Vector3(20,4.4,-21.8),"presentation":"authored","readout":false,"interaction_offset":Vector3(0,1.12,.24),"interaction_pose":Vector3(20,4.42,-20),"interaction_alternate_pose":Vector3(20.55,4.42,-20),"state_count":2,"target":1,"latch_completion":true,"value_labels":["近端 / 闷响","远端 / 延迟回声"],"action":"转动声学挡板","clue":"指针在近路与远路间转动。响声不是密码：静音时仍可看见传动杆和远端回响指示片。"}],"routes":[[Vector3(-32,.42,38),Vector3(-36,.42,38),Vector3(-36,.42,36),Vector3(-36,4.42,-12),Vector3(-36,4.42,-18),Vector3(20,4.42,-18),Vector3(20,4.42,-20),Vector3(36,4.42,-18),Vector3(36,4.42,-12),Vector3(36,.42,36),Vector3(32,.42,38),Vector3(-32,.42,38)],[Vector3(-32,.42,38),Vector3(-32,.42,-34),Vector3(32,.42,-34),Vector3(32,.42,38),Vector3(-32,.42,38)],[Vector3(-36,4.42,-18),Vector3(-43.3,4.42,-18)],[Vector3(-18,.42,38),Vector3(-18,.42,34)],[Vector3(0,.42,38),Vector3(0,.42,17)],[Vector3(0,.42,17),Vector3(0,.24,15.6),Vector3(0,.06,14.8),Vector3(0,-.11,13.6)]],"route_clearance_m":3.0,"ramp_run_m":48.0,"ramp_rise_m":4.0,"channel_clear_air_gap_m":9.2,"upper_channel_end_z":24.0,"near_upper_support_z":20.0,"near_parapet_top_y":6.6,"pool_depth":.45,"cameras":[{"name":"entry_normal_eye","position":Vector3(-32,2.02,38),"target":Vector3(0,12,-14),"fov":62.0},{"name":"halfway_ramp","position":Vector3(-36,4.02,12),"target":Vector3(2,11,-18),"fov":62.0},{"name":"mechanism_close","position":Vector3(20,6.02,-20.4),"target":Vector3(20,5.55,-21.8),"fov":62.0},{"name":"aligned_channels","position":Vector3(-35.1,4.52,6),"target":Vector3(-14,9,-18),"fov":62.0},{"name":"parallax_truth","position":Vector3(32,2.02,-32),"target":Vector3(0,15,-15),"fov":62.0},{"name":"exit_lookback","position":Vector3(-43.1,6.02,-18),"target":Vector3(12,8,-18),"fov":62.0},{"name":"near_parapet_joint","position":Vector3(-32,2.02,-10),"target":Vector3(-29,5.5,-12),"fov":62.0},{"name":"upper_closed_end_truth","position":Vector3(-18,2.02,34),"target":Vector3(0,22,20),"fov":62.0}],"sky_top":Color("809291"),"sky_horizon":Color("cbd4cb"),"ambient":Color("e1e5df"),"ambient_energy":.14,"sun_color":Color("e4eee7"),"sun_energy":0.,"sun_rotation":Vector3(-40,-110,0),"sky_shader":"res://shaders/dreamcore/crossing_channels_sky.gdshader","sky_source_constant_gain":8.0,"sky_source_constant_neutral_mix":.75,"daylight_slot_width_m":3.0,"daylight_slot_sill_y":4.0,"daylight_slot_header_y":59.0,"sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.0,"fog":.00035}
static func pool_steps()->Array[AABB]:
 # Original south entrance, real .8m treads; crossed overhead channels remain dry.
 return [AABB(Vector3(-2.5,-.13,15.2),Vector3(5,.35,.8)),AABB(Vector3(-2.5,-.13,14.4),Vector3(5,.17,.8))]
static func layout(coord:Vector2i)->Dictionary:
 var steps:Array[AABB]=[]
 for step:AABB in pool_steps():
  for rect:Rect2 in G.water_rects(coord,Rect2(Vector2(step.position.x,step.position.z),Vector2(step.size.x,step.size.z))):
   steps.append(AABB(Vector3(rect.position.x,step.position.y,rect.position.y),Vector3(rect.size.x,step.size.y,rect.size.y)))
 return {"coord":coord,"water_enabled":true,"water_floor_y":-.13,"water_steps":steps,"water_rects":G.water_rects(coord,POOL),"solids":[],"spawn_local":Vector3(-32,.42,38)}
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 materials_ready();var a:Array=[]
 # One true ground pool only: .32 surface, -.13 bed; reversible 180/180/170mm descent.
 _box(a,Vector3(0,-.325,0),Vector3(95.98,.39,95.98),"basin_tile")
 for r in [Rect2(-47.99,16,95.98,31.99),Rect2(-47.99,-47.99,95.98,19.99),Rect2(-47.99,-28,19.99,44),Rect2(28,-28,19.99,44)]:_box(a,Vector3(r.get_center().x,.135,r.get_center().y),Vector3(r.size.x,.53,r.size.y),"concrete")
 for step:AABB in pool_steps():_box(a,step.get_center(),step.size,"tile")
 # Solid corner returns close the hall and intentionally occupy all four finite corner cells.
 for x in [-48.4,48.4]:
  for z in [-48.4,48.4]:_box(a,Vector3(x,31,z),Vector3(1.6,62,1.6),"concrete")
 # Real daylight apertures, not emissive wall stripes or hidden fill lights.
 # 3m clear slots at the existing bay rhythm; continuous 4m colliding sills
 # protect every ordinary ground route, and 3m headers close the 62m hall.
 for side in [-1.,1.]:
  for interval in [Vector2(-47.99,-33.5),Vector2(-30.5,-1.5),Vector2(1.5,30.5),Vector2(33.5,47.99)]:
   var center:float=(interval.x+interval.y)*.5;var length:float=interval.y-interval.x
   _box(a,Vector3(side*48.59,31,center),Vector3(1.2,62,length),"concrete")
   _box(a,Vector3(center,31,side*48.59),Vector3(length,62,1.2),"concrete")
  for q in [-32.,0.,32.]:
   _box(a,Vector3(side*48.59,2,q),Vector3(1.2,4,3),"concrete")
   _box(a,Vector3(side*48.59,60.5,q),Vector3(1.2,3,3),"concrete")
   _box(a,Vector3(q,2,side*48.59),Vector3(3,4,1.2),"concrete")
   _box(a,Vector3(q,60.5,side*48.59),Vector3(3,3,1.2),"concrete")
 _box(a,Vector3(0,62.6,0),Vector3(98,1.2,98),"concrete",false)
 # Lower channel is an actual open U: .8m bed, 6m rear wall, local low protected inspection frontage.
 _box(a,Vector3(0,4,-18),Vector3(89,.8,12),"concrete",true,.12)
 _box(a,Vector3(0,7.4,-23.6),Vector3(89,6,.8),"concrete",true,.10)
 _box(a,Vector3(0,4.412,-18),Vector3(88.8,.024,10.38),"cyan",false)
 _box(a,Vector3(0,7.4,-23.185),Vector3(88.8,5.82,.025),"cyan",false)
 # Lower parapet reveals the REAL tall tiled inner rear wall from ordinary entry.
 # Thick near wall is raised upward only; original under-slab clearance is intact.
 _round_box(a,Vector3(0,5.5,-12.43),Vector3(60,2.2,.74),"concrete",.20)
 # Recessed construction joints are real 60mm-deep gaps in the concrete facing,
 # within the original .8m wall envelope, not painted lines or hidden beams.
 for i in 30:_box(a,Vector3(-28.71+i*1.98,5.5,-12.03),Vector3(1.945,1.74,.06),"concrete",false,.01)
 for side in [-1.,1.]:
  _box(a,Vector3(side*32.15,7.4,-12.4),Vector3(4.3,6,.8),"concrete",true,.10)
  _box(a,Vector3(side*41.2,7.4,-12.4),Vector3(6.6,6,.8),"concrete",true,.10)
  # Full-height flanking end buttresses tie into slab and abutment. The west
  # soundlock passage at z-18 stays between them; no perimeter route is crossed.
  for z in [-23.6,-12.4]:_round_box(a,Vector3(side*43,5.4,z),Vector3(4,10,1.6),"bearing_concrete",.22)
  # Deep visible abutments, elastomeric bearing and corbel; no support in wet rectangle.
  _box(a,Vector3(side*43,.4+1.5,-18),Vector3(9.98,3,14),"bearing_concrete",true,.10)
  _box(a,Vector3(side*43,3.48,-18),Vector3(7.6,.16,13.6),"rubber",false,.025)
  _box(a,Vector3(side*43,3.6,-18),Vector3(8.4,.08,14.4),"steel",false,.025)
  # Real 1:12 sidewall ramp: 48m run, 4m rise, 3m clear deck; continuous grounded concrete guards.
  ramp(a,side*36,3.0,36,-12,.4,4.4,.12,.12,"concrete")
  # Thin 600mm-pitch dry porcelain finish follows the exact safe incline.
  var skin=SurfaceTool.new();skin.begin(Mesh.PRIMITIVE_TRIANGLES)
  _quad(skin,[Vector3(side*36-1.49,.412,36),Vector3(side*36+1.49,.412,36),Vector3(side*36+1.49,4.412,-12),Vector3(side*36-1.49,4.412,-12)],Vector3(0,1,1.0/12.0).normalized())
  a.append(G.item(skin.commit(),Vector3.ZERO,PREFIX+"ramp_tile",false))
  for dx in [-1.62,1.62]:
   ramp(a,side*36+dx,.24,36,-12,1.5,5.5,.4,4.4,"concrete")
   a.append(rod(Vector3(side*36+dx,1.54,36),Vector3(side*36+dx,5.54,-12),.035,"steel",16))
  _box(a,Vector3(side*36,4.15,-14.8),Vector3(3,.5,5.6),"concrete")
  # Exact jambs protect opening, without a barrier across the ramp landing.
  for dx in [-1.62,1.62]:_box(a,Vector3(side*36+dx,4.975,-13.2),Vector3(.24,1.15,2.4),"concrete",true,.035)
 # Rounded coping shoulders on true wall tops; periodic dry spill mouth and metal return.
 for z in [-23.6,-12.4]:
  if z<-20:_box(a,Vector3(0,10.42,z),Vector3(89,.16,1.08),"concrete",false,.075)
  else:_round_box(a,Vector3(0,6.62,z),Vector3(60,.16,1.08),"concrete",.07,false)
 for x in range(-40,41,4):
  _box(a,Vector3(x,10.16,-23.153),Vector3(.65,.22,.08),"joint",false)
  _box(a,Vector3(x,10.05,-23.10),Vector3(.70,.07,.26),"steel",false,.015)
  for z in [-23.15,-12.83]:_box(a,Vector3(x,4.421,z),Vector3(.022,.015,.75),"joint",false)
  _box(a,Vector3(x,4.426,-18),Vector3(.022,.012,10.35),"joint",false)
 drain(a,Vector3(0,4.425,-22.7),86,true,.24)
 # Upper dry U ends visibly at z24; its near feet z17..23 stay outside pool z<=16.
 # Core and recessed soffit facing still total .8m; minimum underside stays19.6.
 _round_box(a,Vector3(0,20.03,-11.995),Vector3(12,.74,71.99),"concrete",.24)
 for ix in 5:
  for iz in 18:_box(a,Vector3(-4.56+ix*2.28,19.63,-45.7166667+iz*3.9666667),Vector3(2.245,.06,3.9316667),"concrete",false,.01)
 _box(a,Vector3(0,20.412,-11.995),Vector3(10.4,.024,71.79),"cyan",false)
 for x in [-5.58,5.58]:
  _round_box(a,Vector3(x,23.4,-11.995),Vector3(.76,6,71.99),"concrete",.20)
  _box(a,Vector3(signf(x)*5.185,23.4,-11.995),Vector3(.025,5.8,71.79),"cyan",false)
  _round_box(a,Vector3(signf(x)*5.6,26.42,-11.995),Vector3(1.08,.16,71.99),"concrete",.07,false)
  # Actual inset outer panel joints; facing ends at the closed rounded return.
  for iz in 18:
   for y in [21.6,23.6]:_box(a,Vector3(signf(x)*5.98,y,-45.7361+iz*3.927778),Vector3(.04,1.96,3.892778),"concrete",false,.008)
  # External ceramic fascia is real cladding, not see-through inner lining.
  _box(a,Vector3(signf(x)*6.015,25.48,-12.3),Vector3(.025,1.35,70.6),"cyan",false)
  for z in range(-44,21,4):
   _box(a,Vector3(signf(x)*6.035,25.86,z),Vector3(.08,.24,.7),"joint",false)
   _box(a,Vector3(signf(x)*6.08,25.70,z),Vector3(.18,.07,.76),"steel",false,.015)
 # A substantial curved closed end, not an unbounded off-camera strip.
 _round_box(a,Vector3(0,23.4,23.6),Vector3(12,6,.8),"concrete",.30)
 _box(a,Vector3(0,23.4,23.185),Vector3(10.38,5.8,.025),"cyan",false)
 _round_box(a,Vector3(0,26.42,23.6),Vector3(12,.16,1.08),"concrete",.07,false)
 for z in [-45.,20.]:
  for x in [-7.,7.]:
   _box(a,Vector3(x,9.9,z),Vector3(3.6,19,6),"bearing_concrete",true,.12)
   _box(a,Vector3(x,19.48,z),Vector3(3.1,.16,5.5),"rubber",false)
  _box(a,Vector3(0,19.64,z),Vector3(17.6,.16,6.4),"concrete",true,.06)
  var screen_z=-45. if z<0 else 22.9
  _box(a,Vector3(0,23.4,screen_z),Vector3(10.4,6,.18),"dark_steel",true)
  for x in [-4.,-2.,0.,2.,4.]:_box(a,Vector3(x,23.4,screen_z-signf(screen_z)*.14),Vector3(.075,5.8,.16),"steel",false)
 # Longitudinal underside formwork reveals meet the cross-joints; actual geometry, not painted wear.
 for z in [-22.,-20.,-18.,-16.,-14.]:_box(a,Vector3(0,3.593,z),Vector3(88.7,.012,.014),"joint",false)
 # Reachable cast joints and tie-cone sockets on the inspection parapet's actual exterior.
 for x in range(-28,29,4):a.append(rod(Vector3(x,4.96,-11.982),Vector3(x,4.96,-11.975),.025,"joint",12))
 for x in [-6.016,6.016]:
  for z in range(-42,23,4):
   for y in [21.5,23.5]:a.append(rod(Vector3(x,y,z),Vector3(x+signf(x)*.006,y,z),.028,"joint",12))
 # Subtle cast-panel joints and tie cones explain scale rather than random texture dirt.
 for x in range(-44,45,4):
  _box(a,Vector3(x,3.595,-18),Vector3(.018,.012,11.6),"joint",false)
  _box(a,Vector3(x,7.4,-24.007),Vector3(.018,5.7,.012),"joint",false)
 # Outer/soffit panel recesses above replace the old thin dark line overlays.
 for side in [-1.,1.]:
  # Formwork seams must terminate on real concrete, never float across sky slots.
  for z in range(-44,45,4):
   if z in [-32,0,32]:
    _box(a,Vector3(side*47.99,2.25,z),Vector3(.014,3.5,.016),"joint",false)
    _box(a,Vector3(side*47.99,60.25,z),Vector3(.014,2.5,.016),"joint",false)
   else:_box(a,Vector3(side*47.99,31,z),Vector3(.014,61,.016),"joint",false)
  for y in range(3,61,3):
   if y>4 and y<59:
    for interval in [Vector2(-47.5,-33.5),Vector2(-30.5,-1.5),Vector2(1.5,30.5),Vector2(33.5,47.5)]:
     _box(a,Vector3(side*47.985,y,(interval.x+interval.y)*.5),Vector3(.014,.016,interval.y-interval.x),"joint",false)
   else:_box(a,Vector3(side*47.985,y,0),Vector3(.014,.016,95),"joint",false)
 # Listening resonator: rigid concrete mount, two pipe routes, bearings, a sealed flap case.
 _box(a,Vector3(20,5.04,-22.0),Vector3(.95,1.28,.42),"concrete",true,.05)
 _box(a,Vector3(20,5.52,-21.74),Vector3(.78,.64,.16),"dark_steel",false,.035)
 a.append(rod(Vector3(20,5.52,-21.72),Vector3(20,5.52,-21.46),.065,"steel",24))
 # EXTERNAL SUPPORT-ONLY CANDIDATE: actual flap pivot bearings seat into the
 # existing fixed case, outside the complete rotating panel X envelope.
 # No actor/state/input/collider/route/light/material-map change.
 for x in [19.635,20.365]:
  _box(a,Vector3(x,5.98,-21.75),Vector3(.05,.40,.08),"dark_steel",false,.005)
 for x in [19.64,20.36]:
  var bearing_mesh=TorusMesh.new();bearing_mesh.inner_radius=.037;bearing_mesh.outer_radius=.065;bearing_mesh.rings=24;bearing_mesh.ring_segments=8
  var bearing=G.item(bearing_mesh,Vector3(x,6.22,-21.72),PREFIX+"steel",false);bearing.transform.basis=Basis(Vector3.FORWARD,PI*.5);a.append(bearing)
 # Common fixed backing joins the two existing ceramic index plates to the
 # case. It ends below the analytic full-angle flap sweep, not in its path.
 _box(a,Vector3(20,5.89,-21.625),Vector3(1.02,.22,.12),"dark_steel",false,.004)
 for x in [19.55,20.45]:
  a.append(rod(Vector3(x,5.85,-22),Vector3(x,7.2,-22),.075,"steel",20))
  _box(a,Vector3(x,7.2,-22.4),Vector3(.23,.25,.8),"steel",false,.025)
 for x in [19.72,20.28]:
  for y in [5.3,5.74]:a.append(rod(Vector3(x,y,-21.63),Vector3(x,y,-21.59),.024,"steel",6))
 # The long acoustic return is visibly clipped to channel wall, with expansion sleeves.
 a.append(rod(Vector3(-31,7.2,-22.8),Vector3(20.45,7.2,-22.8),.085,"steel",20))
 for x in range(-30,21,4):
  _box(a,Vector3(x,7.2,-23.02),Vector3(.13,.30,.32),"dark_steel",false,.02)
  a.append(rod(Vector3(x-.07,7.2,-22.8),Vector3(x+.07,7.2,-22.8),.105,"steel",20))
 # Continuous supported soundlock bed reaches the terminal jamb, not an unsupported door.
 _box(a,Vector3(-43,4.0,-18),Vector3(7,.8,4.2),"concrete",true,.04)
 for z in [-19.4,-16.6]:_box(a,Vector3(-45.2,5.8,z),Vector3(.20,2.8,1.2),"concrete",true,.025)
 _box(a,Vector3(-45.2,7.03,-18),Vector3(.20,.34,1.6),"concrete",true,.025)
 # Human-scale two-door acoustic lock at the west channel end; reversible accessible passage.
 for z in [-20.,-16.]:_box(a,Vector3(-43,5.8,z),Vector3(7,2.8,.20),"concrete",true,.04)
 _box(a,Vector3(-43,7.24,-18),Vector3(7,.16,4.2),"concrete",true,.04)
 # First leaf rests open against the passage wall, second is the real exit target.
 door(a,Vector3(-41.5,4.4,-19.85),0.)
 door(a,Vector3(-45.1,4.4,-18),PI*.5)
 _box(a,Vector3(-43,7.1,-18),Vector3(1.2,.045,.09),"warm",false)
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),true);Gloss.install(room,"crossing_channels",Gloss.resources());Clip.install(room,"crossing_channels",ClipShader)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false);Gloss.install(room,"crossing_channels",Gloss.resources());Clip.install(room,"crossing_channels",ClipShader)
 # The sole Omni belongs to the actual warm soundlock fixture.
 G.lamp(room,data,Vector3(-43,6.95,-18),Color("ffe3b5"),.4,8.)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 materials_ready();var actor=Effects.new();actor.name="ChannelListeningFlap";root.add_child(actor);Gloss.bind_actor_when_ready(actor,Gloss.resources())
