extends "res://scripts/player/pool_player.gd"
## Test-only instrumentation. Baseline delegates untouched production behavior.
var samples: Array = []
var mode := "baseline"
var latest: Dictionary = {}
var accepted := 0
var recovery_steps := 0
var step_events: Array = []

func vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func query(motion: Vector3, margin: float, recovery: bool = false) -> Dictionary:
	var hit := KinematicCollision3D.new()
	var collided := test_move(global_transform, motion, hit, margin, recovery)
	var result := {"hit": collided}
	if collided:
		result.merge({"normal": vector(hit.get_normal()), "position": vector(hit.get_position()), "travel": vector(hit.get_travel()), "remainder": vector(hit.get_remainder()), "depth": hit.get_depth()})
		var body: Object = hit.get_collider()
		if body is CollisionObject3D:
			result.collider = str(hit.get_collider_shape().name)
	return result

func _physics_process(delta: float) -> void:
	var before := global_position
	super._physics_process(delta)
	if latest.is_empty(): return
	latest.after = vector(global_position)
	latest.displacement = vector(global_position - before)
	latest.floor = is_on_floor()
	latest.floor_normal = vector(get_floor_normal())
	latest.after_velocity = vector(velocity)
	latest.slides = []
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body: Object = hit.get_collider()
		var name := ""
		if body is CollisionObject3D:
			name = str(hit.get_collider_shape().name)
		latest.slides.append({"collider": name, "normal": vector(hit.get_normal()), "position": vector(hit.get_position()), "travel": vector(hit.get_travel())})
	if samples.size() > 100: samples.pop_front()
	samples.append(latest)
	latest = {}

func _try_step(delta: float, grounded: bool) -> bool:
	var travel := Vector3(velocity.x, 0.0, velocity.z) * delta
	if global_position.z < -64.0 and global_position.x > 0.45 and global_position.x < 1.2:
		latest = {"p": vector(global_position), "v": vector(velocity), "grounded": grounded,
			"snap": floor_snap_length, "snap_pause": _step_snap_pause,
			"horizontal_default": query(travel, .001), "horizontal_margin": query(travel, safe_margin),
			"full_default": query(velocity * delta, .001), "full_margin": query(velocity * delta, safe_margin),
			"horizontal_recovery": query(travel, safe_margin, true)}
	var old_position := global_position
	var result := false
	if mode in ["baseline", "fallback"]: result = super._try_step(delta, grounded)
	var original_accepted := result
	if not result and mode != "baseline": result = _margin_step(delta, grounded)
	if result and not original_accepted: recovery_steps += 1
	if result:
		accepted += 1
		step_events.append({"from": vector(old_position), "to": vector(global_position), "rise": global_position.y - old_position.y, "grounded": grounded, "original": original_accepted})
	if not latest.is_empty(): latest.stepped = result
	return result

func _margin_step(delta: float, grounded: bool) -> bool:
	# Test candidate only: exact source algorithm, passing the body's margin.
	if not grounded or velocity.y > 0.1: return false
	var travel := Vector3(velocity.x, 0.0, velocity.z) * delta
	if travel.length_squared() < 0.0000001: return false
	var wall := KinematicCollision3D.new()
	var wall_found := false
	if mode == "margin": wall_found = test_move(global_transform, travel, wall, safe_margin)
	elif mode in ["recovery", "fallback"]: wall_found = test_move(global_transform, travel, wall, safe_margin, true)
	elif mode == "default-recovery": wall_found = test_move(global_transform, travel, wall, .001, true)
	elif mode == "motion": wall_found = test_move(global_transform, velocity * delta, wall)
	if not wall_found: return false
	if wall.get_normal().y > 0.5: return false
	var probe := global_position + travel.normalized() * (BODY_RADIUS + travel.length() + 0.03)
	var ray := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * (STEP_HEIGHT + 0.02), probe + Vector3.DOWN * 0.02, 1, [get_rid()])
	var landing := get_world_3d().direct_space_state.intersect_ray(ray)
	if landing.is_empty() or (landing.normal as Vector3).y < cos(floor_max_angle): return false
	var elevation: float = landing.position.y - global_position.y + safe_margin
	if elevation < 0.005 or elevation > STEP_HEIGHT + 0.005: return false
	var raised := global_transform
	if test_move(raised, Vector3.UP * elevation): return false
	raised.origin.y += elevation
	if test_move(raised, travel): return false
	raised.origin += travel
	_step_eye_offset -= elevation
	_step_snap_pause = 0.16
	global_position = raised.origin
	return true
