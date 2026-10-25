extends RefCounted
## Independent, conservative two-phalange grip layer for the ithappy rig.
## Rest-derived axes curl toward the palm; authored non-carry animation passes
## through. Only the twenty validated finger rotations can ever be written.
const Rig = preload("res://scripts/player/ithappy_rig.gd")
var _skeleton: Skeleton3D
var _bones: Array[Dictionary] = []
var _reason: String = "not_set_up"
var _weight: float = 0.0
var _telemetry: Dictionary = {}

func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_bones.clear()
	_weight = 0.0
	_telemetry.clear()
	_reason = Rig.validate(skeleton)
	if _reason != "ready": return
	for side: String in ["L", "R"]:
		var palm: Dictionary = Rig.palm_geometry(skeleton, side)
		for digit: String in Rig.DIGITS:
			var first: int = skeleton.find_bone(digit + "1_" + side)
			var second: int = skeleton.find_bone(digit + "2_" + side)
			var first_rest: Transform3D = skeleton.get_bone_global_rest(first)
			var second_rest: Transform3D = skeleton.get_bone_global_rest(second)
			var direction: Vector3 = (second_rest.origin - first_rest.origin).normalized()
			var curl_toward: Vector3 = palm.normal
			if digit == "Thumb":
				# Opposition toward the other fingers, with a restrained palm component.
				curl_toward = ((palm.middle as Vector3) - first_rest.origin).normalized() + (palm.normal as Vector3) * 0.55
			var world_axis: Vector3 = direction.cross(curl_toward).normalized()
			if world_axis.length_squared() < 0.99:
				_reason = "degenerate_curl_axis"
				_bones.clear()
				return
			for index: int in [first, second]:
				var rest: Transform3D = skeleton.get_bone_global_rest(index)
				var axis: Vector3 = (rest.basis.orthonormalized().inverse() * world_axis).normalized()
				_bones.append({"index": index, "axis": axis,
					"rest": skeleton.get_bone_rest(index).basis.orthonormalized().get_rotation_quaternion(),
					"angle": (0.30 if index == first else 0.44) if digit == "Thumb" else (0.38 if index == first else 0.58)})

func apply(delta: float, held_body: RigidBody3D, contact_weight: float, _action_state: Variant = {}) -> Dictionary:
	if _reason != "ready" or not is_instance_valid(_skeleton):
		return {"valid": false, "reason": _reason, "written_bones": 0}
	if not is_finite(delta) or delta <= 0.0: return get_telemetry()
	var holding: bool = is_instance_valid(held_body)
	var contact: float = clampf(contact_weight, 0.0, 1.0) if is_finite(contact_weight) else 0.0
	var goal: float = contact if holding else 0.0
	_weight = lerpf(_weight, goal, 1.0 - exp(-14.0 * minf(delta, 0.1)))
	if _weight < 0.0001: _weight = 0.0
	var written: int = 0
	# Finite, bounded curl; no guesses about missing distal joints and no writes
	# to hands, arm, chest, root or any protected original-rig channels.
	if _weight > 0.0:
		for bone: Dictionary in _bones:
			var index: int = int(bone.index)
			var incoming: Quaternion = _skeleton.get_bone_pose_rotation(index).normalized()
			var target: Quaternion = ((bone.rest as Quaternion) * Quaternion(bone.axis, float(bone.angle))).normalized()
			_skeleton.set_bone_pose_rotation(index, incoming.slerp(target, _weight).normalized())
			written += 1
	_telemetry = {"valid": true, "reason": _reason, "rig_profile": "ithappy_44",
		"finger_bones": _bones.size(), "written_bones": written, "grip_weight": _weight,
		"holding": holding, "authored_passthrough": written == 0, "persistent_overrides": false}
	return _telemetry.duplicate()

func get_telemetry() -> Dictionary:
	return _telemetry.duplicate() if not _telemetry.is_empty() else {"valid": _reason == "ready", "reason": _reason, "written_bones": 0}
