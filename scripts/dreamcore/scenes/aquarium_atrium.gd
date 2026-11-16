extends RefCounted
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const PoolTileMaterial=preload("res://assets/dreamcore/materials/aquarium_pool_tile_planar_clip.tres")
static var _architecture:Array=[]
static func definition()->Dictionary:
 return {"id":"aquarium_atrium","title":"水族中庭","subtitle":"悬浮的折带 / 无人的水光","bounds":Rect2i(-2,-2,5,5),"spawn":Vector3(0,.42,13),"look_at":Vector3(-3,12,-15),"exit":Vector3(-26,.4,-17),"stations":[{"id":"aqua_light","label":"水下的天光","position":Vector3(-23,.4,8),"kind":"light","clue":"环灯不必全部点亮。","target":1},{"id":"aqua_flow","label":"浅池的呼吸","position":Vector3(17,.4,9),"kind":"flow","clue":"让池中的涟漪安静下来。","target":2},{"id":"aqua_align","label":"折带的间隙","position":Vector3(-25,.4,-14),"kind":"observe","clue":"从折带的空隙望向最高的光环。","target":1,"observation_target":Vector3(-15,32,2),"observation_radius":8.0}],"cameras":[{"position":Vector3(-25,2.0,20),"target":Vector3(0,9,-10),"fov":62.0},{"position":Vector3(0,2.0,13),"target":Vector3(-3,13,-15),"fov":62.0}],"routes":[[Vector3(25.36,.4,5.61),Vector3(28.8,4.4,-1),Vector3(24,8.4,-12),Vector3(17.85,11.6,-14.97)]],"sky_top":Color("78b6c7"),"sky_horizon":Color("b7dedb"),"ambient":Color("afd2d1"),"ambient_energy":.35,"sun_color":Color("d1f1eb"),"sun_energy":.65,"sun_rotation":Vector3(-31.5,-110,0),"sky_shader":"res://shaders/dreamcore/annex_day_sky.gdshader","sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.1,"fog":.0012}
static func pool_steps()->Array[AABB]:
 # Two opposite, genuinely supported entries; top .22/.04, then pool floor -.13.
 var steps:Array[AABB]=[]
 for z:float in [6.3,-13.0]:steps.append(AABB(Vector3(-1.2,-.13,z),Vector3(2.4,.35,.7)))
 for z:float in [5.6,-12.3]:steps.append(AABB(Vector3(-1.2,-.13,z),Vector3(2.4,.17,.7)))
 return steps
static func layout(coord:Vector2i)->Dictionary:
 var steps:Array[AABB]=[]
 for step:AABB in pool_steps():
  for rect:Rect2 in G.water_rects(coord,Rect2(Vector2(step.position.x,step.position.z),Vector2(step.size.x,step.size.z))):
   steps.append(AABB(Vector3(rect.position.x,step.position.y,rect.position.y),Vector3(rect.size.x,step.size.y,rect.size.y)))
 return {"coord":coord,"water_enabled":true,"water_floor_y":-.13,"water_steps":steps,"water_rects":G.water_rects(coord,Rect2(-15,-13,28,20)),"solids":[],"spawn_local":Vector3(0,.42,13)}
static func _pool_material_ready()->void:
 assert(PoolTileMaterial is ShaderMaterial,"Aquarium pool requires exact installed planar-clip PBR")
 if G._mats.has("aquarium_pool_tile"):
  assert(G._mats["aquarium_pool_tile"]==PoolTileMaterial,"Aquarium pool material cache identity mismatch")
  return
 G._mats["aquarium_pool_tile"]=PoolTileMaterial
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 _pool_material_ready()
 var a:Array=[]
 # Pool floor and all four promenade foundations meet at -.13; dry tops stay .40.
 a.append(G.box(Vector3(0,-.315,0),Vector3(70,.37,50),"aquarium_pool_tile"))
 for b in [Rect2(-35,7,70,18),Rect2(-35,-25,70,12),Rect2(-35,-13,20,20),Rect2(13,-13,22,20)]:
  a.append(G.box(Vector3(b.get_center().x,.135,b.get_center().y),Vector3(b.size.x,.53,b.size.y),"aquarium_pool_tile"))
 for step:AABB in pool_steps():a.append(G.box(step.get_center(),step.size,"aquarium_pool_tile"))
 # Tall rounded perimeter ribs leave the tank and enormous room legible.
 a.append(G.box(Vector3(-35.5,14,0),Vector3(1,28,38),"ivory"))
 a.append(G.box(Vector3(35.5,14,0),Vector3(1,28,38),"ivory"))
 a.append(G.box(Vector3(0,14,25.5),Vector3(58,28,1),"ivory"))
 a.append(G.box(Vector3(0,35.75,-25.5),Vector3(72,12.5,1),"teal",false))
 a.append(G.box(Vector3(25.5,15,-25.5),Vector3(7,30,1),"ivory"))
 a.append(G.box(Vector3(0,42.5,0),Vector3(72,1,52),"dark",false))
 for x in [-35.5,35.5]:a.append(G.box(Vector3(x,35,0),Vector3(1,14,38),"teal",false))
 a.append(G.box(Vector3(0,35,25.5),Vector3(58,14,1),"teal",false))

 for corner in [[Vector3(29,0,19),0.],[Vector3(-29,0,19),PI*.5],[Vector3(-29,0,-19),PI],[Vector3(29,0,-19),PI*1.5]]:
  G.arc(a,corner[0],6.,1.,28.,corner[1],corner[1]+PI*.5,"ivory",true,24)
  G.arc(a,corner[0]+Vector3(0,28,0),6.,1.,14.,corner[1],corner[1]+PI*.5,"teal",false,24)
 # Tank facade: 48x26m glazed opening, deep aquatic wall behind real glazing.
 a.append(G.box(Vector3(-6,13.5,-36),Vector3(48,26,.6),"aquatic",false))
 # The full eleven-metre tank volume is sealed behind the front safety glass.
 # These inaccessible caps prevent oblique top/side rays seeing exterior sky.
 for x in [-30.3,18.3]:a.append(G.box(Vector3(x,13.5,-30.5),Vector3(.6,26.6,11.6),"aquatic",false))
 a.append(G.box(Vector3(-6,26.8,-30.5),Vector3(48.6,.6,11.6),"teal",false))
 a.append(G.box(Vector3(-6,.2,-30.5),Vector3(48.6,.6,11.6),"teal",false))
 a.append(G.box(Vector3(-6,13.5,-24.7),Vector3(48,26,.09),"glass"))
 for x in [-32.,20.,32.]:a.append(G.box(Vector3(x,17,-25),Vector3(4,34,1.2),"ivory"))
 a.append(G.box(Vector3(-6,.65,-24.2),Vector3(50,.5,1),"metal"))
 a.append(G.box(Vector3(-6,28,-25),Vector3(52,3,2),"ivory",false))
 # Two genuine depth layers of original eroded forms, behind collision glazing.
 for i in 10:
  var x=-28.+i*4.6;var h=9.+sin(i*2.3)*4.+float(i%3)*2.
  a.append(G.reef(Vector3(x,.4,-33.8),Vector3(2.8,h,1.3),i*1.73))
 for i in 7:
  var x=-27.+i*6.2;var h=3.5+sin(i*1.4)*2.
  a.append(G.reef(Vector3(x,.4,-28.5),Vector3(2.1,h,1.1),i*2.3))
 for i in 3:
  var r=[7.,11.,15.][i];var p=[Vector3(19,22,3),Vector3(-13,26,-8),Vector3(0,32,2)][i]
  a.append(G.ring(p,r,.19,"metal"));a.append(G.ring(p-Vector3(0,.13,0),r,.075,"glow"))
  for j in 4:
   var ang=j*PI*.5;var pt=p+Vector3(cos(ang)*r,0,sin(ang)*r)
   a.append(G.box(Vector3(pt.x,(42.+pt.y)*.5,pt.z),Vector3(.035,42.-pt.y,.035),"dark",false))
 # Original folded architectural ribbon: suspended above water, never anatomical.
 a.append(G.item(G.ribbon(),Vector3(2,14,-4),"ivory",true,Vector3(0,.4,.22),Vector3(1.3,1.2,1.3)))
 for x in [-1.,4.]:a.append(G.box(Vector3(x,29,-4),Vector3(.035,26,.035),"metal",false))
 # 3m wide continuous curved staircase: 70 x 16cm risers, solid support,
 # 1.1m protective balustrades on BOTH sides, reversible route to landing.
 for i in 70:
  var t=.8-(float(i)+.5)*2.3/70.;var y=.4+(i+1)*.16;var p=Vector3(17+cos(t)*12,0,-3+sin(t)*12)
  a.append(G.box(Vector3(p.x,y*.5,p.z),Vector3(3,y,.43),"tile",true,Vector3(0,-t,0)))
  for radius in [10.48,13.52]:
   var q=Vector3(17+cos(t)*radius,y+.55,-3+sin(t)*radius)
   a.append(G.box(q,Vector3(.12,1.1,.49),"glass",true,Vector3(0,-t,0)))
   a.append(G.box(q+Vector3(0,.58,0),Vector3(.13,.08,.49),"metal",false,Vector3(0,-t,0)))
 a.append(G.box(Vector3(17.4,11.45,-17.875),Vector3(3.3,.3,2.75),"tile"))
 # Merge tongue meets only the final two risers; never overlays earlier treads.
 a.append(G.box(Vector3(16.925,11.45,-15.625),Vector3(2.35,.3,1.75),"tile"))
 a.append(G.box(Vector3(16.45,12.15,-14.75),Vector3(1.5,1.2,.12),"glass"))
 a.append(G.box(Vector3(15.7,12.15,-17),Vector3(.15,1.2,4.5),"glass"))
 # Right landing guard begins BEHIND the curved-flight merge, not across it.
 a.append(G.box(Vector3(19.1,12.15,-17.875),Vector3(.15,1.2,2.75),"glass"))
 a.append(G.box(Vector3(17.4,12.15,-19.3),Vector3(3.5,1.2,.15),"glass"))
 # Remote stair echoes are explicitly inaccessible behind the tank; no false route.
 for tier in 3:
  for i in 36:
   a.append(G.box(Vector3(-27+i*.7,29+tier*3+i*.075,-29-tier*3),Vector3(.71,.13,2),"ivory",false))
 preload("res://scripts/dreamcore/scenes/aquarium_bench.gd").append_to(a,Vector3(-22,.4,14))
 # Keep the handle at the leaf's local side edge, facing into the room (-X).
 var door_origin:=Vector3(34.92,.4,-10)
 var door_rotation:=Vector3(0,PI/2,0)
 a.append(G.box(door_origin+Vector3(0,1.15,0),Vector3(1.1,2.3,.07),"dark",false,door_rotation))
 a.append(G.box(door_origin+Basis.from_euler(door_rotation)*Vector3(.33,1.08,-.06),Vector3(.04,.19,.07),"metal",false,door_rotation))
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:G.build(room,data,geometry(),true)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false)
 for x in [-22.,-6.,10.]:G.lamp(room,data,Vector3(x,9,-21),Color("69dbe5"),4.,28.)
 G.lamp(room,data,Vector3(0,26,0),Color("d2e9da"),3.,38.)
static func build_horizon(_root:Node3D,_materials:RefCounted)->void:pass
