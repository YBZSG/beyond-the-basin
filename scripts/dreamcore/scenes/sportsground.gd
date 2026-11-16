extends RefCounted
const Grass=preload("res://scripts/dreamcore/scenes/wind_grass.gd")
const Seating=preload("res://scripts/dreamcore/scenes/outdoor_seating.gd")
const G=preload("res://scripts/dreamcore/scenes/outdoor_geometry.gd")
static func definition()->Dictionary:
	return {"id":"sportsground","title":"暮色运动场","subtitle":"最后一次广播以后，跑道仍然通向暮色。","bounds":Rect2i(-4,-4,9,9),"spawn":Vector3(0,.42,0),"look_at":Vector3(30,19,-110),"exit":Vector3(8,.4,-112),"daylight":true,"sky_shader":"res://assets/dreamcore/outdoor/panorama_sky.gdshader","sky_panorama":"res://assets/dreamcore/outdoor/dusk-sky-panorama.png","sun_rotation":Vector3(-1.206,-156,0),"sun_energy":1.7,"fog":.0018,"fog_color":"#a08a7d","light_color":"#ffcb96","light_power":24.,"stations":[{"id":"relay_01","label":"起点接力台","position":Vector3(13,.4,-8),"kind":"broadcast","clue":"第一接力：在起点发送载波，再前往中场。","target":1},{"id":"relay_02","label":"中场转发台","position":Vector3(-38,.4,-46),"kind":"broadcast","clue":"第二接力：接收起点载波，再转发给终点。","target":2},{"id":"relay_03","label":"终点广播台","position":Vector3(13,.4,-95),"kind":"broadcast","clue":"第三接力：收到中场信号后，完成最后广播。","target":3}],"cameras":[{"name":"reference","position":Vector3(-5,2.,8),"target":Vector3(14,10,-110),"fov":62.}]}
static func boundary_specs()->Array:
	var a:Array=G.boundaries();a[2]=AABB(Vector3(-144,-1,-144),Vector3(288,3.6,2));return a
static func structural()->Array:
	var a:Array=boundary_specs();a.append(AABB(Vector3(-144,-.6,-144),Vector3(288,1.,288)))
	a.append(AABB(Vector3(21,.4,-144),Vector3(100,5.6,288)))
	a.append(AABB(Vector3(16,.4,-11),Vector3(5,5.6,7)))
	a.append(AABB(Vector3(15.65,.4,-6.05),Vector3(.1,5,.1)))
	for z in [-14.,-68.,-123.]:a.append(Seating.sports_collision(Vector3(18,.4,z)))
	return a
static func layout(coord:Vector2i)->Dictionary:
	return {"solids":G.solids(structural(),coord),"water_rects":[],"spawn_local":Vector3(0,.42,0)}
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
	G.shell(room,data)
	G.floor_patch(room,data.coord,AABB(Vector3(-144,-.6,-144),Vector3(139,1.,288)),"grass")
	G.floor_patch(room,data.coord,AABB(Vector3(-5,-.6,-144),Vector3(20,1.,288)),"track")
	G.floor_patch(room,data.coord,AABB(Vector3(15,-.6,-144),Vector3(129,1.,288)),"concrete")
	Grass.tint_ground(room)
static func grass_config()->Dictionary:
	var exclusions:Array[Rect2]=[Rect2(-40,-48,35,4)] # worn access to midfield relay
	for x in [-105.,-30.]:exclusions.append(Rect2(x-.3,-110.3,.6,110.6))
	for z in [-110.,0.]:exclusions.append(Rect2(-105.3,z-.3,75.6,.6))
	for station:Dictionary in definition().stations:
		var p:Vector3=station.position;exclusions.append(Rect2(p.x-2.2,p.z-2.2,4.4,4.4))
	return {"meadow":true,"patches":[AABB(Vector3(-142,-.6,-142),Vector3(136.7,1.,284))],"exclusions":exclusions,"density":1.7,"density_patches":[{"rect":Rect2(-24,-20,20,40),"boost":7.0},{"rect":Rect2(-34,-50,28,40),"boost":5.5},{"rect":Rect2(-62,-76,28,42),"boost":4.0}],"height":Vector2(.19,.32),"style":"sports"}
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
	Grass.build(room,data.coord,grass_config())
	for x in [-4.,-1.5,1.,3.5,6.,8.5,11.,13.5]:
		G.floor_patch(room,data.coord,AABB(Vector3(x,.402,-144),Vector3(.065,.006,288)),"pale")
	for z in [-10.,-96.]:G.floor_patch(room,data.coord,AABB(Vector3(-5,.403,z),Vector3(20,.007,.07)),"pale")
	var o:=Vector3(data.coord.x*32.,0,data.coord.y*32.)
	for z in [-14.,-68.,-123.]:
		var p:=Vector3(18,.4,z)
		if Vector2i(floori((p.x+16)/32),floori((p.z+16)/32))==data.coord:
			var r:=Node3D.new();r.position=p-o;r.rotation.y=PI*.5;room.add_child(r);Seating.build(r,Vector3.ZERO,"sports")
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
	for a:AABB in boundary_specs():G.box(root,a.get_center(),a.size)
	G.box(root,Vector3(-74.5,-.12,0),Vector3(139,.2,288),"grass")
	G.box(root,Vector3(5,-.12,0),Vector3(20,.2,288),"track")
	G.box(root,Vector3(79.5,-.12,0),Vector3(129,.2,288),"concrete")
	# The grandstand is a single deliberately authored 960 m elevation, not
	# per-chunk boxes. Treads recede 1.05 m and rise .48 m above the human plinth.
	G.box(root,Vector3(25,3.2,-240),Vector3(8,5.6,960))
	for i in range(100):
		var x:=29.+float(i)*1.05;var y:=6.+float(i)*.48
		G.box(root,Vector3(x,y,-240),Vector3(1.08,.48,960))
		G.box(root,Vector3(x-.08,y+.3,-240),Vector3(1.26,.12,960),"pale")
	G.box(root,Vector3(135,61,-240),Vector3(3,14,960))
	for z in range(-700,241,24):
		G.box(root,Vector3(133,61,float(z)),Vector3(3.2,15,.7),"pale")
		for y in [7.1,7.6]:G.rod(root,Vector3(28,y,z),Vector3(28,y,z+24),.035)
		G.rod(root,Vector3(28,6.3,z),Vector3(28,7.7,z),.04)
	G.box(root,Vector3(18.5,3.2,-7.5),Vector3(5,5.6,7))
	G.box(root,Vector3(18.35,6.1,-7.5),Vector3(5.6,.2,7.4),"pale")
	G.door(root,Vector3(15.94,.4,-8),-PI*.5)
	for z in [-67.,-123.]:G.door(root,Vector3(20.94,.4,z),-PI*.5)
	# Horn loudspeaker over the near service door, physically human-scale.
	G.rod(root,Vector3(15.7,.4,-6),Vector3(15.7,5.3,-6),.045,"rust")
	var horn:=MeshInstance3D.new();var cone:=CylinderMesh.new();cone.top_radius=.1;cone.bottom_radius=.35;cone.height=.55;cone.radial_segments=24;horn.mesh=cone;horn.position=Vector3(15.4,4.7,-6);horn.rotation.z=-PI*.5;horn.material_override=G.mat("metal");root.add_child(horn)
	# Low distant berms, behind physical enclosure, maintain a coherent horizon.
	for i in range(18):
		var hill:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=1.;sphere.height=2.;sphere.radial_segments=32;sphere.rings=12;hill.mesh=sphere;hill.position=Vector3(-550+i*55,0,-390-abs(i-8)*8);hill.scale=Vector3(80,5+sin(i*1.9)*2,110);hill.material_override=G.mat("grass");root.add_child(hill)
	for z in range(-640,200,160):
		for x in [137.,140.]:G.rod(root,Vector3(x,64,z),Vector3(x,93,z),.21)
		for y in range(65,93,3):
			G.rod(root,Vector3(137,y,z),Vector3(140,y+3,z),.07);G.rod(root,Vector3(140,y,z),Vector3(137,y+3,z),.07)
		G.box(root,Vector3(138.5,94,z),Vector3(10,4,.6),"metal")
		for x in range(5):
			for y in range(2):G.box(root,Vector3(134.5+x*2,93+y*1.8,z-.4),Vector3(1.1,1.1,.25),"pale")
	# Sparse field markings carry across the entire empty infield.
	for x in [-105.,-30.]:G.box(root,Vector3(x,.407,-55),Vector3(.1,.01,110),"pale")
	for z in [-110.,0.]:G.box(root,Vector3(-67.5,.407,z),Vector3(75,.01,.1),"pale")
	Grass.tint_ground(root)
	G.batch_static(root)
