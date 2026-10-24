extends "res://scripts/player/pool_avatar.gd"
## Optional visual-only graph layer. Setup-only opt-in; recreate this avatar to
## change the option. No hot-toggle cancellation policy is implied.
@export var arm_air_swim_handoff_enabled: bool = false
const GraphHandoff = preload("res://scripts/art_pass/character/arm_air_swim_continuation.gd")
const ARM_LIBRARY: StringName = &"arm_air_swim_continuation"
var _arm_handoff: RefCounted
var _arm_animation: Animation
var _arm_tracks: Dictionary = {}
var _arm_graph_ready: bool = false

func _allow_arm_handoff() -> bool:
	return arm_air_swim_handoff_enabled and _motion_refinement_allowed and _action_clips_ready

func _build_animation_tree() -> void:
	super._build_animation_tree()
	# Fail closed before allocating or changing any graph edge. Original/legacy
	# motion and an incomplete/different rig retain the exact original graph.
	if not _allow_arm_handoff() or _tree == null or _skeleton == null or _animation_player == null: return
	if _skeleton.get_bone_count() != 54 or not _tree.tree_root is AnimationNodeBlendTree: return
	var source_graph: AnimationNodeBlendTree = _tree.tree_root
	if not source_graph.has_node("ClimbBlend") or not source_graph.has_node("LandBlend"): return
	if source_graph.has_node("ArmContinuation") or source_graph.has_node("ArmHandoffBlend") or _animation_player.has_animation_library(ARM_LIBRARY): return
	for name: String in GraphHandoff.BONES:
		if _skeleton.find_bone(name) < 0: return
	_arm_handoff = GraphHandoff.new()
	var animation_root: Node = _animation_player.get_node(_animation_player.root_node)
	var skeleton_path: String = str(animation_root.get_path_to(_skeleton))
	_arm_animation = Animation.new()
	_arm_animation.length = 1.0
	var filtered := _blend_node()
	filtered.filter_enabled = true
	for name: String in GraphHandoff.BONES:
		var path := NodePath(skeleton_path+":"+name)
		var track: int = _arm_animation.add_track(Animation.TYPE_ROTATION_3D)
		_arm_animation.track_set_path(track,path)
		_arm_animation.track_insert_key(track,0.0,_skeleton.get_bone_pose_rotation(_skeleton.find_bone(name)))
		_arm_tracks[name] = track
		filtered.set_filter_path(path,true)
	var library := AnimationLibrary.new()
	library.add_animation(&"Continuation",_arm_animation)
	_animation_player.add_animation_library(ARM_LIBRARY,library)
	var predicted := AnimationNodeAnimation.new()
	predicted.animation = StringName(str(ARM_LIBRARY)+"/Continuation")
	var graph: AnimationNodeBlendTree = _tree.tree_root
	graph.add_node("ArmContinuation",predicted)
	graph.add_node("ArmHandoffBlend",filtered)
	graph.disconnect_node("ClimbBlend",0)
	graph.connect_node("ArmHandoffBlend",0,"LandBlend")
	graph.connect_node("ArmHandoffBlend",1,"ArmContinuation")
	graph.connect_node("ClimbBlend",0,"ArmHandoffBlend")
	_arm_graph_ready = true
	_tree.set("parameters/ArmHandoffBlend/blend_amount",0.0)

func _integrate_locomotion(displacement: Vector3, delta: float, distance_override: float = -1.0) -> void:
	super._integrate_locomotion(displacement,delta,distance_override)
	if _arm_handoff != null and _action_clips_ready and not _water_actions.state.is_empty(): _arm_handoff.observe(_water_actions.state)

func _write_animation_parameters() -> void:
	super._write_animation_parameters()
	if not _arm_graph_ready: return
	var sample: Dictionary = _arm_handoff.prepare(_water_actions.state,_hold_blend,float(_action_sample.get("throw_weight",0.0)))
	for name: String in sample.rotations:
		_arm_animation.track_set_key_value(int(_arm_tracks[name]),0,sample.rotations[name])
	_tree.set("parameters/ArmHandoffBlend/blend_amount",float(sample.weight))

func _process(delta: float) -> void:
	super._process(delta)
	# Capture only the final rendered arms, after unchanged release/IK/fingers.
	if _arm_handoff != null and _action_clips_ready and is_instance_valid(_skeleton) and not _water_actions.state.is_empty(): _arm_handoff.capture(_skeleton,_water_actions.state)

func get_debug_state() -> Dictionary:
	var result: Dictionary = super.get_debug_state()
	if _arm_handoff == null:
		result.arm_handoff = {"enabled":false,"installed":false}
		return result
	result.arm_handoff = _arm_handoff.debug.duplicate()
	result.arm_handoff.private_animation_resources = 2
	result.arm_handoff.filtered_rotation_tracks = _arm_tracks.size()
	return result
