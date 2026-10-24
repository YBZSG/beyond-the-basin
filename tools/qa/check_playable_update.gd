extends SceneTree
var destination := ""
var mode := "original"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--playable-out="): destination=arg.trim_prefix("--playable-out=")
		if arg == "--formal-hall": mode="formal"
		if arg == "--poolrooms-wing": mode="poolrooms"
	var game=load("res://scenes/main.tscn").instantiate()
	game.qa_capture_hook=_inspect
	root.add_child(game)
func _inspect(game: Node3D) -> int:
	var panel=game.get_node("DesktopQuality")
	panel.set_option("nr",true)
	panel.set_option("dlss","Quality")
	panel.set_option("raytracing",mode!="poolrooms")
	if mode=="poolrooms": game.player.warp_to(game.world.get_spawn_position(game.world.current_room),Vector3(-3,1,-1))
	game.set_menu(false)
	for frame in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/scene.png")
	game.set_menu(true)
	panel.open_panel()
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/settings.png")
	var result={"mode":mode,"rt":panel.raytracing_status,"nr_requested":panel.settings.nr,"fg":panel.settings.frame_generation,"scene":game._spawn_mode,"water_error":game.water.last_error}
	FileAccess.open(destination+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	return 0 if game.water.last_error.is_empty() and (mode=="poolrooms" or bool(panel.raytracing_status.active)) else 1
