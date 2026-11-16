extends RefCounted
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
static var _architecture:Array=[]
static func definition()->Dictionary:
 return {"id":"lime_gallery","retain_full_finite_scene":true,"title":"青柠回廊","subtitle":"一张长椅 / 六十五米的弧线","bounds":Rect2i(-2,-2,5,5),"spawn":Vector3(0,.42,12),"look_at":Vector3(-8,4,-28),"exit":Vector3(-10,.4,-32),"stations":[{"id":"lime_light","label":"玻璃后的日光","position":Vector3(3,.4,5),"kind":"light","clue":"让回廊只留下清晨的颜色。","target":1},{"id":"lime_flow","label":"草原的潮声","position":Vector3(-5,.4,-18),"kind":"flow","clue":"微弱的回声，来自窗外而非脚下。","target":2},{"id":"lime_align","label":"远方的穹顶","position":Vector3(-5,.4,-2),"kind":"observe","clue":"站在这里，望向草原上唯一的穹顶。","target":1,"observation_target":Vector3(-200,26,-220),"observation_radius":6.0}],"cameras":[{"position":Vector3(1,2.0,13),"target":Vector3(-13,6,-25),"fov":62.0}],"sky_top":Color("73b8d2"),"sky_horizon":Color("b1dce4"),"ambient":Color("d2e5d9"),"ambient_energy":.8,"sun_color":Color("fff3db"),"sun_energy":1.2,"sun_rotation":Vector3(-31.5,-110,0),"sky_shader":"res://shaders/dreamcore/annex_day_sky.gdshader","sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.0,"fog":.0008}
static func layout(coord:Vector2i)->Dictionary:
 return {"coord":coord,"water_enabled":false,"water_rects":[],"solids":[],"spawn_local":Vector3(0,.42,0)}
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 var a:Array=[];var c=Vector3(-65,.4,0)
 # Segmented true annular structure, not a scaled box room.
 G.arc(a,Vector3(-65,0,0),65,15,.4,-.795,.795,"tile",true,100)
 var wall_radius:=72.8;var wall_width:=.65;var wall_start:=-.79;var wall_end:=.79;var wall_steps:=100
 G.arc(a,c,wall_radius,wall_width,16,wall_start,wall_end,"ivory",true,wall_steps)
 var plinth_radius:=72.4;var plinth_width:=.3;var plinth_height:=.5
 G.arc(a,c,plinth_radius,plinth_width,plinth_height,wall_start,wall_end,"lime",true,wall_steps)
 G.arc(a,Vector3(-65,15.9,0),65,15.6,.8,-.79,.79,"ivory",false,100)
 G.arc(a,Vector3(-65,15.7,0),71.8,.9,.22,-.79,.79,"lime",false,100)
 G.arc(a,Vector3(-65,15.6,0),59,.6,.24,-.79,.79,"lime",false,100)
 G.arc(a,c,57.5,.5,.55,-.79,.79,"lime",true,100)
 G.arc(a,Vector3(-65,8.8,0),57.5,.8,7.4,-.79,.79,"ivory",false,100)
 G.arc(a,Vector3(-65,8.5,0),57.5,.85,.3,-.79,.79,"lime",false,100)
 # Safety glazing is real transparent geometry; piers register the scale.
 G.arc(a,Vector3(-65,.95,0),57.5,.07,7.55,-.79,.79,"clear_glass",true,100)
 for i in range(-3,4):
  var t=float(i)*.235;var p=c+Vector3(cos(t)*57.5,0,sin(t)*57.5)
  a.append(G.box(p+Vector3(0,4.2,0),Vector3(.8,8.4,.8),"ivory"))
  a.append(G.sphere(p+Vector3(0,8.2,0),Vector3(1.0,1.1,2.4),"ivory"))
 for t in [-.79,.79]:
  var p=c+Vector3(cos(t)*65,0,sin(t)*65)
  a.append(G.box(p+Vector3(0,8,0),Vector3(15.8,16,.5),"ivory",true,Vector3(0,-t,0)))
 a.append_array(preload("res://scripts/dreamcore/scenes/gallery_seating.gd").placed(preload("res://scripts/dreamcore/scenes/gallery_seating.gd").lime(),Vector3(5.8,.4,-2.2),-PI/4))
 # Closed, visual-only service door: keep all existing wall/plinth collision.
 # Derive the mounting facet from the old location and actual arc parameters.
 var old_door:=Vector3(7.26,.4,-5)
 var door_angle:=atan2(old_door.z-c.z,old_door.x-c.x)
 var door_segment:=clampi(int(floor((door_angle-wall_start)/(wall_end-wall_start)*wall_steps)),0,wall_steps-1)
 var door_a:=lerpf(wall_start,wall_end,float(door_segment)/wall_steps)
 var door_b:=lerpf(wall_start,wall_end,float(door_segment+1)/wall_steps)
 var door_mid:=(door_a+door_b)*.5;var chord_scale:=cos((door_b-door_a)*.5)
 # Only the visible face clears the plinth by 2mm; the lower slab embeds in it.
 # This avoids projecting the entire 70mm leaf into the unchanged walk space.
 var front_radius:=(plinth_radius-plinth_width*.5)*chord_scale-.002
 var door_radius:=front_radius+.07*.5
 var back_radius:=(wall_radius-wall_width*.5)*chord_scale+.003
 var return_depth:=back_radius-front_radius
 var return_z:=door_radius-(front_radius+back_radius)*.5
 var door_frame:=Transform3D(Basis(Vector3.UP,-PI*.5-door_mid),c+Vector3(cos(door_mid)*door_radius,0,sin(door_mid)*door_radius))
 var door_parts:Array=[];G.door(door_parts,Vector3.ZERO)
 # Real 3mm side/head clearance distinguishes the leaf from its frame.
 # Jambs meet the lintel; the original wall closes the recessed seam behind.
 var door_gap:=.003;var jamb_width:=.06
 for side in [-1.,1.]:door_parts.append(G.box(Vector3(side*(1.1*.5+door_gap+jamb_width*.5),(2.3+door_gap)*.5,return_z),Vector3(jamb_width,2.3+door_gap,return_depth),"ivory",false))
 door_parts.append(G.box(Vector3(0,2.3+door_gap+jamb_width*.5,return_z),Vector3(1.1+(door_gap+jamb_width)*2.,jamb_width,return_depth),"ivory",false))
 for part:Dictionary in door_parts:
  part.transform=door_frame*part.transform;a.append(part)
 # Three restrained ceiling luminaires are actual native emitters, not preview fill.
 for angle in [-.5,0.,.5]:
  var p=Vector3(-65+cos(angle)*65.,15.75,sin(angle)*65.)
  a.append(G.cylinder(p,1.0,.1,"glow"))
 # A sparse grass/glass pavilion is visible beyond the southern return.
 a.append(G.box(Vector3(-22,.2,48),Vector3(22,.3,15),"grass",false))
 for z in [41.,55.]:
  a.append(G.box(Vector3(-22,6,z),Vector3(22,12,.08),"glass",false))
  for x in [-33.,-22.,-11.]:a.append(G.box(Vector3(x,6,z),Vector3(.16,12,.16),"ivory",false))
 a.append(G.box(Vector3(-22,12.2,48),Vector3(23,.5,16),"lime",false))
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:G.build(room,data,geometry(),true)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false)
 for angle in [-.5,0.,.5]:
  G.lamp(room,data,Vector3(-65+cos(angle)*65.,14.5,sin(angle)*65.),Color("e2efdf"),5.,36.)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 var a:Array=[G.box(Vector3(-190,-.5,0),Vector3(380,.6,650),"grass",false)]
 # 120m original geodesic-like lattice shell: intersecting great-circle ribs.
 var center=Vector3(-200,-6,-220)
 for i in 16:
  var r=G.ring(center,60,.4,"white",Vector3(PI/2,float(i)*PI/16,0));r.transform.basis=r.transform.basis.scaled(Vector3(1,.75,1));a.append(r)
 for i in range(1,6):
  var elevation=float(i)*8.;var radius=sqrt(3600.-elevation*elevation)
  a.append(G.ring(center+Vector3(0,elevation*.75,0),radius,.35,"white"))
 G.horizon(root,a)
