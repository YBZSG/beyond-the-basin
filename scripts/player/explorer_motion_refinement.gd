class_name ExplorerMotionRefinement
extends RefCounted
## Explorer-only, frame-local body mechanics, applied after AnimationTree and
## before any terrain leg placement, then hand grip IK. Never advances gait.
## The imported rig's pose includes rest orientation. Work in Skeleton3D space
## and convert desired global rotations through the CURRENT parent pose.
## No node/camera/collider movement, scale writes, or persistent overrides.

const RESPONSE_HZ: float = 11.0
const TURN_RESPONSE: float = 8.0
const MAX_ACCEL: float = 6.0
const MAX_TURN_RATE: float = 3.0
const LEG_MARGIN: float = 0.00001
var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _legs: Array[Dictionary] = []
var _valid: bool = false
var _has_motion: bool = false
var _epoch: int = -1
var _yaw: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _lean: Vector3 = Vector3.ZERO
var _lean_velocity: Vector3 = Vector3.ZERO
var _turn_rate: float = 0.0
var _acceleration: Vector3 = Vector3.ZERO

func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_valid = false
	_bones.clear()
	_legs.clear()
	if not is_instance_valid(skeleton): return
	for name: String in ["Hips", "Spine", "Chest", "Neck", "Head", "Shoulder_L", "Shoulder_R", "UpperArm_L", "UpperArm_R", "Forearm_L", "Forearm_R", "Hand_L", "Hand_R", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R"]:
		var index: int = skeleton.find_bone(name)
		if index < 0: return
		_bones[name] = index
	for side: String in ["L", "R"]:
		var upper: int = _bones["UpperLeg_" + side]
		var lower: int = _bones["LowerLeg_" + side]
		var foot: int = _bones["Foot_" + side]
		_legs.append({"side": side, "upper": upper, "lower": lower, "foot": foot,
			"l1": skeleton.get_bone_global_rest(upper).origin.distance_to(skeleton.get_bone_global_rest(lower).origin),
			"l2": skeleton.get_bone_global_rest(lower).origin.distance_to(skeleton.get_bone_global_rest(foot).origin)})
	_valid = true

func reset_motion(yaw: float, epoch: int) -> void:
	_epoch = epoch
	_yaw = yaw
	_velocity = Vector3.ZERO
	_lean = Vector3.ZERO
	_lean_velocity = Vector3.ZERO
	_turn_rate = 0.0
	_acceleration = Vector3.ZERO
	_has_motion = true

func integrate(displacement: Vector3, delta: float, yaw: float, epoch: int, enabled: bool) -> void:
	if delta <= 0.0: return
	if not _has_motion or epoch != _epoch:
		reset_motion(yaw, epoch)
	# Physical displacement is the source, not desired velocity. A wall cannot
	# induce a running lean. Epoch resets only inertia, NEVER the gait phase.
	var world_velocity: Vector3 = Vector3(displacement.x, 0.0, displacement.z) / delta if enabled else Vector3.ZERO
	var world_acceleration: Vector3 = (world_velocity - _velocity) / delta
	_velocity = world_velocity
	var frame := Basis(Vector3.UP, yaw)
	_acceleration = (frame.inverse() * world_acceleration).limit_length(MAX_ACCEL)
	var yaw_rate: float = clampf(angle_difference(_yaw, yaw) / delta, -MAX_TURN_RATE, MAX_TURN_RATE)
	_yaw = yaw
	_turn_rate = lerpf(_turn_rate, yaw_rate, 1.0 - exp(-TURN_RESPONSE * delta))
	var target := Vector3(_acceleration.z * 0.016, 0.0, -_acceleration.x * 0.014)
	# Analytic critically damped spring. No per-render Euler integration and no
	# division by render dt; acceleration/turn impulses behave at 15 and 60 Hz.
	var change: Vector3 = _lean - target
	var momentum: Vector3 = _lean_velocity + change * RESPONSE_HZ
	var decay: float = exp(-RESPONSE_HZ * delta)
	_lean = target + (change + momentum * delta) * decay
	_lean_velocity = (_lean_velocity - momentum * RESPONSE_HZ * delta) * decay

func _pose(bone: int) -> Transform3D:
	return _skeleton.get_bone_global_pose(bone)

func _rotation(bone: int, desired: Basis) -> void:
	var parent: int = _skeleton.get_bone_parent(bone)
	var parent_basis: Basis = _pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * desired.orthonormalized()).get_rotation_quaternion().normalized())

func _rotate(name: String, angles: Vector3) -> void:
	var bone: int = _bones[name]
	_rotation(bone, Basis.from_euler(angles) * _pose(bone).basis)

func _aim(bone: int, child: int, target: Vector3) -> void:
	var pose: Transform3D = _pose(bone)
	var from: Vector3 = (_pose(child).origin - pose.origin).normalized()
	var to: Vector3 = (target - pose.origin).normalized()
	var dot: float = clampf(from.dot(to), -1.0, 1.0)
	var cross: Vector3 = from.cross(to)
	var swing := Quaternion(cross.x, cross.y, cross.z, 1.0 + dot).normalized() if dot > -0.99999 else Quaternion(from, to)
	_rotation(bone, Basis(swing) * pose.basis)

func _preserve_ankles(targets: Array[Transform3D], poles: Array[Vector3]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i: int in _legs.size():
		var leg: Dictionary = _legs[i]
		var target: Transform3D = targets[i]
		var hip: Vector3 = _pose(leg.upper).origin
		var vector: Vector3 = target.origin - hip
		var distance: float = vector.length()
		var l1: float = leg.l1
		var l2: float = leg.l2
		var reach: float = clampf(distance, absf(l1-l2)+LEG_MARGIN, l1+l2-LEG_MARGIN)
		var direction: Vector3 = vector / maxf(distance, 0.00001)
		var pole: Vector3 = poles[i] - direction * poles[i].dot(direction)
		if pole.length_squared() < 0.00001: pole = Vector3.RIGHT
		pole = pole.normalized()
		var along: float = (l1*l1-l2*l2+reach*reach)/(2.0*reach)
		var knee: Vector3 = hip + direction*along + pole*sqrt(maxf(0.0,l1*l1-along*along))
		_aim(leg.upper, leg.lower, knee)
		_aim(leg.lower, leg.foot, hip+direction*reach)
		_rotation(leg.foot, target.basis)
		rows.append({"side": leg.side, "ankle_error": _pose(leg.foot).origin.distance_to(target.origin),
			"reach_clamped": absf(distance-reach)>0.0001,
			"knee_flex_degrees": rad_to_deg(PI-acos(clampf((l1*l1+l2*l2-reach*reach)/(2.0*l1*l2),-1.0,1.0)))})
	return rows

func apply(clock: float, gait_phase: float, move: float, run: float, wade: float,
		hold: float, excluded_weight: float, body_yaw: float, depth: float = 0.0) -> Dictionary:
	if not _valid: return {"valid": false}
	var grounded: float = 1.0 - clampf(excluded_weight, 0.0, 1.0)
	if grounded < 0.00001: return {"valid": true, "active": false}
	var idle: float = 1.0-clampf(move,0.0,1.0)
	var free_arms: float = grounded*(1.0-clampf(hold,0.0,1.0))
	var deep: float = smoothstep(0.15,0.65,maxf(depth,0.0))*wade
	var breath: float = sin(clock*TAU/4.8)
	var shift: float = sin(clock*TAU/7.6)
	var phase: float = gait_phase*TAU
	var stride: float = sin(phase)
	var turn: float = _turn_rate
	var local_lean: Vector3 = Basis(Vector3.UP,-body_yaw)*_lean
	var moving: float = clampf(move,0.0,1.0)
	# Extra body articulation is smaller while carrying. Hand IK remains last.
	var carry_damping: float = lerpf(1.0,0.45,hold)
	var target_ankles: Array[Transform3D] = []
	var target_poles: Array[Vector3] = []
	for leg: Dictionary in _legs:
		var ankle: Transform3D = _pose(leg.foot)
		var hip: Vector3 = _pose(leg.upper).origin
		var axis: Vector3 = (ankle.origin-hip).normalized()
		var knee_vector: Vector3 = _pose(leg.lower).origin-hip
		var pole: Vector3 = knee_vector-axis*knee_vector.dot(axis)
		target_ankles.append(ankle)
		target_poles.append(pole.normalized() if pole.length_squared()>0.000001 else Vector3.FORWARD)
	var pelvis_offset := Vector3((0.0045*shift*idle + 0.003*stride*moving)*carry_damping,
		-(0.010+0.002*breath)*idle-0.003*moving*deep, 0.0)
	pelvis_offset *= grounded
	var hips: int = _bones.Hips
	var parent: int = _skeleton.get_bone_parent(hips)
	var parent_basis: Basis = _pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_position(hips,_skeleton.get_bone_pose_position(hips)+parent_basis.inverse()*pelvis_offset)
	_rotate("Hips", Vector3(local_lean.x*0.18,0.018*stride*moving,-0.010*shift*idle+local_lean.z*0.20)*grounded*carry_damping)
	_rotate("Spine", Vector3(local_lean.x*0.55-0.014*deep*moving,-turn*0.018,
		local_lean.z*0.55+turn*0.012*moving+0.006*shift*idle)*grounded*carry_damping)
	_rotate("Chest", Vector3(local_lean.x*0.27+0.009*breath*idle,-0.038*stride*moving-turn*0.024,
		local_lean.z*0.25)*grounded*carry_damping)
	# The chest trails a turn while neck counter-yaw keeps the head near the
	# view direction. Adding another negative yaw here makes the head lag most.
	_rotate("Neck",Vector3(-local_lean.x*0.32,turn*0.035,0.0)*grounded*carry_damping)
	_rotate("Head",Vector3(-0.004*breath*idle,turn*0.012,0.0)*grounded)
	for side: int in [1,-1]:
		var suffix: String = "L" if side==1 else "R"
		var arm_phase: float = phase + (0.0 if side==1 else PI)
		var settle: float = sin(clock*TAU/5.3+float(side)*0.8)
		# Shoulder girdle releases by 0.4-0.9 cm instead of staying square. The
		# imported Idle is already adducted: only 1 degree of extra tuck is safe.
		_rotate("Shoulder_"+suffix,Vector3(0.012*settle*idle, -0.018*sin(arm_phase-0.3)*moving, -float(side)*(0.035+0.007*breath*idle))*free_arms)
		_rotate("UpperArm_"+suffix,Vector3(0.035*settle*idle-local_lean.x*0.65+0.045*sin(arm_phase-0.4)*moving*(1.0-run), -turn*0.025, -float(side)*0.018*idle+float(side)*0.055*deep*moving)*free_arms)
		_rotate("Forearm_"+suffix,Vector3(0.035+0.025*sin(arm_phase-0.65)*moving+0.016*settle*idle+0.065*deep*moving, 0.0, 0.0)*free_arms)
		_rotate("Hand_"+suffix,Vector3(-0.015-0.016*sin(arm_phase-0.9)*moving, float(side)*0.018*settle*idle, 0.0)*free_arms)
	# Preserve the authored heel/toe trajectory in all three axes. Soft knees
	# follow the lower pelvis without shifting soles, changing stride, or phase.
	var legs: Array[Dictionary] = _preserve_ankles(target_ankles, target_poles)
	return {"valid": true,"active": true,"pelvis_offset": pelvis_offset,"lean": local_lean,
		"turn_rate": turn,"acceleration": _acceleration,"free_arm_weight": free_arms,
		"deep_wade_weight": deep,"legs": legs,"persistent_overrides": false}
