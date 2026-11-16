extends RefCounted
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
static var _architecture:Array=[]
static func definition()->Dictionary:
 return {"id":"oculus_hall","title":"天眼巨厅","subtitle":"同心圆之后 / 四十米高的童年","bounds":Rect2i(-2,-2,5,5),"spawn":Vector3(0,.42,14),"look_at":Vector3(0,11,-26),"exit":Vector3(10,.4,-22),"stations":[{"id":"oculus_light","label":"圆窗的昼色","position":Vector3(15,.4,8),"kind":"light","clue":"留下最浅的一层青色。","target":1},{"id":"oculus_flow","label":"光井里的细雨","position":Vector3(-16,.4,1),"kind":"flow","clue":"细小的彩光，不应淹没空旷。","target":2},{"id":"oculus_align","label":"三重圆拱","position":Vector3(13,.4,-17),"kind":"observe","clue":"从地面看向圆窗的中央，停留片刻。","target":1,"observation_target":Vector3(0,11.4,-26),"observation_radius":7.0}],"cameras":[{"position":Vector3(-3,2.0,19),"target":Vector3(-14,11,-24),"fov":62.0}],"sky_top":Color("81c5d8"),"sky_horizon":Color("c9e7e2"),"ambient":Color("d7e4d3"),"ambient_energy":.48,"sun_color":Color("fff1d2"),"sun_energy":1.0,"sun_rotation":Vector3(-31.5,-110,0),"sky_shader":"res://shaders/dreamcore/annex_day_sky.gdshader","sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.05,"fog":.001}
static func layout(coord:Vector2i)->Dictionary:return {"coord":coord,"water_enabled":false,"water_rects":[],"solids":[],"spawn_local":Vector3(0,.42,0)}
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 var a:Array=[G.box(Vector3(0,.1,0),Vector3(44,.6,54),"tile")]
 a.append(G.box(Vector3(22.5,15,0),Vector3(1,30,54),"ivory"))
 a.append(G.box(Vector3(0,15,27.5),Vector3(46,30,1),"ivory"))
 a.append(G.box(Vector3(0,30.5,0),Vector3(46,1,56),"ivory",false))
 # Left arcade opening onto a protected, separate forty-metre lightwell.
 for b in [Vector3(-22.5,15,18.5),Vector3(-22.5,15,-18.5)]:a.append(G.box(b,Vector3(1,30,17),"ivory"))
 a.append(G.box(Vector3(-22.5,28,0),Vector3(1,4,20),"ivory"))
 a.append(G.box(Vector3(-22,1,0),Vector3(.1,1.2,20),"glass"))
 a.append(G.box(Vector3(-22,1.65,0),Vector3(.16,.12,20),"metal",false))
 # Three thick concentric structural ribs, shifted in depth. Radius 19/15/12m.
 for i in 3:
  var r=[19.,15.5,12.][i];var z=[-13.,-20.,-25.][i]
  G.arch(a,Vector3(0,11.4,z),r,1.5,2.0,"lime")
  G.arch(a,Vector3(0,11.4,z-.2),r+1.2,.65,2.2,"ivory")
 # 22m cyan circular glazed window with aquatic depth. Surround is a circular
 # annular wall, not an opaque rectangular plane covering the aperture.
 a.append(G.cylinder(Vector3(0,11.4,-26.65),11,.05,"clear_glass",true,Vector3(PI/2,0,0)))
 a.append(G.ring(Vector3(0,11.4,-26.4),11.2,.16,"glow",Vector3(PI/2,0,0)))
 G.annulus(a,Vector3(0,11.4,-27.3),11.,32.,.8,"ivory")
 # Well is view-only; continuous physical parapet makes the 40m vista safe.
 a.append(G.box(Vector3(-28,.05,0),Vector3(12,.2,22),"teal",false))
 a.append(G.box(Vector3(-34,20,0),Vector3(.6,40,22),"teal",false))
 for z in [-11.,11.]:a.append(G.box(Vector3(-28,20,z),Vector3(12,40,.6),"teal",false))
 for z in [-.55,.55]:a.append(G.box(Vector3(-33.5,20,z),Vector3(.08,40,.08),"metal",false))
 for i in 115:a.append(G.box(Vector3(-33.45,.5+i*.34,0),Vector3(.12,.055,1.2),"metal",false))
 # Abstract pale cloud reliefs and a thin, restrained particle bank, not a pit.
 for i in 6:
  var y=8.+i*4.8;var z=-7.+fmod(i*5.3,14.)
  for j in 3:a.append(G.sphere(Vector3(-33.55,y+sin(j*2.)*.8,z+j*1.2),Vector3(.45,1.5+j*.4,2.5),"ivory"))
 for i in 90:
  var x=-31.+fmod(i*1.713,7.);var z=-9.+fmod(i*2.417,18.);var y=.35+fmod(i*.371,.8)
  a.append(G.sphere(Vector3(x,y,z),Vector3(.07,.07,.07),["lime","aqua","glow","ivory"][i%4]))
 a.append_array(preload("res://scripts/dreamcore/scenes/gallery_seating.gd").placed(preload("res://scripts/dreamcore/scenes/gallery_seating.gd").oculus(),Vector3(-19,.4,4),PI/2))
 G.door(a,Vector3(18,.4,-26.92))
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:G.build(room,data,geometry(),true)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false)
 G.lamp(room,data,Vector3(0,12,-23),Color("81dce2"),5.,35.)
 G.lamp(room,data,Vector3(-29,31,0),Color("8bbfc7"),4.,38.)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 # A true distant vista through the circular glazing, not a flat coloured disk.
 var a:Array=[G.item(G.landscape(),Vector3.ZERO,"aqua")]
 a.append(G.box(Vector3(0,-15.5,-340),Vector3(1000,.3,650),"aquatic",false))
 G.horizon(root,a)
