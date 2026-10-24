extends SceneTree
## Reproduces only the three reviewed main setup hooks with actual Player and
## avatar resources. Does not run the complete custom-engine main/world.
const Selection = preload("res://scripts/art_pass/character/art_character_selection.gd")
const Original = preload("res://scripts/player/pool_avatar.gd")
const Player = preload("res://scripts/player/pool_player.gd")
const Finish = preload("res://scripts/player/avatar_finish_candidate.gd")
const Mobile = preload("res://scripts/mobile/pool_mobile_profile.gd")
var report_path := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path=arg.trim_prefix("--report=")
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var player := Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var avatar: Node3D = Selection.script_or_original(Original).new()
	if "--legacy-avatar-model" not in args:
		avatar.model_path=Finish.CANDIDATE_PATH
		if not Mobile.is_mobile_session() and "--legacy-water-actions" not in args:
			avatar.model_path="res://assets/water_motion/explorer_water_motion.scn"
	Selection.apply_selected_model(avatar)
	avatar.setup(player)
	avatar.set_process(false)
	var state: Dictionary = avatar.get_debug_state()
	var selected: bool = Selection.is_enabled()
	var handoff_expected: bool = selected and "--no-arm-swim-continuation" not in args and "--original-avatar-motion" not in args
	var checks := {
		"loaded":bool(state.get("loaded",false)),
		"script":avatar.get_script()==(Selection.NaturalAvatar if selected else Original),
		"no_preview_permission":not selected or not avatar.allow_preview_contract,
		"natural_contract":not selected or bool(state.get("natural_hand_contract",{}).get("valid",false)),
		"selected_model":not selected or state.get("natural_hand_model_path","")==Selection.MODEL,
		"handoff_install":not selected or avatar._arm_graph_ready==handoff_expected,
		"handoff_tracks":not selected or avatar._arm_tracks.size()==(8 if handoff_expected else 0),
		"old_model_on_rollback":selected or avatar.model_path!=Selection.MODEL,
	}
	var passed := true
	for value: bool in checks.values(): passed=passed and value
	var result := {"pass":passed,"arguments":args,"selected":selected,"model_path":avatar.model_path,"checks":checks,"scope":"Actual imported-resource/setup selection in the current engine; no complete world or GPU validation."}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(result,"  "))
	player.free()
	print("ACCEPTED_CHARACTER_POLICY ",JSON.stringify(result))
	quit(0 if passed else 1)
