class_name SourceTerrainIdentity
extends RefCounted
## Conservative identity for the unchanged preparation kernels. It omits a
## room only when none of its values can enter depth, BVH, or incoming masks.
## A false dependency costs a rebuild; a missing dependency would be incorrect.
const DOMAIN := 96.0
const WATER_LEVEL := .32
const POOL_BOTTOM := -.72

static func digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

static func describe_room(values: Dictionary) -> Dictionary:
	var depth_entries: Array = []
	for collider: Dictionary in values.colliders:
		var center: Vector3 = collider.center
		var half: Vector3 = collider.half
		var rotation: Quaternion = collider.get("rotation", Quaternion.IDENTITY)
		var bounds := Transform3D(Basis(rotation), center) * AABB(-half, half * 2.0)
		if bounds.position.y <= WATER_LEVEL and bounds.end.y > POOL_BOTTOM:
			depth_entries.append(collider)
	var mask_bounds: Array[AABB] = []
	for bounds: AABB in values.solids:
		if bounds.end.y > .31 and bounds.position.y < 7.4:
			mask_bounds.append(bounds)
	return {"depth_entries": depth_entries, "mask_bounds": mask_bounds,
		"depth_digest": digest(values.colliders), "mask_digest": digest(values.solids),
		"optical_digest": digest(values.triangles)}

static func key(coord: Vector2i, size: int, geometry_origin: Vector2, rooms: Dictionary, layouts: Dictionary, lamps: Array, force_revision: int = 0) -> String:
	return components(coord, size, geometry_origin, rooms, layouts, lamps, force_revision).key

static func components(coord: Vector2i, size: int, geometry_origin: Vector2, rooms: Dictionary, layouts: Dictionary, lamps: Array, force_revision: int = 0) -> Dictionary:
	var origin := Vector2(coord) * 32.0
	var shift := Vector3(geometry_origin.x - origin.x, 0, geometry_origin.y - origin.y)
	var depth_dependencies: Array = []
	var mask_dependencies: Array = []
	var optical_dependencies: Array = []
	var authored := false
	var cell := DOMAIN / size
	for layout: Dictionary in layouts.values():
		authored = authored or bool(layout.get("formal", false))
	# Dictionary insertion order is deliberate: it is also the BVH input order.
	for room_coord: Vector2i in rooms:
		var description: Dictionary = rooms[room_coord].description
		var depth_used := false
		for collider: Dictionary in description.depth_entries:
			var half: Vector3 = collider.half
			var rotation: Quaternion = collider.get("rotation", Quaternion.IDENTITY)
			var bounds := Transform3D(Basis(rotation), collider.center + shift) * AABB(-half, half * 2.0)
			# Same grid coverage test as build_depth_data. An AABB can intersect
			# the 96m domain while lying outside its outermost sampled centers.
			var x0 := maxi(0, ceili((bounds.position.x + DOMAIN * .5) / cell - .5))
			var z0 := maxi(0, ceili((bounds.position.z + DOMAIN * .5) / cell - .5))
			var x1 := mini(size - 1, floori((bounds.end.x + DOMAIN * .5) / cell - .5))
			var z1 := mini(size - 1, floori((bounds.end.z + DOMAIN * .5) / cell - .5))
			if x0 <= x1 and z0 <= z1:
				depth_used = true
				break
		if depth_used: depth_dependencies.append([room_coord, description.depth_digest])
		var mask_used := false
		for original: AABB in description.mask_bounds:
			var lo := original.position + shift
			var hi := lo + original.size
			if hi.x > -16.6 and lo.x < 16.6 and hi.z > -16.6 and lo.z < 16.6:
				mask_used = true
				break
		if mask_used: mask_dependencies.append([room_coord, description.mask_digest])
		var delta := room_coord - coord
		var optical_used := maxi(absi(delta.x), absi(delta.y)) <= 1
		if optical_used: optical_dependencies.append([room_coord, description.optical_digest])
	var wet_layouts: Array = []
	if authored:
		for z in range(coord.y - 1, coord.y + 2):
			for x in range(coord.x - 1, coord.x + 2):
				var room_coord := Vector2i(x, z)
				var layout: Dictionary = layouts.get(room_coord, {})
				var wet := bool(layout.get("water_enabled", false))
				wet_layouts.append([room_coord, wet, layout.get("water_rects", []) if wet else []])
	var depth_key := digest([force_revision, geometry_origin, coord, size, depth_dependencies, authored, wet_layouts])
	var bvh_key := digest([force_revision, geometry_origin, coord, optical_dependencies])
	var mask_key := digest([force_revision, geometry_origin, coord, mask_dependencies, lamps])
	return {"key": "%d:%d:%d:%s" % [coord.x, coord.y, size, digest([depth_key, bvh_key, mask_key])],
		"depth_key": depth_key, "bvh_key": bvh_key, "mask_key": mask_key}
