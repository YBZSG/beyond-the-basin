extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for path in ["res://scripts/player/pool_player.gd", "res://scripts/player/pool_avatar.gd", "res://scripts/player/pool_prop_body.gd", "res://scripts/player/avatar_hand_ik.gd"]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			printerr("Cannot compile: " + path); quit(30); return
	var avatar := load("res://assets/models/avatar/pool_explorer.glb") as PackedScene
	if avatar == null:
		printerr("Cannot load imported avatar"); quit(31); return
	var node := avatar.instantiate()
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	var players := node.find_children("*", "AnimationPlayer", true, false)
	if skeletons.size() != 1 or skeletons[0].get_bone_count() != 42 or players.size() != 1:
		printerr("Wrong avatar skeleton or animator"); quit(32); return
	for clip in ["Idle", "Walk", "Run", "Hold", "Wade", "Swim", "Climb"]:
		if not players[0].has_animation(clip):
			printerr("Missing animation: " + clip); quit(33); return
	if load("res://scenes/main.tscn") == null:
		printerr("Main scene does not load"); quit(34); return
	print("AVATAR_REPAIR_EXACT_PACK_SMOKE_OK bones=42 clips=7 scripts=4 main_scene=loaded")
	node.free()
	quit()
