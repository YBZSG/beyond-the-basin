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
	if bool(report.support.available):
		report.frame_generation = root.get("frame_generation")
		_check(bool(report.frame_generation) == bool(panel.frame_generation_status.active), "FG state mismatch")
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
	if test_case == "controls" or test_case == "fallback":
		_check(bool(report.support.available) == (test_case == "controls"), "Unexpected DLSS device capability")
		for mode: String in ["Off", "Quality", "Balanced", "Performance", "DLAA", "Off", "Quality"]:
			panel.set_option("dlss", mode)
			for frame in 30: await process_frame
			var active := bool(report.support.available) and mode != "Off"
			_check(bool(panel.dlss_status.active) == active, "Incorrect active state: " + mode)
			_check(root.use_taa == (bool(original.taa) and not active), "TAA conflict: " + mode)
			_check(int(root.msaa_3d) == (0 if active else int(original.msaa)), "MSAA conflict: " + mode)
			_check(is_equal_approx(root.scaling_3d_scale, float(panel.DLSS_SCALES[mode]) if active else float(original.scale)), "Wrong scale: " + mode)
			_check(int(root.scaling_3d_mode) == (int(report.support.mode) if active else 0), "Wrong scaling mode: " + mode)
			for key: String in original:
				if key != "dlss": _check(panel.settings[key] == original[key], "Changed unrelated setting: " + key)
			report.modes.append({"requested":mode, "status":panel.dlss_status.duplicate(), "msaa":root.msaa_3d, "taa":root.use_taa})
			await _capture("mode-" + mode + ".png")
		# Exercise TAA history at both below-native and supersampled resolutions.
		panel.set_option("dlss", "Off")
		for scale_value: float in [0.75, 1.25]:
			panel.set_option("scale", scale_value)
			for frame in 30: await process_frame
			_check(is_equal_approx(root.scaling_3d_scale, scale_value), "Native scale did not apply")
			await _capture("native-%d.png" % roundi(scale_value * 100.0))
		panel.set_option("scale", original.scale)
		panel.set_option("dlss", "Quality")
		var original_size := root.size
		root.size = Vector2i(1600, 900)
		for frame in 30: await process_frame
		await _capture("resized.png")
		root.size = original_size
		for frame in 30: await process_frame
		# Simulate the host reapplying legacy AA after rebuilding the world.
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 1.25
		root.msaa_3d = Viewport.MSAA_8X
		root.use_taa = true
		panel.apply_settings()
		_check(int(root.scaling_3d_mode) == (int(report.support.mode) if report.support.available else 0), "Lost DLSS after host reapplied AA")
		var requested: Dictionary = panel.settings.duplicate()
		panel.load_settings()
		_check(panel.settings == requested, "Settings did not survive reload")
		game.set_menu(true)
		panel.open_panel()
		for frame in 30: await process_frame
		_check(panel._panel.visible, "Graphics panel did not stay open")
		_check(panel._options.dlss.disabled != bool(report.support.available), "Incorrect availability in menu")
		_check(panel._checks.taa.disabled == bool(report.support.available), "TAA menu conflicts with DLSS")
		await _capture("settings.png")
		panel.close_panel()
	else:
		_check(bool(report.support.available), "DLSS runtime unavailable")
		panel.set_option("dlss", test_case)
		for frame in 120: await process_frame
		report.settings = panel.settings.duplicate()
		report.status = panel.dlss_status.duplicate()
		report.benchmarks.pool = await _benchmark(12.0)
		await _capture("pool.png")
		# Realtime walking samples are separate from the stationary benchmark.
		game.player.camera.rotation.x = -0.85
		game.player.set_enabled(true)
		var walk_position: Vector3 = game.player.global_position
		Input.action_press("move_forward")
		var walk_start := Time.get_ticks_usec()
		var next_capture := 0.0
		var index := 0
		while float(Time.get_ticks_usec() - walk_start) / 1000000.0 < 3.0:
			await process_frame
			if float(Time.get_ticks_usec() - walk_start) / 1000000.0 >= next_capture:
				await _capture("walk-%02d.png" % index)
				index += 1
				next_capture += 0.20
		Input.action_release("move_forward")
		game.player.set_enabled(false)
		report.walk_end = game.player.get_status()
		report.walk_distance_m = game.player.global_position.distance_to(walk_position)
		_check(float(report.walk_distance_m) > 1.0, "Wading movement was blocked")
	report.avatar = game.avatar.get_debug_state()
	report.water = game.water.debug_stats()
	_check(bool(report.avatar.loaded), "Player model missing")
	_check(game.water.last_error.is_empty(), "Water error: " + game.water.last_error)
	_check(str(report.water.caustic_error).is_empty(), "Caustics error")
	_check(int(report.water.liquid.domains) == 0, "Unexpected active splash simulation")
	report.pass = report.errors.is_empty()
	FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("DLSS_QA_RESULT ", JSON.stringify({"pass":report.pass, "errors":report.errors, "benchmarks":report.benchmarks}))
	return 0 if report.pass else 1

func _benchmark(seconds: float) -> Dictionary:
	var frame_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while float(Time.get_ticks_usec() - start) / 1000000.0 < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	var total := float(previous - start) / 1000.0
	frame_ms.sort()
	gpu_ms.sort()
	return {"frames":frame_ms.size(), "elapsed_ms":total, "fps":frame_ms.size() * 1000.0 / total, "median_frame_ms":frame_ms[frame_ms.size() / 2], "p95_frame_ms":frame_ms[int(frame_ms.size() * 0.95)], "median_main_viewport_gpu_ms":gpu_ms[gpu_ms.size() / 2], "frame_ms":frame_ms, "note":"Uncapped realtime wall clock; stationary original pool, current user water settings, props frozen; main viewport GPU time excludes other viewports and standalone water compute."}

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.get_format() in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]:
		var display := Image.create(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
		for y in picture.get_height():
			for x in picture.get_width(): display.set_pixel(x, y, picture.get_pixel(x, y).linear_to_srgb())
		picture = display
	_check(picture.save_png(destination.path_join(name)) == OK, "Capture failed: " + name)
