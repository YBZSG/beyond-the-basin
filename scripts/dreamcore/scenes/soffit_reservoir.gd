extends RefCounted
## 压顶水库 — original, reference-guided concrete caisson, metres.
## Static geometry is clipped/batched/collided by the existing annex helper.
## Four broad recessed bearings support a real hollow 68 x 50 x 18 m shell.
const G = preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const Effects = preload("res://scripts/dreamcore/uncanny/soffit_reservoir_effects.gd")
const ClipMaterial = preload("res://scripts/dreamcore/uncanny/soffit_clip_material.gd")
const ClipShader = preload("res://shaders/dreamcore/uncanny/soffit_clip_base.gdshader")
const FloorComposition = preload("res://scripts/dreamcore/uncanny/soffit_floor_composition.gd")
const FloorShader = preload("res://shaders/dreamcore/uncanny/soffit_floor_composed.gdshader")
const PREFIX = "soffit_reservoir_"
const ASSETS = "res://assets/dreamcore/uncanny/soffit_reservoir/"
const POOL = Rect2(-37.2,-54,74.4,52)
const WHEEL = Vector3(38.55,1.52,-26)
static var _architecture:Array = []
static var _drain_mesh:Mesh
static func definition()->Dictionary:
 return {"id":"soffit_reservoir","title":"压顶水库","subtitle":"一整座水库，停在头顶三米六。","goal":"转动检修手轮，沿变宽的暖光缝找到侧廊。","bounds":Rect2i(-1,-2,3,3),"retain_full_finite_scene":true,"spawn":Vector3(0,.42,10),"look_at":Vector3(0,2.4,-48),"exit":Vector3(44,.4,-66.9),"exit_station":{"presentation":"authored","readout":false,"interaction_offset":Vector3(.35,1.08,.18),"interaction_pose":Vector3(44,.42,-65.2),"interaction_alternate_pose":Vector3(44.5,.42,-65.2),"label":"检修廊门把手"},"stations":[{"id":"reservoir_shutter","label":"检修百叶手轮","kind":"shutter","position":Vector3(38.55,.4,-26),"presentation":"authored","interaction_offset":Vector3(-.28,1.12,0),"readout":false,"latch_completion":true,"interaction_pose":Vector3(37.6,.42,-26),"interaction_alternate_pose":Vector3(37.6,.42,-25.45),"state_count":2,"target":1,"value_labels":["遮光 / 闭合","检修 / 开启"],"action":"转动手轮","clue":"手轮连着后墙的百叶。开启后，暖光会标出右侧的检修通道。"}],"routes":[[Vector3(0,0.42,10),Vector3(0,0.42,4),Vector3(-38.6,0.42,4),Vector3(-38.6,0.42,-25.2),Vector3(-42,0.42,-25.2),Vector3(-42,0.42,-34.8),Vector3(-38.6,0.42,-34.8),Vector3(-38.6,0.42,-41.2),Vector3(-42,0.42,-41.2),Vector3(-42,0.42,-50.8),Vector3(-38.6,0.42,-50.8),Vector3(-38.6,0.42,-61),Vector3(38.6,0.42,-61),Vector3(38.6,0.42,-50.8),Vector3(42,0.42,-50.8),Vector3(42,0.42,-41.2),Vector3(38.6,0.42,-41.2),Vector3(38.6,0.42,-27.2),Vector3(37.6,0.42,-26),Vector3(38.6,0.42,-27.2),Vector3(38.6,0.42,-41.2),Vector3(42,0.42,-41.2),Vector3(42,0.42,-50.8),Vector3(38.6,0.42,-50.8),Vector3(38.6,0.42,-61),Vector3(44,0.42,-60),Vector3(44,0.42,-65.2)]],"route_clearance_m":3.0,"dry_perimeter_min_m":2.8,"support_detour_min_m":3.4,"pool_depth":.20,"caisson_bounds":AABB(Vector3(-36.8,3.6,-53),Vector3(68,18,50)),"clerestory":Rect2(-40,-53,3.2,50),"side_clerestory":{"inner_x":-40.,"outer_x":-48.,"inner_sill_y":10.4,"outer_sill_y":23.6,"header_y":26.8,"z_min":-53.,"z_max":-3.,"extra_lights":false},"cameras":[{"name":"entry_normal_eye","position":Vector3(0,2.0,7),"target":Vector3(0,2.4,-42),"fov":62.0},{"name":"concept_side_return","position":Vector3(-38.3,2.0,-4),"target":Vector3(-6.2,5.3,-50),"fov":62.0},{"name":"near_joint","position":Vector3(-41.8,2.0,-28),"target":Vector3(-39.9,2.5,-30),"fov":62.0},{"name":"mechanical_close","position":Vector3(37.6,2.0,-24.2),"target":WHEEL,"fov":62.0},{"name":"reverse_support","position":Vector3(38,2.0,-60.5),"target":Vector3(29,5.0,-8),"fov":62.0},{"name":"drain_detail","position":Vector3(-38.1,2.0,-8),"target":Vector3(-37.34,.41,-10.4),"fov":62.0},{"name":"deeper_reference_return","position":Vector3(-38.3,2.0,-18),"target":Vector3(-6.2,5.3,-64),"fov":62.0},{"name":"mid_reference_return","position":Vector3(-38.3,2.0,-14),"target":Vector3(-6.2,5.3,-60),"fov":62.0},{"name":"louver_joint_close","position":Vector3(2.3,2.0,-61.4),"target":Vector3(2,2.68,-64),"fov":62.0}],"sky_top":Color("627578"),"sky_horizon":Color("aab9b5"),"ambient":Color("c8c3b9"),"ambient_energy":.10,"sun_color":Color("dce4dc"),"sun_energy":0.0,"sun_rotation":Vector3(-38,-110,0),"sky_radiance_gain":4.0,"sky_shader":"res://assets/dreamcore/uncanny/soffit_reservoir/day_sky.gdshader","sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.0,"fog":.0005}
static func layout(coord:Vector2i)->Dictionary:
 return {"coord":coord,"water_enabled":true,"water_floor_y":.12,"water_rects":G.water_rects(coord,POOL),"solids":[],"spawn_local":Vector3(0,.42,10)}
static func material_specs()->Dictionary:
 var out={}
 for row in [["concrete","concrete",3.2,.45],["tile","ivory_tile",1.6,.55]]:
  out[PREFIX+row[0]]={"albedo":ASSETS+row[1]+"_albedo.png","normal":ASSETS+row[1]+"_normal.png","orm":ASSETS+row[1]+"_orm.png","period":row[2],"strength":row[3],"tint":"ffffff","roughness_channel":"g"}
 out[PREFIX+"tile_damp"]=out[PREFIX+"tile"].duplicate();out[PREFIX+"tile_damp"].roughness_multiplier=.65;out[PREFIX+"tile_damp"].clearcoat=.18;out[PREFIX+"tile_damp"].clearcoat_roughness=.10
 return out
static func materials_ready()->void:
 if G._mats.has(PREFIX+"concrete"):return
 for key:String in material_specs():
  var spec:Dictionary=material_specs()[key];var m=StandardMaterial3D.new();m.resource_name=key;m.albedo_texture=load(spec.albedo);m.normal_enabled=true;m.normal_texture=load(spec.normal);m.normal_scale=spec.strength;m.roughness_texture=load(spec.orm);m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN;m.roughness=float(spec.get("roughness_multiplier",1.));m.clearcoat_enabled=spec.has("clearcoat");m.clearcoat=float(spec.get("clearcoat",0.));m.clearcoat_roughness=float(spec.get("clearcoat_roughness",.1));m.ao_enabled=true;m.ao_texture=m.roughness_texture;m.ao_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED;m.uv1_scale=Vector3.ONE/float(spec.period);m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC;m.set_meta("annex_pbr_spec",spec);G._mats[key]=m
 for row in [["joint","50564d",.92,0.],["steel","777e77",.36,.85],["dark_steel","29322f",.48,.75],["rubber","212725",.94,0.],["paint","a9b6ae",.47,.35],["warm","ffd09a",.45,0.],["warm_recess","ffcf99",.50,0.],["cool","edf0ed",.5,0.]]:
  var m=StandardMaterial3D.new();m.resource_name=PREFIX+row[0];m.albedo_color=Color(row[1]);m.roughness=row[2];m.metallic=row[3]
  if row[0] in ["warm","warm_recess","cool"]:m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=Color.BLACK;m.emission_enabled=true;m.emission=Color(row[1]);m.emission_energy_multiplier=.35 if row[0]=="warm_recess" else 12.0 if row[0]=="warm" else 2.6
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
static func chamfer_mesh(size:Vector3,b:float,tie_face:int=0)->Mesh:
 var h=size*.5;var k=h-Vector3.ONE*minf(b,minf(h.x,minf(h.y,h.z))*.45);var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for axis in 3:
  var u=(axis+1)%3;var v=(axis+2)%3
  for s in [-1.,1.]:
   var q:Array=[];var normal=Vector3.ZERO;normal[axis]=s
   for uv in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
    var p=Vector3.ZERO;p[axis]=s*h[axis];p[u]=uv.x*k[u];p[v]=uv.y*k[v];q.append(p)
   if axis==0 and int(s)==tie_face:_tie_face(st,h,k,s)
   else:_quad(st,q,normal)
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
static func _tie_face(st:SurfaceTool,h:Vector3,k:Vector3,side:float)->void:
 # Six real35mm-deep conical form-tie recesses, not black decals on a cube.
 var hy=k.y*.5;var hz=k.z/3.;var angles:Array[float]=[]
 for j in 32:angles.append(j*TAU/32.)
 for sy in [-1.,1.]:
  for sz in [-1.,1.]:
   var angle=fposmod(atan2(sz*hz,sy*hy),TAU)
   if not angles.any(func(a:float)->bool:return absf(a-angle)<.00001):angles.append(angle)
 angles.sort()
 for row in 2:
  for col in 3:
   var cy=-k.y+(row+.5)*2.*hy;var cz=-k.z+(col+.5)*2.*hz
   var outer:Array=[];var rim:Array=[];var back:Array=[]
   for angle:float in angles:
    var d=Vector2(cos(angle),sin(angle));var reach=minf(hy/absf(d.x) if absf(d.x)>.000001 else INF,hz/absf(d.y) if absf(d.y)>.000001 else INF)
    outer.append(Vector3(side*h.x,cy+d.x*reach,cz+d.y*reach));rim.append(Vector3(side*h.x,cy+d.x*.026,cz+d.y*.026));back.append(Vector3(side*(h.x-.035),cy+d.x*.017,cz+d.y*.017))
   for j in angles.size():
    var n=(j+1)%angles.size();var d:Vector3=((rim[j]+rim[n])*.5-Vector3(side*h.x,cy,cz)).normalized()
    _quad(st,[outer[j],outer[n],rim[n],rim[j]],Vector3(side,0,0))
    _quad(st,[rim[j],rim[n],back[n],back[j]],(Vector3(side*.009/.035,0,0)-d).normalized())
    _tri(st,Vector3(side*(h.x-.035),cy,cz),back[j],back[n],Vector3(side,0,0))
static func _panel_spans(start:float,pitch:float,count:int)->Array:
 var spans:Array=[]
 for i in count:
  var lo=start+i*pitch+.003;var hi=start+(i+1)*pitch-.003
  if i==0:spans.append(Vector2(lo,start+.20));spans.append(Vector2(start+.235,hi))
  elif i==count-1:spans.append(Vector2(lo,start+count*pitch-.235));spans.append(Vector2(start+count*pitch-.20,hi))
  else:spans.append(Vector2(lo,hi))
 return spans
static func _cast_soffit(a:Array)->void:
 # Structural slab behind a real recessed cast face: 6mm joints, 35mm-deep
 # perimeter drip groove, 2mm edge chamfers. Nothing is raised into the light.
 var plane=PlaneMesh.new();plane.size=Vector2(68,50)
 a.append(G.item(plane,Vector3(0,3.635,-28),PREFIX+"joint",false,Vector3(PI,0,0)))
 for xs:Vector2 in _panel_spans(-34,3.4,20):
  for zs:Vector2 in _panel_spans(-53,2.5,20):_box(a,Vector3((xs.x+xs.y)*.5,3.62,(zs.x+zs.y)*.5),Vector3(xs.y-xs.x,.04,zs.y-zs.x),"concrete",false,.002)
static func _drain_module()->Mesh:
 if _drain_mesh!=null:return _drain_mesh
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);var bar=chamfer_mesh(Vector3(.22,.018,.012),.002)
 for i in 33:st.append_from(bar,0,Transform3D(Basis.IDENTITY,Vector3(0,0,-.5+(i+.5)/33.)))
 _drain_mesh=st.commit();return _drain_mesh
static func rod(a:Vector3,b:Vector3,r:float,key:String,segments:int=16)->Dictionary:
 var mesh=CylinderMesh.new();mesh.top_radius=r;mesh.bottom_radius=r;mesh.height=a.distance_to(b);mesh.radial_segments=segments;mesh.rings=0
 var item=G.item(mesh,(a+b)*.5,PREFIX+key,false);item.transform.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()));return item
static func _side_sill_height(x:float)->float:return 23.6-(x+48.)*1.65
static func _left_wall_segment(a:Array,p:Vector3,size_v:Vector3)->void:
 # Real eight-metre-deep splayed daylight reveal, not an emissive panel.
 # Existing support pockets below3.8m are preserved by each source segment.
 var lo=p-size_v*.5;var hi=p+size_v*.5
 var cuts:Array[float]=[lo.z,hi.z]
 for z in [-53.,-3.]:
  if z>lo.z and z<hi.z:cuts.append(z)
 cuts.sort()
 for i in range(cuts.size()-1):
  var za=cuts[i];var zb=cuts[i+1];var mid=(za+zb)*.5
  if mid < -53. or mid > -3.:
   _box(a,Vector3(p.x,p.y,mid),Vector3(size_v.x,size_v.y,zb-za),"concrete");continue
  _box(a,Vector3(p.x,(26.8+hi.y)*.5,mid),Vector3(size_v.x,hi.y-26.8,zb-za),"concrete")
  var yl=_side_sill_height(lo.x);var yr=_side_sill_height(hi.x)
  var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
  _quad(st,[Vector3(lo.x,lo.y,za),Vector3(hi.x,lo.y,za),Vector3(hi.x,yr,za),Vector3(lo.x,yl,za)],Vector3.FORWARD)
  _quad(st,[Vector3(lo.x,lo.y,zb),Vector3(hi.x,lo.y,zb),Vector3(hi.x,yr,zb),Vector3(lo.x,yl,zb)],Vector3.BACK)
  _quad(st,[Vector3(lo.x,lo.y,za),Vector3(lo.x,yl,za),Vector3(lo.x,yl,zb),Vector3(lo.x,lo.y,zb)],Vector3.LEFT)
  _quad(st,[Vector3(hi.x,lo.y,za),Vector3(hi.x,yr,za),Vector3(hi.x,yr,zb),Vector3(hi.x,lo.y,zb)],Vector3.RIGHT)
  _quad(st,[Vector3(lo.x,lo.y,za),Vector3(hi.x,lo.y,za),Vector3(hi.x,lo.y,zb),Vector3(lo.x,lo.y,zb)],Vector3.DOWN)
  _quad(st,[Vector3(lo.x,yl,za),Vector3(hi.x,yr,za),Vector3(hi.x,yr,zb),Vector3(lo.x,yl,zb)],Vector3(yl-yr,hi.x-lo.x,0).normalized())
  a.append(G.item(st.commit(),Vector3.ZERO,PREFIX+"concrete",true))
static func _wall_joint(a:Array,side:float,p:Vector3,size_v:Vector3)->void:
 # Joint strips terminate on real reveal edges, never bridge the open aperture.
 if side>0:_box(a,p,size_v,"joint",false);return
 var lo=p-size_v*.5;var hi=p+size_v*.5
 if size_v.y>.1 and p.z> -53. and p.z< -3.:
  for span in [Vector2(lo.y,10.37),Vector2(26.83,hi.y)]:
   if span.y>span.x:_box(a,Vector3(p.x,(span.x+span.y)*.5,p.z),Vector3(size_v.x,span.y-span.x,size_v.z),"joint",false)
 elif p.y>10.4 and p.y<26.8:
  for span in [Vector2(lo.z,minf(hi.z,-53.)),Vector2(maxf(lo.z,-3.),hi.z)]:
   if span.y>span.x:_box(a,Vector3(p.x,p.y,(span.x+span.y)*.5),Vector3(size_v.x,size_v.y,span.y-span.x),"joint",false)
 else:_box(a,p,size_v,"joint",false)
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 materials_ready();var a:Array=[]
 # Basin and true 2.8m side decks / 3.4m support detours. Source Y=.32 unchanged.
 _box(a,Vector3(0,-.19,-28),Vector3(96,.62,80),"tile")
 # Disjoint real deck regions: .9m damp ceramic finish, no extra water or
 # emissive floor. Same top.40, physical extents and traversal response.
 for r in [Rect2(-48,-1.1,96,13.1),Rect2(-48,-68,96,13.1),Rect2(-48,-2,9.9,.9),Rect2(38.1,-2,9.9,.9),Rect2(-48,-54.9,9.9,.9),Rect2(38.1,-54.9,9.9,.9),Rect2(-48,-54,9.9,52),Rect2(38.1,-54,9.9,52)]:_box(a,Vector3(r.get_center().x,.26,r.get_center().y),Vector3(r.size.x,.28,r.size.y),"tile")
 for r in [Rect2(-38.1,-2,76.2,.9),Rect2(-38.1,-54.9,76.2,.9),Rect2(-38.1,-54,.9,52),Rect2(37.2,-54,.9,52)]:_box(a,Vector3(r.get_center().x,.26,r.get_center().y),Vector3(r.size.x,.28,r.size.y),"tile_damp")
 # Two 140mm risers give a real reversible descent from dry deck to shallow bed.
 _box(a,Vector3(0,.19,-2.60),Vector3(6,.14,1.20),"tile")
 # Full 96 x 80 x 54 enclosure. 8m-thick lateral service piers read as mass.
 # Continuous side walls recede around four true supports, leaving measured dry detours.
 for side in [-1.,1.]:
  var spans=[Vector2(-68,-52.4),Vector2(-39.6,-36.4),Vector2(-23.6,12)] if side<0 else [Vector2(-58,-52.4),Vector2(-39.6,-26.4),Vector2(-13.6,12)]
  for span:Vector2 in spans:
   if side<0:_left_wall_segment(a,Vector3(-44,27,(span.x+span.y)*.5),Vector3(8,54,span.y-span.x))
   else:_box(a,Vector3(side*44,27,(span.x+span.y)*.5),Vector3(8,54,span.y-span.x),"concrete")
  var bays=[-46.,-30.] if side<0 else [-46.,-20.]
  for z in bays:
   if side<0:
    _left_wall_segment(a,Vector3(-46,27,z),Vector3(4,54,12.8));_left_wall_segment(a,Vector3(-42,28.9,z),Vector3(4,50.2,12.8))
   else:
    _box(a,Vector3(side*46,27,z),Vector3(4,54,12.8),"concrete");_box(a,Vector3(side*42,28.9,z),Vector3(4,50.2,12.8),"concrete")
 # East side pier is carved, not a fake door stuck onto a solid wall.
 for r in [Rect2(40,-68,2,6),Rect2(46,-68,2,10),Rect2(42,-68,4,1)]:_box(a,Vector3(r.get_center().x,27,r.get_center().y),Vector3(r.size.x,54,r.size.y),"concrete")
 _box(a,Vector3(44,28.5,-62.5),Vector3(8,51,9),"concrete")
 _box(a,Vector3(0,27,-68.5),Vector3(96,54,1),"concrete");
 # True3.2m clerestory above the side gap. Existing scene sky, no invented fill.
 for rect in [Rect2(-48,-68,8,80),Rect2(-36.8,-68,84.8,80),Rect2(-40,-68,3.2,15),Rect2(-40,-3,3.2,15)]:_box(a,Vector3(rect.get_center().x,54.5,rect.get_center().y),Vector3(rect.size.x,1,rect.size.y),"concrete",false,.025)
 # Continuous concrete reveal lips have real12mm eased edges; the opening
 # remains empty sky, never a luminous fake panel.
 _box(a,Vector3(-39.99,10.375,-28),Vector3(.10,.05,50),"concrete",false,.012)
 _box(a,Vector3(-39.99,26.825,-28),Vector3(.10,.05,50),"concrete",false,.012)
 # Rear light chamber and long thin inspection aperture at human scale.
 _box(a,Vector3(0,1.05,-64.3),Vector3(80,1.3,.6),"concrete")
 _box(a,Vector3(0,28.75,-64.3),Vector3(80,50.5,.6),"concrete")
 _box(a,Vector3(0,1.80,-64.21),Vector3(79.8,.18,.035),"warm",false)
 _box(a,Vector3(0,2.65,-66.4),Vector3(79.8,1.8,.08),"warm_recess",false)
 for y in [1.68,3.49]:_box(a,Vector3(0,y,-64.28),Vector3(80,.08,.20),"dark_steel",false,.012)
 # Front entry compression: 2.40m clear portal in a 5m-deep solid wall.
 _box(a,Vector3(-25,27,10),Vector3(46,54,4),"concrete");_box(a,Vector3(25,27,10),Vector3(46,54,4),"concrete")
 _box(a,Vector3(0,28.4,10),Vector3(4,51.2,4),"concrete")
 for x in [-1.96,1.96]:_box(a,Vector3(x,1.6,9.8),Vector3(.07,2.4,4.5),"steel",false,.01)
 _box(a,Vector3(0,2.825,9.8),Vector3(4,.05,4.5),"steel",false,.01)
 _box(a,Vector3(0,2.785,9.9),Vector3(2.4,.04,.09),"cool",false)
 # A real closed arrival hatch contains a backwards walk before the floor edge.
 _box(a,Vector3(0,1.6,11.9),Vector3(4,2.4,.20),"paint",true,.018)
 a.append(rod(Vector3(-.65,1.35,11.73),Vector3(.65,1.35,11.73),.028,"steel",20))
 for x in [-.55,.55]:a.append(rod(Vector3(x,1.35,11.73),Vector3(x,1.35,11.82),.025,"steel",16))

 # Actual closed shell around a hollow caisson (not a scaled solid BoxMesh).
 var caisson_start=a.size()
 _box(a,Vector3(0,4.145,-28),Vector3(68,1.01,50),"concrete",true,.055)
 _cast_soffit(a)
 _box(a,Vector3(0,21,-28),Vector3(68,1.2,50),"concrete",false,.055)
 for x in [-33.3,33.3]:_box(a,Vector3(x,12.525,-28),Vector3(1.4,15.75,50),"concrete",false,.045)
 for z in [-52.3,-3.7]:_box(a,Vector3(0,12.525,z),Vector3(65.2,15.75,1.4),"concrete",false,.045)
 # Interior diaphragms establish real box-beam construction; visible at service recess.
 for x in [-11.3,11.3]:_box(a,Vector3(x,12.525,-28),Vector3(.7,15.75,47.2),"concrete",false,.03)
 # Intact 68m box is offset left2.8m; asymmetry tightens the real entry composition.
 for index in range(caisson_start,a.size()):a[index].transform.origin.x-=2.8
 # Recessed edge buttresses: exact dry footprints fully outside the pool.
 for x in [-38.6,38.6]:
  var bays=[-46.,-30.] if x<0 else [-46.,-20.]
  for z in bays:
   _box(a,Vector3(x,.475,z),Vector3(2.8,.15,6),"concrete")
   a.append(G.item(chamfer_mesh(Vector3(2.8,2.65,6),.055,int(signf(x))),Vector3(x,1.875,z),PREFIX+"concrete",true))
   _box(a,Vector3(x,3.24,z),Vector3(3.0,.08,6.3),"steel",false,.015)
   _box(a,Vector3(x,3.34,z),Vector3(3.0,.12,6.1),"rubber",false,.01)
   _box(a,Vector3(x,3.50,z),Vector3(3.2,.20,6.4),"concrete",true,.035)
   for dz in [-2.5,-1.25,0.,1.25,2.5]:a.append(rod(Vector3(x+signf(x)*1.52,3.24,z+dz),Vector3(x+signf(x)*1.56,3.24,z+dz),.032,"steel",6))
   for dx in [-1.3,1.3]:
    for dz in [-2.85,2.85]:_box(a,Vector3(x+dx,3.39,z+dz),Vector3(.16,.22,.14),"steel",false,.008)
   _box(a,Vector3(-38.0 if x<0 else 35.0,5.1,z),Vector3(4.4 if x<0 else 10.0,3.0,6.4),"concrete",true,.055)
 # Cast-panel seams: geometric narrow shadow reveals and perimeter drip edge.
 var finish_start=a.size()
 for x in range(-32,33,2):_box(a,Vector3(x,12.6,-2.995),Vector3(.012,17.8,.01),"joint",false)
 for y in range(6,22,2):
  _box(a,Vector3(0,y,-2.993),Vector3(67.8,.012,.012),"joint",false)
  for x in [-34.007,34.007]:_box(a,Vector3(x,y,-28),Vector3(.012,.012,49.8),"joint",false)
 for x in [-34.006,34.006]:
  for z in range(-51,-3,2):_box(a,Vector3(x,12.6,z),Vector3(.012,17.8,.012),"joint",false)
 # Tie-cone recesses in reachable side-return surfaces; closed bevel ring, dark core.
 for side in [-1.,1.]:
  for z in range(-51,-3,4):
   for y in [4.8,6.8,10.8,14.8,18.8]:
    var p=Vector3(side*34.012,y,z);a.append(rod(p,p+Vector3(side*.004,0,0),.027,"joint",12))
 for index in range(finish_start,a.size()):a[index].transform.origin.x-=2.8
 # Coping and narrow slot drainage. Grating is real repeated transverse bars.
 for x in [-37.34,37.34]:
  _box(a,Vector3(x,.405,-28),Vector3(.24,.01,52),"dark_steel",false)
  for i in 52:
   var z=-53.5+i;var front_bearing=-30. if x<0 else -20.
   if absf(z+46.)<3.7 or absf(z-front_bearing)<3.7:continue
   a.append(G.item(_drain_module(),Vector3(x,.418,z),PREFIX+"steel",false))
  for dx in [-.133,.133]:_box(a,Vector3(x+dx,.418,-28),Vector3(.018,.025,52),"steel",false,.004)
 for x in [-37.57,37.57]:_box(a,Vector3(x,.407,-28),Vector3(.18,.014,52),"tile",false,.012)
 # Cast wall joints follow the actual recessed surfaces: no line floats across a pocket.
 for side in [-1.,1.]:
  var panels=[Vector2(-58,-52.4),Vector2(-39.6,-36.4),Vector2(-23.6,8)] if side<0 else [Vector2(-58,-52.4),Vector2(-39.6,-26.4),Vector2(-13.6,8)]
  for span:Vector2 in panels:
   for y in range(3,54,3):_wall_joint(a,side,Vector3(side*39.995,y,(span.x+span.y)*.5),Vector3(.01,.012,span.y-span.x))
   var z=span.x+1.
   while z<span.y:
    _wall_joint(a,side,Vector3(side*39.995,27,z),Vector3(.01,53.5,.012))
    for y in [1.2,2.4,4.8,7.2]:
     var p=Vector3(side*39.987,y,z);a.append(rod(p,p-Vector3(side*.003,0,0),.019,"joint",12))
    z+=4.
 # 2.2m human service door with a proper recessed steel jamb and small pull.
 _box(a,Vector3(-39.975,1.5,-20),Vector3(.045,2.2,1.08),"paint",false,.012)
 for z in [-20.59,-19.41]:_box(a,Vector3(-39.93,1.53,z),Vector3(.10,2.3,.07),"steel",false,.008)
 _box(a,Vector3(-39.93,2.67,-20),Vector3(.10,.07,1.25),"steel",false,.008)
 a.append(rod(Vector3(-39.84,1.3,-19.65),Vector3(-39.84,1.48,-19.65),.016,"steel"))
 # Fixed wheel pedestal / bearings / transmission: wheel itself belongs to actor.
 _box(a,Vector3(39.45,.98,-26),Vector3(.45,1.16,.6),"concrete",true,.035)
 _box(a,Vector3(39.2,1.52,-26),Vector3(.16,.35,.35),"steel",false,.02)
 a.append(rod(Vector3(38.55,1.52,-26),Vector3(39.55,1.52,-26),.037,"steel",24))
 for z in [-26.22,-25.78]:
  for y in [1.38,1.66]:a.append(rod(Vector3(39.09,y,z),Vector3(39.16,y,z),.025,"dark_steel",6))
 # Two bolted right-angle gearboxes explain the mechanical change of shaft axis.
 for p in [Vector3(39.70,1.52,-26),Vector3(39.70,7.0,-26),Vector3(39.70,7.0,-63.8),Vector3(39.70,2.95,-63.8)]:
  _box(a,p,Vector3(.28,.30,.32),"paint",false,.025)
  for dy in [-.10,.10]:
   for dz in [-.105,.105]:a.append(rod(p+Vector3(-.16,dy,dz),p+Vector3(-.145,dy,dz),.016,"steel",6))
 # Service drive rises on the side wall, then follows rear slit to the louver shafts.
 a.append(rod(Vector3(39.70,1.52,-26),Vector3(39.70,7.0,-26),.032,"steel",20))
 a.append(rod(Vector3(39.70,7.0,-26),Vector3(39.70,7.0,-63.8),.032,"steel",20))
 a.append(rod(Vector3(39.70,7.0,-63.8),Vector3(39.70,2.95,-63.8),.032,"steel",20))
 a.append(rod(Vector3(39.70,2.95,-63.8),Vector3(-39.4,2.95,-63.8),.032,"steel",20))
 for z in range(-60,-25,4):_box(a,Vector3(39.85,7.0,z),Vector3(.32,.12,.12),"dark_steel",false,.012)
 # The side passage is a built rectangular folded maintenance gallery, not a pipe.
 for p in [Vector3(42,2.82,-60),Vector3(44,2.82,-64)]:_box(a,p,Vector3(.9,.04,.10),"warm",false)
 # Actual terminal door in the folded gallery, with an accessible handle target.
 _box(a,Vector3(44,1.5,-66.94),Vector3(1.2,2.2,.08),"paint",false,.012)
 for x in [43.36,44.64]:_box(a,Vector3(x,1.55,-66.87),Vector3(.08,2.30,.12),"steel",false,.008)
 _box(a,Vector3(44,2.68,-66.87),Vector3(1.36,.08,.12),"steel",false,.008)
 a.append(rod(Vector3(44.35,1.40,-66.77),Vector3(44.35,1.58,-66.77),.019,"steel",20))
 # Mounted practical slots, no invisible atmosphere-fill lamps.
 for side in [-1.,1.]:
  for z in [-34.,-6.]:_box(a,Vector3(side*39.92,5.2,z),Vector3(.06,.08,2.4),"cool",false)
 _architecture=a;return a
static func _install_floor_receiver(room:Node3D,materials:RefCounted)->void:
 if materials==null:return # Offline callers must supply an actual library to export bindings.
 var receiver=room.get_node_or_null("SoffitFloorReceiver")
 if receiver==null:
  receiver=FloorComposition.new();receiver.name="SoffitFloorReceiver";room.add_child(receiver)
 if receiver is FloorComposition:receiver.configure(room,materials,"soffit_reservoir",FloorShader)
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),true)
 ClipMaterial.install(room,ClipShader)
 _install_floor_receiver(room,_materials)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false)
 ClipMaterial.install(room,ClipShader)
 _install_floor_receiver(room,_materials)
 for side in [-1.,1.]:
  for z in [-34.,-6.]:G.lamp(room,data,Vector3(side*39.7,5.2,z),Color("edf0ed"),2.5,20.)
 G.lamp(room,data,Vector3(0,2.79,9.9),Color("e3eee8"),.7,9.)
 # Elongated emissive fixtures supply continuous reflected highlights; proxy omni lobes do not become point suns.
 for child in room.get_children():
  if child is OmniLight3D:
   child.light_specular=0.0
   if is_equal_approx(child.position.y,5.2):child.shadow_enabled=true;child.set_meta("soffit_side_practical",true)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 materials_ready();var actor=Effects.new();actor.name="ReservoirLouverMechanism";root.add_child(actor)
