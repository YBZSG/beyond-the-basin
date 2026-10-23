extends SceneTree
## Real GPU checks. Benchmarks use wall time, with no screenshot readback in the measured interval.
var destination := ""
var test_case := "controls"
var report: Dictionary = {"errors":[], "modes":[], "benchmarks":{}}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dlss-out="): destination = arg.trim_prefix("--dlss-out=")
		if arg.begins_with("--dlss-case="): test_case = arg.trim_prefix("--dlss-case=")
	var isolated := OS.get_environment("APPDATA").replace("\\", "/")
	if destination.is_empty() or not isolated.contains("/output/dlss/") or not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	game.qa_capture_hook = _inspect
	root.add_child(game)

func _check(condition: bool, message: String) -> void:
	if not condition: report.errors.append(message)

func _inspect(game: Node3D) -> int:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	report.device = RenderingServer.get_video_adapter_name()
	report.engine = Engine.get_version_info()
	report.output_size = root.size
	report.case = test_case
	var panel := game.get_node("DesktopQuality")
	report.support = panel.dlss_support()
	var original: Dictionary = panel.settings.duplicate()
	var config := ConfigFile.new()
	_check(config.load("user://settings.cfg") == OK, "Missing isolated water settings")
	report.water_overrides = config.get_value("water", "settings", {})
	for key: String in report.water_overrides:
		game.water.set_tuning(key, report.water_overrides[key])
	# The desktop panel owns the final cadence, after legacy water settings load.
	game.water.set_tuning("causticsRefresh", int(original.caustic_interval))
	game.set_menu(false)
	game.props.set_enabled(false)
	for body in game.props.bodies:
		body.freeze = true
	game.player.warp_to(Vector3(0, -0.70, 12), Vector3(0, -0.70, 0))
	game.player.camera.rotation.x = -0.42
	game.player.set_enabled(false)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	panel.set_option("dlss", "Balanced")
	panel.set_option("frame_generation", false)
	panel.set_option("raytracing", false)
	for frame in 60: await process_frame
	if test_case == "fallback":
		panel.set_option("frame_generation", true)
		panel.set_option("raytracing", true)
		_check(not panel.frame_generation_status.active, "FG should fall back")
		_check(not panel.raytracing_status.active, "RT should fall back")
	else:
		_check(bool(report.support.available), "DLSS unavailable")
		_check(bool(panel.frame_generation_status.available), "FG unavailable")
		_check(bool(panel.raytracing_status.available), "RT unavailable")
		for mode: String in ["raster", "fg", "rt-fg"]:
			panel.set_option("frame_generation", mode != "raster")
			panel.set_option("raytracing", mode == "rt-fg")
			for frame in 240: await process_frame
			DisplayServer.window_move_to_foreground()
			for frame in 60: await process_frame
			print("POOLCORE_MEASURE_BEGIN ", mode)
			report.benchmarks[mode] = await _benchmark(10.0)
			print("POOLCORE_MEASURE_END ", mode)
			var instances := int(root.call("get_render_info", 0, ClassDB.class_get_integer_constant("Viewport", "RENDER_INFO_RT_TLAS_INSTANCES")))
			_check(instances > 0 if mode == "rt-fg" else instances == 0, "Unexpected RT instance count: " + mode)
			report.modes.append({"mode":mode, "fg":panel.frame_generation_status.duplicate(), "rt":panel.raytracing_status.duplicate(), "rt_instances":instances})
			await _capture(mode + ".png")
		# Actual controller movement with RT, avatar and animated water.
		game.player.camera.rotation.x = -0.85
		game.player.set_enabled(true)
		var position_before: Vector3 = game.player.global_position
		Input.action_press("move_forward")
		var walk_start := Time.get_ticks_usec()
		var index := 0
		while Time.get_ticks_usec() - walk_start < 3000000:
			await process_frame
			if Time.get_ticks_usec() - walk_start > index * 500000:
				await _capture("walk-%02d.png" % index)
				index += 1
		Input.action_release("move_forward")
		game.player.set_enabled(false)
		report.walk_distance_m = game.player.global_position.distance_to(position_before)
		_check(report.walk_distance_m > 1.0, "Wading blocked")
		game.player.camera.rotation.x = -1.45
		for frame in 30: await process_frame
		await _capture("avatar-feet-rt.png")
		# Exercise new room materials and skinned BLAS lifetimes while tracing.
		game.travel_to(Vector2i(1, 0))
		game.world.complete_pending_streaming()
		for frame in 180: await process_frame
		_check(bool(game.environment.environment.get("pathtracing_enabled")), "RT lost during room travel")
		await _capture("rt-next-room.png")
		# Restore raster, and exercise swap-chain re-creation while FG is requested.
		panel.set_option("raytracing", false)
		root.size = Vector2i(1600, 900)
		for frame in 150: await process_frame
		await _capture("resize-fg.png")
		root.size = Vector2i(1920, 1080)
		for frame in 150: await process_frame
		panel.set_option("dlss", "Off")
		for frame in 60: await process_frame
		_check(not panel.frame_generation_status.active and not panel.raytracing_status.active, "DLSS Off did not disable dependents")
		_check(not bool(root.get("frame_generation")), "Viewport still requests FG")
		panel.set_option("dlss", "Balanced")
		for frame in 150: await process_frame
		_check(bool(root.get("frame_generation")), "FG did not restore")
		var before_reload: Dictionary = panel.settings.duplicate()
		panel.load_settings()
		_check(panel.settings == before_reload, "Settings reload mismatch")
		game.set_menu(true)
		panel.open_panel()
		for frame in 30: await process_frame
		await _capture("settings.png")
		panel.close_panel()
	report.avatar = game.avatar.get_debug_state()
	report.water = game.water.debug_stats()
	_check(bool(report.avatar.loaded), "Player model missing")
	_check(int(report.avatar.bone_count) == 54, "New hand rig missing")
	_check(bool(report.avatar.water_actions_ready), "Water action animations missing")
	_check(bool(report.avatar.finger_pose.get("valid", false)), "Finger pose resource missing")
	_check(game.water.last_error.is_empty(), "Water error: " + game.water.last_error)
	_check(str(report.water.caustic_error).is_empty(), "Caustics error")
	_check(int(report.water.liquid.domains) == 0, "Unexpected active splash simulation")
	report.pass = report.errors.is_empty()
	FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("DLSS_QA_RESULT ", JSON.stringify({"pass":report.pass, "errors":report.errors, "modes":report.modes}))
	return 0 if report.pass else 1

func _benchmark(seconds: float) -> Dictionary:
	var frame_ms: Array[float] = []
	var focused_frames := 0
	var gpu_ms: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while float(Time.get_ticks_usec() - start) / 1000000.0 < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		if DisplayServer.window_is_focused(): focused_frames += 1
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	var total := float(previous - start) / 1000.0
	frame_ms.sort()
	gpu_ms.sort()
	return {"focused_frames":focused_frames, "frames":frame_ms.size(), "elapsed_ms":total, "fps":frame_ms.size() * 1000.0 / total, "median_frame_ms":frame_ms[frame_ms.size() / 2], "p95_frame_ms":frame_ms[int(frame_ms.size() * 0.95)], "median_main_viewport_gpu_ms":gpu_ms[gpu_ms.size() / 2], "frame_ms":frame_ms, "note":"Uncapped realtime wall clock; stationary original pool, current user water settings, props frozen; main viewport GPU time excludes other viewports and standalone water compute."}

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.get_format() in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]:
		var display := Image.create(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
		for y in picture.get_height():
			for x in picture.get_width(): display.set_pixel(x, y, picture.get_pixel(x, y).linear_to_srgb())
		picture = display
	_check(picture.save_png(destination.path_join(name)) == OK, "Capture failed: " + name)
