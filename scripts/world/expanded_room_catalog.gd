class_name ExpandedPoolRoomCatalog
extends RefCounted
## Optional maintained facility modules. The original SourceRandom stream is untouched.
const RandomSource := preload("res://scripts/world/source_random.gd")
const ROOM := 32.0
const GROUND := -0.78
const FLOOR_TOP := -0.72
const DECK_TOP := 0.52
const WATER_LEVEL := 0.32
const FIRST_VARIANT := 11
const MODULES := ["shower_changing", "low_arched_bath", "skylight_gallery", "service_transition"]
const NAMES := ["淋浴更衣间", "低拱静浴", "天窗泳廊", "设备过渡厅"]
const SUBTITLES := ["干湿分区 / 淋浴隔间 / 更衣长凳", "低拱券 / 四座浅池 / 连通步道", "真实天窗 / 蓝瓷浅池 / 池边休息", "设备门 / 导向标识 / 顶部采光"]
const CEILINGS := [6.2, 6.4, 7.2, 6.0]
const INNER_CEILINGS := [4.5, 5.8, 6.5, 4.3]
const ANCHORS := {Vector2i.ZERO:0, Vector2i.RIGHT:1, Vector2i.UP:2, Vector2i.LEFT:3}
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func choose_module(coord: Vector2i, seed_value: int) -> int:
	if ANCHORS.has(coord): return ANCHORS[coord]
	var rng := RandomSource.new(coord.x, coord.y, seed_value ^ 0x4e455750)
	# 56% coherent facility modules, 44% untouched original rooms.
	if rng.next() >= .56: return -1
	return int(floor(rng.next() * MODULES.size()))

static func room_layout(coord: Vector2i, seed_value: int, module_index: int) -> Dictionary:
	assert(module_index >= 0 and module_index < MODULES.size())
	var rng := RandomSource.new(coord.x, coord.y, seed_value ^ 0x46495453)
	var wet := module_index in [1,2]
	var daylight := module_index in [2,3]
	var result := {
		"coord":coord, "seed":seed_value, "variant":FIRST_VARIANT+module_index,
		"expanded_mode":true, "expanded":true, "expanded_module":MODULES[module_index],
		"geometry_path":"res://assets/models/expansion/"+MODULES[module_index]+".glb",
		"name":NAMES[module_index], "subtitle":SUBTITLES[module_index],
		"ceiling":CEILINGS[module_index], "interior_ceiling":INNER_CEILINGS[module_index],
		"daylight":daylight, "corrupt":0, "tint":rng.next(), "ducks":0,
		"fog":.013 if daylight else .019, "fog_color":"#a1b5b3" if daylight else "#556f75",
		"light_color":"#e8f1e9", "light_power":90.0,
		"water_enabled":true, "water_floor_y":FLOOR_TOP, "water_door_width":8.0,
		"water_rects":entry_water_rects(), "water_steps":entry_steps(),
		"water_exclusions":[], "water_closed_edges":[], "solids":[], "wfc_grid":[],
		"portal_width":8.0, "portal_top":5.4, "inner_portal_width":4.4,
		"connections":CARDINALS.duplicate(), "spawn_local":Vector3(0,.60,9.8),
		"prop_spawns":[], "fixtures":fixtures(module_index), "expanded_signature":rng.state
	}
	if wet:
		for sx in [-1,1]:
			for sz in [-1,1]:
				result.water_rects.append(Rect2(-10 if sx<0 else 3,-10 if sz<0 else 3,7,7))
				for i in range(5):
					var top: float=DECK_TOP-float(i+1)*(1.24/6.0)
					var x: float=float(sx)*(3.0+(float(i)+.5)*.4)
					result.water_steps.append(AABB(Vector3(x-.2,FLOOR_TOP,float(sz)*6.4-.9),Vector3(.4,top-FLOOR_TOP,1.8)))
		# Two deliberate floats in separate real basins, never on the dry route.
		for side in [-1,1]:
			result.prop_spawns.append({"kind":"duck", "position":Vector3(float(side)*(7.0+rng.next()),.445,7.0+rng.next()), "yaw":rng.next()*TAU})
		result.ducks=2
	return result

static func fixtures(index: int) -> Array[Dictionary]:
	var positions: Array[Vector3]=[]
	match index:
		0: positions=[Vector3(-6,3.6,-6),Vector3(6,3.6,-6),Vector3(-6,3.6,6),Vector3(6,3.6,6)]
		1: positions=[Vector3(-6,4.8,-6),Vector3(6,4.8,-6),Vector3(-6,4.8,6),Vector3(6,4.8,6)]
		2: positions=[Vector3(0,5.4,-8),Vector3(0,5.4,8)]
		3: positions=[Vector3(-6,3.6,-7),Vector3(6,3.6,-7),Vector3(-6,3.6,7),Vector3(6,3.6,7)]
	var result: Array[Dictionary]=[]
	for position in positions:
		result.append({"alive":true,"position":position,"color":Color("e8f1e9"),"power":78.0 if index!=2 else 55.0,"power_scale":1.0,"flicker":false,"flicker_seed":0.0,"flicker_amp":0.0})
	return result

static func entry_water_rects() -> Array[Rect2]:
	# First .365m stair is dry; every lower stair correctly intersects y=.32 water.
	return [Rect2(-4,-16,8,3.5),Rect2(-4,12.5,8,3.5),Rect2(-16,-4,3.5,8),Rect2(12.5,-4,3.5,8)]

static func entry_steps() -> Array[AABB]:
	var result: Array[AABB]=[]
	for side in range(4):
		for i in range(7):
			var top: float=DECK_TOP-float(i+1)*.155
			var distance: float=12.0+(float(i)+.5)*.5
			var center:=Vector3(0,(FLOOR_TOP+top)*.5,distance) if side%2==0 else Vector3(distance,(FLOOR_TOP+top)*.5,0)
			if side>=2: center=Vector3(-center.x,center.y,-center.z)
			var size:=Vector3(8,top-FLOOR_TOP,.5) if side%2==0 else Vector3(.5,top-FLOOR_TOP,8)
			result.append(AABB(center-size*.5,size))
	return result

static func spawn(coord: Vector2i) -> Vector3:
	return Vector3(float(coord.x)*ROOM,.60,float(coord.y)*ROOM+9.8)

static func route_points(coord: Vector2i, entry: Vector2i, exit: Vector2i) -> PackedVector3Array:
	## Human/controller route API: enter shared threshold, climb shallow stairs,
	## pass 4.4m inner portal, cross center, descend to any other cardinal edge.
	assert(entry in CARDINALS and exit in CARDINALS)
	var result:=PackedVector3Array()
	for side in [entry,Vector2i.ZERO,exit]:
		if side==Vector2i.ZERO:
			result.append(Vector3(coord.x*ROOM,DECK_TOP,coord.y*ROOM))
		else:
			var distances: Array=[15.75,11.0] if side==entry else [11.0,15.75]
			for distance in distances:
				result.append(Vector3(float(coord.x)*ROOM+float(side.x)*distance,FLOOR_TOP if distance>15.5 else DECK_TOP,float(coord.y)*ROOM+float(side.y)*distance))
	return result
