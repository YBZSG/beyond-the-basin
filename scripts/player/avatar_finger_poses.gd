class_name AvatarFingerPoses
extends RefCounted
## Frame-local finger-only layer for the revised 54-joint explorer.
## Call after authored motion / hand IK, before the separate wrist-support pass.
## JSON quaternions are Blender bone-local DELTAS, not full Godot local poses.

const CONTRACT_PATH: String = "res://assets/water_hands/hand_pose_contract.json"
const DIGITS: Array[String] = ["Index", "Middle", "Ring", "Little", "Thumb"]
const RESPONSE: float = 14.0
const CONTACT_RESPONSE: float = 12.0
const RELEASE_SECONDS: float = 0.14

var _skeleton: Skeleton3D
var _bones: Array[Dictionary] = []
var _poses: Dictionary = {}
var _valid: bool = false
var _reason: String = "not_set_up"
var _last_output: Dictionary = {}
var _release_from: Dictionary = {}
var _release_age: float = RELEASE_SECONDS
var _was_holding: bool = false
var _hold_weight: float = 0.0
var _radius: float = 0.17
var _telemetry: Dictionary = {}

func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_bones.clear()
	_poses.clear()
	_telemetry.clear()
	_last_output.clear()
	_release_from.clear()
	_valid = false
	_was_holding = false
	_hold_weight = 0.0
	_release_age = RELEASE_SECONDS
	_radius = 0.17
	_reason = "requires_revised_54_joint_rig"
	if not is_instance_valid(skeleton) or skeleton.get_bone_count() != 54: return
	if skeleton.find_bone("WristSupport_L") < 0 or skeleton.find_bone("WristSupport_R") < 0: return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	if not parsed is Dictionary:
		_reason = "pose_contract_unreadable"
		return
	var contract: Dictionary = parsed
	var raw_poses: Dictionary = contract.get("poses", {})
	for pose_name: String in ["neutral", "relaxed", "carry", "release", "swim"]:
		if not raw_poses.has(pose_name):
			_reason = "missing_pose_" + pose_name
			return
		var converted: Dictionary = {}
		for side: String in ["L", "R"]:
			for digit: String in DIGITS:
				for segment: int in [1, 2, 3]:
					var name: String = digit + str(segment) + "_" + side
					var index: int = skeleton.find_bone(name)
					var entry: Dictionary = raw_poses[pose_name].get(name, {})
					var values: Array = entry.get("quaternion_wxyz", [])
					if index < 0 or values.size() != 4:
						_reason = "missing_finger_contract_" + name
						return
					var q := Quaternion(float(values[1]), float(values[2]), float(values[3]), float(values[0]))
					if not q.is_finite() or q.length_squared() < 0.5:
						_reason = "invalid_finger_quaternion_" + name
						return
					converted[name] = q.normalized()
		_poses[pose_name] = converted
	for side: String in ["L", "R"]:
		for digit: String in DIGITS:
			for segment: int in [1, 2, 3]:
				var name: String = digit + str(segment) + "_" + side
				var index: int = skeleton.find_bone(name)
				var rest: Quaternion = skeleton.get_bone_rest(index).basis.orthonormalized().get_rotation_quaternion()
				_bones.append({"name": name, "index": index, "rest": rest, "thumb": digit == "Thumb"})
				_last_output[index] = skeleton.get_bone_pose_rotation(index)
	_valid = _bones.size() == 30
	_reason = "ready" if _valid else "incomplete_fingers"

func _property(body: Object, name: StringName, fallback: Variant) -> Variant:
	for property: Dictionary in body.get_property_list():
		if StringName(property.name) == name: return body.get(name)
	return fallback

func _full_pose(bone: Dictionary, pose_name: String, gain: float = 1.0) -> Quaternion:
	var relative: Quaternion = _poses[pose_name][bone.name]
	if not is_equal_approx(gain, 1.0) and relative.get_angle() > 0.000001:
		relative = Quaternion(relative.get_axis(), relative.get_angle() * gain)
	# Verified against exported Wade / Swim / ThrowCharge tracks in the CPU test.
	# Only WXYZ -> XYZW storage order changes; no Y/Z axis swap in bone-local space.
	return ((bone.rest as Quaternion) * relative).normalized()

func apply(delta: float, held_body: RigidBody3D, contact_weight: float, action_state: Variant = {}) -> Dictionary:
	if not _valid or not is_instance_valid(_skeleton):
		return {"valid": false, "reason": _reason, "written_bones": 0}
	if not is_finite(delta) or delta <= 0.0:
		return get_telemetry()
	var dt: float = minf(delta, 0.1)
	var state: Dictionary = action_state if action_state is Dictionary else {"state": str(action_state)}
	var mode: String = str(state.get("state", "Idle"))
	var release_age: float = float(state.get("throw_release_age", 99.0))
	var authored: bool = bool(state.get("authored_fingers", true))
	var holding: bool = is_instance_valid(held_body)
	var dry_original: bool = mode in ["Idle", "Walk", "Run", "Hold"]
	var authored_release: bool = authored and (release_age < 0.65 or mode.begins_with("Throw"))
	var preserve_authored: bool = authored and (not dry_original or authored_release)
	var contact: float = clampf(contact_weight, 0.0, 1.0) if is_finite(contact_weight) else 0.0
	var goal: float = contact if holding else 0.0
	_hold_weight = lerpf(_hold_weight, goal, 1.0 - exp(-CONTACT_RESPONSE * dt))
	if absf(_hold_weight - goal) < 0.0001: _hold_weight = goal
	if holding:
		var radius: float = clampf(float(_property(held_body, &"radius", 0.17)), 0.10, 0.35)
		if not is_finite(radius): radius = 0.17
		_radius = lerpf(_radius, radius, 1.0 - exp(-10.0 * dt))
		_release_from.clear()
		_release_age = RELEASE_SECONDS
	elif _was_holding:
		# The parent already blends authored throw release from the actual grip.
		# Do not apply a second hold/release envelope to those calibrated tracks.
		if authored_release:
			_release_from.clear()
			_release_age = RELEASE_SECONDS
		else:
			_release_from = _last_output.duplicate()
			_release_age = 0.0
	else:
		_release_age = minf(RELEASE_SECONDS, _release_age + dt)
	var gain: float = clampf(0.17 / maxf(_radius, 0.10), 0.82, 1.12)
	var written: int = 0
	var maximum_delta: float = 0.0
	var smoothing: float = 1.0 - exp(-RESPONSE * dt)
	for bone: Dictionary in _bones:
		var index: int = int(bone.index)
		var incoming: Quaternion = _skeleton.get_bone_pose_rotation(index).normalized()
		var desired: Quaternion = incoming
		var write: bool = false
		if holding:
			var base: Quaternion = incoming if preserve_authored else _full_pose(bone, "relaxed")
			var finger_gain: float = lerpf(1.0, gain, 0.35) if bool(bone.thumb) else gain
			desired = base.slerp(_full_pose(bone, "carry", finger_gain), _hold_weight).normalized()
			var previous: Quaternion = _last_output.get(index, incoming)
			desired = previous.slerp(desired, smoothing).normalized()
			write = true
		elif not preserve_authored:
			var target: String = "swim" if mode in ["Swim", "SwimIdle"] else ("release" if release_age < 0.25 else "relaxed")
			desired = _full_pose(bone, target)
			var previous: Quaternion = _last_output.get(index, incoming)
			desired = previous.slerp(desired, smoothing).normalized()
			write = true
		if not holding and _release_age < RELEASE_SECONDS and _release_from.has(index) and not authored_release:
			var start: Quaternion = _release_from[index]
			desired = start.slerp(desired, smoothstep(0.0, RELEASE_SECONDS, _release_age)).normalized()
			write = true
		if write:
			_skeleton.set_bone_pose_rotation(index, desired)
			written += 1
			var relative: Quaternion = ((bone.rest as Quaternion).inverse() * desired).normalized()
			maximum_delta = maxf(maximum_delta, relative.get_angle())
		_last_output[index] = desired
	if _release_age >= RELEASE_SECONDS: _release_from.clear()
	_was_holding = holding
	_telemetry = {"valid": true, "reason": _reason, "written_bones": written, "finger_bones": _bones.size(),
		"holding": holding, "contact_weight": contact, "grip_weight": _hold_weight, "radius_m": _radius,
		"curl_gain": gain, "release_blend_age": _release_age, "authored_passthrough": written == 0,
		"maximum_finger_delta_radians": maximum_delta, "state": mode, "persistent_overrides": false}
	return _telemetry.duplicate()

func get_telemetry() -> Dictionary:
	if _telemetry.is_empty(): return {"valid": _valid, "reason": _reason, "written_bones": 0}
	return _telemetry.duplicate()
