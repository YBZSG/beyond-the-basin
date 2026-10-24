extends SceneTree
## First-person swim/stop transitions, using the production camera and water capture.
var destination := ""
var report: Dictionary = {"errors": [], "samples": []}
class SwimWater extends Node3D:
	# Test-only deep volume: production map remains the restored shallow pool.
	var source: Node3D
	func is_water_at(_p: Vector3) -> bool: return true
	func surface_height_at(p: Vector3) -> float: return source.surface_height_at(p)
	func depth_at(_p: Vector3) -> float: return 2.20
	func current_velocity_at(_p: Vector3) -> Vector2: return Vector2.ZERO

func _check(ok: bool, reason: String) -> void:
	if not ok: report.errors.append(reason)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dlss-out="): destination = arg.trim_prefix("--dlss-out=")
	if destination.is_empty() or not OS.get_environment("APPDATA").replace("\\", "/").contains("/output/dlss/"):
		quit(3)
		return
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	game.qa_capture_hook = _inspect
	root.add_child(game)

func _capture(game: Node3D, label: String) -> void:
	await RenderingServer.frame_post_draw
	var bones: Dictionary = {}
	var skeleton: Skeleton3D = game.avatar._skeleton
	for name: String in ["Head", "Neck", "Chest", "Hips", "Hand_L", "Hand_R"]:
		bones[name] = game.player.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin)
	report.samples.append({"label": label, "player": game.player.position, "camera": game.player.camera.position,
		"pitch": game.player.camera.rotation.x, "bones": bones, "model_offset": game.avatar._model.position,
		"state": game.player.get_action_state(), "avatar": game.avatar.get_debug_state()})
	_check(root.get_texture().get_image().save_png(destination.path_join(label + ".png")) == OK, "Capture failed: " + label)

func _inspect(game: Node3D) -> int:
	report.version = ProjectSettings.get_setting("application/config/version")
	if preload("res://scripts/art_pass/character/art_character_selection.gd").is_enabled():
		var avatar_state: Dictionary = game.avatar.get_debug_state()
		report.natural_hand_contract = avatar_state.get("natural_hand_contract", {})
		_check(bool(report.natural_hand_contract.get("valid", false)), "Authored hand fell back to the old model")
	var panel := game.get_node("DesktopQuality")
	panel.set_option("frame_generation", false)
	panel.set_option("raytracing", false)
	game.set_menu(false)
	game.props.set_enabled(false)
	for body in game.props.bodies: body.freeze = true
	report.original_depth = game.water.depth_at(Vector3.ZERO)
	_check(absf(report.original_depth - 1.04) < 0.02, "Original pool was not restored")
	game.player.warp_to(Vector3(0, -0.70, 0), Vector3(0, 0.90, -10))
	game.player.set_enabled(true)
	game.player.set_process_unhandled_input(false)
	game.player.camera.rotation.x = -1.3
	for frame in 90: await physics_frame
	await _capture(game, "00-original-wading")
	_check(not game.player._swimming, "Shallow pool must remain wading")
	var test_water := SwimWater.new()
	test_water.source = game.water
	game.add_child(test_water)
	game.player.set_water(test_water)
	game.player.collision_mask = 0
	game.player.warp_to(Vector3(0, -1.15, 0), Vector3(0, 0.45, -10))
	game.player.set_enabled(true)
	game.player.set_process_unhandled_input(false)
	for frame in 120: await physics_frame
	await _capture(game, "01-swim-idle")
	_check(game.player._swimming, "Controlled swim fixture did not enter swimming")
	Input.action_press("move_forward")
	for frame in 120: await physics_frame
	await _capture(game, "02-swim-forward")
	game.player.camera.rotation.x = -1.3
	for frame in 30: await physics_frame
	await _capture(game, "03-swim-down")
	Input.action_release("move_forward")
	for frame in 50: await physics_frame
	await _capture(game, "04-swim-stop-down")
	game.player.camera.rotation.x = 0.0
	for frame in 60: await physics_frame
	await _capture(game, "05-swim-stop-level")
	panel.set_option("raytracing", true)
	for frame in 120: await process_frame
	await _capture(game, "06-swim-stop-rt")
	Input.action_press("move_forward")
	for frame in 100: await physics_frame
	await _capture(game, "07-swim-forward-rt")
	report.rt_status = panel.raytracing_status.duplicate()
	_check(report.rt_status.active, "RT camera path was not exercised")
	game.player.camera.rotation.x = -1.3
	for frame in 30: await physics_frame
	await _capture(game, "08-swim-down-rt")
	Input.action_release("move_forward")
	for frame in 50: await physics_frame
	await _capture(game, "09-swim-stop-down-rt")
	game.player.camera.rotation.x = 1.3
	for frame in 30: await physics_frame
	await _capture(game, "10-swim-up-rt")
	game.player.collision_mask = 1 | 2
	game.player.set_water(game.water)
	game.player.warp_to(Vector3(0,-0.70,12),Vector3(0,0.90,0))
	game.player.camera.rotation.x = -0.85
	Input.action_press("move_forward")
	for frame in 90: await physics_frame
	Input.action_release("move_forward")
	await _capture(game, "11-return-wading-rt")
	_check(not game.player._swimming, "Return to shallow water must restore wading")
	game.player.camera.rotation.x = -0.65
	var prop: RigidBody3D = game.props.bodies[0]
	prop.global_position = game.player.get_hold_anchor()
	prop.linear_velocity = Vector3.ZERO
	prop.angular_velocity = Vector3.ZERO
	game.props.set_enabled(true)
	for body in game.props.bodies: body.freeze = body != prop
	prop.freeze = false
	prop.set_physics_process(true)
	game.player.grab_prop(prop)
	for frame in 60: await physics_frame
	report.held_distance = prop.global_position.distance_to(game.player.get_hold_anchor())
	_check(game.player.held == prop and report.held_distance < .2,"Prop did not reach carry anchor")
	await _capture(game, "12-carry-rt")
	game.player.release_prop()
	report.pass = report.errors.is_empty()
	FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	return 0 if report.pass else 1
