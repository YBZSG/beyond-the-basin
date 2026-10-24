extends SceneTree
## Real production world/material construction with controlled position input.
## No Player, water runtime, lighting/captures or graphical renderer is started.
const World = preload("res://scripts/world/pool_world.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const Refresh = preload("res://scripts/rendering/rt_material_refresh.gd")

class Host extends Node3D:
	var materials: RefCounted

var host: Host
var world: Node3D
var router := Refresh.new()
var rt_enabled := true
var flush_pending := false
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var batches: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var route: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var started := 0
var snapshot_cost_ms := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String, detail: Variant = null) -> void:
	checks.append({"pass": value, "label": label, "detail": detail})
	if not value: failures.append(label)

func _node_added(node: Node) -> void:
	if node is GeometryInstance3D and rt_enabled:
		router.queue_node(node)
		if not flush_pending:
			flush_pending = true
			call_deferred("_flush")

func _flush() -> void:
	flush_pending = false
	router.refresh_pending(rt_enabled)
	var batch: Dictionary = router.get_stats().last
	if int(batch.queued_nodes) > 0: batches.append(batch)

func _new_world() -> void:
	world = World.new()
	world.expanded_mode = true
	world.name = "ProductionStreamWorld"
	host.add_child(world)
	world.room_changed.connect(func(coord: Vector2i, _layout: Dictionary) -> void:
		transitions.append({"coord": [coord.x, coord.y], "process_frame": Engine.get_process_frames()}))
	world.initialize(250821, host.materials)

func _settle() -> void:
	var frames := 0
	while not world._queue.is_empty() and frames < 64:
		await process_frame
		frames += 1
	await process_frame
	await physics_frame
	_check(world._queue.is_empty() and world.resident_rooms.size() == 25, "normal one-interior-per-frame stream settles to 25 rooms", {"frames": frames, "resident_rooms": world.resident_rooms.size()})

func _materials_and_geometry() -> Dictionary:
	var materials: Array = host.materials._receiver_materials()
	var geometry := host.find_children("*", "GeometryInstance3D", true, false)
	for node: GeometryInstance3D in geometry:
		materials.append_array([node.material_override, node.material_overlay])
		if node is MeshInstance3D and node.mesh:
			for index in node.mesh.get_surface_count(): materials.append(node.get_active_material(index))
		elif node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
			for index in node.multimesh.mesh.get_surface_count(): materials.append(node.multimesh.mesh.surface_get_material(index))
	var unique: Dictionary = {}
	for material in materials:
		if material is Material: unique[material.get_instance_id()] = material
	return {"materials": unique.values(), "geometry_count": geometry.size()}

func _inspect(label: String, enabled: bool) -> Dictionary:
	var inspect_started := Time.get_ticks_usec()
	var collected := _materials_and_geometry()
	var families: Dictionary = {}
	var mismatches: Array[String] = []
	var eligible := 0
	for raster: String in Refresh.SHADER_PAIRS: families[raster] = 0
	for value in collected.materials:
		if not value is ShaderMaterial or value.shader == null: continue
		var path: String = value.shader.resource_path
		for raster: String in Refresh.SHADER_PAIRS:
			if path in [raster, Refresh.SHADER_PAIRS[raster]]:
				families[raster] += 1
				eligible += 1
				var expected: String = Refresh.SHADER_PAIRS[raster] if enabled else raster
				if path != expected: mismatches.append(value.resource_name + ": " + path)
	_check(mismatches.is_empty(), label + " all eligible live/library materials match selected mode", mismatches)
	for family: String in families: _check(int(families[family]) > 0, label + " actual production material family present: " + family)
	var collision_count := world.find_children("*", "CollisionShape3D", true, false).size()
	var result := {"phase": label, "geometry_count": collected.geometry_count, "unique_materials": collected.materials.size(), "eligible_materials": eligible, "families": families, "local_receiver_refs": host.materials._local_receiver_refs.size(), "collision_shapes": collision_count, "resident_rooms": world.resident_rooms.size(), "world_profile": world.profile_counters.duplicate(true), "router": router.get_stats()}
	_check(collision_count > 0, label + " production collision shapes remain installed")
	_check(result.local_receiver_refs > 0, label + " actual room-local receiver materials exercised")
	result.inspection_ms = float(Time.get_ticks_usec() - inspect_started) / 1000.0
	snapshot_cost_ms += result.inspection_ms
	phases.append(result)
	return result

func _collision_identity() -> String:
	var values: Array = []
	for node: CollisionShape3D in world.find_children("*", "CollisionShape3D", true, false):
		values.append([node.get_instance_id(), node.shape.get_instance_id(), node.transform, node.disabled])
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(values))
	return context.finish().hex_encode()

func _advance_route(from_x: float, to_x: float, label: String) -> void:
	var direction := 1.0 if to_x > from_x else -1.0
	var position := Vector3(from_x, 0.6, 0.0)
	var steps := roundi(absf(to_x - from_x) / 0.5)
	for step in steps:
		var previous := position
		position.x += 0.5 * direction
		var old_coord: Vector2i = world.current_room
		var shell_before: int = world.profile_counters.shell_builds
		var call_started := Time.get_ticks_usec()
		world.update_player_position(position)
		var update_ms := float(Time.get_ticks_usec() - call_started) / 1000.0
		var synchronous_shells: int = int(world.profile_counters.shell_builds) - shell_before
		await process_frame
		await physics_frame
		var query := PhysicsRayQueryParameters3D.create(Vector3(position.x, 1.5, 0), Vector3(position.x, -2.0, 0), 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		var coord: Vector2i = world.current_room
		var crossing := coord != old_coord
		route.append({"leg": label, "position": [position.x, position.y, position.z], "step_m": position.distance_to(previous), "coord": [coord.x, coord.y], "crossing": crossing, "synchronous_shells_added": synchronous_shells, "shells_added_through_next_physics_frame": int(world.profile_counters.shell_builds) - shell_before, "update_player_position_ms": update_ms, "current_room_ready": world.current_room_ready(), "floor_hit": not hit.is_empty(), "resident_rooms": world.resident_rooms.size()})
		_check(world.current_room_ready() and not hit.is_empty(), "%s step %d has ready destination and real architecture below" % [label, step])
		if crossing:
			_check(synchronous_shells == 5, label + " ordinary cardinal crossing retains baseline five-shell scheduling")
	await _settle()

func _run() -> void:
	started = Time.get_ticks_usec()
	host = Host.new()
	host.name = "ControlledProductionHost"
	root.add_child(host)
	host.materials = Materials.new()
	router.configure(host)
	router.refresh_all(true)
	node_added.connect(_node_added)
	_new_world()
	await _settle()
	var initial := _inspect("initial_expanded_world", true)
	await _advance_route(0.0, 32.0, "outbound")
	var outbound := _inspect("after_cardinal_crossing", true)
	await _advance_route(32.0, 0.0, "return")
	var returned := _inspect("after_boundary_reversal", true)
	_check(world.profile_counters.transitions == 2 and route.size() == 128, "one continuous 32m outbound and return produces exactly two ordinary crossings")
	_check(int(returned.world_profile.shell_builds) - int(initial.world_profile.shell_builds) == 10, "crossing and return create ten entering shells, no distant-teleport batch")
	_check(int(outbound.router.shader_changes) > int(initial.router.shader_changes), "late streamed production-local materials receive RT variants")
	var collision_before := _collision_identity()
	rt_enabled = false
	router.refresh_all(false)
	_inspect("disabled_after_return", false)
	rt_enabled = true
	router.refresh_all(true)
	rt_enabled = false
	router.refresh_all(false)
	_inspect("rapid_toggles_restore_raster", false)
	_check(_collision_identity() == collision_before, "material toggles preserve every collision node shape transform and enable state")

	# Keep one old node alive but detached across a real production replacement.
	rt_enabled = true
	router.refresh_all(true)
	var old_world := world
	var old_reference: WeakRef = weakref(old_world)
	var old_geometry: GeometryInstance3D = old_world.find_children("*", "GeometryInstance3D", true, false)[0]
	router.queue_node(old_geometry)
	host.remove_child(old_world)
	var discarded_before: int = router.get_stats().discarded_nodes
	_new_world()
	await _settle()
	_check(int(router.get_stats().discarded_nodes) > discarded_before, "world replacement rejects queued detached old-world geometry")
	old_world.free()
	old_world = null
	old_geometry = null
	await process_frame
	_check(old_reference.get_ref() == null, "helper weak references do not retain retired production world")
	_inspect("replacement_world_rt", true)
	rt_enabled = false
	router.refresh_all(false)
	_inspect("replacement_world_raster", false)
	await process_frame
	_check(router.get_stats().pending_nodes == 0, "world replacement and final toggle leave no stale pending references")
	var max_position_update_ms := 0.0
	var crossing_calls: Array = []
	for sample: Dictionary in route:
		max_position_update_ms = maxf(max_position_update_ms, sample.update_player_position_ms)
		if sample.crossing: crossing_calls.append(sample)
	var report := {"pass": failures.is_empty(), "checks": checks.size(), "failures": failures, "engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "hardware_rt_enabled": false, "seed": 250821, "mode": "expanded", "scope": "Real production PoolWorld/RoomBuilder/PoolMaterials, 5x5 resident streaming, actual collision floor rays and shader selection in CPU-headless Godot. Controlled positions advance by 0.5m, not a Player/controller traversal. No water runtime, lights/probes, graphical rendering, hardware RT/DLSS/FG or Windows frame-time acceptance.", "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0, "inspection_ms": snapshot_cost_ms, "max_update_player_position_ms": max_position_update_ms, "crossing_calls": crossing_calls, "phases": phases, "material_batches": batches, "route": route, "transitions": transitions, "assertions": checks, "source_sha256": {}}
	for path: String in ["scripts/rendering/rt_material_refresh.gd", "scripts/world/pool_world.gd", "scripts/world/room_builder.gd", "scripts/world/expanded_room_builder.gd", "scripts/rendering/pool_materials.gd", "tests/room_transition/rt_production_stream_contract.gd"]: report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	var output := "/tmp/poolcore-transition-rt/production-stream.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		failures.append("Could not write report: " + output)
	print("RT_PRODUCTION_STREAM_CONTRACT ", JSON.stringify({"pass": failures.is_empty(), "checks": checks.size(), "failures": failures, "elapsed_ms": report.elapsed_ms, "crossing_calls": crossing_calls, "initial_geometry": initial.geometry_count, "return_geometry": returned.geometry_count, "material_batches": batches.size(), "report": output, "scope": report.scope}))
	node_added.disconnect(_node_added)
	host.free()
	quit(0 if failures.is_empty() else 1)
