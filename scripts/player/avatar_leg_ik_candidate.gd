class_name AvatarLegIKCandidate
extends RefCounted
## OPTIONAL visual terrain-height adapter for the unchanged 42-bone Explorer.
## Call exactly once AFTER fresh AnimationTree evaluation, BEFORE hand IK.
## This is not a new gait, foot lock, slope-tilt solver, or controller correction.
## It never writes a node transform, root bone, collider, velocity, or water state.
## Only frame-local Hips translation and leg rotations are written; animation
## must overwrite them before the next call. No persistent bone overrides exist.
## Scope: Idle/Walk/Wade. Fade out dry Run with grounded_gait_weight(); its high
## swing plus split treads requires a new gait, not an excessively folded knee.

const MAX_FOOT_RAISE: float = 0.22
const MAX_FOOT_LOWER: float = 0.22
const MAX_PELVIS_LOWER: float = 0.18
const REACH_MARGIN: float = 0.006
const MIN_REACH: float = 0.26
const ROOT_CLEARANCE: float = 0.002
const SUPPORT_UP_RATE: float = 24.0
const SUPPORT_DOWN_RATE: float = 16.0
const SUPPORT_SPEED: float = 1.6
const PELVIS_RATE: float = 18.0
const PELVIS_SPEED: float = 1.0
const ENGAGE_RATE: float = 14.0
const SUPPORT_DEADBAND: float = 0.0015
const MAX_DELTA: float = 0.1
const MIN_NORMAL_Y: float = 0.70
const PROBE_UP: float = 0.28
const PROBE_DOWN: float = 0.36
const TELEPORT_DISTANCE: float = 1.5
const STEP_CONTACT_GRACE: float = 0.12
const STEP_CONTACT_RANGE: float = 0.24
const STEP_MAX_FALL_SPEED: float = 2.4
const RELEASE_RATE: float = 20.0
# Exactly five rays per shoe, but choose their world-axis extrema from the
# actual rigid-skinned sole volume, not a guessed lower-plane rectangle.
# A tilted upper heel can project beyond the lower sole and cross a riser.

var _skeleton: Skeleton3D
var _hips: int = -1
var _legs: Array[Dictionary] = []
var _valid: bool = false
var _weight: float = 0.0
var _pelvis: float = 0.0
var _epoch: int = -1
var _last_root: Vector3 = Vector3.ZERO
var _has_frame: bool = false
var _reset_count: int = 0
var _air_elapsed: float = 0.0
var _had_ground_contact: bool = false

func setup(skeleton: Skeleton3D, model_root: Node) -> void:
	_skeleton = skeleton
	_legs.clear()
	_valid = false
	_hips = -1
	reset()
	if not is_instance_valid(skeleton): return
	_hips = skeleton.find_bone("Hips")
	if _hips < 0 or skeleton.get_bone_count() != 42: return
	for side: int in [1, -1]:
		var suffix: String = "L" if side == 1 else "R"
		var upper: int = skeleton.find_bone("UpperLeg_" + suffix)
		var lower: int = skeleton.find_bone("LowerLeg_" + suffix)
		var foot: int = skeleton.find_bone("Foot_" + suffix)
		if mini(upper, mini(lower, foot)) < 0: return
		if skeleton.get_bone_parent(upper) != _hips or skeleton.get_bone_parent(lower) != upper or skeleton.get_bone_parent(foot) != lower: return
		var hip_rest: Transform3D = skeleton.get_bone_global_rest(upper)
		var knee_rest: Transform3D = skeleton.get_bone_global_rest(lower)
		var foot_rest: Transform3D = skeleton.get_bone_global_rest(foot)
		_legs.append({"side": suffix, "upper": upper, "lower": lower, "foot": foot,
			"l1": hip_rest.origin.distance_to(knee_rest.origin),
			"l2": knee_rest.origin.distance_to(foot_rest.origin),
			"probes": [], "probe_set": {}, "has_support": false, "support_y": 0.0, "support_target_y": 0.0})
	if not is_instance_valid(model_root): return
	_collect_sole_points(model_root)
	_valid = _legs.size() == 2
	for leg: Dictionary in _legs:
		_valid = _valid and leg.probes.size() > 0
		leg.erase("probe_set")

func _collect_sole_points(node: Node) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("Body_"):
		var instance := node as MeshInstance3D
		if instance.mesh != null and instance.skin != null:
			for surface: int in instance.mesh.get_surface_count():
				var material: Material = instance.mesh.surface_get_material(surface)
				if material == null or not material.resource_name.to_lower().contains("rubber soles"): continue
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if positions.is_empty(): continue
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var stride: int = weights.size() / positions.size()
				for i: int in positions.size():
					for j: int in stride:
						if weights[i * stride + j] < 0.99999: continue
						var bind: int = bones[i * stride + j]
						var bone: int = instance.skin.get_bind_bone(bind)
						if bone < 0: bone = _skeleton.find_bone(instance.skin.get_bind_name(bind))
						for leg: Dictionary in _legs:
							if bone != int(leg.foot): continue
							var point: Vector3 = instance.skin.get_bind_pose(bind) * positions[i]
							if not leg.probe_set.has(point):
								leg.probe_set[point] = true
								leg.probes.append(point)
	for child: Node in node.get_children(): _collect_sole_points(child)

func reset() -> void:
	# Reset smoothing only. Never feed a visual correction back into physics.
	_weight = 0.0
	_pelvis = 0.0
	_epoch = -1
	_has_frame = false
	_air_elapsed = 0.0
	_had_ground_contact = false
	_reset_count += 1
	for leg: Dictionary in _legs: leg.has_support = false

func _world_pose(bone: int) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)

func _world_rotation(bone: int, desired: Basis) -> void:
	var parent: int = _skeleton.get_bone_parent(bone)
	var parent_basis: Basis = _world_pose(parent).basis if parent >= 0 else _skeleton.global_basis
	var local: Basis = parent_basis.orthonormalized().inverse() * desired.orthonormalized()
	_skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion().normalized())

func _aim(bone: int, child: int, target: Vector3) -> void:
	var pose: Transform3D = _world_pose(bone)
	var source: Vector3 = _world_pose(child).origin - pose.origin
	var destination: Vector3 = target - pose.origin
	if source.length_squared() < 0.000001 or destination.length_squared() < 0.000001: return
	var from: Vector3 = source.normalized()
	var to: Vector3 = destination.normalized()
	var cross: Vector3 = from.cross(to)
	var dot: float = clampf(from.dot(to), -1.0, 1.0)
	# Retain very small corrections during release. The cross/(1+dot) form
	# avoids deriving a small angle from acos(dot), which loses precision.
	var turn := Quaternion(cross.x, cross.y, cross.z, 1.0 + dot).normalized() if dot > -0.99999 else Quaternion(from, to)
	_world_rotation(bone, Basis(turn) * pose.basis)

func _smooth(current: float, target: float, rate: float, speed: float, delta: float) -> float:
	var result: float = lerpf(current, target, 1.0 - exp(-rate * delta))
	return move_toward(current, result, speed * delta)

static func grounded_gait_weight(run_blend: float, wade_blend: float) -> float:
	# Wade replaces the dry running leg track, so retain terrain placement there.
	var dry_run: float = clampf(run_blend, 0.0, 1.0) * (1.0 - clampf(wade_blend, 0.0, 1.0))
	return 1.0 - smoothstep(0.05, 0.45, dry_run)

func _static_ray(start: Vector3, end: Vector3) -> Dictionary:
	# Architecture only. Excludes the player's capsule, props, water and Areas.
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.collide_with_areas = false
	query.hit_from_inside = false
	return _skeleton.get_world_3d().direct_space_state.intersect_ray(query)

func _support(leg: Dictionary, pose: Transform3D, root_position: Vector3, query: Callable) -> Dictionary:
	var highest: float = -INF
	var count: int = 0
	var first: Vector3 = pose * (leg.probes[0] as Vector3)
	var min_x: Vector3 = first; var max_x: Vector3 = first
	var min_z: Vector3 = first; var max_z: Vector3 = first
	var center := Vector3.ZERO
	for point: Vector3 in leg.probes:
		var world: Vector3 = pose * point
		if world.x < min_x.x: min_x = world
		if world.x > max_x.x: max_x = world
		if world.z < min_z.z: min_z = world
		if world.z > max_z.z: max_z = world
		center += world
	center /= float(leg.probes.size())
	for world: Vector3 in [min_x, max_x, min_z, max_z, center]:
		var start := Vector3(world.x, root_position.y + PROBE_UP, world.z)
		var end := Vector3(world.x, root_position.y - PROBE_DOWN, world.z)
		var hit: Dictionary = query.call(start, end)
		if hit.is_empty() or not hit.has("position") or not hit.has("normal"): continue
		var normal: Vector3 = hit.normal
		var position: Vector3 = hit.position
		if not position.is_finite() or not normal.is_finite() or normal.y < MIN_NORMAL_Y: continue
		# Out-of-range hits must never make a dangling foot reach a distant floor.
		if position.y > start.y + 0.001 or position.y < end.y - 0.001: continue
		highest = maxf(highest, position.y)
		count += 1
	return {"valid": count > 0, "height": highest, "rays_hit": count, "actual_sole_points": leg.probes.size()}

func apply(root_position: Vector3, avatar_basis: Basis, grounded: bool, delta: float,
		motion_epoch: int = 0, excluded: bool = false, support_query: Callable = Callable(),
		gait_weight: float = 1.0, vertical_velocity: float = 0.0) -> Dictionary:
	if not _valid or not is_instance_valid(_skeleton):
		return {"valid": false, "active": false, "legs": []}
	var dt: float = clampf(delta, 0.0, MAX_DELTA)
	if dt <= 0.0:
		return {"valid": true, "active": false, "reason": "zero_delta", "legs": []}
	var scale: Vector3 = _skeleton.global_basis.get_scale()
	if not scale.is_equal_approx(Vector3.ONE):
		reset()
		return {"valid": false, "active": false, "reason": "unit_scale_required", "legs": []}
	# Epoch is required for scene switches/warps. Distance is a defensive fallback.
	if _has_frame and (motion_epoch != _epoch or root_position.distance_to(_last_root) > TELEPORT_DISTANCE): reset()
	var root_delta_y: float = root_position.y - _last_root.y if _has_frame else 0.0
	_epoch = motion_epoch
	_last_root = root_position
	_has_frame = true
	if excluded:
		# Swim/climb/explicit exclusions cannot retain a contact correction.
		reset()
		return {"valid": true, "active": false, "weight": 0.0, "pelvis_lower": 0.0,
			"legs": [], "reset_count": _reset_count, "persistent_overrides": false}
	if grounded:
		_air_elapsed = 0.0
		_had_ground_contact = true
	else:
		_air_elapsed += dt
		if not _had_ground_contact or (_weight <= 0.00001 and absf(_pelvis) <= 0.00001):
			reset()
			return {"valid": true, "active": false, "reason": "air_no_contact", "legs": [], "contact_grace": false}
	# This does not alter is_on_floor or controller motion. Only a recently
	# grounded, slow-downward step can even ask for visual contact grace.
	# Jumping/upward flight and real falls query no floor and only blend OUT.
	var can_probe: bool = grounded or (_had_ground_contact and _air_elapsed <= STEP_CONTACT_GRACE
		and vertical_velocity <= 0.25 and vertical_velocity >= -STEP_MAX_FALL_SPEED)
	var influence: float = clampf(gait_weight, 0.0, 1.0)
	if influence <= 0.00001 and _weight <= 0.00001 and absf(_pelvis) <= 0.00001:
		reset()
		return {"valid": true, "active": false, "reason": "gait_excluded", "weight": 0.0,
			"pelvis_lower": 0.0, "legs": [], "persistent_overrides": false}
	var query: Callable = support_query if support_query.is_valid() else _static_ray
	var rows: Array[Dictionary] = []
	var any_support: bool = false
	var all_near_support: bool = true
	for leg: Dictionary in _legs:
		var foot_pose: Transform3D = _world_pose(leg.foot)
		var hip: Vector3 = _world_pose(leg.upper).origin
		var knee: Vector3 = _world_pose(leg.lower).origin
		var authored_horizontal: float = Vector2(foot_pose.origin.x - hip.x, foot_pose.origin.z - hip.z).length()
		if authored_horizontal >= float(leg.l1) + float(leg.l2) - REACH_MARGIN:
			# This height-only adapter cannot repair an almost-horizontal authored
			# leg. Fail before any pose writes instead of moving its foot sideways.
			reset()
			return {"valid": true, "active": false, "reason": "horizontal_reach_unsupported", "legs": []}
		var support: Dictionary = _support(leg, foot_pose, root_position, query) if can_probe else {"valid": false, "height": 0.0, "rays_hit": 0}
		any_support = any_support or bool(support.valid)
		all_near_support = all_near_support and bool(support.valid) and absf(float(support.height) - root_position.y) <= STEP_CONTACT_RANGE
		var original_axis: Vector3 = (foot_pose.origin - hip).normalized()
		var pole: Vector3 = knee - hip
		pole -= original_axis * pole.dot(original_axis)
		if pole.length_squared() < 0.000001: pole = -avatar_basis.z
		rows.append({"side": leg.side, "hip_before": hip, "foot_before": foot_pose,
			"pole": pole.normalized(), "support": support})
	var contact_grace: bool = not grounded and can_probe and all_near_support
	var release_blend: bool = not grounded and not contact_grace
	for i: int in _legs.size():
		var leg: Dictionary = _legs[i]
		var row: Dictionary = rows[i]
		var support: Dictionary = row.support
		var desired_y: float = float(support.height) if support.valid else root_position.y - ROOT_CLEARANCE
		if not leg.has_support:
			leg.support_y = root_position.y - ROOT_CLEARANCE
			leg.support_target_y = leg.support_y
			leg.has_support = bool(support.valid)
		# Outside confirmed contact, freeze only the previous relative correction
		# and fade it out. Never chase a stale world-floor target during flight.
		if release_blend:
			leg.support_y = float(leg.support_y) + root_delta_y
			leg.support_target_y = leg.support_y
			desired_y = float(leg.support_y)
		# Hysteresis belongs on the measured target, not the filtered output.
		# Otherwise settling stops just inside the deadband and tiny hit noise
		# can repeatedly wake the filter, producing a creeping stationary pose.
		if absf(desired_y - float(leg.support_target_y)) > SUPPORT_DEADBAND:
			leg.support_target_y = desired_y
		desired_y = float(leg.support_target_y)
		var rate: float = SUPPORT_UP_RATE if desired_y > float(leg.support_y) else SUPPORT_DOWN_RATE
		leg.support_y = _smooth(float(leg.support_y), desired_y, rate, SUPPORT_SPEED, dt)
		var correction: float = clampf(float(leg.support_y) - root_position.y + ROOT_CLEARANCE, -MAX_FOOT_LOWER, MAX_FOOT_RAISE)
		row.offset = correction
		row.support_filtered_y = float(leg.support_y)
	_weight = lerpf(_weight, influence if any_support and not release_blend else 0.0,
		1.0 - exp(-(RELEASE_RATE if release_blend else ENGAGE_RATE) * dt))
	var wanted_pelvis: float = 0.0
	for i: int in _legs.size():
		var leg: Dictionary = _legs[i]
		var row: Dictionary = rows[i]
		var target: Vector3 = (row.foot_before as Transform3D).origin + Vector3.UP * float(row.offset) * _weight
		var hip: Vector3 = row.hip_before
		var horizontal: float = Vector2(target.x - hip.x, target.z - hip.z).length()
		var reach: float = float(leg.l1) + float(leg.l2) - REACH_MARGIN
		var allowed_y: float = target.y + sqrt(maxf(0.0, reach * reach - horizontal * horizontal))
		# Keep the pelvis at the lower tread's height even while that foot swings.
		# Following only instantaneous ankle reach makes the hips rise on every
		# swing and then chase the next contact, especially at high sample rates.
		wanted_pelvis = minf(wanted_pelvis, minf(float(row.offset), 0.0) * _weight)
		# A flat authored gait must remain bit-identical. Only request extra hip
		# room when terrain actually changes the ankle, never "fix" authored IK.
		if absf(float(row.offset) * _weight) > 0.002:
			wanted_pelvis = minf(wanted_pelvis, allowed_y - hip.y)
		row.target = target
	wanted_pelvis = clampf(wanted_pelvis, -MAX_PELVIS_LOWER, 0.0)
	_pelvis = _smooth(_pelvis, wanted_pelvis, PELVIS_RATE, PELVIS_SPEED, dt)
	if absf(_pelvis) < 0.000001: _pelvis = 0.0
	if _pelvis != 0.0:
		var parent: int = _skeleton.get_bone_parent(_hips)
		var parent_basis: Basis = _world_pose(parent).basis if parent >= 0 else _skeleton.global_basis
		_skeleton.set_bone_pose_position(_hips, _skeleton.get_bone_pose_position(_hips) + parent_basis.inverse() * Vector3.UP * _pelvis)
	for i: int in _legs.size():
		var leg: Dictionary = _legs[i]
		var row: Dictionary = rows[i]
		var hip: Vector3 = _world_pose(leg.upper).origin
		var target: Vector3 = row.target
		var vector: Vector3 = target - hip
		var distance: float = vector.length()
		var l1: float = leg.l1
		var l2: float = leg.l2
		# The authored Idle is almost straight. A fixed 6 mm reach margin during
		# the last millimetres of release would leave a 5 mm hover, then pop when
		# the adapter becomes exactly zero. Fade back to its existing reach.
		var correction_size: float = maxf(absf(float(row.offset) * _weight), absf(_pelvis))
		var reach_margin: float = lerpf(0.0004, REACH_MARGIN, smoothstep(0.0, 0.02, correction_size))
		# Reach saturation must preserve X/Z too. Radial distance clamping can
		# pull the shoe only a few mm backwards across a riser AFTER probing,
		# causing an entire stair-height penetration despite a small IK error.
		var horizontal_squared: float = vector.x * vector.x + vector.z * vector.z
		var max_reach: float = l1 + l2 - reach_margin
		var min_reach: float = maxf(MIN_REACH, absf(l1 - l2) + 0.004)
		var max_vertical: float = sqrt(maxf(0.0, max_reach * max_reach - horizontal_squared))
		var min_vertical: float = sqrt(maxf(0.0, min_reach * min_reach - horizontal_squared))
		var vertical: float = clampf(absf(vector.y), min_vertical, max_vertical) * (1.0 if vector.y > 0.0 else -1.0)
		var ankle := Vector3(target.x, hip.y + vertical, target.z)
		var reach: float = hip.distance_to(ankle)
		var direction: Vector3 = (ankle - hip) / reach
		var pole: Vector3 = row.pole
		pole -= direction * pole.dot(direction)
		if pole.length_squared() < 0.000001: pole = direction.cross(avatar_basis.x)
		pole = pole.normalized()
		var along: float = (l1 * l1 - l2 * l2 + reach * reach) / (2.0 * reach)
		var height: float = sqrt(maxf(0.0, l1 * l1 - along * along))
		var knee: Vector3 = hip + direction * along + pole * height
		if absf(float(row.offset) * _weight) + absf(_pelvis) > 0.000001:
			_aim(leg.upper, leg.lower, knee)
			_aim(leg.lower, leg.foot, ankle)
			# Preserve the authored shoe pitch, roll and yaw, including swing lift.
			_world_rotation(leg.foot, (row.foot_before as Transform3D).basis)
		var final: Transform3D = _world_pose(leg.foot)
		row.erase("pole")
		row["ankle_after"] = final.origin
		row["target_error"] = final.origin.distance_to(target)
		row["horizontal_target_error"] = Vector2(final.origin.x - target.x, final.origin.z - target.z).length()
		row["clamped"] = absf(distance - reach) > 0.0001
		row["reach_requested"] = distance
		row["reach_solved"] = reach
		row["reach_margin"] = reach_margin
		row["knee_after"] = _world_pose(leg.lower).origin
		row["foot_basis_error"] = final.basis.get_rotation_quaternion().angle_to((row.foot_before as Transform3D).basis.get_rotation_quaternion())
	return {"valid": true, "active": true, "weight": _weight, "pelvis_lower": _pelvis,
		"grounded_input": grounded, "contact_grace": contact_grace, "release_blend": release_blend,
		"air_elapsed": _air_elapsed, "support_queries": 10 if can_probe else 0,
		"wanted_pelvis_lower": wanted_pelvis, "legs": rows, "reset_count": _reset_count,
		"maximum_rays": 10, "persistent_overrides": false}
