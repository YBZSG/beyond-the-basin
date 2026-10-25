extends SceneTree
## Bounded ten-ray investigation using actual source AABB visibility and the
## directly decoded authored GLB triangles. No import, full mask build or GPU.
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const Caustics = preload("res://scripts/water/source_port/source_caustics.gd")
const DepthField = preload("res://scripts/reference_wing/reference_depth_field.gd")
var meshes: Array[Dictionary] = []

func _initialize() -> void: _run.call_deferred()

func triangle_blockers(start: Vector3, end: Vector3) -> Array:
	var blockers: Array = []
	var delta := end - start
	for mesh: Dictionary in meshes:
		if not mesh.bounds.grow(0.00001).intersects_segment(start, end): continue
		var faces: PackedVector3Array = mesh.faces
		var nearest := 1.0
		for index in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2])
			if hit is Vector3:
				var t: float = (hit - start).dot(delta) / delta.length_squared()
				if t > 0.005 and t < 0.995: nearest = minf(nearest, t)
		if nearest < 1.0: blockers.append({"name": mesh.name, "t": nearest})
	return blockers

func _run() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("CPU-only probe requires dummy renderer."); quit(2); return
	var layout: Dictionary = Catalog.room_layout(Vector2i(1, -2), 250821)
	var triangle_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--triangle-json="): triangle_path = argument.trim_prefix("--triangle-json=")
	if triangle_path.is_empty():
		push_error("Run water_run_mask_probe.py to decode current GLB without cached imports."); quit(2); return
	var triangle_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(triangle_path))
	for entry: Dictionary in triangle_data.meshes:
		var faces := PackedVector3Array()
		for value: Array in entry.faces: faces.append(Catalog.vec3(value))
		var bounds := AABB(faces[0], Vector3.ZERO)
		for point: Vector3 in faces: bounds = bounds.expand(point)
		meshes.append({"name": entry.name, "bounds": bounds, "faces": faces})
	var solids: Array[AABB] = []
	var names: Array[String] = []
	for proxy: Dictionary in layout.geometry_contract.collision_proxies:
		var bounds: AABB
		if proxy.type == "BOX":
			var size: Vector3 = Catalog.vec3(proxy.size)
			bounds = AABB(Catalog.vec3(proxy.center) - size * 0.5, size)
		else:
			bounds = AABB(Catalog.vec3(proxy.vertices[0]), Vector3.ZERO)
			for point: Array in proxy.vertices: bounds = bounds.expand(Catalog.vec3(point))
		if not Caustics.filter_occlusion_solids([bounds]).is_empty():
			solids.append(bounds); names.append(proxy.name)
	var rows: Array = []
	var false_occlusions := 0
	var probes := [Vector2(2, -2), Vector2(1.9375, -2.0625), Vector2(2.0625, -2.0625), Vector2(1.9375, -1.9375), Vector2(2.0625, -1.9375)]
	if "--grid" in OS.get_cmdline_user_args():
		var profile: Dictionary = DepthField.profiles({Vector2i(1, -2): layout})[0]
		for z in range(-3, 4):
			for x in range(-3, 4):
				var point := Vector2(x, z)
				if DepthField.point_depth(point, profile) > 0.0 and not point in probes: probes.append(point)
	for point: Vector2 in probes:
		for lamp_id in 2:
			var start := Vector3(point.x, 0.31, point.y)
			var end: Vector3 = layout.fixtures[lamp_id].position
			var approximate := Caustics.ray_blocked(start, end, solids)
			var aabb_names: Array[String] = []
			for index in solids.size():
				var single: Array[AABB] = [solids[index]]
				if Caustics.ray_blocked(start, end, single): aabb_names.append(names[index])
			var exact := triangle_blockers(start, end)
			if approximate and exact.is_empty(): false_occlusions += 1
			rows.append({"point": [point.x, point.y], "mask_start_y": 0.31, "lamp_index": lamp_id,
				"lamp_name": layout.geometry_contract.lights[lamp_id].name, "lamp": [end.x, end.y, end.z],
				"source_mask_value": 0 if approximate else 255, "triangle_oracle_value": 255 if exact.is_empty() else 0,
				"aabb_blockers": aabb_names, "actual_triangle_blockers": exact})
	print("REFERENCE_OCTAGON_MASK_PROBE ", JSON.stringify({"probes": rows, "source_solids": solids.size(), "actual_meshes": meshes.size(), "glb_sha256": triangle_data.sha256,
		"contract_sha256": FileAccess.get_sha256("res://assets/models/reference_wing/octagonal_bath.geometry.json"), "proven_false_occlusions": false_occlusions, "gpu_run": false,
		"scope": "Bounded finite source-mask rays using actual first-two fixtures, .31 start plane, source slab kernel and directly decoded current GLB triangle oracle with .005/.995 segment bounds. Not a rendered caustic image."}))
	quit(0)
