extends RefCounted
const PoolClip=preload("res://scripts/dreamcore/scenes/sluice_planar_material_bridge.gd")
const RaisedVisual=preload("res://scripts/dreamcore/scenes/courtyard_raised_visual.gd")
const Grass=preload("res://scripts/dreamcore/scenes/wind_grass.gd")
const G=preload("res://scripts/dreamcore/scenes/outdoor_geometry.gd")
static func definition()->Dictionary:
	return {"id":"sluice_courtyard","title":"雾中水庭","subtitle":"在水声停止之前，找到门的尺度。","bounds":Rect2i(-4,-4,9,9),"spawn":Vector3(0,.42,0),"look_at":Vector3(0,47,-110),"exit":Vector3(0,.4,-106),"daylight":true,"fog":.003,"fog_height":1.4,"fog_height_density":.10,"fog_color":"#aebdbb","light_color":"#edf0d8","light_power":25.,"stations":[{"id":"sluice_west","label":"西庭水闸","position":Vector3(-42,.4,-32),"kind":"sluice","clue":"西闸铭牌：NORTH。先将进水导向北侧。","target":1},{"id":"sluice_east","requires":"sluice_west","requires_value":1,"label":"东庭水闸","position":Vector3(42,.4,-64),"kind":"sluice","clue":"东闸铭牌：OVERFLOW。西闸向北后，接通溢流。","target":3},{"id":"sluice_axis","requires":"sluice_east","requires_value":3,"label":"轴心水闸","position":Vector3(0,.4,-88),"kind":"sluice","clue":"轴心铭牌：EAST。溢流接通后，出口向东。","target":2}],"cameras":[{"name":"reference","position":Vector3(0,2.,9),"target":Vector3(0,20,-110),"fov":62.}]}
static func pool_floor()->AABB:
	return AABB(Vector3(-144,-.88,-144),Vector3(288,.75,288))
static func horizon_floor()->AABB:
	# Visual-only far apron stays 1 cm below the real streamed floor, never above it.
	return AABB(Vector3(-144,-.34,-144),Vector3(288,.20,288))
static func pool_steps()->Array[AABB]:
	return [AABB(Vector3(6.4,-.13,15.2),Vector3(3.2,.35,.8)),AABB(Vector3(6.4,-.13,14.4),Vector3(3.2,.17,.8)),AABB(Vector3(6.4,-.13,-112),Vector3(3.2,.35,.8)),AABB(Vector3(6.4,-.13,-111.2),Vector3(3.2,.17,.8))]
static func ring_bases()->Array[AABB]:
	var bases:Array[AABB]=[]
	for x:float in [-18.,54.]:bases.append(AABB(Vector3(x-12,-.13,-119),Vector3(24,3.25,18)))
	return bases
static func _grass_support_recipe()->Array:
	var a:Array=[AABB(Vector3(-144,.12,-144),Vector3(80,.28,288)),AABB(Vector3(64,.12,-144),Vector3(80,.28,288)),AABB(Vector3(-64,.12,-144),Vector3(128,.28,32)),AABB(Vector3(-64,.12,16),Vector3(128,.28,128)),AABB(Vector3(-1.5,.12,-142),Vector3(3,.28,284))]
	for x in [-23.,5.]:a.append(AABB(Vector3(x,.12,-14),Vector3(18,.28,16)))
	for z in [-32.,-64.]:a.append(AABB(Vector3(-142,.12,z-1.5),Vector3(284,.28,3)))
	for x in [-104.,-72.,-40.,24.,56.,88.]:
		for z in [-112.,-80.,-48.,-16.,16.,48.,80.,112.]:a.append(AABB(Vector3(x,.12,z),Vector3(18,.28,14)))
	return a
static func raised()->Array:
	# Grass placement uses unchanged surface footprints/top, not support thickness.
	var a:Array=_grass_support_recipe()
	for i:int in range(a.size()):
		a[i]=AABB(Vector3(a[i].position.x,-.13,a[i].position.z),Vector3(a[i].size.x,.53,a[i].size.z))
	return a
static func structural()->Array:
	var a:Array=G.boundaries();a.append(pool_floor());a.append_array(raised());a.append_array(pool_steps());a.append_array(ring_bases())
	for z in [-16.,-84.]:
		for x in [-1.1,1.1]:a.append(AABB(Vector3(x-.12,.4,z-.19),Vector3(.24,3.2,.38)))
	return a
static func layout(coord:Vector2i)->Dictionary:
	var rect:=Rect2(-64,-112,128,128).intersection(Rect2(coord.x*32-16,coord.y*32-16,32,32))
	var wet:Array=[]
	if rect.has_area():wet.append(Rect2(rect.position-Vector2(coord)*32,rect.size))
	var steps:Array[AABB]=G.solids(pool_steps(),coord)
	return {"solids":G.solids(structural(),coord),"water_rects":wet,"water_steps":steps,"water_floor_y":-.13,"spawn_local":Vector3(0,.42,0)}
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
	G.shell(room,data);G.floor_patch(room,data.coord,pool_floor(),"tile")
	for step:AABB in pool_steps():G.floor_patch(room,data.coord,step,"tile")
	RaisedVisual.build(room,data.coord,raised())
	Grass.tint_ground(room)
	var binding:Dictionary=PoolClip.apply(room)
	if not binding.get("accepted",false):
		push_error("Sluice pool material binding failed: "+str(binding.get("reason","unknown")))
		return
static func grass_config()->Dictionary:
	var patches:Array=[]
	for a:AABB in _grass_support_recipe():
		if a.size.x==18.:patches.append(a)
	# Islands are above the .32 m water; these cross-path and foundation masks
	# keep every tuft off the actual walking axes and ring plinths.
	var exclusions:Array[Rect2]=[Rect2(-1.9,-142,3.8,284),Rect2(-142,-33.9,284,3.8),Rect2(-142,-65.9,284,3.8),Rect2(-30.4,-119.4,24.8,18.8),Rect2(41.6,-119.4,24.8,18.8)]
	for station:Dictionary in definition().stations:
		var p:Vector3=station.position;exclusions.append(Rect2(p.x-2.2,p.z-2.2,4.4,4.4))
	return {"meadow":true,"patches":patches,"exclusions":exclusions,"density":2.8,"height":Vector2(.17,.34),"style":"courtyard"}
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
	Grass.build(room,data.coord,grass_config())
	var o:=Vector3(data.coord.x*32.,0,data.coord.y*32.)
	for z in [-16.,-84.]:
		var p:=Vector3(0,.4,z)
		if Vector2i(floori((p.x+16)/32),floori((p.z+16)/32))==data.coord:
			for x in [-1.1,1.1]:G.box(room,p-o+Vector3(x,1.6,0),Vector3(.24,3.2,.38),"pale")
			G.box(room,p-o+Vector3(0,3.15,0),Vector3(2.45,.3,.38),"pale")
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
	G.boundary_visual(root,"pale");G.box(root,horizon_floor().get_center(),horizon_floor().size,"tile");G.arch(root,Vector3(18,49,-110),58.,7.,12.)
	for base:AABB in ring_bases():G.box(root,base.get_center(),base.size,"pale")
	# Courtyard enclosure has occupied thickness, deep shadowed reveals and
	# actual lintels, rather than a paper-thin repeated facade.
	for x in [-151.,151.]:
		G.box(root,Vector3(x,9,0),Vector3(6,18,310),"pale")
		for z in range(-144,145,8):
			G.box(root,Vector3(x+(-4 if x>0 else 4),5.5,z),Vector3(4,11,1.2),"pale")
		G.box(root,Vector3(x+(-4 if x>0 else 4),11.3,0),Vector3(4,1.2,304),"pale")
	G.box(root,Vector3(0,8,-151),Vector3(304,16,8),"pale")
	for x in [-110.,-76.,76.,110.]:G.box(root,Vector3(x,20,-159),Vector3(11,40,16),"pale")
	for x in [-90.,90.]:G.door(root,Vector3(x,.4,-141.8))
	Grass.tint_ground(root)
	var binding:Dictionary=PoolClip.apply(root)
	if not binding.get("accepted",false):
		push_error("Sluice horizon material binding failed: "+str(binding.get("reason","unknown")))
		return
	G.batch_static(root)
