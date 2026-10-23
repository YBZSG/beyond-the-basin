extends SceneTree
## Compare the original-room finish on an actual GPU, using the same cameras.
var destination := ""
var report: Dictionary = {"views": {}, "errors": []}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--finish-out="): destination = argument.trim_prefix("--finish-out=")
	var isolated := OS.get_environment("APPDATA").replace("\\", "/")
	if destination.is_empty() or not isolated.contains("/output/photoreal/") or not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	game.qa_capture_hook = _inspect
	root.add_child(game)

func _inspect(game: Node3D) -> int:
	report.device = RenderingServer.get_video_adapter_name()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.resolution = [root.size.x, root.size.y]
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	game.props.set_enabled(false)
	# Let the same room lighting transition and SDFGI settle before measuring.
	for i in 180: await process_frame
	await _view(game, "hall")
	game.player.warp_to(Vector3(14.2, 0.6, 6.0), Vector3(15.8, 0.7, 3.0))
	await _view(game, "ceramic")
	game.player.warp_to(Vector3(5.5, -0.95, 7), Vector3(-3, 0.8, -8))
	await _view(game, "waterline")
	game.travel_to(Vector2i(-1,-1))
	game.world.complete_pending_streaming()
	game.player.set_enabled(false)
	game.player.warp_to(Vector3(-22, -0.18, -20), Vector3(-36, 1.9, -42))
	for i in 180: await process_frame
	await _view(game, "oculus")
	var daylight_coord := Vector2i(0,-1) # Original high-arched daylight anchor.
	if game.world.get_layout(daylight_coord).get("daylight",false):
		game.travel_to(daylight_coord)
		game.world.complete_pending_streaming()
		game.player.set_enabled(false)
		var center := Vector3(daylight_coord.x*32,0,daylight_coord.y*32)
		game.player.warp_to(center+Vector3(10,-0.18,12),center+Vector3(-4,1.9,-10))
		var started := Time.get_ticks_msec()
		for i in 60: await process_frame
		while not game.water.is_terrain_ready() and Time.get_ticks_msec()-started<90000: await process_frame
		for i in 180: await process_frame
		await _view(game,"daylight")
	report.state = game.inspect_state()
	report.water = game.water.debug_stats()
	for capture in game._capture_distance_fogs:
		if not is_equal_approx(capture.density,game.distance_fog.density): report.errors.append("Reflected fog density differs from main camera")
	if not game.water.last_error.is_empty(): report.errors.append(game.water.last_error)
	if not str(report.water.caustic_error).is_empty(): report.errors.append(report.water.caustic_error)
	if not bool(report.water.planar_ready): report.errors.append("Planar reflection unavailable")
	if int(report.water.caustic_frames) == 0: report.errors.append("No caustics frames")
	FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SOURCE_FINISH_QA ", JSON.stringify(report.views))
	return 0 if report.errors.is_empty() else 1

func _view(game: Node3D, label: String) -> void:
	game.set_menu(false)
	game.player.set_enabled(false)
	game.props.set_enabled(false)
	var phase_before: float = game.water.wind_waves.elapsed
	for i in 90: await process_frame
	var times: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - previous) / 1000.0)
		previous = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	if game.water.wind_waves.elapsed <= phase_before: report.errors.append("Paused water during "+label)
	report.views[label] = {"frame":_summary(times),"main_viewport_gpu":_summary(gpu),"main_viewport_cpu_submit":_summary(cpu),"camera":str(game.player.camera.global_transform),"fog_density":game.distance_fog.density,"exposure":game.environment.environment.tonemap_exposure,"quality":game.get_node("DesktopQuality").settings.duplicate(),"note":"Short stationary sample; GPU timing covers the main viewport, not every water compute/capture pass."}
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.get_format() in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]:
		var display := Image.create(picture.get_width(),picture.get_height(),false,Image.FORMAT_RGBA8)
		for y in picture.get_height():
			for x in picture.get_width(): display.set_pixel(x,y,picture.get_pixel(x,y).linear_to_srgb())
		picture=display
	picture.save_png(destination.path_join(label+".png"))
	print("SOURCE_FINISH_VIEW ",label," ",JSON.stringify(report.views[label].frame))

func _summary(values: Array[float]) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values: total += value
	return {"mean_ms":total/values.size(),"p95_ms":values[113],"max_ms":values[-1]}
