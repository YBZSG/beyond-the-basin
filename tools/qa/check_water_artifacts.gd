extends SceneTree
## Real water after movement, then expanded-map floor and RT fallback regression.
var destination := ""
var report: Dictionary = {"errors": [], "rooms": []}
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dlss-out="): destination = arg.trim_prefix("--dlss-out=")
	if destination.is_empty() or not OS.get_environment("APPDATA").replace("\\", "/").contains("/output/dlss/"):
		quit(3)
		return
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	game.qa_capture_hook = _inspect
	root.add_child(game)
func _check(ok: bool, message: String) -> void:
	if not ok: report.errors.append(message)
func _capture(label: String) -> void:
	for frame in 45: await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(destination.path_join(label + ".png")) == OK, "Capture failed: " + label)
func _inspect(game: Node3D) -> int:
	report.version = ProjectSettings.get_setting("application/config/version")
	var panel := game.get_node("DesktopQuality")
	panel.set_option("frame_generation", false)
	panel.set_option("raytracing", false)
	game.set_menu(false)
	game.props.set_enabled(false)
	for body in game.props.bodies: body.freeze = true
	game.player.warp_to(Vector3(0, -0.70, 3), Vector3(0, 0.90, -10))
	game.player.set_enabled(true)
	game.player.set_process_unhandled_input(false)
	game.player.camera.rotation.x = -1.1
	for frame in 120: await physics_frame
	var before: Vector3 = game.player.position
	Input.action_press("move_forward")
	for frame in 150: await physics_frame
	Input.action_release("move_forward")
	report.moved = game.player.position.distance_to(before)
	_check(report.moved > 1.0, "Water movement was not exercised")
	game.player.set_physics_process(false)
	game.avatar.set_process(false)
	game.water.set_process(false)
	await _capture("01-moving-foam")
	var field: Image = game.water.solver.get_state_texture().get_image()
	var peak: float = 0.0
	for z in range(0,field.get_height(),4):
		for x in range(0,field.get_width(),4): peak = maxf(peak,field.get_pixel(x,z).a)
	report.foam_peak = peak
	_check(peak > 0.015, "Foam field was not exercised")
	for material in game.water._materials.values(): material.set_shader_parameter("foamOn",0.0)
	await _capture("02-foam-off-control")
	for material in game.water._materials.values(): material.set_shader_parameter("foamOn",1.0)
	game.water.set_process(true)
	game.avatar.set_process(true)
	game.player.set_physics_process(true)
	for frame in 120: await physics_frame
	await _capture("03-foam-decay")
	game.player.set_enabled(false)
	game._spawn_mode = "expanded"
	# Preserve an RT request while switching into a map without adapted shaders.
	panel.set_option("raytracing",true)
	await game.regenerate(250821)
	game.world.complete_pending_streaming()
	var start := Time.get_ticks_msec()
	while not game.water.is_terrain_ready() or not game.water.debug_stats().cubemap_ready:
		if Time.get_ticks_msec()-start > 180000:
			report.errors.append("Expanded water readiness timed out")
			break
		await process_frame
	game.set_menu(false)
	game.player.set_enabled(false)
	game.player.set_process_unhandled_input(false)
	panel.set_option("raytracing",true)
	report.rt_status = panel.raytracing_status.duplicate()
	_check(report.rt_status.requested and not report.rt_status.active, "Expanded map must fall back to raster")
	_check(bool(game.world.expanded_mode), "Expanded map was not exercised")
	for coord: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]:
		game.world.ensure_room_ready(coord)
		var origin := Vector3(coord.x*32.0,0.0,coord.y*32.0)
		game.player.warp_to(origin+Vector3(0,.60,9.8),origin+Vector3(0,1.6,0))
		game.player.set_enabled(false)
		game.player.camera.rotation.x = -.62
		await physics_frame
		var missing: Array = []
		var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
		for z in range(-15,16):
			for x in range(-15,16):
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin+Vector3(x,.58,z),origin+Vector3(x,-2,z),1))
				if hit.is_empty(): missing.append(Vector2i(x,z))
		var module: String = game.world.get_layout(coord).expanded_module
		report.rooms.append({"module":module,"floor_samples":961,"missing":missing})
		_check(missing.is_empty(),"Floor collision gaps: "+module)
		await _capture("04-"+module)
	# Preference survives a return to the supported original map.
	game._spawn_mode = "original"
	await game.regenerate(250821)
	panel.apply_settings()
	# Exercise delayed RT cache eviction after both map replacements.
	for frame in 300: await process_frame
	report.original_rt_status = panel.raytracing_status.duplicate()
	_check(report.original_rt_status.active,"Original pool RT preference did not restore")
	report.pass = report.errors.is_empty()
	FileAccess.open(destination.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	return 0 if report.pass else 1
