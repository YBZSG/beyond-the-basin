extends SceneTree
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const DepthField = preload("res://scripts/reference_wing/reference_depth_field.gd")
const SurfaceMesh = preload("res://scripts/reference_wing/reference_surface_mesh.gd")
var checks := {}
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(label: String, valid: bool) -> void:
	checks[label] = valid
	if not valid: failures.append(label)

func triangle_cross(vertices: PackedVector3Array, indices: PackedInt32Array, first: int) -> Vector3:
	var a: Vector3 = vertices[indices[first]] if not indices.is_empty() else vertices[first]
	var b: Vector3 = vertices[indices[first + 1]] if not indices.is_empty() else vertices[first + 1]
	var c: Vector3 = vertices[indices[first + 2]] if not indices.is_empty() else vertices[first + 2]
	return (b - a).cross(c - a)

func _run() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("Dummy renderer required."); quit(2); return
	var plane := PlaneMesh.new()
	var plane_arrays := plane.get_mesh_arrays()
	var plane_cross := triangle_cross(plane_arrays[Mesh.ARRAY_VERTEX], plane_arrays[Mesh.ARRAY_INDEX], 0)
	check("real_plane_mesh_has_nonzero_y_winding", absf(plane_cross.y) > 0.001)
	checks.real_plane_mesh_cross_y = plane_cross.y
	var layouts := {}
	for coord: Vector2i in Catalog.COORDS: layouts[coord] = Catalog.room_layout(coord, 250821)
	var profiles: Array = DepthField.profiles(layouts)
	check("three_authored_water_profiles", profiles.size() == 3)
	var octagon: Dictionary
	for profile: Dictionary in profiles:
		if profile.polygon.size() == 8: octagon = profile
	check("octagon_interior_no_false_aabb_step", is_equal_approx(DepthField.point_depth(Vector2(2, -2), octagon), 0.54))
	check("octagon_corner_outside_is_dry", DepthField.point_depth(Vector2(4, 4), octagon) == 0.0)
	check("octagon_center_deep", is_equal_approx(DepthField.point_depth(Vector2.ZERO, octagon), 0.54))
	for coord: Vector2i in Catalog.COORDS:
		var layout: Dictionary = layouts[coord]
		for region: Dictionary in layout.reference_water_regions:
			var polygon: PackedVector2Array = DepthField.polygon(region.polygon_xz)
			for density: float in [1.0, 2.0, 4.0, 512.0 / 96.0]:
				var started := Time.get_ticks_usec()
				var mesh := SurfaceMesh.build(region.polygon_xz, density)
				var arrays := mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
				var matches_plane := true
				var inside := true
				var finite := true
				var nondegenerate := true
				var max_edge := 0.0
				for i in range(0, vertices.size(), 3):
					var cross_value := triangle_cross(vertices, indices, i)
					matches_plane = matches_plane and cross_value.y * plane_cross.y > 0.0
					nondegenerate = nondegenerate and absf(cross_value.y) > 0.00000001
					var center := (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
					inside = inside and Geometry2D.is_point_in_polygon(Vector2(center.x, center.z), polygon)
					for j in 3:
						finite = finite and vertices[i + j].is_finite() and normals[i + j].is_finite() and normals[i + j].dot(Vector3.UP) > 0.9999
						max_edge = maxf(max_edge, vertices[i + j].distance_to(vertices[i + (j + 1) % 3]))
				var label: String = layout.reference_id + "_density_" + str(density)
				check(label + "_matches_plane_winding", matches_plane)
				check(label + "_only_inside_authored_basin", inside)
				check(label + "_finite_up_normals", finite)
				check(label + "_no_zero_area_triangles", nondegenerate)
				check(label + "_bounded_source_spacing", max_edge <= sqrt(2.0) / density + 0.0001)
				checks[label + "_vertices"] = vertices.size()
				checks[label + "_build_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	var payload := {"coord": Vector2i(1, -2), "origin": Vector2(32, -64), "size": 96, "domain": 96.0, "depth_data": PackedFloat32Array([99.0]), "packed_bvh": {"sentinel": 17}, "masks": ["sentinel"]}
	var result := DepthField.build(payload, profiles)
	check("build_keeps_source_payload_arrays_immutable", payload.depth_data == PackedFloat32Array([99.0]) and result.depth_data.size() == 96 * 96)
	check("build_does_not_replace_bvh_or_masks", result.packed_bvh == payload.packed_bvh and result.masks == payload.masks)
	var finite_depth := true
	for value: float in result.depth_data: finite_depth = finite_depth and is_finite(value) and value >= 0.0 and value <= 0.540001
	check("depth_is_finite_and_bounded", finite_depth)
	var reference_step: Dictionary = profiles[0].steps[0]
	var step_center: Vector2 = reference_step.bounds.get_center()
	check("step_depth_matches_real_tread_top", is_equal_approx(DepthField.point_depth(step_center, profiles[0]), maxf(0.0, profiles[0].surface - reference_step.top)))
	check("column_exclusion_is_dry", DepthField.point_depth(profiles[0].exclusions[0].bounds.get_center(), profiles[0]) == 0.0)
	print("REFERENCE_WATER_GEOMETRY ", JSON.stringify({"passed": failures.is_empty(), "failures": failures, "checks": checks, "gpu_run": false, "scope": "Actual Geometry2D/ArrayMesh/PlaneMesh and authored depth CPU checks; no graphics or solver dispatch."}))
	quit(0 if failures.is_empty() else 1)
