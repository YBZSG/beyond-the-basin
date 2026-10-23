class_name PoolPropBody
extends RigidBody3D
## Native rigid-body translation of app/pool-vct/physics.ts PropPhysics.
## Godot resolves contacts; the original per-kind buoyancy/drag constants are retained.

signal water_impact(position: Vector3, power: float)
signal hard_impact(kind: String, position: Vector3, strength: float)
signal picked_up(body: RigidBody3D)

var prop_kind: String = "duck"
var display_name: String = "小黄鸭"
var radius: float = 0.2
var float_bias: float = 0.125
var buoy_k: float = 90.0
var buoy_zeta: float = 0.32
var buoy_max: float = 30.0
var flow_rate: float = 2.0
var splash_boost: float = 1.0
var water: Node
var held: bool = false
var promoted: bool = false
var hold_target: Vector3
var _carry_rotation: Quaternion = Quaternion.IDENTITY
var _carry_rotation_weight: float = 0.0
var _splash_cooldown: float = 0.0
var _hit_cooldown: float = 0.0
var _wake_time: float = 0.0
var _wake_impulse: Vector2 = Vector2.ZERO
var _previous_y: float = INF
var _previous_velocity: Vector3 = Vector3.ZERO
var _surface_before: float = 0.32
var _physics_material: PhysicsMaterial

# Source active-set owner. Missing/retired owner retains original callback.
var source_activity_owner: WeakRef
var source_activity_callback_frame := -1
var source_activity_force_frame := -1

func source_bind_activity(owner: Node) -> void:
	source_activity_owner = weakref(owner) if owner != null else null


func configure(kind: String, spec: Dictionary, water_node: Node) -> void:
	prop_kind = kind
	display_name = str(spec.get("name", kind))
	radius = float(spec.get("radius", 0.2))
	float_bias = float(spec.get("float_bias", 0.0))
	buoy_k = float(spec.get("buoy_k", 64.0))
	buoy_zeta = float(spec.get("buoy_zeta", 0.44))
	buoy_max = float(spec.get("buoy_max", 30.0))
	flow_rate = float(spec.get("flow_rate", 8.0))
	splash_boost = float(spec.get("splash_boost", 1.0))
	water = water_node
	mass = float(spec.get("mass", 1.0))
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	custom_integrator = true
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.15
	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = 0.35
	_physics_material.bounce = 0.62 if kind == "ball" else 0.3
	physics_material_override = _physics_material
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision.shape = sphere
	add_child(collision)
	add_to_group("pool_interactable")
	set_meta("kind", kind)
	set_meta("display_name", display_name)

func set_held(value: bool) -> void:
	held = value
	if not value:_carry_rotation_weight=0.0
	sleeping = false
	_physics_material.bounce = 0.0 if value else (0.62 if prop_kind == "ball" else 0.3)
	if held:
		promoted = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		hold_target = global_position
		picked_up.emit(self)

func set_hold_target(target: Vector3) -> void:
	hold_target = target

func set_carry_rotation(target: Quaternion, weight: float) -> void:
	_carry_rotation=target.normalized()
	_carry_rotation_weight=clampf(weight,0.0,1.0)

func launch(direction: Vector3, speed: float) -> void:
	set_held(false)
	linear_velocity = direction.normalized() * speed + Vector3.UP * 1.2
	_previous_velocity = linear_velocity

func _water_height(point: Vector3) -> float:
	if is_instance_valid(water) and water.has_method("surface_height_at"):
		return float(water.call("surface_height_at", point))
	return 0.32

func _water_current(point: Vector3) -> Vector2:
	if is_instance_valid(water) and water.has_method("current_velocity_at"):
		var value: Variant = water.call("current_velocity_at", point)
		if value is Vector2:
			return value
	return Vector2.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	source_activity_callback_frame = Engine.get_physics_frames()
	var owner: Node = source_activity_owner.get_ref() if source_activity_owner != null else null
	if is_instance_valid(owner) and owner.owns_callbacks and is_instance_valid(owner.camera):
		return
	source_activity_force_frame = Engine.get_physics_frames()
	source_integrate_active(state)

func source_integrate_active(state: PhysicsDirectBodyState3D) -> void:
	var h: float = state.step
	var point: Vector3 = state.transform.origin
	var surface: float = _water_height(point)
	var water_present: bool = not (is_instance_valid(water) and water.has_method("is_water_at")) or bool(water.call("is_water_at", point))
	var target_water: float = surface + float_bias
	var v: Vector3 = state.linear_velocity
	_splash_cooldown = maxf(0.0, _splash_cooldown - h)
	_hit_cooldown = maxf(0.0, _hit_cooldown - h)
	if not held and _hit_cooldown <= 0.0 and state.get_contact_count() > 0:
		var hit: float = (v - _previous_velocity).length()
		for index in range(state.get_contact_count()):
			hit = maxf(hit, state.get_contact_impulse(index).length() / maxf(mass, 0.01))
		if hit > 1.15:
			_hit_cooldown = 0.18
			hard_impact.emit(prop_kind, point, hit)
	v = _source_velocity_step(v, point, surface, water_present, h)
	var submerged: float = clampf((target_water + radius - point.y) / (2.0 * radius), 0.0, 1.0) if water_present else 0.0
	if held:
		state.angular_velocity = Vector3.ZERO
		if _carry_rotation_weight>0.0:
			var carried: Transform3D=state.transform
			var before_rotation: Quaternion=carried.basis.orthonormalized().get_rotation_quaternion()
			carried.basis=Basis(before_rotation.slerp(_carry_rotation,(1.0-exp(-18.0*h))*_carry_rotation_weight))
			state.transform=carried
	elif submerged > 0.0 and prop_kind != "ball":
		# This finite-difference normal is ONLY for visual hull tilt. Translational
		# acceleration/Stokes drift come from the original solver's slope_at below.
		var normal := Vector3(
			(_water_height(point - Vector3.RIGHT * radius) - _water_height(point + Vector3.RIGHT * radius)) / (2.0 * radius),
			1.0,
			(_water_height(point - Vector3.BACK * radius) - _water_height(point + Vector3.BACK * radius)) / (2.0 * radius)).normalized()
		var current_quat: Quaternion = state.transform.basis.orthonormalized().get_rotation_quaternion()
		var yaw: float = current_quat.get_euler(EULER_ORDER_YXZ).y
		var tilt: Quaternion = Quaternion(Vector3.UP, normal) * Quaternion(Vector3.UP, yaw)
		var transform_now: Transform3D = state.transform
		transform_now.basis = Basis(current_quat.slerp(tilt, 1.0 - exp(-12.0 * h)))
		state.transform = transform_now
		state.angular_velocity = Vector3.ZERO
	if water_present and _previous_y != INF and _previous_y > _surface_before and point.y <= surface and v.length() > 1.0 and _splash_cooldown <= 0.0:
		_emit_source_splash(point, v)
		_splash_cooldown = 0.7
	_previous_y = point.y
	_surface_before = surface
	state.linear_velocity = v
	_previous_velocity = v

func _source_velocity_step(v: Vector3, point: Vector3, surface: float, water_present: bool, h: float) -> Vector3:
	# physics.ts PropPhysics.update's per-substep water/velocity equations. Keep
	# contacts/position integration in Godot; h is actual elapsed physics time.
	var target_water: float = surface + float_bias
	if held:
		v = ((hold_target - point) * 16.0).limit_length(12.0)
	else:
		if water_present and point.y < target_water + radius:
			var subm_rest: float = (float_bias + radius) / (2.0 * radius)
			var ramp: float = minf(1.0, (target_water + radius - point.y) / (2.0 * radius) / subm_rest)
			var spring: float = clampf((target_water - point.y) * buoy_k * ramp, -buoy_max, buoy_max)
			v.y += (spring - v.y * 2.0 * buoy_zeta * sqrt(buoy_k) * ramp) * h
		else:
			v.y -= 9.81 * h
		v = v.limit_length(18.0)
	var submerged: float = clampf((target_water + radius - point.y) / (2.0 * radius), 0.0, 1.0) if water_present else 0.0
	if submerged <= 0.0:
		_reset_source_wake()
		return v
	var target: Vector2 = _water_current(point)
	if not held and is_instance_valid(water) and water.has_method("slope_at"):
		var sample: Variant = water.call("slope_at", point, 0.38)
		if sample is Vector4:
			v.x += sample.x * submerged * h
			v.z += sample.y * submerged * h
			target += Vector2(sample.z, sample.w)
	var relative := Vector2(v.x, v.z) - target
	var overtaken: bool = target.length_squared() > Vector2(v.x, v.z).length_squared()
	var drag: float = 1.0 - exp(-(10.0 if overtaken else flow_rate) * submerged * h)
	v.x -= relative.x * drag
	v.z -= relative.y * drag
	var relative_speed: float = relative.length()
	if relative_speed > 0.08 and is_instance_valid(water) and water.has_method("push_wake") and water.has_method("wake_dipole"):
		_wake_time += h
		# Source form-drag momentum is accumulated, not replaced by a pulse
		# based on the last tick. The bow/stern pressure is a separate source.
		var wake_drag: float = 1.0 - exp(-8.0 * submerged * h)
		var share: float = (0.8 if held else 1.0) * 0.09
		_wake_impulse += relative * relative_speed * wake_drag * share
		if _wake_time >= 0.05:
			var sigma: float = radius * 0.6 + 0.06
			water.call("push_wake", point, _wake_impulse, sigma)
			water.call("wake_dipole", point, relative / relative_speed, relative_speed, sigma)
			_reset_source_wake()
	else:
		_reset_source_wake()
	return v

func _reset_source_wake() -> void:
	_wake_time = 0.0
	_wake_impulse = Vector2.ZERO

func _emit_source_splash(point: Vector3, entry_velocity: Vector3) -> void:
	var power: float = minf(0.5 * splash_boost, (0.06 + entry_velocity.length() * 0.028) * splash_boost)
	if is_instance_valid(water) and water.has_method("splash"):
		# engine.ts splash combines these original hull-entry terms with the
		# sampled fluid current. Do not discard the vertical speed or radius.
		water.call("splash", point, power, {"u": entry_velocity.x, "v": entry_velocity.z, "vertical": entry_velocity.y, "radius": radius})
	# The prop collection forwards this as audio only when source splash exists;
	# legacy water adapters still inject their impact through that collection.
	water_impact.emit(point, power)
