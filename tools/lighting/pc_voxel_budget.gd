extends RefCounted
## Native 4.6.3 allocation model, not observed process/GPU memory.
## Source: scene/3d/voxelizer.{cpp,h}, renderer_rd/environment/gi.cpp.

static func estimate(size: Vector3, subdivisions: int) -> Dictionary:
	if subdivisions not in [64, 128] or size.x <= 0 or size.y <= 0 or size.z <= 0:
		return {"valid": false, "reason": "Only positive bounds and 64/128 subdivisions are permitted."}
	var longest := maxf(size.x, maxf(size.y, size.z))
	var cells := Vector3i(subdivisions, subdivisions, subdivisions)
	for axis in 3:
		var span := longest
		while span / 2.0 >= size[axis]:
			span /= 2.0
			cells[axis] >>= 1
	var voxels := cells.x * cells.y * cells.z
	var level := cells
	var nodes := 0
	var mip_voxels := 0
	var levels := 0
	while true:
		var count := level.x * level.y * level.z
		nodes += count
		mip_voxels += count
		levels += 1
		if level == Vector3i.ONE: break
		level = Vector3i(maxi(1, level.x >> 1), maxi(1, level.y >> 1), maxi(1, level.z >> 1))
	# gi.cpp allocates these even with NO dynamic meshes. nearest_power_of_2(4)
	# is 4, so the first 2D map is 16 times the longest grid axis, not 4 times.
	var dmap_texels := 0
	for oversample in range(4, 0, -1):
		var side := subdivisions * (1 << oversample)
		dmap_texels += side * side
	for mip in levels:
		var side := maxi(1, subdivisions >> mip)
		dmap_texels += side * side
	var first_side := subdivisions * 16
	var dmap_bytes := dmap_texels * 12 + first_side * first_side * 16
	# Last 16 = three RGBA8 targets plus worst-case 32-bit framebuffer depth.
	return {
		"valid": true, "subdivisions": subdivisions,
		"grid": [cells.x, cells.y, cells.z], "cell_metres": longest / subdivisions,
		"dense_voxels": voxels, "octree_nodes_upper_bound": nodes,
		"native_static_octree_data_sdf_bytes_upper_bound": 48 * nodes + voxels,
		"native_instance_write_and_volume_bytes_upper_bound": 16 * nodes + 4 * mip_voxels,
		"native_dynamic_map_bytes_upper_bound": dmap_bytes,
		"native_probe_gpu_bytes_upper_bound": 64 * nodes + voxels + 4 * mip_voxels + dmap_bytes,
		"cpu_sort_cells_and_maps_bytes_upper_bound": 180 * nodes,
		"cpu_sdf_work_and_result_bytes": 5 * voxels,
		"cpu_material_cache_bytes_per_unique_material": 2 * 128 * 128 * 16,
		"exclusions": "Not a total RSS/VRAM bound: excludes mesh/texture resources, framebuffer/shadow/SSAO/reflection resources, shaders, driver alignment, upload staging and allocator capacity. Native cell count is normally sparse; this is a dense-topology upper bound."
	}
