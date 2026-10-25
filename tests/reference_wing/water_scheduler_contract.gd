extends SceneTree
const Runtime = preload("res://scripts/reference_wing/reference_scene_water_runtime.gd")
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
var checks := {}
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func check(label: String, valid: bool) -> void:
	checks[label] = valid
	if not valid: failures.append(label)

func fixture() -> Node3D:
	var water := Runtime.new()
	for coord: Vector2i in Catalog.COORDS: water._layouts[coord] = Catalog.room_layout(coord, 250821).duplicate(true)
	root.add_child(water)
	return water

func job(water: Node3D, coord := Vector2i(1, -2)) -> Dictionary:
	var values := PackedFloat32Array(); values.resize(water.solver.size * water.solver.size); values.fill(99.0)
	return {"value": {"coord": coord, "size": water.solver.size, "domain": 96.0, "origin": Vector2(coord) * 32.0, "revision": 1,
		"depth_data": values, "packed_bvh": {"sentinel": 1}, "masks": [], "timing_ms": {}},
		"key": water._terrain_key(coord), "identity": {"sentinel": 7}, "force": water._terrain_force_revision}

func drain(water: Node3D) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while water.preparation_pending() and Time.get_ticks_msec() < deadline:
		water._advance_terrain()
		await create_timer(0.001).timeout
	return not water.preparation_pending()

func _run() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("CPU-only scheduler contract requires dummy renderer."); quit(2); return
	var water := fixture()
	var first := job(water)
	var second := job(water, Vector2i(0, -1))
	check("identity_hash_is_idempotent", first.key == water._terrain_key(first.value.coord))
	water.source_results = [first, second]
	water._advance_terrain()
	check("two_source_completions_are_bounded", water._reference_depth_thread != null and water._reference_depth_jobs.size() == 1)
	check("internal_suspend_latch_is_restored", not water._prepare_suspended)
	check("no_duplicate_source_job_before_corrected_publish", water.duplicate_launches == 0)
	check("pending_covers_authored_thread_and_queue", water.preparation_pending())
	var status: Dictionary = water.get_preparation_status()
	check("status_reports_authored_stage", status.stage == "authored_polygon_depth" and status.worker_count == 1 and status.reference_depth_queued == 1)
	water.suspend_preparation(true)
	check("suspended_corrections_drain_without_new_source_jobs", await drain(water))
	check("user_suspension_survives_both_completions", water._prepare_suspended and water.duplicate_launches == 0)
	check("both_results_reach_source_accept_once", water.source_accepts.size() == 2)
	check("corrected_depth_does_not_mutate_source_payload", first.value.depth_data[0] == 99.0 and water.source_accepts[0].value.depth_data[0] != 99.0)
	check("source_bvh_payload_is_preserved", water.source_accepts[0].value.packed_bvh == first.value.packed_bvh)
	water.suspend_preparation(false)
	var old_key: String = first.key
	water._layouts[Vector2i(1, -2)].geometry_contract.water_regions[0].bottom_y = -0.42
	water._terrain_keys.clear()
	check("profile_revision_changes_depth_identity", old_key != water._terrain_key(Vector2i(1, -2)))
	water._accept_terrain_result(first.value, first.key, first.identity, first.force)
	check("old_profile_key_rejected_before_worker", water._reference_depth_jobs.is_empty() and water._reference_depth_thread == null and water._terrain_metrics.stale_results == 1)
	var current := job(water)
	water._accept_terrain_result(current.value, current.key, current.identity, current.force + 1)
	var wrong_size: Dictionary = current.value.duplicate(true); wrong_size.size += 1
	water._accept_terrain_result(wrong_size, current.key, current.identity, current.force)
	check("force_and_quality_stale_rejected_before_worker", water._reference_depth_jobs.is_empty() and water._terrain_metrics.stale_results == 3)
	var incomplete: Dictionary = current.value.duplicate(true); incomplete.erase("origin")
	water._accept_terrain_result(incomplete, current.key, current.identity, current.force)
	check("incomplete_payload_rejected_before_correction_worker", water._reference_depth_jobs.is_empty() and water.source_errors.size() == 1)
	# Keep the remaining scheduler assertions independent even on a failing
	# preflight guard; never actually launch a known malformed CPU payload.
	water._reference_depth_jobs.clear(); water._prepare_suspended = false
	water.source_results = [current]; water._advance_terrain()
	var captured_bottom: float = water._reference_depth_current.profiles[2].bottom
	water._layouts[Vector2i(1, -2)].geometry_contract.water_regions[0].bottom_y = -0.62
	check("queued_profiles_are_immutable_values", water._reference_depth_current.profiles[2].bottom == captured_bottom)
	water._terrain_force_revision += 1
	check("force_revision_during_correction_drains", await drain(water))
	check("force_revision_during_correction_never_publishes", water.source_accepts.size() == 2 and water._terrain_metrics.stale_results == 4)
	water._terrain_keys.clear()
	var quality_job := job(water)
	water.source_results = [quality_job]; water._advance_terrain()
	water.solver.size += 32
	check("quality_change_during_worker_drains", await drain(water))
	check("quality_change_during_worker_never_publishes", water.source_accepts.size() == 2 and water._terrain_metrics.stale_results == 5)
	water.dispose(); water.queue_free(); await process_frame

	water = fixture()
	var room := Node3D.new(); root.add_child(room)
	var coord := Vector2i(1, -2)
	water.add_room(room, coord, water._layouts[coord])
	await process_frame
	var group: Node3D = water._surfaces[coord]
	check("new_basin_is_arraymesh", group.get_child_count() == 1 and group.get_child(0).mesh is ArrayMesh)
	for tier: String in ["High", "Ultra", "Low", "High"]:
		water.set_quality(tier)
		await process_frame
		check("quality_" + tier + "_keeps_exact_surface", water._surfaces[coord] == group and group.get_child_count() == 1 and group.get_child(0).mesh is ArrayMesh)
	check("source_quality_never_sees_arraymesh_cast", not water.source_arraymesh_seen and water.source_quality_calls == 4)
	check("quality_rebuild_restores_visibility", water.visibility_refreshes == 4)
	var quality_calls: int = water.source_quality_calls
	water.set_quality("High"); water.set_quality("NotAQuality")
	check("same_or_invalid_quality_has_no_rebuild", water.source_quality_calls == quality_calls)
	water._terrain_keys.clear()
	water.source_results = [job(water)]; water._advance_terrain()
	check("disposal_has_pending_authored_job", water.preparation_pending())
	water.dispose()
	check("disposal_joins_and_clears_owned_work", water._reference_depth_thread == null and water._reference_depth_jobs.is_empty() and water._reference_depth_current.is_empty() and water._disposed)
	water.dispose()
	check("repeated_disposal_is_idempotent", water.source_dispose_calls == 1)
	water.queue_free(); room.queue_free(); await process_frame
	print("REFERENCE_WATER_SCHEDULER ", JSON.stringify({"passed": failures.is_empty(), "failures": failures, "checks": checks, "gpu_run": false,
		"scope": "Actual new scene adapter and real CPU correction threads against an isolated source scheduler double; no solver or caustic GPU dispatch."}))
	quit(0 if failures.is_empty() else 1)
