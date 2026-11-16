extends RefCounted
const Grass=preload("res://scripts/dreamcore/scenes/wind_grass.gd")
const Seating=preload("res://scripts/dreamcore/scenes/outdoor_seating.gd")
const G=preload("res://scripts/dreamcore/scenes/outdoor_geometry.gd")
static func definition()->Dictionary:
	return {"id":"night_busstop","title":"末班车站","subtitle":"时刻表没有下一班，但远处的灯还亮着。","bounds":Rect2i(-4,-4,9,9),"spawn":Vector3(0,.42,0),"look_at":Vector3(-15,24,-100),"exit":Vector3(8,.4,-112),"daylight":false,"sun_rotation":Vector3(-35,-25,0),"sun_energy":.18,"ambient_energy":.18,"fog":.004,"fog_height":.8,"fog_height_density":.04,"fog_color":"#263646","light_color":"#a3bdd6","light_power":6.,"stations":[{"id":"last_departure","label":"末班时刻表","position":Vector3(-3,.54,-8),"kind":"departure_signal","clue":"接通站牌，等待远处楼梯的回应。","target":1},{"id":"stair_observation","label":"高架观察点","position":Vector3(8,.4,-70),"kind":"observe","requires":"last_departure","clue":"在空旷路面停留，凝望楼梯上的灯。","target":0,"observation_target":Vector3(-44,38,-95),"observation_seconds":12.}],"cameras":[{"name":"reference","position":Vector3(8,2.,12),"target":Vector3(-18,20,-76),"fov":62.}]}
static func structural()->Array:
	var a:Array=G.boundaries();a.append(AABB(Vector3(-144,-.6,-144),Vector3(288,1.,288)))
	for z in [-125.,-65.,-5.,55.,115.]:
		for x in [-20.,44.]:a.append(AABB(Vector3(x-4,.4,z-5),Vector3(8,68,10)))
	a.append(AABB(Vector3(-30.1,.54,-142),Vector3(.2,.96,284)))
	a.append(AABB(Vector3(-31,.4,-142),Vector3(30,.14,284)))
	a.append(AABB(Vector3(-55.5,.4,-99.5),Vector3(7,70,9)))
	a.append_array(Seating.bus_collision(Vector3(-5.3,.54,-11.3)))
	for x in [-8.,-2.4]:
		for z in [-12.,-9.8]:a.append(AABB(Vector3(x-.04,.54,z-.04),Vector3(.08,2.8,.08)))
	# Shelter has open frontage; bench is the only low obstruction.
	a.append(AABB(Vector3(-8,.4,-12),Vector3(5.6,2.7,.14)))
	a.append(AABB(Vector3(-8.04,.54,-11.8),Vector3(.08,2.4,1.6)))
	a.append(AABB(Vector3(9,.4,-142),Vector3(14,9,.3)))
	for x in [3.5,25.5]:a.append(AABB(Vector3(x,.4,-142.5),Vector3(3,12,2)))
	return a
static func layout(coord:Vector2i)->Dictionary:
	return {"solids":G.solids(structural(),coord),"water_rects":[],"spawn_local":Vector3(0,.42,0)}
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
	G.shell(room,data);G.floor_patch(room,data.coord,AABB(Vector3(-144,-.6,-144),Vector3(288,1.,288)),"asphalt")
	G.floor_patch(room,data.coord,AABB(Vector3(-31,.4,-142),Vector3(30,.14,284)),"concrete")
static func grass_config()->Dictionary:
	# Deliberately narrow cracks/verges, not a meadow on the wet roadway.
	var patches:Array=[AABB(Vector3(-29.5,.4,-140),Vector3(.85,.14,280)),AABB(Vector3(-1.8,.4,-140),Vector3(.65,.14,280)),AABB(Vector3(32.8,-.6,-140),Vector3(.8,1.,280))]
	var exclusions:Array[Rect2]=[Rect2(-10.5,-13.5,10.5,6.5),Rect2(-4,-3,8,6)]
	for station:Dictionary in definition().stations:
		var p:Vector3=station.position;exclusions.append(Rect2(p.x-2.4,p.z-2.4,4.8,4.8))
	for a:AABB in structural():
		if a.position.y>=.4 and a.size.y>.2:exclusions.append(Rect2(a.position.x-.2,a.position.z-.2,a.size.x+.4,a.size.z+.4))
	return {"meadow":true,"patches":patches,"exclusions":exclusions,"density":3.0,"height":Vector2(.09,.24),"style":"verge"}
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
	Grass.build(room,data.coord,grass_config())
	for z in range(-140,141,12):G.floor_patch(room,data.coord,AABB(Vector3(16,.405,z),Vector3(.12,.009,4)),"pale")
	for x in [2.,30.]:G.floor_patch(room,data.coord,AABB(Vector3(x,.405,-142),Vector3(.08,.009,284)),"pale")
	var o:=Vector3(data.coord.x*32.,0,data.coord.y*32.)
	if data.coord==Vector2i.ZERO:
		Seating.build(room,Vector3(-5.3,.54,-11.3)-o,"bus")
		G.box(room,Vector3(1.5,.407,-8)-o,Vector3(.7,.012,1.2),"metal")
		for z in range(9):G.box(room,Vector3(1.5,.42,-8.5+z*.12)-o,Vector3(.62,.018,.035),"rust")
	for z in range(-140,141,2):G.floor_patch(room,data.coord,AABB(Vector3(-1.02,.54,z),Vector3(.06,.008,.025)),"metal")
static func lamp(root:Node3D,p:Vector3,power:float=3.)->void:
	G.rod(root,p,p+Vector3(0,8,0),.06,"rust");G.rod(root,p+Vector3(0,8,0),p+Vector3(1,8,0),.04,"rust")
	var n:=G.box(root,p+Vector3(1,7.96,0),Vector3(.55,.1,.3),"metal");n.material_override=G.plain(Color("ffd9a0"),3.)
	var light:=OmniLight3D.new();light.position=p+Vector3(1,7.7,0);light.light_color=Color("ffcf8c");light.light_energy=power;light.omni_range=22.;light.shadow_enabled=false;root.add_child(light)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
	G.boundary_visual(root)
	G.box(root,Vector3(0,-.12,0),Vector3(288,.2,288),"asphalt")
	# Two carriageways, deep longitudinal girders, transverse pier caps.
	for x in [-20.,44.]:
		G.box(root,Vector3(x,69,-260),Vector3(27,3.5,1000))
		for dx in [-11.,-5.,5.,11.]:G.box(root,Vector3(x+dx,66.5,-260),Vector3(1.5,3.5,1000))
		for z in range(-725,236,60):
			G.box(root,Vector3(x,34.4,z),Vector3(8,68,10))
			G.box(root,Vector3(x,64.5,z),Vector3(25,4,12))
			for dx in [-13.,13.]:
				G.rod(root,Vector3(x+dx,71,z),Vector3(x+dx,72.2,z),.04)
				G.rod(root,Vector3(x+dx,72.2,z),Vector3(x+dx,72.2,z+60),.04)
	# Standalone remote maintenance stair tower: landings, risers, rails,
	# and a sky bridge, all dimensioned and not climbable from the street.
	G.box(root,Vector3(-52,35,-95),Vector3(7,70,9))
	for level in range(10):
		var y:=7.+float(level)*5.7
		G.box(root,Vector3(-43,y,-95),Vector3(11,.25,3.2))
		for j in range(20):
			var t:=float(j)/20.;var x:float=-48.+10.*(t if level%2==0 else 1.-t)
			G.box(root,Vector3(x,y+t*5.7,-92.8),Vector3(.55,.18,1.4))
		for z in [-93.5,-92.1]:
			var a:=Vector3(-48 if level%2==0 else -38,y+1,z);var b:=Vector3(-38 if level%2==0 else -48,y+6.7,z)
			G.rod(root,a,b,.035)
			for j in range(11):
				var p:=a.lerp(b,float(j)/10.);G.rod(root,p-Vector3.UP,p,.025)
		var glow:=G.box(root,Vector3(-48,y+2,-91.8),Vector3(.18,.3,.15),"metal");glow.material_override=G.plain(Color("ffc58c"),4.)
	for y in [20.,49.]:
		var stair_light:=OmniLight3D.new();stair_light.position=Vector3(-46,y,-90);stair_light.light_color=Color("ffc88a");stair_light.light_energy=2.;stair_light.omni_range=20.;root.add_child(stair_light)
	G.box(root,Vector3(-35,61,-95),Vector3(28,.6,4))
	for z in [-97.,-93.]:G.rod(root,Vector3(-49,62,z),Vector3(-21,62,z),.05)
	# Human shelter foreground: thin structural posts, corrugated back,
	# weather lip, three wooden seat slats, readable unbranded route pole.
	for x in [-8.,-2.4]:
		for z in [-12.,-9.8]:G.box(root,Vector3(x,1.94,z),Vector3(.08,2.8,.08),"rust")
	G.box(root,Vector3(-5.2,3.39,-10.9),Vector3(6.2,.14,3.),"metal")
	G.box(root,Vector3(-5.2,1.9,-12),Vector3(5.6,2.7,.14),"metal")
	var glass:=G.box(root,Vector3(-8,1.74,-11),Vector3(.025,2.4,1.6),"metal")
	var glazing:=StandardMaterial3D.new();glazing.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glazing.albedo_color=Color(.3,.45,.48,.18);glazing.roughness=.13;glazing.cull_mode=BaseMaterial3D.CULL_DISABLED;glass.material_override=glazing
	for x in range(56):G.rod(root,Vector3(-7.95+x*.1,.58,-11.91),Vector3(-7.95+x*.1,3.24,-11.91),.018,"rust")
	var strip:=G.box(root,Vector3(-5.2,3.24,-10.5),Vector3(1.4,.05,.12),"pale");strip.material_override=G.plain(Color("ffddaa"),4.)
	var light:=OmniLight3D.new();light.position=Vector3(-5.2,2.9,-10.4);light.light_color=Color("ffd6a0");light.light_energy=1.6;light.omni_range=11.;root.add_child(light)
	G.rod(root,Vector3(-9.6,.54,-9.7),Vector3(-9.6,4.3,-9.7),.045,"rust")
	G.box(root,Vector3(-9.6,3.9,-9.7),Vector3(.7,1.,.1),"pale")
	for z in [-20.,-80.,-130.]:lamp(root,Vector3(32,.4,z))
	# An explicitly closed service depot terminates the finite road, not an
	# unexplained horizon wall or a promise of an infinite walk.
	G.box(root,Vector3(16,9.4,-151),Vector3(112,18,16))
	for x in [5.,27.]:G.box(root,Vector3(x,6.4,-141.5),Vector3(3,12,2),"pale")
	G.box(root,Vector3(16,12.4,-141.5),Vector3(25,2,2),"pale")
	G.box(root,Vector3(16,4.9,-141.8),Vector3(14,9,.3),"metal")
	for row in range(45):G.box(root,Vector3(16,.5+row*.2,-141.58),Vector3(14,.035,.06),"rust")
	G.door(root,Vector3(1,.4,-141.75))
	var depot_light:=OmniLight3D.new();depot_light.position=Vector3(16,10,-137);depot_light.light_color=Color("ffc88a");depot_light.light_energy=2.;depot_light.omni_range=24.;root.add_child(depot_light)
	# Crash rail and parapet bound the verge physically, not invisible walls.
	for z in range(-140,141,4):G.rod(root,Vector3(-30,.54,z),Vector3(-30,1.5,z),.06)
	for y in [1.,1.5]:G.rod(root,Vector3(-30,y,-142),Vector3(-30,y,142),.06)
	G.batch_static(root)
