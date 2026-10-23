extends SceneTree
## Mobile renderer regression: real skinned body, camera layers and pixel output.
var report: Dictionary = {"errors":[],"method":"Host Mobile/Vulkan GPU; real avatar and synthetic controller input, not Android hardware."}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	game.qa_capture_hook = _inspect
	root.add_child(game)

func check(value: bool, label: String) -> void:
	if not value: report.errors.append(label)

func capture(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var display := Image.create(picture.get_width(),picture.get_height(),false,Image.FORMAT_RGBA8)
	var linear := picture.get_format() in [Image.FORMAT_RGBH,Image.FORMAT_RGBAH,Image.FORMAT_RGBF,Image.FORMAT_RGBAF]
	for y in picture.get_height():
		for x in picture.get_width():
			var color := picture.get_pixel(x,y)
			display.set_pixel(x,y,color.linear_to_srgb() if linear else color)
	display.save_png("res://output/android8400/" + path + ".png")
	return display

func _inspect(game: Node3D) -> int:
	check(is_instance_valid(game.avatar), "Avatar absent from Mobile scene")
	if not is_instance_valid(game.avatar): return 1
	var avatar: Node3D = game.avatar
	var state: Dictionary = avatar.get_debug_state()
	check(state.loaded, "Skinned model/animation tree not loaded")
	check(int(state.bone_count) > 0 and int(state.body_mesh_count) > 0, "Missing skeleton/body meshes")
	for clip in ["Idle","Walk","Run","Hold","Wade","Swim","Climb"]:
		check(state.clips.has(clip), "Missing animation " + clip)
	check((game.player.camera.cull_mask & avatar.BODY_LAYER) != 0, "First person camera excludes body")
	check((game.player.camera.cull_mask & avatar.HEAD_LAYER) == 0, "First person camera includes own head")
	check((game.water.planar.mirror.cull_mask & avatar.BODY_LAYER) != 0 and (game.water.planar.mirror.cull_mask & avatar.HEAD_LAYER) != 0, "Reflection camera excludes body or head")
	check(int(game._avatar_finish_status.get("applied_surfaces",0)) == 2, "Clothing finish missing")
	var body_controls := 0
	for node in game._menu.find_children("*","CheckButton",true,false):
		if "PLAYER BODY" in node.text: body_controls += 1
	check(body_controls == 1, "Mobile body menu switch missing")
	game.set_menu(false)
	game.player.set_enabled(false)
	game.props.set_enabled(false)
	game.water.set_paused(true)
	game.player.warp_to(Vector3(0,-.70,14),Vector3(0,-.70,0))
	game.player.camera.rotation.x = -1.15
	avatar.show()
	for _i in 12: await process_frame
	var shown := await capture("mobile-avatar-body")
	avatar.hide()
	for _i in 3: await process_frame
	var hidden := await capture("mobile-avatar-hidden")
	var pixels := 0
	for y in shown.get_height():
		for x in shown.get_width():
			var a := shown.get_pixel(x,y)
			var b := hidden.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .08: pixels += 1
	check(pixels > 1000, "Body not visible in first person pixels")
	avatar.show()
	game.player.camera.rotation.x = -.35
	game.player.set_enabled(true)
	var body: RigidBody3D = game.props.bodies[0]
	body.global_position = game.player.global_position + Vector3(0,1.3,-.75)
	game.player.grab_prop(body)
	game.player.held_distance = .75
	for _i in 90: await physics_frame
	check(game.player.held == body, "Controller failed to hold prop")
	report.holding = avatar.get_debug_state()
	check(float(report.holding.hold_blend) > .01, "Hold animation not blended")
	await capture("mobile-avatar-hold")
	game.player.release_prop()
	check(game.player.held == null, "Controller did not release prop")
	report.avatar = state
	report.body_visible_pixels = pixels
	report.device = RenderingServer.get_video_adapter_name()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.pass = report.errors.is_empty()
	FileAccess.open("res://output/android8400/mobile-avatar.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MOBILE_AVATAR_QA ",JSON.stringify({"pass":report.pass,"errors":report.errors,"body_pixels":pixels,"bones":state.bone_count}))
	return 0 if report.pass else 1
