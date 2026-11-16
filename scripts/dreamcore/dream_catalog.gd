extends RefCounted
## Independent expansion registry. Never extends the six-chapter v2 campaign.
## Existing six IDs keep their order and v1 save identity; reference rooms append.
const IDS := ["lime_gallery", "sportsground", "sluice_courtyard", "aquarium_atrium", "night_busstop", "oculus_hall", "cloud_ballpit", "hanging_hand", "stair_labyrinth", "soffit_reservoir", "parallax_bath", "crossing_channels", "inverted_pool", "hollow_visage", "glasswell_bath"]
const TITLES := ["青柠回廊", "暮色运动场", "雾中水庭", "水族中庭", "末班车站", "天眼巨厅", "云朵球海", "悬手浅池", "无尽交错楼梯", "压顶水库", "错尺长池", "交错旱渠", "倒悬浴场", "空面水殿", "浅水深井"]
# Approved stable expansion identities. Registration follows builder readiness;
# this list also restricts opt-in completion latching to the six new rooms.
const UNCANNY_IDS := ["soffit_reservoir", "parallax_bath", "crossing_channels", "inverted_pool", "hollow_visage", "glasswell_bath"]
const UNCANNY_TITLES := ["压顶水库", "错尺长池", "交错旱渠", "倒悬浴场", "空面水殿", "浅水深井"]
const UNCANNY_BINARY_CONTROLS := {"soffit_reservoir":"reservoir_shutter", "parallax_bath":"parallax_measure", "crossing_channels":"channel_resonator", "inverted_pool":"inverted_plumb", "hollow_visage":"visage_raking", "glasswell_bath":"glasswell_sounder"}
const ROOT := "res://scripts/dreamcore/scenes/"
static func builder(id: String) -> Script:
	if id not in IDS: return null
	var path := ROOT + id + ".gd"
	return load(path) as Script if ResourceLoader.exists(path) else null
static func available(id: String) -> bool:
	return builder(id) != null
static func definition(id: String) -> Dictionary:
	var scene := builder(id)
	return scene.definition() if scene != null else {}
static func next_id(id: String) -> String:
	var index := IDS.find(id)
	return IDS[index+1] if index >= 0 and index+1 < IDS.size() else ""
static func base_layout(coord: Vector2i, data: Dictionary) -> Dictionary:
	return {"coord":coord,"seed":0,"variant":3,"dreamcore":true,"dream_id":data.id,
		"expanded":true,"name":data.title,"subtitle":data.get("subtitle",""),
		"ceiling":128.0,"interior_ceiling":128.0,"daylight":data.get("daylight",true),
		"corrupt":0,"tint":0.0,"ducks":0,"fog":data.get("fog",.001),
		"fog_color":data.get("fog_color","#8d9aa0"),"light_color":data.get("light_color","#e9ebde"),
		"light_power":data.get("light_power",30.0),"water_enabled":true,"water_floor_y":.12,
		"water_rects":[],"water_steps":[],"water_exclusions":[],"water_closed_edges":[],
		"solids":[],"wfc_grid":[],"connections":[],"prop_spawns":[],"fixtures":[],
		"spawn_local":Vector3(0,.42,0),"expanded_signature":0}
