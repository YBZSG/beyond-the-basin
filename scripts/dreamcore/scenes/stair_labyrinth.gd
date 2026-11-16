extends RefCounted
## Connected, staggered, four-storey stair fabric. All graph edges are playable.
## Compact junctions own their slab once; flights start/end at its actual edges.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const R=preload("res://scripts/dreamcore/scenes/reference_space_geometry.gd")
const LANDING=3.2
const WIDTH=2.6
const RISER=.15
const U=preload("res://scripts/dreamcore/scenes/stair_upright_once.gd")
static var _architecture:Array=[]
static func graph()->Dictionary:
 var nodes:Dictionary={};var edges:Array=[]
 for tier in 4:
  var shift=9.0 if tier%2==1 else 0.0
  for j in 4:
   for i in 4:
    var id="t%d_%d_%d"%[tier,i,j]
    nodes[id]=Vector3(-27.+18.*i+shift,.4+12.*tier+(8. if (i+j)%2==0 else 0.),-27.+18.*j+shift)
    if i>0 and not (i==2 and j==1+tier%2):edges.append(["t%d_%d_%d"%[tier,i-1,j],id])
    if j>0 and not (j==2 and i==1+(tier+1)%2):edges.append(["t%d_%d_%d"%[tier,i,j-1],id])
 # Perimeter links: two ascending flights, a short level turn, then a true
 # shared next-tier junction. Alternate ends so progression crosses each tier.
 for tier in 3:
  var east=tier%2==0
  var from_id="t%d_3_3"%tier if east else "t%d_0_0"%tier
  var to_id="t%d_3_3"%(tier+1) if east else "t%d_0_0"%(tier+1)
  var p:Vector3=nodes[from_id];var q:Vector3=nodes[to_id]
  var outer=52. if east else -49.
  var a="link%d_a"%tier;var b="link%d_b"%tier
  nodes[a]=Vector3(outer,(p.y+q.y)*.5,p.z)
  nodes[b]=Vector3(outer,(p.y+q.y)*.5,q.z)
  edges.append([from_id,a]);edges.append([a,b]);edges.append([b,to_id])
 return {"nodes":nodes,"edges":edges,"spawn_node":"t0_1_2"}
static func route()->Array:
 var g=graph();var out:Array=[]
 for id in ["t0_1_2","t0_0_2","t0_0_3","t0_1_3","t0_2_3","t0_3_3","link0_a","link0_b","t1_3_3","t1_2_3","t1_1_3","t1_0_3","t1_0_2","t1_0_1","t1_0_0","link1_a","link1_b","t2_0_0","t2_1_0","t2_2_0","t2_3_0","t2_3_1","t2_3_2","t2_3_3","link2_a","link2_b","t3_3_3"]:out.append(g.nodes[id])
 return out
static func side_routes()->Array:
 var g=graph();var out:Array=[]
 for e in g.edges:out.append([g.nodes[e[0]],g.nodes[e[1]]])
 return out
static func definition()->Dictionary:
 var g=graph();var spawn:Vector3=g.nodes[g.spawn_node]
 var d=R.definition("stair_labyrinth","无尽交错楼梯",spawn+Vector3(0,.02,0),Vector3(14,17,-18),2,true)
 d.stations=[R.station("stairs_light","黑暗里的刻度",spawn+Vector3(-.95,0,-.8),"light"),R.station("stairs_flow","交错的回声",g.nodes.t1_0_0+Vector3(.8,0,-.8),"flow"),R.station("stairs_observe","交错的最高处",g.nodes.t3_3_3+Vector3(-.8,0,-.8),"observe",Vector3(0,54.932,30))]
 d.cameras=[{"position":Vector3(0,43.51233,32.48423)+Vector3(0,1.6,0),"target":Vector3(4,24,-10),"fov":62.0},{"position":spawn+Vector3(0,1.6,0),"target":Vector3(15,17,-22),"fov":62.0},{"position":g.nodes.t1_0_0+Vector3(.2,1.6,.2),"target":Vector3(24,15,24),"fov":62.0}]
 d.retain_full_finite_scene=true
 d.preview_vantage="Top camera stands 1.9m down the front-middle north descent, settled by original player controller; other views on real junctions; eye offset1.6m"
 d.exit=spawn+Vector3(.8,0,-.8);d.routes=[route()]+side_routes();d.stair_riser_max=RISER;d.stair_width=WIDTH;d.rail_height=1.1;d.ceiling_height=64.;d.ambient_energy=.18;d.ambient=Color("819099");return d
static func layout(coord:Vector2i)->Dictionary:return {"coord":coord,"water_enabled":false,"water_rects":[],"solids":[],"spawn_local":definition().spawn}
static func _materials()->void:
 if G._mats.has("stair_stone"):return
 var m=StandardMaterial3D.new();m.albedo_color=Color("8d9295");m.roughness=.87;m.albedo_texture=load(G.PBR_ROOT+"tile_pearl_albedo_2k.png");m.uv1_scale=Vector3.ONE/2.4;m.roughness=1.;m.roughness_texture=load(G.PBR_ROOT+"plaster_orm_2k.png");m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN;m.metallic_texture=m.roughness_texture;m.metallic_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE;m.metallic=1.;m.ao_enabled=true;m.ao_texture=m.roughness_texture;m.ao_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
 G._mats.stair_stone=m
 var steel=StandardMaterial3D.new();steel.albedo_color=Color("30393d");steel.roughness=.8;G._mats.stair_iron=steel
 var hall=StandardMaterial3D.new();hall.albedo_color=Color("20272a");hall.roughness=.95;G._mats.stair_hall=hall
static func _guard(a:Array,p:Vector3,q:Vector3,uprights:Dictionary)->void:
 # An unobtrusive 35 mm dark handrail and 25 mm uprights, not a slab rail.
 # Three matte horizontal infill rods and the top rail are real colliders.
 # Clear gaps <0.30m cannot admit the player capsule; no showroom glazing.
 for height in [.25,.52,.79]:R.beam(a,p+Vector3(0,height,0),q+Vector3(0,height,0),.018,.025,"stair_iron")
 R.beam(a,p+Vector3(0,1.10,0),q+Vector3(0,1.10,0),.035,.035,"stair_iron")
 var count=maxi(1,int(ceil(p.distance_to(q)/2.4)))
 for i in count+1:
  var at=p.lerp(q,float(i)/count)
  var center=at+Vector3(0,.55,0)
  if U.claim(uprights,center):a.append(G.box(center,Vector3(.025,1.10,.025),"stair_iron",false))
static func _flight(a:Array,p:Vector3,q:Vector3,uprights:Dictionary)->void:
 # Reverse descending edges before meshing: each low-to-high tread top is
 # exactly low + (i+1)*riser and the final tread meets the upper slab plane.
 if p.y>q.y:
  var tmp=p;p=q;q=tmp
 var dir=Vector3(q.x-p.x,0,q.z-p.z).normalized();var side=dir.cross(Vector3.UP)
 var start=p+dir*LANDING*.5;var end=q-dir*LANDING*.5
 var run=Vector2(end.x-start.x,end.z-start.z).length();var rise=q.y-p.y
 var count=maxi(1,int(ceil((rise-.00001)/RISER)))
 var depth=run/count;var angle=atan2(-dir.x,-dir.z)
 if rise<.001:
  a.append(G.box((start+end)*.5-Vector3(0,.18,0),Vector3(WIDTH,.36,run),"stair_stone",true,Vector3(0,angle,0)))
 else:
  for i in count:
   var at=start+dir*depth*(i+.5);at.y=p.y+rise*float(i+1)/count-.18
   a.append(G.box(at,Vector3(WIDTH,.36,depth),"stair_stone",true,Vector3(0,angle,0)))
  # A continuous structural waist under the treads; top never protrudes
  # through risers. It meets the landing undersides at both ends.
  R.beam(a,start-Vector3(0,.34,0),end-Vector3(0,.34,0),WIDTH,.22,"stair_stone")
 for sign_v in [-1.,1.]:_guard(a,start+side*(WIDTH*.5)*sign_v,end+side*(WIDTH*.5)*sign_v,uprights)
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 _materials()
 var uprights:Dictionary={}
 var a:Array=[G.box(Vector3(0,-.3,0),Vector3(144,.6,144),"stair_hall")]
 R.enclosure(a,Vector2(72,72),64,"stair_hall")
 var g=graph();var openings:Dictionary={}
 for id in g.nodes:openings[id]=[]
 for e in g.edges:
  var p:Vector3=g.nodes[e[0]];var q:Vector3=g.nodes[e[1]]
  openings[e[0]].append(Vector3(q.x-p.x,0,q.z-p.z).normalized());openings[e[1]].append(Vector3(p.x-q.x,0,p.z-q.z).normalized())
  _flight(a,p,q,uprights)
 for id in g.nodes:
  var p:Vector3=g.nodes[id]
  a.append(G.box(p-Vector3(0,.18,0),Vector3(LANDING,.36,LANDING),"stair_stone"))
  for dir in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
   var side:Vector3=dir.cross(Vector3.UP);var edge=p+dir*LANDING*.5
   if dir in openings[id]:
    for sign_v in [-1.,1.]:
     _guard(a,edge+side*WIDTH*.5*sign_v,edge+side*LANDING*.5*sign_v,uprights)
   else:_guard(a,edge-side*LANDING*.5,edge+side*LANDING*.5,uprights)
 # Four corner pylons per staggered fabric anchor the interconnected folded
 # slabs to the hall floor. Pylons sit at slab corners, outside every opening.
 for tier in [2,3]:
  for ij in [Vector2i(0,0),Vector2i(3,0),Vector2i(0,3),Vector2i(3,3)]:
   var p:Vector3=g.nodes["t%d_%d_%d"%[tier,ij.x,ij.y]]
   var dx=-1.42 if ij.x==0 else 1.42;var dz=-1.42 if ij.y==0 else 1.42
   a.append(G.box(Vector3(p.x+dx,(p.y-.36)*.5,p.z+dz),Vector3(.28,p.y-.36,.28),"stair_iron"))
 # Restrained suspended practical above the front-middle descent.
 # Housing, suspension and emitted light share the same authored position.
 a.append(G.box(Vector3(0,59.5,30),Vector3(.022,9.,.022),"stair_iron",false))
 a.append(G.box(Vector3(0,55,30),Vector3(.9,.12,.35),"stair_iron",false))
 a.append(G.box(Vector3(0,54.932,30),Vector3(.64,.015,.2),"glow",false))
 for i in 9:
  var x=-60.+15.*i;var y=19.+float(i%3)*13.
  a.append(G.box(Vector3(x,y,-71.7),Vector3(.65,.18,.24),"glow",false))
 
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_mat:RefCounted)->void:G.build(room,data,geometry(),true)
static func build_detail(room:Node3D,data:Dictionary,_mat:RefCounted)->void:
 G.build(room,data,geometry(),false)
 G.lamp(room,data,Vector3(0,54.7,30),Color("c8d0d6"),1.8,32.)
 for i in 9:G.lamp(room,data,Vector3(-60.+15.*i,19.+float(i%3)*13.,-68),Color("c8d0d6"),2.8,38.)
 for p in [Vector3(-28,37,8),Vector3(26,42,-26),Vector3(9,25,35),Vector3(-36,13,-22)]:G.lamp(room,data,p,Color("b9c6d0"),2.4,32.)
static func build_horizon(_root:Node3D,_materials:RefCounted)->void:pass
