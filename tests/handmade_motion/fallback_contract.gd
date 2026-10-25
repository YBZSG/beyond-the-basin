extends SceneTree
const Avatar=preload("res://scripts/art_pass/character/handmade_pool_avatar.gd")
const Player=preload("res://tests/handmade_motion/fixture_player.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var p=Player.new();root.add_child(p)
	var cam=Camera3D.new();cam.name="ViewCamera";p.add_child(cam)
	var a=Avatar.new();a.model_path="res://assets/character_refinement/natural_hand_finish/explorer_natural_hand.glb";a.hand_contract_path="res://assets/character_refinement/natural_hand_finish/model_contract.json"
	a.handmade_library_path="res://tests/handmade_motion/INTENTIONALLY_MISSING.tres"
	a.setup(p);a.set_process(false)
	var s=a.get_debug_state()
	var pass_ok=bool(s.loaded) and not bool(s.handmade_actions.installed) and bool(s.water_actions_ready) and a._clips.size()==14
	p.free();print("HANDMADE_MISSING_LIBRARY_FALLBACK pass=",pass_ok)
	quit(0 if pass_ok else 1)
