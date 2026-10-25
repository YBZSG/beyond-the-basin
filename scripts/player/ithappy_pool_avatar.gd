extends "res://scripts/player/pool_avatar.gd"
## Isolated 44-joint adapter. Never passes this rig through the original
## natural-hand contract or changes controller, camera, collision or water.
const Rig = preload("res://scripts/player/ithappy_rig.gd")
const NewHands = preload("res://scripts/player/ithappy_hand_ik.gd")
const ThrowActions = preload("res://scripts/player/ithappy_throw_actions.gd")
const NewFingers = preload("res://scripts/player/ithappy_finger_poses.gd")
const CHARACTER_MODEL := "res://assets/models/avatar/ithappy_explorer.glb"
const SOURCE_CLIPS := {
	"Idle": "Idle_Relaxed", "Walk": "Walk_Forward", "Run": "Run_Forward",
	"Wade": "Walk_Forward", "Hold": "Idle_Relaxed", "Climb": "Climb_Ladder",
	"JumpRise": "Jump_Start", "JumpAir": "Jump_Loop", "Land": "Jump_End",
	# This asset has no swim animation. These are graph fallback references,
	# not generated/retargeted swimming actions; original swimmer remains intact.
	"Swim": "Idle_Relaxed", "SwimIdle": "Idle_Relaxed",
}
var _rig_status: Dictionary = {"valid": false, "reason": "not_loaded"}

func _init() -> void:
	model_path = CHARACTER_MODEL
	# Keep this taller rig's neck behind the first-person eye; leave the
	# controller/camera height and world-space grip targets unchanged.
	body_visual_offset = Vector3(0.0, 0.0, 0.28)

func _discover_clips() -> void:
	var reason: String = Rig.validate(_skeleton)
	_rig_status = {"valid": reason == "ready", "reason": reason}
	if not bool(_rig_status.get("valid", false)):
		_load_error = "ithappy rig rejected: " + str(_rig_status)
		return
	# Never edit shared imported animations: canonical aliases are private copies.
	var library := AnimationLibrary.new()
	for canonical: String in SOURCE_CLIPS:
		var source: Animation
		for imported: StringName in _animation_player.get_animation_list():
			var leaf := String(imported).replace("|", "/").replace(":", "/").get_file()
			if leaf == SOURCE_CLIPS[canonical] or (canonical == "JumpAir" and leaf == "Jump"):
				# Default Godot import recognizes and removes the _Loop suffix.
				source = _animation_player.get_animation(imported)
				break
		if source == null:
			_load_error = "ithappy missing action: " + str(SOURCE_CLIPS[canonical])
			return
		var clip := source.duplicate(true) as Animation
		if canonical in ["JumpRise", "Land"]:
			_retime(clip, 0.25 if canonical == "JumpRise" else 0.30)
		clip.loop_mode = Animation.LOOP_NONE if canonical in ["JumpRise", "Land"] else Animation.LOOP_LINEAR
		library.add_animation(StringName(canonical), clip)
	var animation_root: Node = _animation_player.get_node(_animation_player.root_node)
	var throw_library := ThrowActions.build_action_library(_skeleton, animation_root.get_path_to(_skeleton), library.get_animation(&"Idle"))
	for clip: StringName in throw_library.get_animation_list():
		library.add_animation(clip, throw_library.get_animation(clip))
	_animation_player.add_animation_library(&"Character", library)
	super._discover_clips()

func _retime(animation: Animation, duration: float) -> void:
	var ratio := duration / maxf(animation.length, 0.0001)
	for track: int in animation.get_track_count():
		# Change from last key to first to retain sorted keys when compressing time.
		var values: Array = []
		for key: int in animation.track_get_key_count(track):
			values.append([animation.track_get_key_time(track, key) * ratio,
				animation.track_get_key_value(track, key), animation.track_get_key_transition(track, key)])
		for key: int in range(animation.track_get_key_count(track)-1, -1, -1):
			animation.track_remove_key(track, key)
		for value: Array in values:
			animation.track_insert_key(track, value[0], value[1], value[2])
	animation.length = duration

func _build_animation_tree() -> void:
	if not _load_error.is_empty() or not bool(_rig_status.get("valid", false)): return
	super._build_animation_tree()
	if _tree == null: return
	_hand_ik = NewHands.new()
	_hand_ik.setup(_skeleton)
	_finger_poses = NewFingers.new()
	_finger_poses.setup(_skeleton)

func _apply_swim_body_alignment(_delta: float) -> void:
	# No fabricated swim pose/translation for the shallow-water character.
	# The original avatar still has its exact existing swim alignment.
	_swim_body_offset = Vector3.ZERO
	_model.position = body_visual_offset

func get_debug_state() -> Dictionary:
	var result := super.get_debug_state()
	result.character_id = "ithappy"
	result.ithappy_rig = _rig_status.duplicate(true)
	result.authored_swim = false
	result.swim_visual_fallback = "upright_idle_no_new_swim_action"
	result.action_sources = SOURCE_CLIPS.duplicate()
	return result
