extends SceneTree
## Real exported avatars and main's exact factory/transaction, without loading
## rooms, native water or a GPU renderer. Not a visual acceptance test.
const Main = preload("res://scripts/main.gd")
const Player = preload("res://scripts/player/pool_player.gd")
const Preferences = preload("res://scripts/player/character_preferences.gd")
var failures: Array[String] = []
var samples: Array[Dictionary] = []
func expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var host := Main.new()
	host._character_settings_path = "user://character_ui_contract.cfg"
	host._character_select = OptionButton.new()
	for label: String in Preferences.LABELS: host._character_select.add_item(label)
	host._character_status = Label.new()
	var player := Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(2, 1, 3)
	player.velocity = Vector3(0.4, 0.2, -0.3)
	var held := RigidBody3D.new()
	held.freeze = true
	root.add_child(held)
	held.position = player.position + Vector3(0, 1.3, -0.45)
	player.held = held
	player._locomotion_epoch = 9
	player._action.release_serial = 7
	host.player = player
	host.avatar = host._create_character_visual("original")
	expect(bool(host.avatar.get_debug_state().get("loaded",false)), "Initial original loaded")
	var camera_id := player.camera.get_instance_id()
	var capsule_id := player.get_node("PlayerCapsule").get_instance_id()
	for id: String in ["ithappy", "original", "ithappy", "original", "ithappy"]:
		var before := host.avatar
		host._select_character(Preferences.IDS.find(id))
		var success: bool = host._character_id == id
		expect(Preferences.load_character(host._character_settings_path) == id, "UI saves choice")
		expect(host._character_select.selected == Preferences.IDS.find(id), "UI reflects choice")
		expect(success, "Loaded replacement " + id)
		if not success: continue
		expect(not is_instance_valid(before), "Previous visual freed")
		expect(player.locomotion_step.get_connections().size() == 1, "Exactly one locomotion listener")
		expect(player.position == Vector3(2,1,3) and player.velocity == Vector3(0.4,0.2,-0.3), "Physical controller unchanged")
		expect(player.held == held and player._action.release_serial == 7 and player.locomotion_epoch == 9, "Held body, throw serial, epoch retained")
		expect(player.camera.get_instance_id() == camera_id and player.get_node("PlayerCapsule").get_instance_id() == capsule_id, "Camera and capsule retained")
		# Menu/pause state stays disabled while the visual can evaluate a grip.
		expect(not player.enabled, "Pause state unchanged")
		host.avatar._process(1.0/60.0)
		var state: Dictionary = host.avatar.get_debug_state()
		expect(bool(state.get("loaded",false)), "Loaded after pose evaluation")
		samples.append({"id":id,"bones":state.get("bone_count",0),"loaded":state.get("loaded",false),"error":state.get("error","")})
	var same_visual := host.avatar
	host._select_character(1)
	expect(host.avatar == same_visual, "Repeated same UI choice is a no-op")
	host._switching_spawn = true
	host._select_character(0)
	expect(host.avatar == same_visual and host._character_id == "ithappy", "Switch blocked during world transition")
	host._switching_spawn = false
	host._retiring_world = true
	host._select_character(0)
	expect(host.avatar == same_visual and host._character_id == "ithappy", "Switch blocked during world retirement")
	host._retiring_world = false
	# Dropped/throw-released prop and reset epoch must remain owned by player.
	player.held = null
	player._action.release_serial = 8
	player._locomotion_epoch = 10
	expect(host._replace_character_visual("original"), "Return original after release")
	expect(player.held == null and player._action.release_serial == 8 and player.locomotion_epoch == 10, "Release/reset state retained")
	var stable := host.avatar
	expect(not host._replace_character_visual("unknown") and host.avatar == stable, "Invalid ID rollback")
	# Simulated teardown/recreation uses the independent preference, not campaign.
	var path := "user://character_scene_transition_contract.cfg"
	expect(Preferences.save_character("ithappy",path) == OK, "Persist transition preference")
	player.free()
	host._character_select.free()
	host._character_status.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host._character_settings_path))
	host.free()
	host = Main.new()
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	host.player = player
	host.avatar = host._create_character_visual("original")
	expect(host._replace_character_visual(Preferences.load_character(path)), "New controller restores preference")
	expect(str(host.avatar.get_debug_state().get("character_id","original")) == "ithappy", "Restored new character")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	player.free()
	host.free()
	held.free()
	print("CHARACTER_SELECTION_INTEGRATION ",JSON.stringify({"passed":failures.is_empty(),"failures":failures,"samples":samples,"scope":"headless real avatars; world/death UI/GPU not exercised"}))
	quit(0 if failures.is_empty() else 1)
