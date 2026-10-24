extends RefCounted
## Imported-bone-space contract. Validates the actual loaded rig, not raw GLB
## bytes that may be absent after Godot resource import/export remapping.
const POSE_NAMES := ["neutral", "relaxed", "carry", "release", "swim"]
const DIGITS := ["Thumb", "Index", "Middle", "Ring", "Little"]
const REST_TOLERANCE := 0.00001

static func _vector(value: Variant) -> Variant:
	if not value is Array or value.size() != 3: return null
	for v: Variant in value:
		if not (v is float or v is int) or not is_finite(float(v)): return null
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _fail(reason: String) -> Dictionary:
	return {"valid":false,"reason":reason}

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result if result is Dictionary else {}

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = find_skeleton(child)
		if found != null: return found
	return null

static func validate(contract: Dictionary, skeleton: Skeleton3D, model_path: String, allow_preview: bool = false) -> Dictionary:
	if contract.is_empty(): return _fail("missing_contract")
	if str(contract.get("schema", "")) != "poolcore.natural_hand" or int(contract.get("version", -1)) != 1: return _fail("unsupported_schema")
	if not allow_preview and str(contract.get("acceptance", "")) != "accepted": return _fail("contract_not_accepted")
	if not contract.get("model", {}) is Dictionary or not contract.get("skeleton", {}) is Dictionary: return _fail("invalid_schema")
	var model: Dictionary = contract.model
	if model_path not in [str(model.get("glb_path", "")), str(model.get("scn_path", ""))]: return _fail("model_identity_mismatch")
	if not is_instance_valid(skeleton) or skeleton.get_bone_count() != 54: return _fail("requires_54_bones")
	var bone_spec: Variant = contract.skeleton.get("bones", [])
	if not bone_spec is Array or bone_spec.size() != 54: return _fail("incomplete_rest_contract")
	var names: Dictionary = {}
	var maximum_rest_error: float = 0.0
	for row: Variant in bone_spec:
		if not row is Dictionary: return _fail("invalid_bone_entry")
		var name: String = str(row.get("name", ""))
		var index: int = skeleton.find_bone(name)
		if name.is_empty() or names.has(name) or index < 0: return _fail("missing_or_duplicate_bone_" + name)
		names[name] = true
		var parent_index: int = skeleton.get_bone_parent(index)
		var parent_name: String = skeleton.get_bone_name(parent_index) if parent_index >= 0 else ""
		if parent_name != str(row.get("parent", "")): return _fail("parent_mismatch_" + name)
		var rest: Variant = row.get("rest_godot", {})
		if not rest is Dictionary: return _fail("invalid_rest_" + name)
		var origin: Variant = _vector(rest.get("origin"))
		var columns: Variant = rest.get("basis_columns", [])
		if origin == null or not columns is Array or columns.size() != 3: return _fail("invalid_rest_" + name)
		var actual: Transform3D = skeleton.get_bone_rest(index)
		for k: int in range(3):
			maximum_rest_error = maxf(maximum_rest_error, absf(actual.origin[k] - origin[k]))
			var column: Variant = _vector(columns[k])
			if column == null: return _fail("invalid_basis_" + name)
			for axis: int in range(3): maximum_rest_error = maxf(maximum_rest_error, absf(actual.basis[k][axis] - column[axis]))
		if not actual.is_finite() or actual.basis.determinant() <= 0.0: return _fail("invalid_loaded_rest_" + name)
	if maximum_rest_error > REST_TOLERANCE: return _fail("rest_mismatch_" + str(maximum_rest_error))
	var protected: Variant = contract.skeleton.get("protected_names", [])
	if not protected is Array or protected.size() != 24: return _fail("missing_protected_bone_contract")
	var seen_protected: Dictionary = {}
	for name: Variant in protected:
		if not names.has(str(name)) or seen_protected.has(str(name)): return _fail("invalid_protected_bone")
		seen_protected[str(name)] = true
	var finger_names: Array[String] = []
	for side: String in ["L", "R"]:
		for digit: String in DIGITS:
			for segment: int in [1,2,3]:
				var name: String = digit + str(segment) + "_" + side
				if not names.has(name) or seen_protected.has(name): return _fail("invalid_finger_partition")
				finger_names.append(name)
	var poses: Variant = contract.get("poses", {})
	if not poses is Dictionary: return _fail("invalid_poses")
	for pose_name: String in POSE_NAMES:
		var pose: Variant = poses.get(pose_name, {})
		if not pose is Dictionary or pose.size() != 30: return _fail("incomplete_pose_" + pose_name)
		for name: String in finger_names:
			var entry: Variant = pose.get(name, {})
			if not entry is Dictionary: return _fail("invalid_pose_entry_" + name)
			var q: Variant = entry.get("quaternion_wxyz", [])
			if not q is Array or q.size() != 4: return _fail("invalid_pose_quaternion_" + name)
			var norm: float = 0.0
			for component: Variant in q:
				if not (component is int or component is float) or not is_finite(float(component)): return _fail("nonfinite_pose_" + name)
				norm += float(component) * float(component)
			if absf(norm - 1.0) > 0.001: return _fail("unnormalized_pose_" + name)
	var contacts: Variant = contract.get("hand_contact", {})
	if not contacts is Dictionary: return _fail("invalid_contact_contract")
	for side: String in ["L", "R"]:
		var hand: Variant = contacts.get(side, {})
		if not hand is Dictionary: return _fail("invalid_contact_" + side)
		var palm: Variant = _vector(hand.get("palm_local_godot"))
		var along: Variant = _vector(hand.get("long_local_godot"))
		var inward: Variant = _vector(hand.get("inward_local_godot"))
		if palm == null or along == null or inward == null: return _fail("nonfinite_contact_" + side)
		if palm.length() > 0.2 or palm.length() < 0.01: return _fail("implausible_palm_anchor_" + side)
		if absf(along.length() - 1.0) > 0.001 or absf(inward.length() - 1.0) > 0.001 or absf(along.dot(inward)) > 0.01: return _fail("invalid_palm_axes_" + side)
	return {"valid":true,"reason":"imported_rest_and_hand_contract_match","bones":54,"finger_bones":30,"protected_bones":24,"maximum_rest_error":maximum_rest_error,"preview":allow_preview}
