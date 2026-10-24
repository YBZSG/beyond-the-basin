extends "res://tests/room_transition/rt_production_stream_contract.gd"
## Compare actual pre/post-stream snapshots, not a synthetic node population.
const OldScan = preload("res://tests/room_transition/rt_material_refresh_contract.gd")
const REPETITIONS := 8
const BASELINE_WORLD_SHA256 := "a0ebc2d9a49b359b57e1f2887288d326f22c5c78da46cd44bec3a3e69e74cd5b"
const PARAMETERS := ["source_domain_origin", "repeat_metres", "pigment", "normal_strength", "base_color", "scan_albedo", "normal_gl", "scan_normal", "orm", "scan_roughness", "coat_strength", "glazed_ceramic"]

func _geometry() -> Dictionary:
	var result: Dictionary = {}
	for node: GeometryInstance3D in host.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_queued_for_deletion(): result[node.get_instance_id()] = weakref(node)
	return result

func _material_state() -> Dictionary:
	var collected := _materials_and_geometry()
	var result: Dictionary = {}
	for value in collected.materials:
		if not value is ShaderMaterial or value.shader == null: continue
		var parameters: Dictionary = {}
		for parameter: String in PARAMETERS:
			var item: Variant = value.get_shader_parameter(parameter)
			parameters[parameter] = [item.get_instance_id(), item.resource_path] if item is Resource else item
		result[str(value.get_instance_id())] = {"shader": value.shader.resource_path, "parameters": parameters}
	return result

func _restore(rows: Array[Dictionary]) -> void:
	for row: Dictionary in rows:
		var material: ShaderMaterial = row.material
		material.shader = row.shader

func _stats(rows: Array[Dictionary], key: String) -> Dictionary:
	var sorted: Array[float] = []
	var total := 0.0
	for row: Dictionary in rows:
		var number := float(row[key])
		sorted.append(number)
		total += number
	sorted.sort()
	return {"samples": sorted.size(), "mean_ms": total / sorted.size(), "median_ms": sorted[sorted.size() / 2], "min_ms": sorted[0], "max_ms": sorted[-1]}

func _benchmark_batch(label: String, before: Dictionary, creation_ms: float) -> Dictionary:
	var now := _geometry()
	var entering: Array[GeometryInstance3D] = []
	var entering_ids: Array[int] = []
	for identity: int in now:
		if not before.has(identity):
			entering.append(now[identity].get_ref())
			entering_ids.append(identity)
	var collected := _materials_and_geometry()
	var original_shaders: Array[Dictionary] = []
	var material_ids: Array[int] = []
	for value in collected.materials:
		material_ids.append(value.get_instance_id())
		if value is ShaderMaterial: original_shaders.append({"material": value, "shader": value.shader})
	material_ids.sort()
	var baseline_rows: Array[Dictionary] = []
	var candidate_rows: Array[Dictionary] = []
	var reference_state: Dictionary = {}
	for repetition in REPETITIONS:
		var baseline_state: Dictionary = {}
		var candidate_state: Dictionary = {}
		for ordering in 2:
			# Restore the exact shader objects from the real pre-refresh snapshot.
			# Shared resident materials stay RT; actual newly authored locals return
			# to raster. No artificial new material or synthetic geometry is added.
			_restore(original_shaders)
			if (repetition + ordering) % 2 == 0:
				var old := OldScan._baseline_exact(host, true)
				old.repetition = repetition
				baseline_rows.append(old)
				baseline_state = _material_state()
			else:
				var queue_started := Time.get_ticks_usec()
				for node: GeometryInstance3D in entering: router.queue_node(node)
				var queue_ms := float(Time.get_ticks_usec() - queue_started) / 1000.0
				var flush_started := Time.get_ticks_usec()
				router.refresh_pending(true)
				var flush_call_ms := float(Time.get_ticks_usec() - flush_started) / 1000.0
				var current: Dictionary = router.get_stats().last
				current.repetition = repetition
				current.queue_ms = queue_ms
				current.flush_call_ms = flush_call_ms
				current.queue_and_flush_ms = queue_ms + flush_call_ms
				candidate_rows.append(current)
				candidate_state = _material_state()
		_check(baseline_state == candidate_state, "%s repetition %d exact same material IDs shader output and selected texture/parameter state" % [label, repetition])
		if repetition == 0: reference_state = baseline_state
		_check(reference_state == baseline_state, "%s repetition %d preserves identical scene/material snapshot" % [label, repetition])
		_check(int(candidate_rows[-1].geometry_visited) == entering.size() and int(baseline_rows[-1].geometry_visited) == int(collected.geometry_count), "%s repetition %d actual old versus entering-only traversal counts" % [label, repetition])
	_check(router.get_stats().pending_nodes == 0, label + " queue drains after every repeated flush")
	var result := {"phase": label, "world_construction_ms_outside_comparison": creation_ms, "resident_rooms": world.resident_rooms.size(), "actual_geometry": collected.geometry_count, "entering_geometry": entering.size(), "entering_node_ids": entering_ids, "unique_materials": collected.materials.size(), "material_ids": material_ids, "local_receiver_refs": host.materials._local_receiver_refs.size(), "baseline": baseline_rows, "candidate": candidate_rows, "baseline_total": _stats(baseline_rows, "total_ms"), "candidate_queue_and_flush_total": _stats(candidate_rows, "queue_and_flush_ms"), "world_profile": world.profile_counters.duplicate(true)}
	return result

func _run() -> void:
	started = Time.get_ticks_usec()
	_check(FileAccess.get_sha256("res://scripts/world/pool_world.gd") == BASELINE_WORLD_SHA256, "production shell scheduling is exact 4876a68, not staged candidate")
	host = Host.new()
	root.add_child(host)
	host.materials = Materials.new()
	router.configure(host)
	world = World.new()
	world.expanded_mode = true
	host.add_child(world)
	world.set_process(false)
	world.initialize(250821, host.materials)
	while not world._queue.is_empty():
		world._process(1.0 / 60.0)
		await process_frame
	await process_frame
	router.refresh_all(true)
	_inspect("benchmark_initial_rt", true)
	var results: Array[Dictionary] = []
	var before := _geometry()
	world.update_player_position(Vector3(15.9, 0.6, 0))
	var construct_started := Time.get_ticks_usec()
	world.update_player_position(Vector3(16.0, 0.6, 0))
	var construction_ms := float(Time.get_ticks_usec() - construct_started) / 1000.0
	await process_frame
	results.append(_benchmark_batch("actual_five_entering_shells", before, construction_ms))
	var jobs := 0
	while not world._queue.is_empty() and jobs < 5:
		before = _geometry()
		construct_started = Time.get_ticks_usec()
		world._process(1.0 / 60.0)
		construction_ms = float(Time.get_ticks_usec() - construct_started) / 1000.0
		await process_frame
		results.append(_benchmark_batch("actual_interior_job_%d" % jobs, before, construction_ms))
		jobs += 1
	_check(jobs == 5 and world._queue.is_empty() and world.resident_rooms.size() == 25, "all five actual interior jobs finish with original residency")
	_inspect("benchmark_final_rt", true)
	router.refresh_all(false)
	_inspect("benchmark_final_raster", false)
	var report := {"pass": failures.is_empty(), "checks": checks.size(), "failures": failures, "engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "hardware_rt_enabled": false, "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0, "scope": "Actual production Expanded PoolWorld/RoomBuilder/PoolMaterials, unchanged baseline synchronous shells, exact old material scan versus incremental queue on the same live scene and material IDs. Eight alternating repetitions per real shell/interior batch. CPU-headless only; no water, lights/probes, GPU RT, DLSS/FG or game frame-time claim.", "measurement": "Each variant restores original shader Resource objects from that batch's actual pre-refresh snapshot. Scene creation, shader restoration, full verification scans, parameter inspection, and retirement are outside timed calls. Candidate includes queueing and external flush-call duration. Entrant nodes that were created then freed during atomic construction are absent from the settled snapshot; this compares the live material work, not construction-time node-added callback overhead.", "batches": results, "phases": phases, "router": router.get_stats(), "assertions": checks, "source_sha256": {}}
	for path: String in ["scripts/world/pool_world.gd", "scripts/rendering/rt_material_refresh.gd", "tests/room_transition/rt_material_refresh_contract.gd", "tests/room_transition/rt_real_world_benchmark.gd"]: report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	var output := "/tmp/poolcore-transition-rt/rt-real-world-benchmark.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()
	else: failures.append("Cannot save report " + output)
	var summary: Array = []
	for result: Dictionary in results: summary.append({"phase": result.phase, "geometry": result.actual_geometry, "entering": result.entering_geometry, "baseline": result.baseline_total, "candidate": result.candidate_queue_and_flush_total})
	print("RT_REAL_WORLD_BENCHMARK ", JSON.stringify({"pass": failures.is_empty(), "checks": checks.size(), "failures": failures, "elapsed_ms": report.elapsed_ms, "batches": summary, "report": output}))
	host.free()
	quit(0 if failures.is_empty() else 1)
