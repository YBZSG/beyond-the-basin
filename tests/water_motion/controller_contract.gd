extends SceneTree
## Real CharacterBody3D/Jolt and RigidBody3D fixture at fixed simulation rates.
## Headless CPU contract, not a full-scene, graphical or GPU-FPS acceptance test.
const Player = preload("res://scripts/player/pool_player.gd")
const Motion = preload("res://scripts/player/water_motion_state.gd")
const Prop = preload("res://scripts/player/pool_prop_body.gd")
var hz: int = 60
var dt: float = 1.0 / 60.0
var checks: Dictionary = {}
var failures: Array[String] = []
var metrics: Dictionary = {}
var arena: Node3D
var player: CharacterBody3D
var water: Node3D
var event_log: Array[Dictionary] = []
var release_log: Array[Dictionary] = []
var locomotion_states: Array[Dictionary] = []

class WaterSpy extends Node3D:
	var wet: bool = true
	var surface: float = 1.04
	var depth: float = 1.04
	var split: bool = false
	var feet: int = 0
	var wave_power: float = 0.0
	var wake_width: float = 0.0
	var wake_impulse: float = 0.0
	var dipoles: int = 0
	var splashes: int = 0
	func is_water_at(_p: Vector3) -> bool: return wet
	func surface_height_at(_p: Vector3) -> float: return surface
	func depth_at(p: Vector3) -> float: return (1.04 if p.z > 0.0 else 2.20) if split else depth
	func foot_splash(_p: Vector3, _speed: float, _depth: float, _direction: Vector2) -> void: splashes += 1
	func wave_impact(_p: Vector3, power: float) -> void: feet += 1; wave_power = maxf(wave_power, power)
	func wake_dipole(_p: Vector3, _d: Vector2, _speed: float, _sigma: float) -> void: dipoles += 1
	func push_wake(_p: Vector3, impulse: Vector2, sigma: float) -> void: wake_width = sigma; wake_impulse += impulse.length()
	func push(_p: Vector3, _i: Vector2, _sigma: float) -> void: pass
	func player_impact(_p: Vector3, _power: float) -> void: pass
	func current_velocity_at(_p: Vector3) -> Vector2: return Vector2.ZERO
	func slope_at(_p: Vector3, _r: float) -> Vector4: return Vector4.ZERO

class PropSpy extends "res://scripts/player/pool_prop_body.gd":
	var target_writes: int = 0
	var rotation_writes: int = 0
	func set_hold_target(target: Vector3) -> void:
		target_writes += 1
		super.set_hold_target(target)
	func set_carry_rotation(target: Quaternion, weight: float) -> void:
		rotation_writes += 1
		super.set_carry_rotation(target, weight)

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	dt = 1.0 / float(hz)
	Engine.physics_ticks_per_second = hz
	_run.call_deferred()

func _check(name: String, passed: bool) -> void:
	checks[name] = passed
	if not passed: failures.append(name)

func _floor(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = size; shape.shape = box
	body.add_child(shape); arena.add_child(body); body.position = center

func _make(surface: float, depth: float, floor_y: float, spawn: Vector3) -> void:
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	for action in ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump", "throw_prop", "grab_prop", "interact", "pause"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		Input.action_release(action)
	arena = Node3D.new(); root.add_child(arena)
	water = WaterSpy.new(); water.surface = surface; water.depth = depth; arena.add_child(water)
	_floor(Vector3(0.0, floor_y - 0.10, 0.0), Vector3(20.0, 0.20, 20.0))
	player = Player.new(); arena.add_child(player); player.set_physics_process(false)
	player.set_water(water); player.enabled = true; player.water_motion_actions_enabled = true
	player.warp_to(spawn, spawn + Vector3(0.0, 1.60, -1.0))
	event_log.clear(); release_log.clear(); locomotion_states.clear()
	player.locomotion_step.connect(func(_displacement: Vector3, _delta: float): locomotion_states.append(player.get_action_state().duplicate()))
	player.action_event.connect(func(kind: String, state: Dictionary): event_log.append({"kind": kind, "state": state.duplicate()}))
	player.throw_released.connect(func(body: RigidBody3D, charge: float, direction: Vector3, speed: float, serial: int):
		release_log.append({"held_is_null": player.held == null, "body_held": body.held, "charge": charge, "direction": direction, "speed": speed, "serial": serial, "velocity": body.linear_velocity}))
	await _ticks(4)

func _ticks(count: int) -> void:
	for index in count:
		await physics_frame
		player._physics_process(dt)

func _seconds(seconds: float) -> void:
	await _ticks(ceili(seconds * hz))

func _action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new(); event.action = name; event.pressed = pressed
	player._unhandled_input(event)

func _wheel(button: int, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new(); event.pressed = true; event.button_index = button; event.factor = factor
	player._unhandled_input(event)

func _prop() -> RigidBody3D:
	var prop := PropSpy.new()
	prop.configure("duck", {"radius": 0.12, "mass": 0.30}, water)
	arena.add_child(prop)
	prop.global_position = player.get_hold_anchor()
	return prop

func _test_supported_and_boundary() -> void:
	await _make(1.04, 1.04, 0.0, Vector3(0.0, 0.02, 3.0))
	Input.action_press("move_forward")
	await _seconds(2.0)
	Input.action_release("move_forward")
	var state: Dictionary = player.get_action_state()
	_check("no_clearance_queries_when_supported_wading", state.swim_clearance_queries == 0)
	_check("supported_1_04m_is_wade", state.mode == "wade" and state.grounded and not state.swimming)
	_check("supported_footfalls_remain_real_grounded", water.feet >= 3)
	_check("broad_continuous_wading_wake_preserved", water.wake_impulse > 1.0 and is_equal_approx(water.wake_width, 0.62))
	_check("small_foot_ripples_without_forward_slaps", water.wave_power > 0.05 and water.wave_power < 0.15 and water.dipoles == 0)
	_check("no_foot_splash_particles", water.splashes == 0)
	_check("camera_eye_and_capsule_unchanged", is_equal_approx(player.camera.position.y, 1.60) and is_equal_approx(player.get_node("PlayerCapsule").shape.height, 1.64) and player.camera.rotation.z == 0.0)
	var base_y: float = player.position.y
	var toggles: int = 0
	for index in hz * 2:
		water.surface = 1.04 + sin(float(index) * 0.71) * 0.05
		water.depth = 1.25 + sin(float(index) * 0.63) * 0.05
		await _ticks(1)
		if player.get_action_state().swimming: toggles += 1
	_check("supported_boundary_005m_drift_no_swim_or_lift", toggles == 0 and absf(player.position.y - base_y) < 0.006)
	metrics.supported_root_y = player.position.y

func _test_deep_float_and_space() -> void:
	await _make(0.0, 2.20, -2.20, Vector3(0.0, -2.18, 2.0))
	# A submerged-floor spawn must surface, not remain permanently supported Wade.
	await _seconds(4.0)
	var state: Dictionary = player.get_action_state()
	_check("deep_supported_spawn_surfaces_to_swim", state.swimming and not state.grounded)
	_check("physical_eye_surface_clearance_012m", absf(state.eye_clearance - 0.12) < 0.018)
	_check("float_root_not_legacy_standing_torso", absf(player.position.y + 1.48) < 0.018)
	var before_pitch: float = player.camera.rotation.x
	var max_eye: float = state.eye_clearance
	_action("jump", true)
	for index in hz * 2:
		await _ticks(1)
		max_eye = maxf(max_eye, player.get_action_state().eye_clearance)
	_check("space_swim_up_bounded_not_dolphin_jump", max_eye < 0.20 and player.get_action_state().swimming)
	_check("swim_never_forces_camera_pitch", player.camera.rotation.x == before_pitch)
	metrics.float_eye_clearance = state.eye_clearance
	metrics.space_max_eye_clearance = max_eye
	# Mid-band depth changes and wave drift cannot chatter a settled swim.
	var swim_ticks: int = 0
	for index in hz * 2:
		water.depth = 1.20 + sin(float(index) * 0.63) * 0.05
		water.surface = sin(float(index) * 0.37) * 0.05
		await _ticks(1)
		if player.get_action_state().swimming: swim_ticks += 1
	_check("unsupported_boundary_005m_drift_no_swim_chatter", swim_ticks == hz * 2)
	var time_before: float = player.get_action_state().time
	var stroke_before: float = player.get_action_state().stroke_phase
	var old_epoch: int = player.get_action_state().epoch
	player.set_enabled(false)
	await _seconds(0.5)
	_check("pause_freezes_action_time_and_stroke", player.get_action_state().time == time_before and player.get_action_state().stroke_phase == stroke_before)
	player.set_enabled(true)
	_check("pause_resume_invalidates_interpolation_epoch", player.get_action_state().epoch == old_epoch + 2)
	player.warp_to(Vector3(0.0, 1.0, 2.0), Vector3(0.0, 2.6, 1.0))
	_check("warp_clears_swim_jump_release_interpolation", not player.get_action_state().swimming and player.get_action_state().throw_release_age == -1.0 and player.get_action_state().stroke_phase == 0.0)

func _test_walk_swim_walk() -> void:
	await _make(0.0, 2.20, -2.20, Vector3(0.0, -1.02, 2.0))
	_floor(Vector3(0.0, -1.14, 3.0), Vector3(10.0, 0.20, 6.0))
	# Gentle ramp from deep floor (-2.20) to supported bath (-1.04).
	var ramp := StaticBody3D.new(); ramp.collision_layer = 1
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.20, 3.10); collision.shape = box; ramp.add_child(collision); arena.add_child(ramp)
	ramp.rotation.x = -atan2(1.16, 3.0); ramp.position = Vector3(0.0, -1.72, -1.50)
	water.split = true
	await _seconds(0.5)
	_check("route_starts_wading", player.get_action_state().mode == "wade")
	Input.action_press("move_forward"); await _seconds(6.0); Input.action_release("move_forward")
	_check("route_wade_to_swim_real_collisions", player.get_action_state().swimming)
	Input.action_press("move_back"); await _seconds(6.0); Input.action_release("move_back")
	_check("route_swim_to_wade_real_ramp_support", player.get_action_state().mode == "wade" and player.is_on_floor())
	metrics.route_final_position = str(player.position)

func _test_jump_carry_and_throw() -> void:
	await _make(-2.0, 0.0, 0.0, Vector3(0.0, 0.02, 2.0)); water.wet = false
	await _seconds(0.3)
	var prop: RigidBody3D = _prop(); player.grab_prop(prop)
	await _seconds(0.2)
	_action("jump", true)
	var starting_y: float = player.position.y
	await _ticks(1)
	_check("locomotion_signal_observes_post_collision_takeoff", not locomotion_states.is_empty() and locomotion_states.back().jump_phase == "takeoff" and not locomotion_states.back().grounded)
	_check("jump_real_liftoff_first_tick_while_carrying", player.position.y > starting_y + 0.04 and not player.is_on_floor() and player.held == prop and player.get_action_state().jump_phase == "takeoff")
	var max_y: float = player.position.y
	var saw_fall: bool = false
	for index in hz * 2:
		await _ticks(1); max_y = maxf(max_y, player.position.y)
		saw_fall = saw_fall or player.get_action_state().jump_phase == "fall"
	var land_events: Array = event_log.filter(func(item: Dictionary): return item.kind == "land")
	_check("jump_air_fall_and_true_landing_event", saw_fall and not land_events.is_empty() and player.is_on_floor())
	_check("locomotion_signal_observes_same_tick_landing", locomotion_states.any(func(item: Dictionary): return item.jump_phase == "land" and item.grounded and item.landing_age == 0.0))
	_check("landing_impact_measures_pre_collision_speed", not land_events.is_empty() and land_events.back().state.landing_impulse > 3.0)
	metrics.jump_apex = max_y
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check("wheel_up_moves_prop_away", absf(player.held_distance - 0.68) < 0.0001)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check("wheel_down_returns_near_carry", absf(player.held_distance - 0.48) < 0.0001)
	_action("throw_prop", true); await _seconds(0.55)
	_check("right_hold_charges_without_release", player.get_action_state().throw_phase == "charging" and player.get_charge() > 0.45 and player.held == prop)
	var charge: float = player.get_charge()
	var before_release: Vector3 = prop.position
	_action("throw_prop", false)
	_check("release_event_same_tick_as_launch", release_log.size() == 1 and release_log[0].held_is_null and not release_log[0].body_held and prop.position == before_release and player.get_action_state().throw_release_age == 0.0)
	_check("release_event_velocity_is_actual_rigidbody_velocity", release_log.size() == 1 and release_log[0].velocity == prop.linear_velocity and player.get_action_state().throw_release_velocity == prop.linear_velocity)
	_check("charge_controls_original_6_to_17_speed", release_log.size() == 1 and absf(release_log[0].speed - (6.0 + charge * 11.0)) < 0.0001)
	var targets: int = prop.target_writes; var rotations: int = prop.rotation_writes
	await _seconds(0.3)
	_check("released_body_never_receives_hold_target_or_rotation", prop.target_writes == targets and prop.rotation_writes == rotations and prop.position.distance_to(before_release) > 0.2)
	_check("release_followthrough_state", player.get_action_state().throw_phase == "recover")
	await _seconds(0.5)
	_check("throw_followthrough_finishes", player.get_action_state().throw_phase == "none")
	var dropped: RigidBody3D = _prop(); player.grab_prop(dropped)
	_action("throw_prop", true); await _ticks(2); player.interact_action()
	_check("drop_during_charge_cancels_throw", player.held == null and not player._charging and player.get_action_state().release_kind == "drop" and player.get_action_state().throw_phase == "none")
	_action("throw_prop", false)
	_check("later_right_release_cannot_throw_dropped_body", release_log.size() == 1)
	metrics.release_charge = charge
	metrics.release_velocity = str(release_log[0].velocity) if not release_log.is_empty() else "none"


func _test_swim_walls_and_carry() -> void:
	await _make(0.0, 2.20, -2.20, Vector3(0.0, -1.5, 0.0))
	for center in [Vector3(-1.5, -0.5, 0.0), Vector3(1.5, -0.5, 0.0)]:
		_floor(center, Vector3(0.50, 5.0, 4.0))
	for center in [Vector3(0.0, -0.5, -1.5), Vector3(0.0, -0.5, 1.5)]:
		_floor(center, Vector3(4.0, 5.0, 0.50))
	await _seconds(2.0)
	var prop: RigidBody3D = _prop(); player.grab_prop(prop)
	await _seconds(0.5)
	_check("genuine_swim_carry_remains_held", player.get_action_state().swimming and player.held == prop and prop.held and prop.target_writes > 0)
	var max_radius: float = 0.0
	for direction in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_press(direction)
		await _seconds(3.0)
		Input.action_release(direction)
		max_radius = maxf(max_radius, maxf(absf(player.position.x), absf(player.position.z)))
		_check("swim_%s_wall_capsule_blocked" % direction, max_radius < 0.936 and player.position.is_finite() and player.get_action_state().swimming)
	_check("swim_wall_contact_does_not_raise_camera", absf(player.get_action_state().eye_clearance - 0.12) < 0.02)
	metrics.swim_wall_max_center_abs = max_radius
	metrics.swim_collision_scope = "Upright capsule core only, not authored horizontal limb envelope."
	_action("throw_prop", true); await _seconds(0.25); _action("throw_prop", false)
	_check("swim_throw_release_keeps_unchanged_input_semantics", release_log.size() == 1 and player.held == null and player.get_action_state().swimming)
	var age_before: float = player.get_action_state().throw_release_age
	player.set_enabled(false); await _seconds(0.2); player.set_enabled(true)
	await _ticks(1)
	_check("paused_release_does_not_replay_after_resume", age_before == 0.0 and player.get_action_state().throw_phase == "none" and player.get_action_state().throw_release_age == -1.0)

func _test_input_edge_cases() -> void:
	await _make(-2.0, 0.0, 0.0, Vector3(0.0, 0.02, 2.0)); water.wet = false
	await _seconds(0.3)
	var prop: RigidBody3D = _prop(); player.grab_prop(prop)
	_wheel(MOUSE_BUTTON_WHEEL_UP, 50.0)
	_check("scroll_distance_upper_bound_preserved", player.held_distance == player.HELD_DISTANCE_MAX)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, 50.0)
	_check("scroll_distance_lower_bound_preserved", player.held_distance == player.HELD_DISTANCE_MIN)
	_action("throw_prop", true); _action("throw_prop", false)
	_check("tap_throw_releases_at_original_minimum_speed", release_log.size() == 1 and release_log.back().speed == 6.0)
	var second: RigidBody3D = _prop(); player.grab_prop(second)
	_action("throw_prop", true); await _seconds(1.4)
	_check("full_charge_is_clamped_at_one", player.get_charge() == 1.0)
	_action("throw_prop", false)
	_check("full_charge_releases_at_original_maximum_speed", release_log.size() == 2 and release_log.back().speed == 17.0 and release_log.back().serial > release_log[0].serial)
	var third: RigidBody3D = _prop(); player.grab_prop(third); player._dragging = true
	_action("throw_prop", true); await _ticks(1); _action("throw_prop", false)
	var count: int = release_log.size()
	_action("grab_prop", false)
	_check("left_release_after_right_throw_cannot_drop_or_retarget", release_log.size() == count and player.get_action_state().release_kind == "throw" and player.held == null)
	var fourth: RigidBody3D = _prop(); player.grab_prop(fourth); player._dragging = true
	_action("grab_prop", false)
	_check("left_drag_release_remains_drop_not_throw", player.held == null and player.get_action_state().release_kind == "drop" and release_log.size() == count)


func _test_fast_entry_ladder_and_legacy() -> void:
	await _make(0.0, 8.0, -8.0, Vector3(0.0, 1.0, 0.0))
	player.velocity.y = -6.0
	await _seconds(3.0)
	_check("real_fast_deep_entry_captures_without_velocity_gate", player.get_action_state().swimming and absf(player.get_action_state().eye_clearance - 0.12) < 0.04)
	var ladder := Node3D.new(); arena.add_child(ladder)
	ladder.set_meta("base", Vector3(0.0, -2.20, 0.0)); ladder.set_meta("top", Vector3(0.0, 0.50, 0.0)); ladder.set_meta("exit", Vector3(0.0, 0.50, 1.0))
	player.climbing = ladder; player.climb_progress = 1.0
	await _ticks(1)
	_check("ladder_mode_excludes_swim_and_air_actions", player.get_action_state().mode == "ladder" and not player.get_action_state().swimming and player.get_action_state().jump_phase == "grounded")
	await _make(0.0, 2.20, -2.20, Vector3(0.0, -2.18, 0.0))
	player.water_motion_actions_enabled = false
	await _seconds(5.0)
	_check("disabled_feature_runs_zero_clearance_queries", player.get_action_state().swim_clearance_queries == 0)
	# The legacy spring is tick-rate dependent. At 120 Hz the pre-merge
	# controller measured 0.548 m after this five-second trajectory.
	var legacy_eye: float = player.get_action_state().eye_clearance
	metrics.legacy_eye_clearance = legacy_eye
	var legacy_bounds := Vector2(0.45, 0.65) if hz == 120 else Vector2(0.70, 1.10)
	_check("disabled_feature_preserves_legacy_surface_response", legacy_eye > legacy_bounds.x and legacy_eye < legacy_bounds.y)
	var defaults := Player.new()
	var mobile := OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args()
	_check("action_default_matches_platform", defaults.water_motion_actions_enabled == (not mobile and "--legacy-water-actions" not in OS.get_cmdline_user_args()))
	defaults.free()


func _test_supported_neck_depth_deadband() -> void:
	await _make(1.48, 1.48, 0.0, Vector3(0.0, 0.02, 0.0))
	await _seconds(0.3)
	var swimming_frames: int = 0
	for index in hz * 4:
		water.surface = 1.48 + sin(float(index) * dt * TAU * 2.0) * 0.05
		await _ticks(1)
		if player.get_action_state().swimming: swimming_frames += 1
	_check("supported_neck_depth_005m_waves_do_not_chatter", swimming_frames == 0 and player.is_on_floor())
	water.surface = 1.70; water.depth = 1.70
	await _seconds(2.0)
	_check("supported_neck_depth_becomes_swim_when_really_submerged", player.get_action_state().swimming and not player.is_on_floor())
	water.surface = 1.20; water.depth = 1.20
	await _seconds(2.0)
	_check("supported_swimmer_returns_to_wade_after_deadband", player.get_action_state().mode == "wade" and player.is_on_floor())


func _test_swim_stroke_clearance() -> void:
	await _make(0.0, 2.20, -2.20, Vector3(0.0, -1.5, 0.0))
	await _seconds(1.0)
	_check("open_swim_has_full_clearance_and_eight_queries", player.get_action_state().swim_stroke_clearance == 1.0 and player.get_action_state().swim_clearance_queries == 8)
	var prop: RigidBody3D = _prop(); prop.collision_layer = 1; player.grab_prop(prop)
	await _seconds(0.3)
	_check("held_prop_excluded_from_stroke_clearance", player.get_action_state().swim_stroke_clearance == 1.0)
	player.release_prop(); prop.queue_free(); await _ticks(1)
	_floor(Vector3(2.75, -0.5, 0.0), Vector3(0.50, 5.0, 12.0))
	player.rotation.y = -PI / 2.0
	Input.action_press("move_forward"); Input.action_press("sprint")
	var previous: float = player.get_action_state().swim_stroke_clearance
	var max_step: float = 0.0
	var monotone_approach: bool = true
	var exactly_eight: bool = true
	for index in hz * 2:
		await _ticks(1)
		var value: float = player.get_action_state().swim_stroke_clearance
		max_step = maxf(max_step, absf(value - previous))
		monotone_approach = monotone_approach and value <= previous + 0.00001
		exactly_eight = exactly_eight and player.get_action_state().swim_clearance_queries == 8
		previous = value
	Input.action_release("move_forward")
	_check("rotated_swim_approach_clearance_is_monotone", monotone_approach)
	_check("rotated_swim_approach_has_bounded_transition", max_step < 0.40)
	_check("stroke_clearance_exact_zero_at_wall", player.get_action_state().swim_stroke_clearance == 0.0 and player.position.x < 2.19)
	_check("stroke_clearance_query_budget_exactly_eight", exactly_eight)
	metrics.stroke_clearance_max_step = max_step
	metrics.stroke_clearance_queries_per_swim_tick = 8
	Input.action_press("move_back")
	previous = player.get_action_state().swim_stroke_clearance
	var monotone_retreat: bool = true
	for index in hz * 2:
		await _ticks(1)
		var value: float = player.get_action_state().swim_stroke_clearance
		monotone_retreat = monotone_retreat and value + 0.00001 >= previous
		previous = value
	Input.action_release("move_back"); Input.action_release("sprint")
	_check("stroke_clearance_restores_without_jitter", monotone_retreat and previous > 0.99)
	# A warp directly beside a wall must not briefly allow a full first stroke.
	player.warp_to(Vector3(2.15, -1.48, 0.0), Vector3(3.15, 0.12, 0.0))
	var first_swim_clearance: float = -1.0
	for index in ceili(0.3 * hz):
		await _ticks(1)
		if player.get_action_state().swimming:
			first_swim_clearance = player.get_action_state().swim_stroke_clearance
			break
	_check("near_wall_warp_first_swim_frame_is_guarded", first_swim_clearance == 0.0)
	await _make(0.0, 2.20, -2.20, Vector3(0.0, -1.5, 0.0))
	_floor(Vector3(2.75, -0.5, 0.0), Vector3(0.50, 5.0, 12.0))
	_floor(Vector3(0.0, -0.5, -2.75), Vector3(12.0, 5.0, 0.50))
	await _seconds(0.4)
	player.rotation.y = -PI / 4.0
	Input.action_press("move_forward"); Input.action_press("sprint")
	await _seconds(3.0)
	Input.action_release("move_forward"); Input.action_release("sprint")
	await _seconds(0.3)
	_check("diagonal_corner_approach_is_guarded", player.get_action_state().swim_stroke_clearance == 0.0 and player.position.x < 2.19 and player.position.z > -2.19)
	var clearance_min: float = 1.0
	var clearance_max: float = 0.0
	for index in hz * 2:
		player.rotation.y = float(index) * TAU / float(hz * 2)
		await _ticks(1)
		clearance_min = minf(clearance_min, player.get_action_state().swim_stroke_clearance)
		clearance_max = maxf(clearance_max, player.get_action_state().swim_stroke_clearance)
	_check("corner_yaw_changes_have_no_clearance_jitter", clearance_max - clearance_min < 0.001)
	metrics.stroke_clearance_corner_jitter = clearance_max - clearance_min
	player.set_enabled(false); await _ticks(1)
	_check("paused_swim_runs_zero_clearance_queries", player.get_action_state().swim_clearance_queries == 0)

func _test_dwell_numeric() -> void:
	var state = Motion.new()
	state.sample_water(dt, true, 2.20, 1.40, false, -3.0)
	_check("swim_enter_has_dwell_not_one_frame_velocity_gate", not state.swimming)
	for index in ceili(0.14 / dt): state.sample_water(dt, true, 2.20, 1.40, false, -3.0)
	_check("fast_fall_does_not_exclude_real_swim", state.swimming)
	state.sample_water(dt, true, 1.04, 1.04, true, 0.0)
	_check("supported_exit_is_immediate", not state.swimming)
	for index in ceili(0.14 / dt): state.sample_water(dt, true, 2.20, 1.40, false, 0.0)
	state.sample_water(dt, false, 0.0, 0.0, false, 0.0)
	_check("unsupported_exit_has_dwell", state.swimming)
	for index in ceili(0.18 / dt): state.sample_water(dt, false, 0.0, 0.0, false, 0.0)
	_check("unsupported_exit_completes", not state.swimming)

func _run() -> void:
	_check("cpu_headless_no_rendering_device", DisplayServer.get_name() == "headless" and RenderingServer.get_rendering_device() == null)
	_test_dwell_numeric()
	await _test_supported_and_boundary()
	await _test_deep_float_and_space()
	await _test_walk_swim_walk()
	await _test_jump_carry_and_throw()
	await _test_swim_walls_and_carry()
	await _test_input_edge_cases()
	await _test_fast_entry_ladder_and_legacy()
	await _test_supported_neck_depth_deadband()
	await _test_swim_stroke_clearance()
	var result := {"pass": failures.is_empty(), "hz": hz, "checks": checks, "failures": failures, "metrics": metrics, "scope": "CPU headless real CharacterBody3D/Jolt + RigidBody3D fixtures. Fixed simulation time, no GPU or target-PC FPS claim."}
	var path: String = "res://output/water-motion/controller-%dhz.json" % hz
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var output := FileAccess.open(path, FileAccess.WRITE); output.store_string(JSON.stringify(result, "  ") + "\n"); output.close()
	print("WATER_MOTION_CONTROLLER ", JSON.stringify(result))
	quit(0 if result.pass else 1)
