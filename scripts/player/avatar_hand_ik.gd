class_name AvatarHandIK
extends RefCounted
## Visual-only, two-bone grip adapter. Call after the authored animation evaluates.
## Local pose rotations are frame-local; no persistent Skeleton3D overrides exist.

const REACH_MARGIN: float = 0.012
const TARGET_RATE: float = 22.0
const WEIGHT_RATE: float = 12.0
const RELEASE_RATE: float = 14.0
const PALM_THICKNESS: float = 0.028
const CONTACT_SIDE: float = 0.85
# Native PoolProps._make_visual egg ellipsoid. This is visual contact geometry,
# not its deliberately larger 0.17 m collision/buoyancy radius.
const EGG_VISUAL_AXES: Vector3 = Vector3(0.145, 0.205, 0.145)
# Native duck body, head, beak, eyes and wings from PoolProps._make_visual.
# Each pair is ellipsoid centre / half axes in the rigid body's local frame.
const DUCK_PARTS: Array[Vector3] = [
	Vector3(0,-0.085,0),Vector3(0.16,0.105,0.235),
	Vector3(0,0.065,-0.1),Vector3(0.11,0.12,0.115),
	Vector3(0,0.045,-0.222),Vector3(0.075,0.026,0.06),
	Vector3(-0.087,0.098,-0.158),Vector3(0.018,0.02,0.015),
	Vector3(0.087,0.098,-0.158),Vector3(0.018,0.02,0.015),
	Vector3(-0.125,-0.055,0.025),Vector3(0.052,0.055,0.13),
	Vector3(0.125,-0.055,0.025),Vector3(0.052,0.055,0.13)]

var _skeleton: Skeleton3D
var _arms: Array[Dictionary] = []
var _body_id: int = 0
var _contact_weight: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _radius: float = 0.2
var _egg_shape: bool = false
var _duck_shape: bool = false
var _shape_basis: Basis = Basis.IDENTITY
var _valid: bool = false
var _has_target: bool = false
var _last_frame: Transform3D = Transform3D.IDENTITY
var _has_frame: bool = false

func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_arms.clear()
	_valid = false
	_has_target = false
	_body_id = 0
	_contact_weight = 0.0
	_has_frame = false
	_egg_shape = false
	_duck_shape = false
	if not is_instance_valid(skeleton): return
	for side: int in [1, -1]:
		var suffix: String = "L" if side == 1 else "R"
		var upper: int = skeleton.find_bone("UpperArm_" + suffix)
		var forearm: int = skeleton.find_bone("Forearm_" + suffix)
		var hand: int = skeleton.find_bone("Hand_" + suffix)
		var middle: int = skeleton.find_bone("Middle1_" + suffix)
		if mini(mini(upper, forearm), mini(hand, middle)) < 0: return
		var shoulder_rest: Transform3D = skeleton.get_bone_global_rest(upper)
		var elbow_rest: Transform3D = skeleton.get_bone_global_rest(forearm)
		var hand_rest: Transform3D = skeleton.get_bone_global_rest(hand)
		var knuckle_rest: Vector3 = skeleton.get_bone_global_rest(middle).origin
		# The palm lies between wrist and knuckle. Its inward fleshy surface is
		# 28 mm inside the centreline on this authored rig (25 mm × 1.12 hand
		# refinement), not the fingertip. CPU-skinned contact verifies this patch.
		var long_axis: Vector3 = (knuckle_rest - hand_rest.origin).normalized()
		var inward: Vector3 = Vector3(-side, 0, 0)
		inward = (inward - long_axis * inward.dot(long_axis)).normalized()
		var palm_rest: Vector3 = hand_rest.origin.lerp(knuckle_rest, 0.78) + inward * PALM_THICKNESS
		var palm_local: Vector3 = hand_rest.affine_inverse() * palm_rest
		# Measured contact centres of the new continuous palm, not the older
		# inflated 28 mm pad. Legacy 42-bone assets retain their original anchor.
		if skeleton.find_bone("WristSupport_" + suffix) >= 0 and skeleton.find_bone("Middle3_" + suffix) >= 0:
			palm_local = Vector3(-0.0209279060, 0.0671776533, 0.0010641515) if side == 1 else Vector3(0.0209339261, 0.0671775341, 0.0010622740)
		var local_long: Vector3 = hand_rest.basis.inverse() * long_axis
		var local_normal: Vector3 = hand_rest.basis.inverse() * inward
		_arms.append({"side": side, "upper": upper, "forearm": forearm, "hand": hand,
			"upper_length": shoulder_rest.origin.distance_to(elbow_rest.origin),
			"forearm_length": elbow_rest.origin.distance_to(hand_rest.origin),
			"palm_local": palm_local, "palm_offset": palm_local.length(),
			"palm_frame": _frame(local_long, local_normal)})
	_valid = _arms.size() == 2

func _frame(long_axis: Vector3, normal: Vector3) -> Basis:
	var y: Vector3 = long_axis.normalized()
	var z: Vector3 = (normal - y * normal.dot(y)).normalized()
	if z.length_squared() < 0.5:
		z = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
	var x: Vector3 = y.cross(z).normalized()
	z = x.cross(y).normalized()
	return Basis(x, y, z).orthonormalized()

func _world_pose(bone: int) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)

func _world_rotation(bone: int, desired: Basis, weight: float) -> void:
	var parent: int = _skeleton.get_bone_parent(bone)
	var parent_basis: Basis = _world_pose(parent).basis if parent >= 0 else _skeleton.global_basis
	var desired_local: Quaternion = (parent_basis.orthonormalized().inverse() * desired.orthonormalized()).get_rotation_quaternion()
	var current: Quaternion = _skeleton.get_bone_pose_rotation(bone)
	_skeleton.set_bone_pose_rotation(bone, current.slerp(desired_local, weight).normalized())

func _aim(bone: int, child: int, target: Vector3, weight: float) -> void:
	var pose: Transform3D = _world_pose(bone)
	var from: Vector3 = _world_pose(child).origin - pose.origin
	var to: Vector3 = target - pose.origin
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001: return
	var swing := Quaternion(from.normalized(), to.normalized())
	_world_rotation(bone, Basis(swing) * pose.basis, weight)

func _target(arm: Dictionary, basis: Basis, center: Vector3, radius: float) -> Dictionary:
	var side: float = float(arm.side)
	var right: Vector3 = basis.x.normalized()
	var back: Vector3 = basis.z.normalized()
	var outward: Vector3 = (right * side * CONTACT_SIDE + back * sqrt(1.0 - CONTACT_SIDE * CONTACT_SIDE)).normalized()
	var normal: Vector3 = -outward
	var palm: Vector3 = center + outward * radius
	if _egg_shape:
		# Intersect the chosen world-space grip ray with the actually oriented
		# ellipsoid, then use its surface normal rather than a spherical normal.
		var inverse: Basis = _shape_basis.inverse()
		var local_direction: Vector3 = inverse * outward
		var surface_distance: float = 1.0 / maxf(local_direction.length(), 0.0001)
		var local_contact: Vector3 = local_direction * surface_distance
		palm = center + outward * surface_distance
		normal = -(inverse.transposed() * local_contact).normalized()
	elif _duck_shape:
		# Support points keep the whole hand's tangent plane outside the visible
		# compound hull, avoiding fingers cutting through a neighbouring wing.
		# The normal stays anatomical even if the duck was picked up tilted.
		var local_normal: Vector3 = _shape_basis.transposed()*outward
		var support: float = -INF
		for i: int in range(0,DUCK_PARTS.size(),2):
			var axes: Vector3 = DUCK_PARTS[i+1]
			var scaled: Vector3 = axes*local_normal
			var contact: Vector3 = DUCK_PARTS[i]+axes*scaled/maxf(scaled.length(),0.0001)
			var offset: Vector3 = _shape_basis*contact
			var extent: float = offset.dot(outward)
			if extent > support:
				support = extent
				palm = center+offset
	var forward: Vector3 = -back
	var tangent: Vector3 = (forward - normal * forward.dot(normal)).normalized()
	var hand_basis: Basis = _frame(tangent, normal) * (arm.palm_frame as Basis).inverse()
	var wrist: Vector3 = palm - hand_basis * (arm.palm_local as Vector3)
	return {"palm": palm, "wrist": wrist, "hand_basis": hand_basis}

func apply(held: RigidBody3D, avatar_basis: Basis, weight: float, delta: float) -> Dictionary:
	if not _valid or not is_instance_valid(_skeleton):
		return {"valid": false, "contact_weight": 0.0, "reachable": false, "arms": []}
	var dt: float = clampf(delta, 0.0, 0.1)
	var frame: Transform3D = _skeleton.global_transform
	# Smooth relative to the moving avatar, never lag a rigidly carried target
	# merely because the entire player is translating or turning in the world.
	if _has_frame and _has_target:
		_center = frame * (_last_frame.affine_inverse() * _center)
	_last_frame = frame
	_has_frame = true
	var active: bool = is_instance_valid(held) and weight > 0.0001
	var desired_weight: float = 0.0
	var reachable: bool = false
	var raw_center: Vector3 = _center
	var target_rows: Array[Dictionary] = []
	var basis: Basis = avatar_basis.orthonormalized()
	if active:
		raw_center = held.global_position
		var id: int = held.get_instance_id()
		var prop_radius: Variant = held.get("radius")
		_radius = clampf(float(prop_radius) if prop_radius is float or prop_radius is int else 0.2, 0.02, 0.6)
		_egg_shape = str(held.get("prop_kind")) == "egg"
		_duck_shape = str(held.get("prop_kind")) == "duck"
		if _egg_shape:
			_shape_basis = held.global_basis * Basis.from_scale(EGG_VISUAL_AXES)
		elif _duck_shape:
			_shape_basis = held.global_basis
		if id != _body_id or not _has_target:
			_center = raw_center
			_body_id = id
			_has_target = true
			_contact_weight = 0.0
		else:
			_center = _center.lerp(raw_center, 1.0 - exp(-TARGET_RATE * dt))
		var reach_intent: float = 1.0
		for arm: Dictionary in _arms:
			# Decide reach from the live body, not from a delayed smoothed target.
			var live: Dictionary = _target(arm, basis, raw_center, _radius)
			var shoulder: Vector3 = _world_pose(arm.upper).origin
			var maximum: float = float(arm.upper_length) + float(arm.forearm_length) - REACH_MARGIN
			var distance: float = shoulder.distance_to(live.wrist)
			var intent: float = 1.0 - smoothstep(maximum - 0.005, maximum + 0.065, distance)
			reach_intent = minf(reach_intent, intent)
			target_rows.append({"live_wrist_distance": distance, "maximum_reach": maximum, "intent": intent})
		reachable = reach_intent > 0.99
		desired_weight = clampf(weight, 0.0, 1.0) * reach_intent
	var rate: float = WEIGHT_RATE if desired_weight > _contact_weight else RELEASE_RATE
	_contact_weight = lerpf(_contact_weight, desired_weight, 1.0 - exp(-rate * dt))
	if _contact_weight < 0.0001:
		_contact_weight = 0.0
		if not active:
			_has_target = false
			_body_id = 0
			return {"valid": true, "active": false, "reachable": false,
				"contact_weight": 0.0, "desired_weight": 0.0, "arms": [],
				"target_lag": 0.0, "persistent_overrides": false}
	var results: Array[Dictionary] = []
	# Settled contact follows the live physics body exactly. Target smoothing is
	# only an approach/release aid, not a permanent floating hand/prop offset.
	var solve_center: Vector3 = _center.lerp(raw_center, _contact_weight) if active else _center
	for i: int in _arms.size():
		var arm: Dictionary = _arms[i]
		var shoulder: Vector3 = _world_pose(arm.upper).origin
		var target: Dictionary = _target(arm, basis, solve_center, _radius)
		var vector: Vector3 = target.wrist - shoulder
		var distance: float = vector.length()
		var l1: float = arm.upper_length
		var l2: float = arm.forearm_length
		var clamped: float = clampf(distance, absf(l1 - l2) + 0.003, l1 + l2 - REACH_MARGIN)
		var direction: Vector3 = vector / distance if distance > 0.0001 else -basis.z
		var wrist: Vector3 = shoulder + direction * clamped
		# Pole is anatomical (outward and down), not inherited from a noisy pose.
		var pole: Vector3 = basis.x * float(arm.side) * 0.35 - basis.y * 0.9 + basis.z * 0.1
		pole = pole - direction * pole.dot(direction)
		if pole.length_squared() < 0.0001:
			pole = direction.cross(basis.z if absf(direction.dot(basis.z)) < 0.9 else basis.x)
		pole = pole.normalized()
		var along: float = (l1 * l1 - l2 * l2 + clamped * clamped) / (2.0 * clamped)
		var height: float = sqrt(maxf(0.0, l1 * l1 - along * along))
		var elbow: Vector3 = shoulder + direction * along + pole * height
		if _has_target and _contact_weight > 0.0:
			_aim(arm.upper, arm.forearm, elbow, _contact_weight)
			_aim(arm.forearm, arm.hand, wrist, _contact_weight)
			_world_rotation(arm.hand, target.hand_basis, _contact_weight)
		var final_hand: Transform3D = _world_pose(arm.hand)
		var final_palm: Vector3 = final_hand * (arm.palm_local as Vector3)
		var final_elbow: Vector3 = _world_pose(arm.forearm).origin
		var forearm_axis: Vector3 = (final_hand.origin - final_elbow).normalized()
		var hand_axis: Vector3 = (final_hand.basis * (arm.palm_frame as Basis).y).normalized()
		var live_target: Dictionary = _target(arm, basis, raw_center, _radius)
		results.append({"side": "L" if arm.side == 1 else "R", "upper_length": l1,
			"forearm_length": l2, "palm_offset": arm.palm_offset,
			"requested_reach": distance, "clamped_reach": clamped,
			"clamped": distance > clamped + 0.0001,
			"palm_error": final_palm.distance_to(live_target.palm),
			"palm": final_palm, "contact_target": live_target.palm,
			"wrist": final_hand.origin, "elbow": final_elbow,
			"wrist_bend_degrees": rad_to_deg(acos(clampf(forearm_axis.dot(hand_axis), -1.0, 1.0))),
			"live_reach": target_rows[i] if i < target_rows.size() else {}})
	return {"valid": true, "reachable": reachable, "contact_weight": _contact_weight,
		"desired_weight": desired_weight, "active": active, "arms": results,
		"target_lag": solve_center.distance_to(raw_center), "persistent_overrides": false}

func clear_contact() -> void:
	# Physical throw has released the body. The avatar blends a captured local
	# grip pose into followthrough; never continue targeting a stale world point.
	_contact_weight = 0.0
	_has_target = false
	_body_id = 0
	_has_frame = false
