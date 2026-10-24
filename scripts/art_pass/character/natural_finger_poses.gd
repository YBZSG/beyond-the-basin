extends "res://scripts/player/avatar_finger_poses.gd"
## Reuse the shipped temporal/contact policy, with the actual model's authored
## finger deltas. No old-axis finger pose is used by the new natural-rest rig.
var model_contract: Dictionary = {}

func setup(skeleton: Skeleton3D) -> void:
	super.setup(skeleton)
	_valid = false
	_reason = "natural_hand_contract_not_bound"
	if not is_instance_valid(skeleton) or model_contract.is_empty(): return
	var raw: Dictionary = model_contract.get("poses", {})
	_poses.clear()
	for pose_name: String in ["neutral", "relaxed", "carry", "release", "swim"]:
		var converted: Dictionary = {}
		for side: String in ["L", "R"]:
			for digit: String in DIGITS:
				for segment: int in [1,2,3]:
					var name: String = digit + str(segment) + "_" + side
					var values: Array = raw.get(pose_name, {}).get(name, {}).get("quaternion_wxyz", [])
					if values.size() != 4: return
					converted[name] = Quaternion(float(values[1]),float(values[2]),float(values[3]),float(values[0])).normalized()
		_poses[pose_name] = converted
	_valid = _bones.size() == 30
	_reason = "natural_hand_contract_ready" if _valid else "incomplete_natural_fingers"
