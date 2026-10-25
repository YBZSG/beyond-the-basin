extends RefCounted
## Five authored references, finite closed loop plus the dry descending entrance.
## The original seeded catalog and all its identities are intentionally unchanged.
const COORDS := [Vector2i(0,0), Vector2i(0,-1), Vector2i(0,-2), Vector2i(1,-2), Vector2i(1,-1)]
const IDS := ["stair_gallery", "colonnade", "cyan_corridor", "octagonal_bath", "ball_lounge"]
const NAMES := ["釉光阶厅", "暗柱水厅", "青窗水廊", "粉阶八角池", "圆窗球池休息室"]
const SUBTITLES := ["干地 / 下行楼梯 / 分砖灯影", "方柱 / 中轴顶灯 / 静水", "青窗 / 水道 / 禁行标志", "八角台阶 / 叠级穹顶 / 双门", "软垫 / 球池 / 圆形窗龛"]
const SPAWNS := [Vector3(1.4,4.76,10.8), Vector3(0,.60,14.4), Vector3(0,.60,14.4), Vector3(-14.4,.60,0), Vector3(-14.4,.60,0)]
const ROOT := "res://assets/models/reference_wing/"
static var _geometry: Dictionary = {}

static func vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func bounds_xz(points: Array) -> Rect2:
	assert(not points.is_empty(), "Empty authored footprint")
	var result := Rect2(Vector2(float(points[0][0]),float(points[0][1])), Vector2.ZERO)
	for p: Array in points: result = result.expand(Vector2(float(p[0]),float(p[1])))
	return result

static func geometry(index: int) -> Dictionary:
	if not _geometry.has(index):
		var path: String = ROOT + IDS[index] + ".geometry.json"
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(parsed is Dictionary, "Missing/invalid reference geometry contract: " + path)
		_geometry[index] = parsed
	return _geometry[index]

static func room_layout(coord: Vector2i, seed_value: int) -> Dictionary:
	var index := COORDS.find(coord)
	assert(index >= 0, "Reference wing does not generate unrelated rooms")
	var data := geometry(index)
	var rects: Array = []
	var steps: Array = []
	var exclusions: Array = []
	for region: Dictionary in data.get("water_regions", []): rects.append(bounds_xz(region.polygon_xz))
	for step: Dictionary in data.get("water_steps", []):
		var rect := bounds_xz(step.footprint_xz)
		steps.append(AABB(Vector3(rect.position.x,-.22,rect.position.y),Vector3(rect.size.x,maxf(0,float(step.top_y)+.22),rect.size.y)))
	# Physics uses exact authored proxies. These coarse exclusions are metadata only;
	# the scene adapter resolves exact authored polygons rather than these coarse boxes.
	for exclusion: Dictionary in data.get("water_exclusions", []):
		if exclusion.has("polygon_xz"):
			var rect := bounds_xz(exclusion.polygon_xz)
			exclusions.append(AABB(Vector3(rect.position.x,-.22,rect.position.y),Vector3(rect.size.x,1.0,rect.size.y)))
	var fixtures: Array = []
	for light: Dictionary in data.get("lights", []):
		if not light.get("runtime_enabled",true): continue
		var rgb: Array = light.get("color",[1,1,1])
		fixtures.append({"alive":true,"position":vec3(light.position),"color":Color(float(rgb[0]),float(rgb[1]),float(rgb[2])),
			"power":float(light.get("energy",1.0))/.07,"power_scale":1.0,"range":float(light.get("range",6.0)),
			"geometry":"authored_wall","shadow":bool(light.get("shadow",true)),"flicker":false,
			"flicker_seed":0.0,"flicker_amp":0.0,"fixture_object":light.get("fixture_object",light.get("name","")),
			"reference_light":light.duplicate(true)})
	var connections: Array = []
	for portal: Dictionary in data.get("portal_contracts", []):
		if portal.get("open",true): connections.append({"north":Vector2i.UP,"south":Vector2i.DOWN,"east":Vector2i.RIGHT,"west":Vector2i.LEFT}[portal.side])
	return {"coord":coord,"seed":seed_value,"variant":20+index,"reference_wing":true,"reference_id":IDS[index],
		"expanded":true,"expanded_mode":true,"name":NAMES[index],"subtitle":SUBTITLES[index],
		"geometry_path":ROOT+IDS[index]+".glb","geometry_contract":data,"spawn_local":vec3(data.spawn_local) if data.has("spawn_local") else SPAWNS[index],
		"ceiling":float(data.get("ceiling",data.get("datums",{}).get("ceiling_y",5.5))),"interior_ceiling":float(data.get("interior_ceiling",5.5)),
		"daylight":false,"corrupt":0,"tint":0.0,"ducks":0,"fog":.009,"fog_color":"#9eaaa7","light_color":"#e5eee9","light_power":30.0,
		"water_enabled":not rects.is_empty(),"water_floor_y":-.22,"water_rects":rects,"water_steps":steps,"water_exclusions":exclusions,
		"water_closed_edges":[],"solids":[],"wfc_grid":[],"portal_width":3.0,"portal_top":3.32,"connections":connections,
		"prop_spawns":[],"fixtures":fixtures,"expanded_signature":seed_value,"reference_water_regions":data.get("water_regions",[])}

static func camera(index: int) -> Dictionary:
	var data := geometry(index)
	var views: Array = data.get("camera_views", data.get("recommended_views", []))
	assert(not views.is_empty(), "Every reference needs an authored matching camera")
	var view: Dictionary = views[0]
	var offset := Vector3(COORDS[index].x*32.0,0,COORDS[index].y*32.0)
	var lens := float(view.get("lens_mm",view.get("blender_focal_length_mm",24.0)))
	# Authored Godot KEEP_HEIGHT vertical FOV; reference_resolution preserves the Blender framing.
	return {"position":vec3(view.get("position",view.get("from")))+offset,
		"target":vec3(view.get("target",view.get("toward")))+offset,"fov":float(view.get("fov_degrees",rad_to_deg(2.0*atan(36.0/(2.0*lens))))),"reference_resolution":view.get("reference_resolution",[1000,1000])}
