extends SceneTree
## NR execution is verified by the native log and paired input/output, not UI flags.
var destination := ""
var test_case := "timing"
var capture_prefix := ""
var report: Dictionary = {"errors": [], "benchmarks": {}}

func _initialize() -> void:
	capture_prefix = OS.get_environment("POOLCORE_NR_CAPTURE")
	OS.set_environment("POOLCORE_NR_CAPTURE", "")
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

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.save_png(destination.path_join(name)) != OK: report.errors.append("Capture failed: " + name)

func _inspect(game: Node3D) -> int:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var panel := game.get_node("DesktopQuality")
	panel.set_option("frame_generation", false)
	panel.set_option("raytracing", test_case == "rr")
	panel.set_option("dlss", "DLAA")
	game.set_menu(false)
	game.props.set_enabled(false)
	for body in game.props.bodies: body.freeze = true
	game.player.warp_to(Vector3(0, -0.70, 12), Vector3(0, -0.70, 0))
	game.player.camera.rotation.x = -0.42
	game.player.set_enabled(false)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for frame in 180: await process_frame
	if not capture_prefix.is_empty(): OS.set_environment("POOLCORE_NR_CAPTURE", capture_prefix)
	report.device = RenderingServer.get_video_adapter_name()
	report.nr_requested = OS.get_environment("POOLCORE_DLSS_NR") == "1"
	report.settings = panel.settings.duplicate()
	report.frame_generation = root.get("frame_generation")
	if bool(report.frame_generation): report.errors.append("FG must be off for NR isolation")
	var samples: Array[float] = []
	var gpu: Array[float] = []
	var previous := Time.get_ticks_usec()
	var start := previous
	for frame in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	var elapsed := float(previous - start) / 1000.0
	samples.sort()
	gpu.sort()
	report.benchmarks = {"frames": samples.size(), "elapsed_ms": elapsed, "fps": samples.size() * 1000.0 / elapsed, "median_frame_ms": samples[samples.size() / 2], "p95_frame_ms": samples[int(samples.size() * 0.95)], "median_main_viewport_gpu_ms": gpu[gpu.size() / 2], "note": "300 uncapped frames after 180 warmup; paired-readback runs must not be used as timing evidence"}
	await _capture("pool.png")
	if test_case == "controls":
		for mode: String in ["Quality", "Off", "DLAA"]:
			panel.set_option("dlss", mode)
			for frame in 45: await process_frame
			await _capture("mode-" + mode + ".png")
		var old_size := root.size
		root.size = Vector2i(1600, 900)
		for frame in 60: await process_frame
		await _capture("resize-1600.png")
		root.size = old_size
		for frame in 60: await process_frame
		await _capture("resize-restored.png")
		game.player.set_enabled(true)
		var before: Vector3 = game.player.global_position
		Input.action_press("move_forward")
		for frame in 100:
			game.player.camera.rotation.y += 0.003
			await process_frame
		Input.action_release("move_forward")
		report.walk_distance = game.player.global_position.distance_to(before)
		if float(report.walk_distance) < 0.5: report.errors.append("Wading did not move")
		await _capture("wading-turn.png")
		game.player.set_enabled(false)
		game.set_menu(true)
		panel.open_panel()
		for frame in 20: await process_frame
		await _capture("hud.png")
	report.water = game.water.debug_stats()
	if not game.water.last_error.is_empty(): report.errors.append(game.water.last_error)
	report.pass = report.errors.is_empty()
	FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("DLSS_NR_QA_RESULT ", JSON.stringify(report))
	return 0 if report.pass else 1
