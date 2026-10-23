class_name PoolRoomCatalog
extends RefCounted
const SourceRandom := preload("res://scripts/world/source_random.gd")
const Expanded := preload("res://scripts/world/expanded_room_catalog.gd")
const ROOM := 32.0
const GROUND := -0.78
const FLOOR_TOP := -0.72
const WATER_LEVEL := 0.32
# Original 66a4543 generator: six anchors, eight procedural variants.
# Authored/formal rooms are selected separately and must not perturb this RNG.
const ANCHORS := {Vector2i(0,0):0, Vector2i(0,-1):3, Vector2i(-1,0):6, Vector2i(1,0):5, Vector2i(0,1):4, Vector2i(1,1):7}
const ATMOSPHERES := [
	{"name":"旧泳池","subtitle":"褪色瓷砖与旧跳台","ceiling":9.2,"daylight":false,"fog":0.036,"fog_color":"#22343d","light_color":"#b5dfdc","light_power":95.0},
	{"name":"漂浮物厅","subtitle":"水面上的异物","ceiling":9.2,"daylight":false,"fog":0.036,"fog_color":"#22343d","light_color":"#b5dfdc","light_power":95.0},
	{"name":"沉阶水厅","subtitle":"台阶没入安静的水面","ceiling":9.2,"daylight":false,"fog":0.036,"fog_color":"#22343d","light_color":"#b5dfdc","light_power":95.0},
	{"name":"高拱门大厅","subtitle":"高处洒下的日光","ceiling":14.0,"daylight":true,"fog":0.024,"fog_color":"#7e999a","light_color":"#fff5de","light_power":175.0},
	{"name":"夜间浴场","subtitle":"低矮而安静的荧光灯","ceiling":5.8,"daylight":false,"fog":0.036,"fog_color":"#22343d","light_color":"#b5dfdc","light_power":55.0},
	{"name":"跳台高廊","subtitle":"从高处望向下一片水","ceiling":9.2,"daylight":true,"fog":0.024,"fog_color":"#7e999a","light_color":"#fff5de","light_power":175.0},
	{"name":"连通浴池","subtitle":"岛台之间的浅水","ceiling":5.8,"daylight":true,"fog":0.024,"fog_color":"#7e999a","light_color":"#fff5de","light_power":175.0},
	{"name":"柱阵水厅","subtitle":"不断重组的柱影","ceiling":13.0,"daylight":false,"fog":0.036,"fog_color":"#22343d","light_color":"#b5dfdc","light_power":95.0},
	{"name":"天光环庭","subtitle":"日光 / 双层尺度 / 环形看台","ceiling":14.4,"daylight":true,"fog":0.014,"fog_color":"#a1b5b3","light_color":"#e5f4f0","light_power":145.0},
	{"name":"穹顶泳廊","subtitle":"重复拱券 / 长水道 / 暖光尽头","ceiling":11.6,"daylight":false,"fog":0.021,"fog_color":"#405c60","light_color":"#f8e6c4","light_power":120.0},
	{"name":"更衣回廊","subtitle":"淹水更衣区 / 淋浴间 / 维修细节","ceiling":6.4,"daylight":false,"fog":0.023,"fog_color":"#46575a","light_color":"#d7eee6","light_power":78.0}
]

static func corruption_level(coord: Vector2i) -> int:
	var distance: int = maxi(absi(coord.x), absi(coord.y))
	return 0 if distance <= 1 else (1 if distance <= 3 else (2 if distance <= 6 else 3))

static func room_layout(coord: Vector2i, seed_value: int, expanded: bool = false) -> Dictionary:
	if expanded:
		var module_index: int = Expanded.choose_module(coord, seed_value)
		if module_index >= 0: return Expanded.room_layout(coord, seed_value, module_index)
	var rng := SourceRandom.new(coord.x, coord.y, seed_value)
	# Null-coalescing in the JS original does not consume a draw for anchor rooms.
	var variant: int = ANCHORS[coord] if ANCHORS.has(coord) else int(floor(rng.next() * 8.0))
	var layout: Dictionary = ATMOSPHERES[variant].duplicate(true)
	layout.merge({"variant":variant,"tint":rng.next(),"ducks":8 + int(floor(rng.next() * 14.0)),"corrupt":corruption_level(coord),"coord":coord,"seed":seed_value})
	if expanded: layout["expanded_mode"] = true
	return layout
