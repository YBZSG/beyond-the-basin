extends RefCounted
## Monumental teal/cloud room. All visible play balls are persistent rigid bodies,
## not a decorative MultiMesh or replaced camera-local patch.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const R=preload("res://scripts/dreamcore/scenes/reference_space_geometry.gd")
const Pit=preload("res://scripts/dreamcore/ballpit/ball_pit.gd")
const BALL_GRID=Vector2i(48,32)
const BALL_RADIUS=.14
static var _architecture:Array=[]
static func definition()->Dictionary:
 var d=R.definition("cloud_ballpit","云朵球海",Vector3(0,.02,5.8),Vector3(4,4,-25),1,true)
 d.stations=[R.station("cloud_light","云墙的夜灯",Vector3(-13,.02,11),"light"),R.station("cloud_flow","球海的回声",Vector3(13,.02,11),"flow"),R.station("cloud_observe","梯子尽头的黑门",Vector3(12,.02,-17),"observe",Vector3(10,39,-27.8))]
 d.exit=Vector3(5,.02,24);d.ball_count=BALL_GRID.x*BALL_GRID.y;d.ball_radius=BALL_RADIUS;d.ambient_energy=.24;d.fog=.0018
 d.routes=[[Vector3(0,.02,5.8),Vector3(0,.02,5),Vector3(6,.02,0),Vector3(12,.02,-17),Vector3(18,.02,18)]]
 return d
static func layout(coord:Vector2i)->Dictionary:return {"coord":coord,"water_enabled":false,"water_rects":[],"solids":[],"spawn_local":Vector3(0,.02,5.8)}
static func _cloud_mesh()->Mesh:
 # A single closed silhouette avoids interpenetrating oval surfaces/z-fighting.
 var outline:Array=[]
 var ellipses=[Vector4(0,-.25,2.7,.575),Vector4(-2,0,.75,.54),Vector4(-.7,.7,.95,.684),Vector4(1,.6,.85,.612),Vector4(2.2,0,.6,.432)]
 for i in 192:
  var angle=float(i)*TAU/192.;var d=Vector2(cos(angle),sin(angle));var reach=0.
  for e:Vector4 in ellipses:
   var aa=d.x*d.x/(e.z*e.z)+d.y*d.y/(e.w*e.w)
   var bb=-2.*(d.x*e.x/(e.z*e.z)+d.y*e.y/(e.w*e.w))
   var cc=e.x*e.x/(e.z*e.z)+e.y*e.y/(e.w*e.w)-1.;var disc=bb*bb-4.*aa*cc
   if disc>=0:reach=maxf(reach,(-bb+sqrt(disc))/(2.*aa))
  outline.append(Vector3(d.x*reach,d.y*reach,0))
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in outline.size():
  var j=(i+1)%outline.size();var a:Vector3=outline[i];var b:Vector3=outline[j]
  for tri in [[Vector3(0,0,.1),b+Vector3(0,0,.1),a+Vector3(0,0,.1)],[Vector3(0,0,-.1),a-Vector3(0,0,.1),b-Vector3(0,0,.1)],[a+Vector3(0,0,.1),b+Vector3(0,0,.1),b-Vector3(0,0,.1)],[a+Vector3(0,0,.1),b-Vector3(0,0,.1),a-Vector3(0,0,.1)]]:
   for v in tri:st.add_vertex(v)
 st.generate_normals();return st.commit()
static func _cloud(a:Array,center:Vector3,size:float,side:bool=false)->void:
 var mesh=_cloud_mesh();var rotation=Vector3(0,-PI*.5,0) if side else Vector3.ZERO
 for border in [true,false]:
  var offset=Vector3(.12 if border else -.03,0,0) if side else Vector3(0,0,-.12 if border else .03)
  var scale_v=Vector3(size+.09 if border else size,size+.09 if border else size,1.)
  if side:scale_v=Vector3(1.,scale_v.y,scale_v.x)
  a.append(G.item(mesh,center+offset,"dark" if border else "white",false,rotation,scale_v))
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 var a:Array=[G.box(Vector3(0,-.3,0),Vector3(48,.6,56),"dark",false)]
 R.enclosure(a,Vector2(24,28),42,"teal")
 for item in a:item.collision=false # containment is persistent, never duplicated by streamed chunks
 for c in [Vector3(-12,13,-27.85),Vector3(4,27,-27.85),Vector3(-11,35,-27.85)]:_cloud(a,c,2.8)
 for c in [Vector3(23.85,17,-10),Vector3(23.85,31,13)]:_cloud(a,c,3.2,true)
 # Forty-metre service ladder is a distant scale cue, not a fake usable exit.
 # A ground-level mesh cage makes its non-traversable status physical and clear.
 for x in [9.35,10.65]:a.append(G.box(Vector3(x,20,-27.5),Vector3(.09,40,.12),"dark",false))
 for i in 114:a.append(G.box(Vector3(10,.5+i*.35,-27.4),Vector3(1.4,.06,.16),"dark",false))
 a.append(G.box(Vector3(10,39,-27.35),Vector3(2,4,.15),"dark",false))
 for x in [8.7,11.3]:a.append(G.box(Vector3(x,1.2,-26.8),Vector3(.12,2.4,2),"metal"))
 a.append(G.box(Vector3(10,1.2,-25.8),Vector3(2.7,2.4,.08),"glass"))
 # Bed dimensions are exactly the persistent physics tray's contract.
 var size=Vector2(BALL_GRID)*(BALL_RADIUS*2.+.008)+Vector2.ONE*.12
 for side in [-1.,1.]:
  a.append(G.box(Vector3(side*(size.x*.5+.08),.12,0),Vector3(.16,.24,size.y+.32),"teal",false))
  a.append(G.box(Vector3(0,.12,side*(size.y*.5+.08)),Vector3(size.x+.32,.24,.16),"teal",false))
 for z in [-20.,20.]:a.append(G.box(Vector3(0,41.5,z),Vector3(18,.15,.8),"glow",false))
 # This south-wall door faces the room (-Z); keep its handle on that side.
 var door_origin:=Vector3(5,0,27.9)
 a.append(G.box(door_origin+Vector3(0,1.15,0),Vector3(1.1,2.3,.07),"dark",false,Vector3.ZERO))
 a.append(G.box(door_origin+Vector3(.33,1.08,-.06),Vector3(.04,.19,.07),"metal",false))
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:G.build(room,data,geometry(),true)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false)
 for p in [Vector3(-12,16,6),Vector3(12,22,-12),Vector3(0,38,15)]:G.lamp(room,data,p,Color("a3cbd0"),3.,40.)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 # Non-overlapping persistent floor apron: balls can be carried/thrown outside
 # the tray and never lose support when a visual terrain chunk retires.
 var half=(Vector2(BALL_GRID)*(BALL_RADIUS*2.+.008)+Vector2.ONE*.52)*.5
 for rect in [Rect2(-24,-28,48,28-half.y),Rect2(-24,half.y,48,28-half.y),Rect2(-24,-half.y,24-half.x,half.y*2),Rect2(half.x,-half.y,24-half.x,half.y*2)]:
  _persistent_box(root,Vector3(rect.get_center().x,-.3,rect.get_center().y),Vector3(rect.size.x,.6,rect.size.y))
 for x in [-24.5,24.5]:_persistent_box(root,Vector3(x,21,0),Vector3(1,42,58))
 for z in [-28.5,28.5]:_persistent_box(root,Vector3(0,21,z),Vector3(48,42,1))
 var pit=Pit.new();pit.name="PersistentInteractiveBallSea";root.add_child(pit);pit.configure(Vector3.ZERO,BALL_GRID,BALL_RADIUS,250821)

static func _persistent_box(root:Node3D,point:Vector3,size:Vector3)->void:
 var body=StaticBody3D.new();body.name="PersistentChamberContainment";body.position=point;root.add_child(body)
 var shape=BoxShape3D.new();shape.size=size;var cs=CollisionShape3D.new();cs.shape=shape;body.add_child(cs)
