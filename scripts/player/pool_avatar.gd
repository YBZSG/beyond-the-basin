class_name PoolAvatar
extends Node3D
## An original, fully skinned visual body attached to the controller's feet.
## This node does not move the player, change its capsule, or add physics bodies.
## Camera pitch remains on ViewCamera; the whole body inherits only player yaw.

const MODEL_PATH: String = "res://assets/models/avatar/pool_explorer.glb"
const BODY_LAYER: int = 1 << 16 # Layer 17: dynamic avatar, excluded from static room cubes.
const PLANAR_CLIP_MARKER: int = 1 << 19
const PLANAR_CLIP_HEIGHT: float = 0.318
const HandIK = preload("res://scripts/player/avatar_hand_ik.gd")
const MotionRefinement = preload("res://scripts/player/explorer_motion_refinement.gd")
const CarryContact = preload("res://scripts/player/avatar_carry_contact_candidate.gd")
const AVATAR_SHADER: Shader = preload("res://shaders/avatar_body.gdshader")
const HEAD_LAYER: int = 1 << 17 # Layer 18: visible in mirrors, hidden in first person.
const WALK_SPEED: float = 1.65
const RUN_SPEED: float = 3.8
const REQUIRED_CLIPS: Array[String] = ["Idle", "Walk", "Run", "Hold", "Wade", "Swim", "Climb"]

## Optional override supports alternate authored skins and isolated runtime tests.
@export var avatar_scene: PackedScene
@export var model_path: String = MODEL_PATH
## Keep the eye just ahead of the chest without moving the camera or capsule.
@export var body_visual_offset: Vector3 = Vector3(0.0, 0.0, 0.13)
@export_range(1.0, 24.0) var transition_rate: float = 9.0
## Reversible candidate switch, also used by matched native baseline captures.
@export var motion_refinement_enabled: bool = true

var _player: CharacterBody3D
var _camera: Camera3D
var _model: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _tree: AnimationTree
var _clips: Dictionary = {}
var _player_properties: Dictionary = {}
var _body_meshes: Array[MeshInstance3D] = []
var _head_meshes: Array[MeshInstance3D] = []
var _shadow_meshes: Array[MeshInstance3D] = []
var _hold_filter_paths: Array[NodePath] = []
var _surface_materials: Dictionary = {}
var _speed: float = 0.0
var _target_speed: float = 0.0
var _wade_blend: float = 0.0
var _swim_blend: float = 0.0
var _climb_blend: float = 0.0
var _hold_blend: float = 0.0
var _animation_speed: float = 1.0
var _state: String = "Idle"
var _load_error: String = ""
var _loading: bool = false
# One distance-driven normalized phase, shared by all grounded gait clips.
# Timed sampling of unrelated clip lengths was the source of phase drift.
const WALK_CYCLE_METERS: float = 1.15
const WADE_CYCLE_METERS: float = 1.05
const RUN_CYCLE_METERS: float = 2.4
var _gait_phase: float = 0.0
var _idle_clock: float = 0.0
var _swim_clock: float = 0.0
var _climb_phase: float = 0.0
var _move_blend: float = 0.0
var _run_blend: float = 0.0
var _last_distance: float = 0.0
var _last_motion_time: float = 0.0
var _last_motion_epoch: int = -1
var _body_yaw: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _motion_initialized: bool = false
var _last_gait_distance: float = 0.0
var _pending_gait_distance: float = 0.0
var _uses_locomotion_signal: bool = false
var _ik_debug: Dictionary = {}
var _hand_ik: RefCounted
var _motion_refinement: RefCounted
var _motion_debug: Dictionary = {}
var _motion_refinement_allowed: bool = true


func _ready() -> void:
	name = "PoolAvatar"
	if _player == null and get_parent() is CharacterBody3D:
		setup(get_parent() as CharacterBody3D)

func setup(player: CharacterBody3D) -> void:
	if not is_instance_valid(player):
		_load_error = "PoolAvatar.setup requires a valid CharacterBody3D."
		return
	if is_instance_valid(_player) and _player != player and _player.has_signal("locomotion_step"):
		if _player.is_connected("locomotion_step", _on_locomotion_step):
			_player.disconnect("locomotion_step", _on_locomotion_step)
	_motion_refinement_allowed = not (OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args() or "--original-avatar-motion" in OS.get_cmdline_user_args())
	var changed_player: bool = _player != player
	_player = player
	_player_properties.clear()
	for property: Dictionary in player.get_property_list():
		_player_properties[String(property.name)] = true
	_uses_locomotion_signal = player.has_signal("locomotion_step")
	if _uses_locomotion_signal and not player.is_connected("locomotion_step", _on_locomotion_step):
		player.connect("locomotion_step", _on_locomotion_step)
	if changed_player:
		_pending_gait_distance = 0.0
		_last_gait_distance = 0.0
		_cache_motion_sample()
	if get_parent() == null:
		player.add_child(self)
	elif get_parent() != player:
		reparent(player, false)
	transform = Transform3D.IDENTITY
	var camera_node: Node = player.get_node_or_null("ViewCamera")
	if player.has_method("get_view_camera"):
		camera_node = player.call("get_view_camera") as Node
	if camera_node is Camera3D:
		set_first_person_camera(camera_node as Camera3D)
	if _model == null and not _loading:
		_load_visual()

func set_first_person_camera(camera: Camera3D) -> void:
	_camera = camera
	if is_instance_valid(_camera):
		# Retain the dynamic body; remove the head and planar-reflection marker.
		_camera.cull_mask = (_camera.cull_mask | BODY_LAYER) & ~(HEAD_LAYER | PLANAR_CLIP_MARKER)

func _load_visual() -> void:
	_loading = true
	_load_error = ""
	var packed: PackedScene = avatar_scene
	if packed == null and ResourceLoader.exists(model_path):
		packed = load(model_path) as PackedScene
	if packed == null:
		_load_error = "Avatar scene is unavailable: " + model_path
		_loading = false
		return
	var instance: Node = packed.instantiate()
	if not instance is Node3D or instance is CollisionObject3D:
		instance.free()
		_load_error = "Avatar scene root must be a visual Node3D, not a physics body."
		_loading = false
		return
	_model = instance as Node3D
	add_child(_model)
	_model.position += body_visual_offset
	# No imported collision object is allowed to interfere with native physics.
	_remove_physics_nodes(_model)
	_find_rig(_model)
	_configure_meshes(_model)
	if _skeleton == null or _animation_player == null:
		_load_error = "Avatar requires a Skeleton3D and AnimationPlayer."
	else:
		_discover_clips()
		_build_animation_tree()
	_loading = false

func _remove_physics_nodes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is CollisionPolygon3D:
			node.remove_child(child)
			child.free()
		else:
			_remove_physics_nodes(child)

func _find_rig(node: Node) -> void:
	if node is Skeleton3D and _skeleton == null:
		_skeleton = node as Skeleton3D
	if node is AnimationPlayer and _animation_player == null:
		_animation_player = node as AnimationPlayer
	for child: Node in node.get_children():
		_find_rig(child)

func _configure_meshes(node: Node) -> void:
	# Snapshot children before creating shadow siblings, avoiding recursive copies.
	for child: Node in node.get_children():
		_configure_meshes(child)
	if not node is MeshInstance3D:
		return
	var mesh_instance := node as MeshInstance3D
	_configure_surface_materials(mesh_instance)
	if String(mesh_instance.name).begins_with("Head_"):
		mesh_instance.layers = HEAD_LAYER
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_head_meshes.append(mesh_instance)
		var shadow := MeshInstance3D.new()
		shadow.name = "Shadow_" + String(mesh_instance.name)
		shadow.mesh = mesh_instance.mesh
		shadow.skin = mesh_instance.skin
		shadow.skeleton = mesh_instance.skeleton
		shadow.transform = mesh_instance.transform
		shadow.material_override = mesh_instance.material_override
		shadow.material_overlay = mesh_instance.material_overlay
		shadow.extra_cull_margin = mesh_instance.extra_cull_margin
		shadow.layers = BODY_LAYER
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		for surface: int in mesh_instance.get_surface_override_material_count():
			shadow.set_surface_override_material(surface, mesh_instance.get_surface_override_material(surface))
		# A sibling resolves the same relative skeleton path and shares the same skin.
		mesh_instance.get_parent().add_child(shadow)
		_shadow_meshes.append(shadow)
	else:
		mesh_instance.layers = BODY_LAYER
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_body_meshes.append(mesh_instance)

func _configure_surface_materials(instance: MeshInstance3D) -> void:
	if instance.mesh == null:
		return
	for surface: int in instance.mesh.get_surface_count():
		var original: Material = instance.get_active_material(surface)
		instance.set_surface_override_material(surface, _avatar_material(original))
	# Surface overrides now preserve any imported whole-mesh override as well.
	instance.material_override = null
	if instance.material_overlay != null:
		instance.material_overlay = _avatar_material(instance.material_overlay)

func _channel_mask(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0.0, 0.0, 0.0, 1.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Vector4(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0.0)
	return Vector4(1.0, 0.0, 0.0, 0.0)

func _avatar_material(original: Material) -> ShaderMaterial:
	var key: int = original.get_instance_id() if original != null else 0
	if _surface_materials.has(key):
		return _surface_materials[key]
	var result := ShaderMaterial.new()
	result.shader = AVATAR_SHADER
	result.resource_name = (original.resource_name if original != null else "Avatar default") + " | planar-aware PBR"
	var source := original as BaseMaterial3D
	if source != null:
		result.render_priority = source.render_priority
		result.set_shader_parameter("albedo_color", source.albedo_color)
		result.set_shader_parameter("albedo_texture", source.albedo_texture)
		result.set_shader_parameter("has_albedo_texture", source.albedo_texture != null)
		result.set_shader_parameter("roughness_value", source.roughness)
		result.set_shader_parameter("roughness_texture", source.roughness_texture)
		result.set_shader_parameter("has_roughness_texture", source.roughness_texture != null)
		result.set_shader_parameter("roughness_channel", _channel_mask(source.roughness_texture_channel))
		result.set_shader_parameter("metallic_value", source.metallic)
		result.set_shader_parameter("metallic_texture", source.metallic_texture)
		result.set_shader_parameter("has_metallic_texture", source.metallic_texture != null)
		result.set_shader_parameter("metallic_channel", _channel_mask(source.metallic_texture_channel))
		result.set_shader_parameter("specular_value", source.metallic_specular)
		result.set_shader_parameter("normal_texture", source.normal_texture)
		result.set_shader_parameter("normal_enabled", source.normal_enabled and source.normal_texture != null)
		result.set_shader_parameter("normal_scale", source.normal_scale)
		result.set_shader_parameter("ao_texture", source.ao_texture)
		result.set_shader_parameter("ao_enabled", source.ao_enabled and source.ao_texture != null)
		result.set_shader_parameter("ao_channel", _channel_mask(source.ao_texture_channel))
		result.set_shader_parameter("ao_light_affect", source.ao_light_affect)
		result.set_shader_parameter("emission_color", source.emission)
		result.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
		result.set_shader_parameter("emission_enabled", source.emission_enabled)
		result.set_shader_parameter("emission_texture", source.emission_texture)
		result.set_shader_parameter("has_emission_texture", source.emission_texture != null)
		result.set_shader_parameter("emission_multiply", source.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)
		result.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
		result.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
		result.set_shader_parameter("vertex_color_albedo", source.vertex_color_use_as_albedo)
		result.set_shader_parameter("texture_repeat_enabled", source.texture_repeat)
		result.set_shader_parameter("source_cull_mode", source.cull_mode)
		result.set_shader_parameter("alpha_scissor_enabled", source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
		result.set_shader_parameter("alpha_scissor_threshold", source.alpha_scissor_threshold)
		if source is ORMMaterial3D:
			var orm: Texture2D = (source as ORMMaterial3D).orm_texture
			for texture_name: String in ["roughness_texture", "metallic_texture", "ao_texture"]:
				result.set_shader_parameter(texture_name, orm)
			result.set_shader_parameter("has_roughness_texture", orm != null)
			result.set_shader_parameter("has_metallic_texture", orm != null)
			result.set_shader_parameter("ao_enabled", source.ao_enabled and orm != null)
			result.set_shader_parameter("roughness_channel", Vector4(0.0, 1.0, 0.0, 0.0))
			result.set_shader_parameter("metallic_channel", Vector4(0.0, 0.0, 1.0, 0.0))
			result.set_shader_parameter("ao_channel", Vector4(1.0, 0.0, 0.0, 0.0))
	_surface_materials[key] = result
	return result

func _discover_clips() -> void:
	for wanted: String in REQUIRED_CLIPS:
		for imported: StringName in _animation_player.get_animation_list():
			# Blender/glTF names may have an action, armature or library prefix.
			var leaf: String = String(imported).replace("|", "/").replace(":", "/").get_file()
			if leaf.to_lower() == wanted.to_lower():
				_clips[wanted] = imported
				# glTF has no loop flag; imported authored cycles must loop at runtime.
				_animation_player.get_animation(imported).loop_mode = Animation.LOOP_LINEAR
				break
	var missing: Array[String] = []
	for wanted: String in REQUIRED_CLIPS:
		if not _clips.has(wanted):
			missing.append(wanted)
	if not missing.is_empty():
		_load_error = "Missing avatar clips: " + ", ".join(missing)

func _animation_node(clip: String) -> AnimationNodeAnimation:
	var result := AnimationNodeAnimation.new()
	result.animation = StringName(_clips.get(clip, _clips.get("Idle", "")))
	return result

func _blend_node() -> AnimationNodeBlend2:
	var result := AnimationNodeBlend2.new()
	result.sync = true
	return result

func _build_animation_tree() -> void:
	if not _clips.has("Idle"):
		return
	var graph := AnimationNodeBlendTree.new()
	for clip: String in REQUIRED_CLIPS:
		graph.add_node(clip, _animation_node(clip))
		graph.add_node(clip + "Seek", AnimationNodeTimeSeek.new())
		graph.connect_node(clip + "Seek", 0, clip)
	graph.add_node("RunBlend", _blend_node())
	graph.connect_node("RunBlend", 0, "WalkSeek")
	graph.connect_node("RunBlend", 1, "RunSeek")
	graph.add_node("WadeBlend", _blend_node())
	graph.connect_node("WadeBlend", 0, "RunBlend")
	graph.connect_node("WadeBlend", 1, "WadeSeek")
	graph.add_node("MoveBlend", _blend_node())
	graph.connect_node("MoveBlend", 0, "IdleSeek")
	graph.connect_node("MoveBlend", 1, "WadeBlend")
	graph.add_node("SwimBlend", _blend_node())
	graph.connect_node("SwimBlend", 0, "MoveBlend")
	graph.connect_node("SwimBlend", 1, "SwimSeek")
	graph.add_node("ClimbBlend", _blend_node())
	graph.connect_node("ClimbBlend", 0, "SwimBlend")
	graph.connect_node("ClimbBlend", 1, "ClimbSeek")
	var hold := _blend_node()
	hold.filter_enabled = true
	if _clips.has("Hold"):
		var animation: Animation = _animation_player.get_animation(_clips["Hold"])
		for track: int in animation.get_track_count():
			var path: NodePath = animation.track_get_path(track)
			if _is_upper_body_track(path):
				hold.set_filter_path(path, true)
				if not _hold_filter_paths.has(path):
					_hold_filter_paths.append(path)
	graph.add_node("HoldBlend", hold)
	graph.connect_node("HoldBlend", 0, "ClimbBlend")
	graph.connect_node("HoldBlend", 1, "HoldSeek")
	graph.connect_node("output", 0, "HoldBlend")
	_tree = AnimationTree.new()
	_tree.name = "AvatarAnimationTree"
	add_child(_tree)
	_tree.tree_root = graph
	_tree.anim_player = _tree.get_path_to(_animation_player)
	var animation_root: Node = _animation_player.get_node(_animation_player.root_node)
	_tree.root_node = _tree.get_path_to(animation_root)
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.deterministic = true
	_animation_player.stop()
	_tree.active = true
	_write_animation_parameters()
	_tree.advance(0.0)
	_hand_ik = HandIK.new()
	_hand_ik.setup(_skeleton)
	_motion_refinement = MotionRefinement.new()
	_motion_refinement.setup(_skeleton)

func _is_upper_body_track(path: NodePath) -> bool:
	if path.get_subname_count() == 0:
		return false
	var bone_name: String = String(path.get_subname(0)).to_lower()
	for excluded: String in ["root", "hip", "pelvis", "thigh", "shin", "calf", "leg", "foot", "toe"]:
		if bone_name.contains(excluded):
			return false
	for included: String in ["spine", "chest", "clavicle", "shoulder", "arm", "hand", "wrist", "finger", "thumb", "index", "middle", "ring", "little"]:
		if bone_name.contains(included):
			return true
	return false

func _player_value(property_name: String, fallback: Variant) -> Variant:
	return _player.get(property_name) if _player_properties.has(property_name) else fallback

func _cache_motion_sample() -> void:
	_last_distance = float(_player_value("locomotion_distance", 0.0))
	_last_motion_time = float(_player_value("locomotion_time", 0.0))
	_last_motion_epoch = int(_player_value("locomotion_epoch", 0))
	_last_position = _player.global_position
	_motion_initialized = true

func _integrate_locomotion(displacement: Vector3, delta: float, distance_override: float = -1.0) -> void:
	if delta <= 0.0:
		return
	var enabled: bool = bool(_player_value("enabled", true))
	if _motion_refinement_allowed and motion_refinement_enabled and _motion_refinement != null:
		_motion_refinement.integrate(displacement, delta, _player.global_rotation.y, int(_player_value("locomotion_epoch", 0)), enabled)
	var climbing: bool = enabled and is_instance_valid(_player_value("climbing", null))
	var swimming: bool = enabled and bool(_player_value("_swimming", false)) and not climbing
	var wading: bool = enabled and bool(_player_value("_in_water", false)) and not swimming and not climbing
	var travelled: float = Vector2(displacement.x, displacement.z).length() if distance_override < 0.0 else distance_override
	_target_speed = minf(RUN_SPEED, travelled / delta) if enabled else 0.0
	var blend_delta: float = 1.0 - exp(-transition_rate * delta)
	_speed = lerpf(_speed, _target_speed, blend_delta)
	_move_blend = lerpf(_move_blend, clampf(_target_speed / 0.28, 0.0, 1.0), blend_delta)
	_run_blend = lerpf(_run_blend, clampf((_target_speed-WALK_SPEED)/(RUN_SPEED-WALK_SPEED),0.0,1.0), blend_delta)
	_wade_blend = lerpf(_wade_blend, 1.0 if wading else 0.0, blend_delta)
	var cycle_distance: float = lerpf(lerpf(WALK_CYCLE_METERS,RUN_CYCLE_METERS,_run_blend),WADE_CYCLE_METERS,_wade_blend)
	if enabled and not swimming and not climbing:
		# Sign each actual physics displacement, not the final velocity of a render
		# interval that may contain both backward and forward travel.
		var direction: float = -1.0 if displacement.dot(-_player.global_basis.z) < -0.05 * travelled else 1.0
		_gait_phase = fposmod(_gait_phase + direction * travelled / cycle_distance, 1.0)
		_pending_gait_distance += travelled
	_animation_speed = _target_speed / cycle_distance

func _on_locomotion_step(displacement: Vector3, delta: float) -> void:
	# This path is independent of visibility and render frequency. It only updates
	# scalar locomotion state; AnimationTree and IK are still sampled on render.
	if not is_instance_valid(_player):
		return
	var epoch: int = int(_player_value("locomotion_epoch", 0))
	if epoch != _last_motion_epoch:
		_pending_gait_distance = 0.0
		_last_gait_distance = 0.0
		_last_motion_epoch = epoch
	_integrate_locomotion(displacement, delta)

func _sample_fallback_locomotion(delta: float) -> void:
	# Alternate/test controllers without the signal retain distance-driven gait.
	# Only a physics signal can disambiguate a within-render direction reversal.
	var displacement: Vector3 = _player.global_position - _last_position
	displacement.y = 0.0
	var travelled: float = displacement.length() if _motion_initialized else 0.0
	var interval: float = delta
	if _motion_initialized and _player_properties.has("locomotion_distance"):
		travelled = maxf(0.0, float(_player_value("locomotion_distance", 0.0)) - _last_distance)
		interval = maxf(0.0, float(_player_value("locomotion_time", 0.0)) - _last_motion_time)
	if travelled > maxf(2.0, RUN_SPEED * interval * 2.0) or int(_player_value("locomotion_epoch", 0)) != _last_motion_epoch:
		travelled = 0.0
	_integrate_locomotion(displacement, interval if interval > 0.000001 else delta, travelled)

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or _tree == null or delta <= 0.0:
		return
	var enabled: bool = bool(_player_value("enabled", true))
	if _uses_locomotion_signal:
		if int(_player_value("locomotion_epoch", 0)) != _last_motion_epoch:
			_pending_gait_distance = 0.0
		# Disabled controllers do not emit movement. Ease only the stopped weights;
		# no phase or distance is advanced while a menu is open.
		if not enabled:
			_integrate_locomotion(Vector3.ZERO, delta)
	else:
		_sample_fallback_locomotion(delta)
	_last_gait_distance = _pending_gait_distance
	_pending_gait_distance = 0.0
	_cache_motion_sample()
	var climbing: bool = enabled and is_instance_valid(_player_value("climbing", null))
	var swimming: bool = enabled and bool(_player_value("_swimming", false)) and not climbing
	var wading: bool = enabled and bool(_player_value("_in_water", false)) and not swimming and not climbing
	var held_body: RigidBody3D = _player_value("held", null)
	var holding: bool = is_instance_valid(held_body) and not climbing and not swimming
	var carry_intent: float = 0.0
	if holding:
		var to_prop: Vector3 = held_body.global_position-(_player.global_position+Vector3.UP*1.30)
		carry_intent = 1.0-smoothstep(0.55,0.85,to_prop.length())
	var blend_delta: float = 1.0 - exp(-transition_rate * delta)
	_swim_blend = lerpf(_swim_blend, 1.0 if swimming else 0.0, blend_delta)
	_climb_blend = lerpf(_climb_blend, 1.0 if climbing else 0.0, blend_delta)
	_hold_blend = lerpf(_hold_blend, carry_intent, blend_delta)
	_state = "Climb" if climbing else ("Swim" if swimming else ("Wade" if wading else ("Run" if _target_speed > WALK_SPEED+0.15 else ("Walk" if _target_speed > 0.06 else "Idle"))))
	var real_motion: Vector3 = _player.get_real_velocity()
	var local_motion: Vector3 = _player.global_basis.inverse()*real_motion
	var wanted_yaw: float = _body_yaw
	if Vector2(local_motion.x,local_motion.z).length()>0.1:
		if local_motion.z>0.08:local_motion = -local_motion
		wanted_yaw = atan2(-local_motion.x,-local_motion.z)
		# Carry keeps shoulders facing the grip; ordinary strafe aligns the legs.
		if holding:wanted_yaw = clampf(wanted_yaw,-0.26,0.26)
	# Carry changes the yaw goal, so stored and displayed body yaw stay aligned.
	wanted_yaw = CarryContact.facing_yaw(wanted_yaw, _hold_blend)
	_body_yaw = lerp_angle(_body_yaw,wanted_yaw,1.0-exp(-10.0*delta))
	_model.rotation.y = _body_yaw
	_idle_clock += delta
	if enabled:
		_swim_clock += delta * clampf(0.65 + _target_speed * 0.12, 0.65, 1.25)
		_climb_phase = fposmod(_climb_phase + absf(_player.velocity.y) * delta / 0.8, 1.0)
	_write_animation_parameters()
	# Explicit time seeks sample all gait clips at one normalized phase. Zero
	# additional advance avoids accidentally adding a second render-delta clock.
	_tree.advance(0.0)
	# Frame-local body mechanics precede terrain leg placement (when enabled)
	# and grip IK. AnimationTree overwrites the correction every render.
	if _motion_refinement_allowed and motion_refinement_enabled and _motion_refinement != null:
		var terrain_depth: float = float(_player.call("_water_depth", _player.global_position)) if _player.has_method("_water_depth") else 0.0
		_motion_debug = _motion_refinement.apply(_idle_clock, _gait_phase, _move_blend, _run_blend, _wade_blend, _hold_blend, maxf(_swim_blend, _climb_blend), _body_yaw, terrain_depth)
	if _hand_ik != null:
		_ik_debug = _hand_ik.apply(_player_value("held", null), _player.global_basis, _hold_blend, delta)

func _seek_clip(clip: String, phase: float) -> void:
	if _clips.has(clip):
		var length: float = _animation_player.get_animation(_clips[clip]).length
		_tree.set("parameters/"+clip+"Seek/seek_request", fposmod(phase,1.0)*length)

func _write_animation_parameters() -> void:
	_tree.set("parameters/MoveBlend/blend_amount", _move_blend)
	_tree.set("parameters/RunBlend/blend_amount", _run_blend)
	_tree.set("parameters/WadeBlend/blend_amount", _wade_blend)
	_tree.set("parameters/SwimBlend/blend_amount", _swim_blend)
	_tree.set("parameters/ClimbBlend/blend_amount", _climb_blend)
	_tree.set("parameters/HoldBlend/blend_amount", _hold_blend)
	for clip: String in ["Walk","Run","Wade"]:
		_seek_clip(clip,_gait_phase)
	_seek_clip("Idle",_idle_clock/2.4)
	_seek_clip("Hold",_idle_clock/2.4)
	_seek_clip("Swim",_swim_clock/1.5)
	_seek_clip("Climb",_climb_phase)

func get_debug_state() -> Dictionary:
	var walk_weight: float = clampf(_speed / WALK_SPEED, 0.0, 1.0)
	var run_weight: float = clampf((_speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var bones: PackedStringArray = []
	if is_instance_valid(_skeleton):
		for bone: int in _skeleton.get_bone_count():
			bones.append(_skeleton.get_bone_name(bone))
	return {
		"loaded": is_instance_valid(_model) and _tree != null and _load_error.is_empty(),
		"error": _load_error,
		"model_path": model_path,
		"body_visual_offset": body_visual_offset,
		"visual_model_position": _model.position if is_instance_valid(_model) else Vector3.ZERO,
		"state": _state,
		"planar_speed": _target_speed,
		"blended_speed": _speed,
		"animation_speed": _animation_speed,
		"gait_phase":_gait_phase,"distance_driven":true,"gait_distance_delta":_last_gait_distance,
		"physics_driven_gait":_uses_locomotion_signal,
		"motion_refinement":_motion_debug,"motion_refinement_enabled":motion_refinement_enabled and _motion_refinement_allowed,
		"motion_refinement_desktop_allowed":_motion_refinement_allowed,
		"move_blend":_move_blend,"run_blend":_run_blend,"hand_ik":_ik_debug,
		"locomotion_blends": {"idle": 1.0 - walk_weight, "walk": walk_weight * (1.0 - run_weight), "run": run_weight},
		"hold_blend": _hold_blend,
		"wade_blend": _wade_blend,
		"swim_blend": _swim_blend,
		"climb_blend": _climb_blend,
		"clips": _clips.duplicate(),
		"skeleton_path": String(get_path_to(_skeleton)) if is_instance_valid(_skeleton) else "",
		"bone_count": bones.size(),
		"bones": bones,
		"body_mesh_count": _body_meshes.size(),
		"head_mesh_count": _head_meshes.size(),
		"shadow_head_count": _shadow_meshes.size(),
		"hold_filter_track_count": _hold_filter_paths.size(),
		"head_layer": HEAD_LAYER,
		"body_layer": BODY_LAYER,
		"material_shader": AVATAR_SHADER.resource_path,
		"material_count": _surface_materials.size(),
		"planar_clip_marker": PLANAR_CLIP_MARKER,
		"planar_clip_height": PLANAR_CLIP_HEIGHT,
		"camera_hides_head": is_instance_valid(_camera) and (_camera.cull_mask & HEAD_LAYER) == 0,
		"camera_planar_clip_disabled": is_instance_valid(_camera) and (_camera.cull_mask & PLANAR_CLIP_MARKER) == 0,
		"animation_tree_active": _tree != null and _tree.active,
		"visual_only": true,
	}
