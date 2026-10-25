extends RefCounted
## Separate two-phalange rig contract. Never shares the original 54-bone contract.
const DIGITS: Array[String] = ["Thumb", "Index", "Middle", "Ring", "Little"]

static func validate(skeleton: Skeleton3D) -> String:
	if not is_instance_valid(skeleton) or skeleton.get_bone_count() != 44:
		return "requires_ithappy_44_joint_rig"
	var parents: Dictionary = {"Root": "", "Hips": "Root", "Spine": "Hips", "Chest": "Spine", "Neck": "Chest", "Head": "Neck"}
	for side: String in ["L", "R"]:
		for link: Array in [["Shoulder", "Chest"], ["UpperArm", "Shoulder"], ["Forearm", "UpperArm"], ["Hand", "Forearm"], ["HandProp", "Hand"], ["UpperLeg", "Hips"], ["LowerLeg", "UpperLeg"], ["Foot", "LowerLeg"], ["Toe", "Foot"]]:
			parents[String(link[0])+"_"+side] = String(link[1]) if link[1] in ["Chest", "Hips"] else String(link[1])+"_"+side
		for digit: String in DIGITS:
			parents[digit+"1_"+side] = "Hand_"+side
			parents[digit+"2_"+side] = digit+"1_"+side
	for name: String in parents:
		var index: int = skeleton.find_bone(name)
		if index < 0: return "missing_bone_" + name
		var parent: int = skeleton.get_bone_parent(index)
		if (parent != -1 if String(parents[name]).is_empty() else (parent < 0 or skeleton.get_bone_name(parent) != parents[name])):
			return "invalid_parent_" + name
		var rest: Transform3D = skeleton.get_bone_rest(index)
		if not rest.is_finite(): return "nonfinite_rest_" + name
		var scale: Vector3 = rest.basis.get_scale()
		if scale.distance_to(Vector3.ONE) > 0.02 or rest.basis.determinant() < 0.95:
			return "unsupported_rest_scale_" + name
	for side: String in ["L", "R"]:
		if skeleton.find_bone("WristSupport_" + side) >= 0:
			return "unexpected_wrist_support"
		var upper: int = skeleton.find_bone("UpperArm_" + side)
		var forearm: int = skeleton.find_bone("Forearm_" + side)
		var hand: int = skeleton.find_bone("Hand_" + side)
		if mini(upper, mini(forearm, hand)) < 0:
			return "missing_arm_chain"
		if skeleton.get_bone_parent(forearm) != upper or skeleton.get_bone_parent(hand) != forearm:
			return "invalid_arm_parent"
		for digit: String in DIGITS:
			var first: int = skeleton.find_bone(digit + "1_" + side)
			var second: int = skeleton.find_bone(digit + "2_" + side)
			if mini(first, second) < 0 or skeleton.find_bone(digit + "3_" + side) >= 0:
				return "requires_two_phalanges_" + digit + "_" + side
			if skeleton.get_bone_parent(first) != hand or skeleton.get_bone_parent(second) != first:
				return "invalid_finger_parent_" + digit + "_" + side
			if skeleton.get_bone_global_rest(first).origin.distance_to(skeleton.get_bone_global_rest(second).origin) < 0.005:
				return "degenerate_finger_" + digit + "_" + side
		var upper_length: float = skeleton.get_bone_global_rest(upper).origin.distance_to(skeleton.get_bone_global_rest(forearm).origin)
		var lower_length: float = skeleton.get_bone_global_rest(forearm).origin.distance_to(skeleton.get_bone_global_rest(hand).origin)
		if minf(upper_length, lower_length) < 0.10 or maxf(upper_length, lower_length) > 0.60:
			return "unsupported_arm_dimensions_" + side
		var geometry: Dictionary = palm_geometry(skeleton, side)
		if float(geometry.length) < 0.03 or (geometry.normal as Vector3).length_squared() < 0.99:
			return "degenerate_palm_" + side
	return "ready"

static func palm_geometry(skeleton: Skeleton3D, side: String) -> Dictionary:
	var hand: Transform3D = skeleton.get_bone_global_rest(skeleton.find_bone("Hand_" + side))
	var middle: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("Middle1_" + side)).origin
	var index: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("Index1_" + side)).origin
	var little: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("Little1_" + side)).origin
	var longitudinal: Vector3 = (middle - hand.origin).normalized()
	var normal: Vector3 = longitudinal.cross(index - little).normalized()
	# The authored A-pose palms face inward. Resolve mirrored cross-product sign
	# geometrically, not by assuming bone-local X/Z axes like the original rig.
	var toward_center := Vector3(-hand.origin.x, 0.0, 0.0)
	if normal.dot(toward_center) < 0.0: normal = -normal
	return {"hand": hand, "middle": middle, "long": longitudinal,
		"normal": normal, "length": hand.origin.distance_to(middle)}
