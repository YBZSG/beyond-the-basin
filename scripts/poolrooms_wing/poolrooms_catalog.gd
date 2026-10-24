extends RefCounted
## Three original assembled rooms using licensed Cenji geometry and existing project materials.
## Only selected in Poolrooms Wing mode; the seeded catalog remains untouched.
const Geometry = preload("res://scripts/poolrooms_wing/geometry_contract.gd")
const Expansion = preload("res://scripts/world/expanded_room_catalog.gd")
const ANCHORS := {Vector2i.ZERO:0, Vector2i.UP:1, Vector2i.RIGHT:2}
const MODULES := ["poolrooms_court", "poolrooms_lanes", "poolrooms_bath"]
const FILES := ["crescent_court", "vaulted_lanes", "circular_bath"]
const NAMES := ["曲廊镜池", "拱顶水廊", "圆门侧浴"]
const SUBTITLES := ["曲墙 / 浅水 / 环池步道", "低拱 / 双水道 / 天光窄缝", "圆门 / 静水侧池 / 干地休息龛"]
const CEILINGS := [5.2,4.7,5.2]
const SPAWNS := [Vector3(7,.60,8),Vector3(0,.60,9.8),Vector3(7,.60,0)]
const BASINS := [[Rect2(-8,-7,12,10)],[Rect2(-6,-9,4,18),Rect2(2,-9,4,18)],[Rect2(-8,-6,8,12)]]

static func room_layout(coord: Vector2i, seed_value: int) -> Dictionary:
	assert(ANCHORS.has(coord), "Unknown Poolrooms Wing anchor")
	var index: int = ANCHORS[coord]
	var result := {
		"coord":coord, "seed":seed_value, "variant":15+index,
		"expanded_mode":true, "expanded":true, "poolrooms_wing":true,
		"expanded_module":MODULES[index],
		"geometry_path":"res://assets/models/poolrooms_wing/"+FILES[index]+".glb",
		"name":NAMES[index], "subtitle":SUBTITLES[index],
		"ceiling":6.2, "interior_ceiling":CEILINGS[index],
		"daylight":true, "corrupt":0, "tint":0.0, "ducks":1,
		"fog":.013, "fog_color":"#a1b5b3", "light_color":"#e8f1e9", "light_power":78.0,
		"water_enabled":true, "water_floor_y":-.72, "water_door_width":8.0,
		"water_rects":Expansion.entry_water_rects(), "water_steps":Expansion.entry_steps(),
		"water_exclusions":[], "water_closed_edges":[], "solids":[], "wfc_grid":[],
		"portal_width":8.0, "portal_top":5.4, "inner_portal_width":4.4,
		"connections":Expansion.CARDINALS.duplicate(), "spawn_local":SPAWNS[index],
		"prop_spawns":[], "fixtures":[], "expanded_signature":seed_value
	}
	for basin: Rect2 in BASINS[index]:
		result.water_rects.append(basin)
		# Finite central pool depth .54 m. Exterior shared thresholds retain
		# their original -.72 m floor. This is geometry/depth, not a raised water plane.
		result.water_steps.append(AABB(Vector3(basin.position.x,-.72,basin.position.y),Vector3(basin.size.x,.50,basin.size.y)))
	var float_position: Vector3 = [Vector3(-4,.445,-2),Vector3(-4,.445,-3),Vector3(-4,.445,-2)][index]
	result.prop_spawns.append({"kind":"duck","position":float_position,"yaw":1.1})
	for position: Vector3 in [Vector3(-7,CEILINGS[index]-.65,8),Vector3(7,CEILINGS[index]-.65,-8)]:
		result.fixtures.append({"alive":true,"position":position,"color":Color("eef1e9"),"power":46.0,"power_scale":1.0,"flicker":false,"flicker_seed":0.0,"flicker_amp":0.0})
	# Use the actual final geometry, including every basin tread and mounted light.
	result.merge(Geometry.ROOMS[index].duplicate(true), true)
	return result
