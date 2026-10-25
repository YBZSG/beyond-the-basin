extends "res://scripts/art_pass/character/natural_pool_avatar.gd"
## Supplemental authored actions. Existing swim/jump/throw clips and all physical
## authority remain untouched. Actual palm IK has final priority over a gesture.
const HandmadeState = preload("res://scripts/art_pass/character/handmade_action_state.gd")
const HANDMADE_LIBRARY_PATH := "res://assets/character_refinement/handmade_motion/handmade_actions.tres"
const HandmadeFingers=preload("res://scripts/art_pass/character/handmade_finger_poses.gd")
@export_file("*.tres","*.res") var handmade_library_path:=HANDMADE_LIBRARY_PATH
var _handmade_state := HandmadeState.new()
var _handmade_ready := false
var _handmade_sample: Dictionary = {}

func _build_animation_tree() -> void:
	super._build_animation_tree()
	if "--legacy-handmade-motion" in OS.get_cmdline_user_args(): return
	if not bool(_natural_contract_status.get("valid",false)) or not _action_clips_ready or _tree==null: return
	if not ResourceLoader.exists(handmade_library_path):
		push_warning("Supplemental handmade actions unavailable; retaining natural avatar actions")
		return
	var source := load(handmade_library_path) as AnimationLibrary
	if source == null: return
	for required: StringName in [&"Pickup",&"SetDown",&"WadeRest"]:
		if not source.has_animation(required): return
	var library := source.duplicate(true) as AnimationLibrary
	var animation_root: Node = _animation_player.get_node(_animation_player.root_node)
	var skeleton_path := str(animation_root.get_path_to(_skeleton))
	var graph := _tree.tree_root as AnimationNodeBlendTree
	for clip: StringName in library.get_animation_list():
		var animation := library.get_animation(clip)
		for t in animation.get_track_count():
			var bone := str(animation.track_get_path(t).get_subname(0))
			if _skeleton.find_bone(bone)<0: return
			animation.track_set_path(t,NodePath(skeleton_path+":"+bone))
	_animation_player.add_animation_library(&"Handmade",library)
	for clip: String in ["Pickup","SetDown","WadeRest"]:
		var node := AnimationNodeAnimation.new();node.animation=StringName("Handmade/"+clip)
		graph.add_node("Handmade"+clip,node)
		graph.add_node("Handmade"+clip+"Seek",AnimationNodeTimeSeek.new())
		graph.connect_node("Handmade"+clip+"Seek",0,"Handmade"+clip)
		var blend := _blend_node();blend.filter_enabled=true
		var animation := library.get_animation(clip)
		for t in animation.get_track_count(): blend.set_filter_path(animation.track_get_path(t),true)
		graph.add_node("Handmade"+clip+"Blend",blend)
	# Resting in water gets its own planted-feet upper-body balance pose.
	graph.disconnect_node("MoveBlend",0)
	graph.connect_node("HandmadeWadeRestBlend",0,"IdleSeek")
	graph.connect_node("HandmadeWadeRestBlend",1,"HandmadeWadeRestSeek")
	graph.connect_node("MoveBlend",0,"HandmadeWadeRestBlend")
	graph.disconnect_node("output",0)
	graph.connect_node("HandmadePickupBlend",0,"ThrowBlend")
	graph.connect_node("HandmadePickupBlend",1,"HandmadePickupSeek")
	graph.connect_node("HandmadeSetDownBlend",0,"HandmadePickupBlend")
	graph.connect_node("HandmadeSetDownBlend",1,"HandmadeSetDownSeek")
	graph.connect_node("output",0,"HandmadeSetDownBlend")
	var fingers:=HandmadeFingers.new()
	fingers.model_contract=_natural_contract
	fingers.supplemental_sample=func()->Dictionary: return _handmade_sample
	fingers.setup(_skeleton)
	_finger_poses=fingers
	_handmade_ready=true
	_write_animation_parameters()

func _integrate_locomotion(displacement: Vector3, delta: float, distance_override: float=-1.0) -> void:
	super._integrate_locomotion(displacement,delta,distance_override)
	if not _handmade_ready or _water_actions.state.is_empty(): return
	var held: RigidBody3D=_player_value("held",null)
	_handmade_state.integrate(_water_actions.state,delta,held.get_instance_id() if is_instance_valid(held) else 0)
	_handmade_sample=_handmade_state.sample()

func _write_animation_parameters() -> void:
	super._write_animation_parameters()
	if not _handmade_ready: return
	_tree.set("parameters/HandmadeWadeRestBlend/blend_amount",_wade_blend)
	_tree.set("parameters/HandmadeWadeRestSeek/seek_request",fposmod(float(_handmade_sample.get("clock",0.0)),2.8))
	for clip: String in ["Pickup","SetDown"]:
		var key := "pickup" if clip=="Pickup" else "setdown"
		_tree.set("parameters/Handmade"+clip+"Blend/blend_amount",float(_handmade_sample.get(key+"_weight",0.0)))
		_tree.set("parameters/Handmade"+clip+"Seek/seek_request",float(_handmade_sample.get(key+"_time",0.0)))

func get_debug_state() -> Dictionary:
	var result := super.get_debug_state()
	result.handmade_actions=_handmade_sample.duplicate()
	result.handmade_actions.installed=_handmade_ready
	result.handmade_actions.authored_clips=["Pickup","SetDown","WadeRest"] if _handmade_ready else []
	return result
