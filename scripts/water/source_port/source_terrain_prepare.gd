class_name SourceTerrainPrepare
extends RefCounted
## CPU-only preparation of the original source-water static terrain.
## Call build() on an exclusively owned immutable snapshot. It does not touch
## Nodes, resources, RenderingServer, live solver/caustic state, or shared arrays.
## Join the worker before publishing its returned data on the main thread.

const Solver = preload("res://scripts/water/source_port/source_wave_solver.gd")
const Caustics = preload("res://scripts/water/source_port/source_caustics.gd")

class Progress extends RefCounted:
	var mutex := Mutex.new()
	var stage := "queued"
	var started_usec := Time.get_ticks_usec()
	var stage_started_usec := started_usec
	func mark(value: String) -> void:
		mutex.lock()
		stage = value; stage_started_usec = Time.get_ticks_usec()
		mutex.unlock()
	func read() -> Dictionary:
		mutex.lock()
		var result := {"stage": stage, "elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
			"stage_elapsed_ms": float(Time.get_ticks_usec() - stage_started_usec) / 1000.0}
		mutex.unlock()
		return result

static func build(snapshot: Dictionary, progress: Callable = Callable()) -> Dictionary:
	var started := Time.get_ticks_usec()
	if progress.is_valid(): progress.call("translate")
	var size: int = snapshot.size
	var domain: float = snapshot.get("domain", 96.0)
	var origin: Vector2 = snapshot.origin
	var geometry_origin: Vector2 = snapshot.get("geometry_origin", origin)
	var shift := Vector3(geometry_origin.x - origin.x, 0.0, geometry_origin.y - origin.y)
	var colliders: Array = snapshot.get("colliders", [])
	var solids: Array = snapshot.get("solids", [])
	var triangles: PackedVector3Array = snapshot.get("triangles", PackedVector3Array())
	# Source engine.ts collectRtItems excludes the far ring; keep all colliders
	# for physics/depth, but rebuild optical triangles for THIS cached origin.
	if snapshot.has("triangles_by_room"):
		triangles=PackedVector3Array()
		var center:=Vector2i(roundi(origin.x/32.0),roundi(origin.y/32.0))
		for coord:Vector2i in snapshot.triangles_by_room:
			var delta:=coord-center
			if maxi(absi(delta.x),absi(delta.y))<=1:triangles.append_array(snapshot.triangles_by_room[coord])
	# The main thread may cache one geometry snapshot for several room origins.
	# Copy only where translating, never mutate the main thread's shared snapshot.
	if shift != Vector3.ZERO:
		colliders = colliders.duplicate(true)
		for collider: Dictionary in colliders:
			collider.center += shift
		var shifted_solids: Array = []
		for value in solids:
			if value is AABB:
				shifted_solids.append(AABB(value.position + shift, value.size))
			elif value is Dictionary and value.has("min") and value.has("max"):
				shifted_solids.append({"min": value.min + shift, "max": value.max + shift})
			else:
				shifted_solids.append(value)
		solids = shifted_solids
		triangles = triangles.duplicate()
		for i in range(triangles.size()):
			triangles[i] += shift
	var translated := Time.get_ticks_usec()
	if progress.is_valid(): progress.call("depth")
	var depth_data := Solver.build_depth_data(colliders, size, domain)
	var depth_built := Time.get_ticks_usec()
	if progress.is_valid(): progress.call("wet_mask")
	_apply_authored_wet_mask(depth_data, size, domain, origin, snapshot.get("layouts", {}))
	var wet_built := Time.get_ticks_usec()
	if progress.is_valid(): progress.call("bvh")
	# Reuse is supplied only by the runtime's exact per-component dependency
	# identity. These packed arrays are immutable, never rebased or edited here.
	var reused_bvh := snapshot.has("prepared_bvh")
	var packed_bvh: Dictionary = snapshot.prepared_bvh if reused_bvh else Caustics.build_triangle_bvh(triangles)
	var bvh_built := Time.get_ticks_usec()
	if progress.is_valid(): progress.call("masks")
	var reused_masks := snapshot.has("prepared_occlusion")
	var filtered_solids: Array[AABB] = snapshot.prepared_occlusion.filtered_solids if reused_masks else Caustics.filter_occlusion_solids(solids)
	var masks: Array[PackedByteArray] = snapshot.prepared_occlusion.masks if reused_masks else Caustics.build_occlusion_masks(filtered_solids, snapshot.lamps)
	var completed := Time.get_ticks_usec()
	if progress.is_valid(): progress.call("complete")
	return {
		"reused_bvh": reused_bvh, "reused_masks": reused_masks,
		"coord": snapshot.get("coord", Vector2i(roundi(origin.x / 32.0), roundi(origin.y / 32.0))),
		"revision": snapshot.get("revision", 0),
		"origin": origin, "size": size, "domain": domain,
		"depth_data": depth_data, "packed_bvh": packed_bvh,
		"masks": masks, "filtered_solids": filtered_solids,
		"timing_ms": {
			"translate": float(translated - started) / 1000.0,
			"depth": float(depth_built - translated) / 1000.0,
			"wet_mask": float(wet_built - depth_built) / 1000.0,
			"bvh": float(bvh_built - wet_built) / 1000.0,
			"masks": float(completed - bvh_built) / 1000.0,
			"total": float(completed - started) / 1000.0,
		},
	}

static func _apply_authored_wet_mask(data: PackedFloat32Array, size: int, domain: float, origin: Vector2, layouts: Dictionary) -> void:
	var authored := false
	for layout: Dictionary in layouts.values():
		authored = authored or layout.get("formal", false)
	if not authored:
		return
	var cell := domain / size
	for z in size:
		for x in size:
			# Authored runtime domain is exactly 96m, as in the source shader.
			var world_point := Vector2((x + .5) * cell - 48.0, (z + .5) * cell - 48.0) + origin
			var coord := Vector2i(floori((world_point.x + 16) / 32), floori((world_point.y + 16) / 32))
			var layout: Dictionary = layouts.get(coord, {})
			var wet := false
			if layout.get("water_enabled", false):
				for rect: Rect2 in layout.get("water_rects", []):
					if rect.has_point(world_point - Vector2(coord) * 32):
						wet = true
						break
			if not wet:
				data[x + z * size] = 0.0
