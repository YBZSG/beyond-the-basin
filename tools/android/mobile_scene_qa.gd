extends SceneTree
## Actual Mobile renderer QA. This runs on the host GPU, not a phone.
var game: Node3D
var report: Dictionary = {"errors":[], "method":"Actual Mobile renderer on the reported host GPU; synthetic input, not Android hardware."}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_capture_hook = _inspect
	root.add_child(game)

func _check(value: bool, message: String) -> void:
	if not value: report.errors.append(message)

func _inspect(host: Node3D) -> int:
	game = host
	var water: Node3D = game.water
	var quality: Node = game.get_node("MobileRuntime").quality
	report.saved_frame_cap = quality.frame_cap
	_check(is_instance_valid(game.avatar), "Mobile player body was not created")
	if is_instance_valid(game.avatar):
		_check(bool(game.avatar.get_debug_state().loaded), "Mobile player body failed to load")
	# Compare wall timing uncapped; gameplay keeps its saved/default cap.
	Engine.max_fps = 0
	_check(water._liquid == null and water._whitewater == null and water._liquid_surface == null, "Splash resources were allocated")
	_check(water._probe == null, "Unused splash room cubemap was allocated")
	_check(game.world.resident_rooms.size() == 9, "Expected 3x3 resident rooms")
	_check(water.solver.size == 384, "Expected mobile High SWE grid")
	_check(water.planar.resolution == 512, "Expected mobile High reflection size")
	_check(water.planar.viewport.msaa_3d == Viewport.MSAA_2X, "Expected mobile 2x reflection MSAA")
	game.set_menu(false)
	game.player.set_enabled(false)
	game.player.warp_to(Vector3(1.0,-.12,3.4), Vector3(0,.4,0))
	for _i in 90: await process_frame
	var frames: Array[float] = []
	var before_impacts: int = water.interaction_count
	water.splash(Vector3(0,.32,0), .65, {"vertical":-3.0,"radius":.17})
	var previous := Time.get_ticks_usec()
	for _i in 180:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-previous)/1000.0)
		previous = now
	_check(water.interaction_count > before_impacts, "Impact did not drive surface waves")
	_check(float(water.solver.debug().get("simulated", 0.0)) > 0.0, "SWE did not advance")
	_check(water._liquid == null and water._liquid_surface == null, "Impact recreated splash resources")
	_check(game.get_node("MobileRuntime").source_blocker.is_empty(), "Mobile capability/runtime blocker")
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	report.capture_format = picture.get_format()
	# HDR ViewportTextures contain linear floats; PNG needs display sRGB.
	if picture.get_format() in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]:
		var display := Image.create(picture.get_width(),picture.get_height(),false,Image.FORMAT_RGBA8)
		for y in picture.get_height():
			for x in picture.get_width(): display.set_pixel(x,y,picture.get_pixel(x,y).linear_to_srgb())
		picture = display
	picture.save_png("res://output/android8400/mobile-water.png")
	report.water = water.debug_stats()
	report.device = RenderingServer.get_video_adapter_name()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.quality = quality.preset
	frames.sort()
	report.timing = {"p50_ms":frames[90],"p95_ms":frames[171],"max_ms":frames[-1],"frames":frames.size(),"cap_during_measurement":0}
	# Continuous input crosses the room boundary without teleporting mid-route.
	game.player.warp_to(Vector3(0,-.64,15.25), Vector3(0,.9,0))
	game.player.set_enabled(true)
	Input.action_press("move_back")
	for _i in 240: await physics_frame
	Input.action_release("move_back")
	game.player.set_enabled(false)
	_check(game.world.current_room == Vector2i(0,1), "Movement did not cross into neighbor room")
	_check(game.player.global_position.y > -1.3, "Player fell through collision")
	game.world.complete_pending_streaming()
	var started := Time.get_ticks_msec()
	while not water.is_terrain_ready() and Time.get_ticks_msec()-started < 60000: await process_frame
	_check(water.is_terrain_ready(), "Neighbor water not ready")
	_check(game.world.resident_rooms.size() == 9, "Streaming residency exceeded mobile budget")
	report.neighbor = game.inspect_state()
	var controls: Control = game.get_node("MobileRuntime").controls
	game.player.set_enabled(true)
	controls.set_gameplay_enabled(true)
	var press := InputEventScreenTouch.new()
	press.index = 5; press.position = Vector2(160,560); press.pressed = true
	controls._input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 5; drag.position = Vector2(160,490); drag.relative = Vector2(0,-70)
	controls._input(drag)
	var joystick_ok := Input.is_action_pressed("move_forward")
	_check(joystick_ok, "Touch joystick did not drive movement")
	controls._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(not Input.is_action_pressed("move_forward"), "Pause retained touch movement")
	_check(controls._move_finger == -1, "Pause retained a touch finger")
	game.player.set_enabled(false)
	report.touch = {"synthetic_joystick":joystick_ok,"pause_releases_input":not Input.is_action_pressed("move_forward"),"hardware_tested":false}
	report.pass = report.errors.is_empty()
	FileAccess.open("res://output/android8400/mobile-scene.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MOBILE_SCENE_QA ", JSON.stringify({"pass":report.pass,"errors":report.errors,"timing":report.timing,"device":report.device}))
	return 0 if report.pass else 1
