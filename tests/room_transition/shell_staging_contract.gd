extends SceneTree
## Exact frozen scheduler versus staged shells, using production room builders.
const STAGED_PATH := "res://tests/room_transition/fixtures/pool_world_staged_candidate.gd.txt"
var staged_script: GDScript
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const Snapshot = preload("res://scripts/water/source_room_snapshot.gd")
const Identity = preload("res://scripts/water/source_terrain_identity.gd")
const BASELINE_PATH := "res://tests/room_transition/fixtures/pool_world_4876a68.gd.txt"
const BASELINE_SHA256 := "a0ebc2d9a49b359b57e1f2887288d326f22c5c78da46cd44bec3a3e69e74cd5b"
var baseline: GDScript
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var records: Array[Dictionary] = []
var library: RefCounted
var snapshot_ms := 0.0
var started := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String, details: Variant = null) -> void:
	checks.append({"pass": ok, "label": label, "details": details})
	if not ok: failures.append(label)

func _coord(coord: Vector2i) -> String: return "%d,%d" % [coord.x, coord.y]

func _trace_room(room: Node3D, coord: Vector2i, _layout: Dictionary, trace: Dictionary) -> void:
	trace.events.append(_coord(coord))
	trace.live[coord] = weakref(room)
	var identity := room.get_instance_id()
	room.tree_exiting.connect(func() -> void:
		var current: Node3D = trace.live[coord].get_ref() if trace.live.has(coord) else null
		if is_instance_valid(current) and current.get_instance_id() == identity: trace.live.erase(coord))

func _make(script: Script, mode: String, seed_value: int, rollback: bool = false) -> Dictionary:
	var world: Node3D = script.new()
	world.formal_mode = mode == "formal"
	world.expanded_mode = mode in ["expanded", "poolrooms"]
	world.poolrooms_mode = mode == "poolrooms"
	if script == staged_script: world.staged_outer_shells = not rollback
	root.add_child(world)
	world.set_process(false)
	var trace := {"events": [], "live": {}}
	world.room_loaded.connect(_trace_room.bind(trace))
	var init_started := Time.get_ticks_usec()
	world.initialize(seed_value, library)
	return {"world": world, "trace": trace, "initialization_ms": float(Time.get_ticks_usec() - init_started) / 1000.0}

func _near_ready(world: Node3D, label: String) -> void:
	if world.formal_mode: return
	var missing: Array[String] = []
	for y in range(world.current_room.y - 1, world.current_room.y + 2):
		for x in range(world.current_room.x - 1, world.current_room.x + 2):
			var coord := Vector2i(x, y)
			if not world.resident_rooms.has(coord) or world.resident_rooms[coord].find_children("*", "CollisionShape3D", true, false).is_empty(): missing.append(_coord(coord))
	_check(missing.is_empty() and world.current_room_ready(), label + " current complete and all adjacent 3x3 collision shells installed", missing)
	var queued: Dictionary = {}
	for coord: Vector2i in world._queue:
		_check(world._desired.has(coord) and not queued.has(coord), label + " queued coordinate is desired and unique: " + _coord(coord))
		queued[coord] = true

func _job(world: Node3D, jobs: Array, label: String) -> void:
	var shell_before: int = world.profile_counters.shell_builds
	var interior_before: int = world.profile_counters.interior_builds
	var job_started := Time.get_ticks_usec()
	world._process(1.0 / 60.0)
	jobs.append({"phase": label, "ms": float(Time.get_ticks_usec() - job_started) / 1000.0, "shells": int(world.profile_counters.shell_builds) - shell_before, "interiors": int(world.profile_counters.interior_builds) - interior_before})
	_check(int(world.profile_counters.interior_builds) - interior_before <= 1 and int(world.profile_counters.shell_builds) - shell_before <= 1, label + " process job builds at most one shell and one complete interior")

func _drain(world: Node3D, jobs: Array, label: String) -> void:
	var limit := 0
	while not world._queue.is_empty() and limit < 64:
		_job(world, jobs, label)
		limit += 1
		await process_frame
	await process_frame
	await physics_frame
	_check(world._queue.is_empty() and world._builders.is_empty(), label + " queue and builders drain")
	_check(world.resident_rooms.size() == (5 if world.formal_mode else 25), label + " exact eventual residency")
	for coord: Vector2i in world.resident_rooms:
		_check(world._desired.has(coord) and world.is_room_ready(coord), label + " resident room desired and complete: " + _coord(coord))

func _boundary_floor(world: Node3D, x: float, z: float, label: String) -> void:
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 2, z), Vector3(x, -3, z), 1)
	_check(not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), label + " real architecture floor ray")

func _update(world: Node3D, position: Vector3, calls: Array, label: String) -> void:
	var shells: int = world.profile_counters.shell_builds
	var interiors: int = world.profile_counters.interior_builds
	var update_started := Time.get_ticks_usec()
	world.update_player_position(position)
	calls.append({"phase": label, "position": [position.x, position.y, position.z], "ms": float(Time.get_ticks_usec() - update_started) / 1000.0, "shells": int(world.profile_counters.shell_builds) - shells, "interiors": int(world.profile_counters.interior_builds) - interiors, "queued": world._queue.size()})
	_near_ready(world, label)

func _visual(room: Node3D) -> Dictionary:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var meshes := 0
	var surfaces := 0
	for mesh: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		meshes += 1
		context.update(var_to_bytes([mesh.transform, mesh.visible, mesh.layers, mesh.cast_shadow, mesh.gi_mode]))
		for index in mesh.mesh.get_surface_count():
			surfaces += 1
			context.update(var_to_bytes(mesh.mesh.surface_get_arrays(index)))
			var material: Material = mesh.get_active_material(index)
			context.update(var_to_bytes(material.resource_name if material != null else ""))
	for label: Label3D in room.find_children("*", "Label3D", true, false):
		context.update(var_to_bytes([label.text, label.transform, label.modulate, label.font_size, label.pixel_size]))
	return {"sha256": context.finish().hex_encode(), "meshes": meshes, "surfaces": surfaces}

func _capture(world: Node3D, trace: Dictionary, label: String) -> Dictionary:
	var capture_started := Time.get_ticks_usec()
	var rooms: Dictionary = {}
	var live_order: Array[String] = []
	var optical_order: Array[String] = []
	var optical := HashingContext.new()
	optical.start(HashingContext.HASH_SHA256)
	for coord: Vector2i in trace.live:
		var room: Node3D = trace.live[coord].get_ref()
		if not is_instance_valid(room): continue
		live_order.append(_coord(coord))
		var capture := Snapshot.new()
		capture.begin(room, coord, Vector2.ZERO)
		while not capture.complete:
			capture.advance(2000)
			if not capture.complete: await process_frame
		var values: Dictionary = capture.result
		rooms[_coord(coord)] = {"layout": Identity.digest(world.get_layout(coord)), "colliders": Identity.digest(values.colliders), "solids": Identity.digest(values.solids), "triangles": Identity.digest(values.triangles), "triangle_count": values.triangles.size() / 3, "visual": _visual(room)}
		var delta: Vector2i = coord - world.current_room
		if maxi(absi(delta.x), absi(delta.y)) <= 1:
			optical_order.append(_coord(coord))
			optical.update(values.triangles.to_byte_array())
	var elapsed := float(Time.get_ticks_usec() - capture_started) / 1000.0
	snapshot_ms += elapsed
	return {"phase": label, "rooms": rooms, "live_room_order": live_order, "near_optical_order": optical_order, "near_optical_bytes_sha256": optical.finish().hex_encode(), "load_events": trace.events.duplicate(), "profile": world.profile_counters.duplicate(true), "snapshot_ms": elapsed}

func _case(script: Script, name: String, mode: String, seed_value: int, rollback: bool = false) -> Dictionary:
	var created := _make(script, mode, seed_value, rollback)
	var world: Node3D = created.world
	var trace: Dictionary = created.trace
	var jobs: Array = []
	var calls: Array = []
	var checkpoints: Array = []
	_near_ready(world, name + " initial")
	_check(world.resident_rooms.size() == (9 if script == staged_script and not rollback else 25), name + " initial shell population", world.resident_rooms.size())
	await _drain(world, jobs, "initial")
	checkpoints.append(await _capture(world, trace, "initial"))
	for x in [0.0, 8.0, 15.5, 15.9, 16.0]:
		_update(world, Vector3(x, 0.6, 0), calls, "outbound")
		await _boundary_floor(world, x, 0, name + " outbound " + str(x))
	await _drain(world, jobs, "outbound")
	checkpoints.append(await _capture(world, trace, "outbound"))
	for x in [20.0, 24.0, 32.0, 24.0, 20.0, 16.0, 15.9]:
		_update(world, Vector3(x, 0.6, 0), calls, "return")
		await _boundary_floor(world, x, 0, name + " return " + str(x))
	await _drain(world, jobs, "return")
	checkpoints.append(await _capture(world, trace, "return"))
	# Reverse before all five entering rooms finish, then reverse again. The
	# same exact process-job sequence is used by baseline and candidate.
	for x in [16.1, 15.9, 16.1, 15.9]:
		_update(world, Vector3(x, 0.6, 0), calls, "rapid_reversal")
		_job(world, jobs, "rapid_reversal")
		await _boundary_floor(world, x, 0, name + " rapid reversal")
	await _drain(world, jobs, "rapid_reversal")
	checkpoints.append(await _capture(world, trace, "rapid_reversal"))
	_update(world, Vector3(320, 0.6, -224), calls, "far_teleport")
	await _boundary_floor(world, 320, -224, name + " far destination")
	var pending_before: int = world._queue.size()
	var completion_started := Time.get_ticks_usec()
	world.complete_pending_streaming()
	var complete_ms := float(Time.get_ticks_usec() - completion_started) / 1000.0
	await process_frame
	_check(pending_before > 0 and world._queue.is_empty() and world.resident_rooms.size() == 25, name + " explicit deterministic completion creates queued missing shells")
	checkpoints.append(await _capture(world, trace, "far_teleport"))
	# Direct arbitrary ensure is still synchronous and does not require a queued
	# shell. Deterministic completion then retires that out-of-window room.
	_check(not world.resident_rooms.has(Vector2i(20, -7)), name + " direct ensure target starts outside resident window")
	world.ensure_room_ready(Vector2i(20, -7))
	_check(world.is_room_ready(Vector2i(20, -7)), name + " direct ensure synchronously builds arbitrary room")
	await _boundary_floor(world, 640, -224, name + " direct ensure destination")
	world.complete_pending_streaming()
	await process_frame
	_check(not world.resident_rooms.has(Vector2i(20, -7)) and world.resident_rooms.size() == 25, name + " subsequent completion safely retires out-of-window ensured room")
	var result := {"name": name, "mode": mode, "seed": seed_value, "rollback": rollback, "initialization_ms": created.initialization_ms, "calls": calls, "jobs": jobs, "complete_pending_ms": complete_ms, "checkpoints": checkpoints}
	world.free()
	await process_frame
	return result

func _compare(reference: Dictionary, candidate: Dictionary) -> void:
	for index in reference.checkpoints.size():
		var a: Dictionary = reference.checkpoints[index]
		var b: Dictionary = candidate.checkpoints[index]
		var label: String = candidate.name + " / " + a.phase
		_check(a.rooms == b.rooms, label + " exact per-room layouts render arrays colliders solids and optical triangles", {"baseline_rooms": a.rooms.size(), "candidate_rooms": b.rooms.size()})
		_check(a.live_room_order == b.live_room_order and a.load_events == b.load_events, label + " exact room_loaded and live optical insertion order", {"baseline": a.live_room_order, "candidate": b.live_room_order})
		_check(a.near_optical_order == b.near_optical_order and a.near_optical_bytes_sha256 == b.near_optical_bytes_sha256, label + " exact near-field optical concatenation order and bytes")
		if a.phase in ["initial", "outbound", "return"] or candidate.rollback:
			_check(a.profile.shell_builds == b.profile.shell_builds and a.profile.interior_builds == b.profile.interior_builds and a.profile.retirements == b.profile.retirements, label + " equal completed work, not a reduced-room benchmark", {"baseline": a.profile, "candidate": b.profile})
		else:
			# The two partial five-room batches each completed only one room before
			# reversal. Their other four shells are now never built, rather than built
			# and immediately retired. Required interiors, publications and final
			# complete geometry above must still match exactly.
			_check(int(a.profile.shell_builds) - int(b.profile.shell_builds) == 8 and int(a.profile.retirements) - int(b.profile.retirements) == 8 and a.profile.interior_builds == b.profile.interior_builds, label + " exactly eight cancelled unused shells avoided, all completed room work equal", {"baseline": a.profile, "candidate": b.profile})
	for index in reference.calls.size():
		var a: Dictionary = reference.calls[index]
		var b: Dictionary = candidate.calls[index]
		if a.phase in ["outbound", "return"] and int(a.shells) == 5:
			_check(int(b.shells) == (5 if candidate.rollback else 0), candidate.name + " ordinary settled boundary defers five shell builds", {"baseline": a, "candidate": b})

func _formal(script: Script, name: String) -> Dictionary:
	var made := _make(script, "formal", 1337)
	var world: Node3D = made.world
	_check(world.resident_rooms.size() == 5, name + " formal shells remain all synchronous")
	world.ensure_room_ready(Vector2i(0, -2))
	world.complete_pending_streaming()
	await process_frame
	var state := await _capture(world, made.trace, "formal")
	world.free()
	await process_frame
	return state

func _startup_rapid(script: Script, name: String) -> Dictionary:
	var made := _make(script, "expanded", 250821)
	var world: Node3D = made.world
	var calls: Array = []
	var jobs: Array = []
	_near_ready(world, name + " unfinished startup")
	for x in [16.1, 15.9, 16.1]:
		_update(world, Vector3(x, 0.6, 0), calls, "unfinished_startup_reversal")
		await _boundary_floor(world, x, 0, name + " unfinished startup boundary")
	await _drain(world, jobs, "unfinished_startup_reversal")
	var state := await _capture(world, made.trace, "unfinished_startup_reversal")
	world.free()
	await process_frame
	return {"state": state, "calls": calls, "jobs": jobs}

func _phase_costs(record: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in record.calls:
		if not result.has(row.phase): result[row.phase] = {"request_ms": 0.0, "request_shells": 0, "job_ms": 0.0, "max_job_ms": 0.0, "job_shells": 0, "job_interiors": 0, "jobs": 0}
		result[row.phase].request_ms += row.ms
		result[row.phase].request_shells += row.shells
	for row: Dictionary in record.jobs:
		if not result.has(row.phase): result[row.phase] = {"request_ms": 0.0, "request_shells": 0, "job_ms": 0.0, "max_job_ms": 0.0, "job_shells": 0, "job_interiors": 0, "jobs": 0}
		result[row.phase].job_ms += row.ms
		result[row.phase].max_job_ms = maxf(result[row.phase].max_job_ms, row.ms)
		result[row.phase].job_shells += row.shells
		result[row.phase].job_interiors += row.interiors
		result[row.phase].jobs += 1
	return result

func _run() -> void:
	started = Time.get_ticks_usec()
	_check(FileAccess.get_sha256(BASELINE_PATH) == BASELINE_SHA256, "frozen baseline source is exact pre-edit 4876a68")
	baseline = GDScript.new()
	# The only evaluation transformation removes the global class registration;
	# every scheduler statement remains byte-for-byte baseline source.
	baseline.source_code = FileAccess.get_file_as_string(BASELINE_PATH).replace("class_name PoolWorld\n", "")
	_check(baseline.reload() == OK, "frozen baseline compiles without duplicate global class registration")
	staged_script = GDScript.new()
	staged_script.source_code = FileAccess.get_file_as_string(STAGED_PATH).replace("class_name PoolWorld\n", "")
	_check(staged_script.reload() == OK, "experimental staged snapshot compiles without production file edits")
	_check(FileAccess.get_sha256("res://scripts/world/pool_world.gd") == BASELINE_SHA256, "production PoolWorld remains exact baseline while testing opt-in candidate")
	library = Materials.new()
	for spec: Dictionary in [{"mode": "original", "seed": 1337}, {"mode": "expanded", "seed": 250821}, {"mode": "poolrooms", "seed": 250821}]:
		var a := await _case(baseline, spec.mode + "_baseline", spec.mode, spec.seed)
		var b := await _case(staged_script, spec.mode + "_staged", spec.mode, spec.seed)
		_compare(a, b)
		a.phase_costs = _phase_costs(a)
		b.phase_costs = _phase_costs(b)
		records.append(a)
		records.append(b)
	var rollback := await _case(staged_script, "expanded_rollback", "expanded", 250821, true)
	_compare(records[2], rollback)
	rollback.phase_costs = _phase_costs(rollback)
	records.append(rollback)
	var early_a := await _startup_rapid(baseline, "baseline")
	var early_b := await _startup_rapid(staged_script, "candidate")
	_check(early_a.state.rooms == early_b.state.rooms and early_a.state.load_events == early_b.state.load_events and early_a.state.near_optical_bytes_sha256 == early_b.state.near_optical_bytes_sha256, "unfinished startup reversals preserve final exact room and optical inputs plus completion order")
	var formal_a := await _formal(baseline, "baseline")
	var formal_b := await _formal(staged_script, "candidate")
	_check(formal_a.rooms == formal_b.rooms and formal_a.load_events == formal_b.load_events and formal_a.near_optical_bytes_sha256 == formal_b.near_optical_bytes_sha256, "formal exact geometry layout early-travel publication order and optical bytes unchanged")
	var report := {"pass": failures.is_empty(), "checks": checks.size(), "failures": failures, "engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0, "snapshot_ms": snapshot_ms, "scope": "CPU-headless production World/Builder/Material comparison against exact frozen pre-edit source. Main-thread method timings exclude shader rendering, water runtime callbacks, RT/FG and target-PC frame time. Controlled process jobs and position inputs, not Player locomotion.", "timing_limits": "One controlled run per mode. Initial baseline asset loads may be cold and candidate cached, so startup timings are not an isolated speed comparison. Ordinary crossing assets are already resident/cached in both. Shell work moves into subsequent atomic jobs; phase_costs reports that work. Snapshot/hash/assertion overhead is outside measured method calls.", "water_integration": "Actual SourceRoomSnapshot collector compares collider/solid/triangle values and room_loaded/live insertion order at settled checkpoints. No SourceWaterRuntime, GPU preparation, capture or simulation dispatch is executed; rapid navigation's transient optical publication timing requires integration validation.", "baseline_sha256": FileAccess.get_sha256(BASELINE_PATH), "candidate_sha256": FileAccess.get_sha256(STAGED_PATH), "production_sha256": FileAccess.get_sha256("res://scripts/world/pool_world.gd"), "fixture_sha256": FileAccess.get_sha256("res://tests/room_transition/shell_staging_contract.gd"), "records": records, "unfinished_startup": {"baseline": early_a, "candidate": early_b}, "formal": {"baseline": formal_a, "candidate": formal_b}, "assertions": checks}
	var output := "/tmp/poolcore-transition-rt/shell-staging.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()
	else: failures.append("Could not save report " + output)
	print("SHELL_STAGING_CONTRACT ", JSON.stringify({"pass": failures.is_empty(), "checks": checks.size(), "failures": failures, "elapsed_ms": report.elapsed_ms, "snapshot_ms": snapshot_ms, "report": output, "scope": report.scope}))
	quit(0 if failures.is_empty() else 1)
