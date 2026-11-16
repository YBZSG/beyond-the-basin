extends Node3D
## Bounded, persistent physical bed: no decorative substitutes or camera swaps.
const Ball = preload("res://scripts/dreamcore/ballpit/ball_body.gd")
const MAX_BALLS := 4096
var balls: Array[RigidBody3D] = []
var _player: CharacterBody3D
var _paused := true
var _pause_state: Dictionary = {}
var _configured := false
var _playable := false
var _pause_generation := 0
var _held_ball: RigidBody3D
var _audit_elapsed := 0.0
var _audit_cursor := 0
var _saved_platform_floor_layers: int = -1

func _ready() -> void:
	add_to_group("dream_ball_pit")

func bind_player(value: CharacterBody3D) -> void:
	if value == _player: return
	_release_held()
	_restore_player_platform_policy()
	if is_instance_valid(_player) and _player.held_changed.is_connected(_on_held_changed):
		_player.held_changed.disconnect(_on_held_changed)
	_player = value
	_saved_platform_floor_layers = _player.platform_floor_layers if is_instance_valid(_player) else -1
	if is_instance_valid(_player):
		_player.held_changed.connect(_on_held_changed)
	for ball in balls:
		if is_instance_valid(ball): ball.player = value
	if value == null: set_paused(true)
	elif not _paused and _playable:
		_player.platform_floor_layers = _saved_platform_floor_layers & ~2

func set_playable(value: bool) -> void:
	_playable = value
	if not value:
		_release_held()
		set_paused(true)

func _restore_player_platform_policy() -> void:
	if is_instance_valid(_player) and _saved_platform_floor_layers >= 0:
		_player.platform_floor_layers = _saved_platform_floor_layers

func _on_held_changed(body: RigidBody3D) -> void:
	_held_ball = body if is_instance_valid(body) and body in balls else null

func _release_held() -> void:
	if is_instance_valid(_player) and is_instance_valid(_player.get("held")) and _player.held in balls:
		_player.release_prop()
	# Player may be destroyed before its world. Keep the one held reference,
	# rather than scanning thousands of balls on every paused physics frame.
	if is_instance_valid(_held_ball) and _held_ball.held:
		_held_ball.set_held(false)
		_held_ball.linear_velocity = Vector3.ZERO
	_held_ball = null
var floor_center := Vector3.ZERO
var bed_size := Vector2.ZERO
var radius := 0.16

func configure(center: Vector3, grid := Vector2i(48,32), ball_radius := 0.14, seed_value := 250821) -> void:
	assert(not _configured, "Configure ball pit only once")
	assert(grid.x > 0 and grid.y > 0 and grid.x * grid.y <= MAX_BALLS)
	_configured = true; floor_center = center; radius = clampf(ball_radius, 0.10, 0.25)
	var spacing := radius * 2.0 + 0.008
	bed_size = Vector2(grid) * spacing + Vector2.ONE * 0.12
	# Persistent collision catch tray survives surrounding chunk retirement.
	_solid(center + Vector3(0,-0.12,0), Vector3(bed_size.x+0.4,0.24,bed_size.y+0.4))
	for side in [-1.0,1.0]:
		_solid(center + Vector3(side*(bed_size.x*0.5+0.08),0.12,0), Vector3(0.16,0.24,bed_size.y+0.32))
		_solid(center + Vector3(0,0.12,side*(bed_size.y*0.5+0.08)), Vector3(bed_size.x+0.32,0.24,0.16))
	var mesh := SphereMesh.new(); mesh.radius = radius; mesh.height = radius*2.0
	mesh.radial_segments = 12; mesh.rings = 6
	var materials: Array[Material] = []
	for color in ["df315b","e8ba25","2cab66","2770d9","853cb8","e96228"]:
		var material := StandardMaterial3D.new(); material.albedo_color = Color(color)
		material.roughness = 0.28; materials.append(material)
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	for z in grid.y:
		for x in grid.x:
			var ball := Ball.new()
			ball.configure(balls.size(), radius, mesh, materials[rng.randi_range(0,materials.size()-1)])
			ball.position = center + Vector3((float(x)-float(grid.x-1)*0.5)*spacing, radius+0.002, (float(z)-float(grid.y-1)*0.5)*spacing)
			add_child(ball); balls.append(ball)
			ball.sleeping = true; ball.freeze = true
			_pause_state[ball.get_instance_id()] = [Vector3.ZERO,Vector3.ZERO,true]

func _solid(point: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new(); body.position = point
	body.collision_layer = 1; body.collision_mask = 0
	var shape := BoxShape3D.new(); shape.size = size
	var collision := CollisionShape3D.new(); collision.shape = shape
	body.add_child(collision); add_child(body)

func _physics_process(delta: float) -> void:
	set_paused(not _playable or not is_instance_valid(_player) or not bool(_player.get("enabled")))
	if _paused: return
	_audit_elapsed += delta
	if _audit_elapsed >= 0.5:
		_audit_elapsed = 0.0
		_audit_lost_balls()
	# A small forward foot query makes walking through the bed tangible, without
	# waking the entire pile or applying impulses through walls.
	var movement := Vector3(_player.velocity.x,0,_player.velocity.z)
	# Use the controller's separately smoothed intent when a ball blocks its
	# resolved velocity; otherwise the first obstruction disables foot pushing.
	var intended: Variant = _player.get("_move_velocity")
	if intended is Vector2: movement = Vector3(intended.x,0,intended.y)
	if movement.length_squared() < 0.04: return
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new(); shape.radius = 0.55
	query.shape = shape; query.collision_mask = 2
	query.transform.origin = _player.global_position + Vector3.UP*radius + movement.normalized()*0.24
	var now := Time.get_ticks_msec()
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,12):
		var body: Object = hit.collider
		if not body is RigidBody3D or not body.is_in_group("dream_physical_ball") or body.held: continue
		if now - body.last_push_msec < 150: continue
		var ray := PhysicsRayQueryParameters3D.create(_player.global_position+Vector3.UP*radius,body.global_position,1,[_player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var away: Vector3 = body.global_position-_player.global_position
		away.y = 0.0
		if away.dot(movement) < -0.05: continue
		var direction: Vector3 = (away.normalized()+movement.normalized()*0.35).normalized()
		body.last_push_msec = now
		body.sleeping = false
		body.apply_central_impulse((direction+Vector3.UP*0.04)*minf(0.18,movement.length()*0.035))

func set_paused(value: bool) -> void:
	if value: _release_held()
	if value == _paused: return
	_paused = value
	if value: _restore_player_platform_policy()
	elif is_instance_valid(_player) and _saved_platform_floor_layers >= 0:
		# A rolling plastic ball is not a moving platform. Keep all collision
		# masks/pickup semantics; only prevent inherited departure velocity.
		_player.platform_floor_layers = _saved_platform_floor_layers & ~2
	_pause_generation += 1
	var resting: Array[RigidBody3D] = []
	for ball in balls:
		if not is_instance_valid(ball) or ball.has_meta("retired"): continue
		var id := ball.get_instance_id()
		if value:
			_pause_state[id] = [ball.linear_velocity,ball.angular_velocity,ball.sleeping]
			ball.freeze = true
		else:
			ball.freeze = false
			var saved: Array = _pause_state.get(id,[Vector3.ZERO,Vector3.ZERO,true])
			ball.linear_velocity = saved[0]; ball.angular_velocity = saved[1]
			ball.sleeping = saved[2] and not ball.held
			if saved[2]: resting.append(ball)
	if not value:
		_pause_state.clear()
		_restore_resting_after_registration(_pause_generation, resting)

func _restore_resting_after_registration(generation: int, resting: Array[RigidBody3D]) -> void:
	# Jolt wakes newly re-registered shapes on thaw. Reapply only the stored
	# resting state once, after that registration; never distance-freeze motion.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree() or _paused or generation != _pause_generation: return
	for ball in resting:
		if not is_instance_valid(ball) or ball.held or ball.has_meta("retired"): continue
		if Time.get_ticks_msec()-ball.last_push_msec < 250: continue
		if ball.linear_velocity.length_squared() < 0.0144 and ball.angular_velocity.length_squared() < 0.0144:
			ball.sleeping = true

func _audit_lost_balls() -> void:
	# Bounded rare safety work, not a distance-based physics active set. A corrupt
	# or below-world ball cannot be recovered visibly without a teleport pop.
	# Quarantine it unseen until deterministic scene reconstruction instead.
	for offset in mini(128,balls.size()):
		var ball: RigidBody3D = balls[_audit_cursor % balls.size()]
		_audit_cursor += 1
		if not is_instance_valid(ball) or ball.has_meta("retired"): continue
		if ball.global_position.is_finite() and ball.linear_velocity.is_finite() and ball.angular_velocity.is_finite() and ball.global_position.y > floor_center.y-64.0: continue
		if ball == _held_ball: _release_held()
		ball.set_held(false); ball.freeze = true; ball.visible = false
		ball.collision_layer = 0; ball.collision_mask = 0
		ball.set_meta("retired",true)

func get_status() -> Dictionary:
	var awake := 0
	for ball in balls:
		if is_instance_valid(ball) and not ball.sleeping and not ball.freeze: awake += 1
	return {"physical_balls":balls.size(),"awake":awake,"cap":MAX_BALLS,"paused":_paused}

func _exit_tree() -> void:
	_release_held()
	_restore_player_platform_policy()
	_player = null
	_pause_state.clear()
