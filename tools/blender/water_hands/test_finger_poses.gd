extends SceneTree
const Helper = preload("res://scripts/player/avatar_finger_poses.gd")
class TestProp extends RigidBody3D:
	var radius: float = 0.17

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var errors: Array[String] = []
var report: Dictionary = {}
var contract: Dictionary

func _initialize() -> void:
	call_deferred("run")

func inspect(node: Node) -> void:
	if node is Skeleton3D: skeleton = node
	if node is AnimationPlayer: animation_player = node
	for child: Node in node.get_children(): inspect(child)

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)

func quat(values: Array) -> Quaternion:
	return Quaternion(float(values[1]), float(values[2]), float(values[3]), float(values[0])).normalized()

func distance(a: Quaternion, b: Quaternion) -> float:
	return 1.0 - absf(a.normalized().dot(b.normalized()))

func all_rotations() -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for bone: int in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose_rotation(bone))
	return result

func set_clip(name: String, time: float = 0.0) -> void:
	var found: String = ""
	for candidate: String in animation_player.get_animation_list():
		if candidate.get_slice("/", candidate.get_slice_count("/") - 1) == name: found = candidate
	check(not found.is_empty(), "Missing clip " + name)
	if found.is_empty(): return
	animation_player.play(found)
	animation_player.seek(time, true)
	animation_player.advance(0.0)

func run() -> void:
	var packed: PackedScene = load("res://assets/water_motion/explorer_water_motion.scn")
	check(packed != null, "Final revised scene missing")
	if packed == null: finish(); return
	var model: Node = packed.instantiate()
	root.add_child(model)
	inspect(model)
	check(skeleton != null and animation_player != null, "Missing final skeleton / animation")
	if skeleton == null or animation_player == null: finish(); return
	contract = JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_hands/hand_pose_contract.json"))
	var helper = Helper.new()
	helper.setup(skeleton)
	check(bool(helper.get_telemetry().valid), "Setup did not accept revised rig")
	# Actual imported authored local rotations are the correspondence authority.
	var correspondences: Dictionary = {}
	for pair: Array in [["Wade", "relaxed"], ["Swim", "swim"], ["ThrowCharge", "carry"]]:
		set_clip(pair[0], 0.0)
		var maximum: float = 0.0
		for name: String in contract.poses[pair[1]]:
			var bone: int = skeleton.find_bone(name)
			var rest: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			var expected: Quaternion = (rest * quat(contract.poses[pair[1]][name].quaternion_wxyz)).normalized()
			maximum = maxf(maximum, distance(expected, skeleton.get_bone_pose_rotation(bone)))
		correspondences[pair[0]] = maximum
		check(maximum < 0.000002, "Source-local/Godot quaternion correspondence failed for " + str(pair[0]))
	report.authored_pose_quaternion_one_minus_abs_dot_max = correspondences
	# No-hold authored swim/release is exactly preserved, not overwritten by idle curl.
	for clip: String in ["Swim", "SwimIdle", "ThrowRelease", "JumpAir", "Wade"]:
		set_clip(clip, 0.1)
		var before: Array[Quaternion] = all_rotations()
		var state: Dictionary = {"state": clip, "throw_release_age": 0.1 if clip == "ThrowRelease" else 99.0}
		var result: Dictionary = helper.apply(1.0 / 60.0, null, 0.0, state)
		check(int(result.written_bones) == 0, "Authored no-hold pose overwritten: " + clip)
		for i: int in before.size(): check(distance(before[i], skeleton.get_bone_pose_rotation(i)) < 0.0000002, "Authored bone changed: " + clip)
	# Original 42-bone rigs are rejected and remain unmodified.
	var legacy := Skeleton3D.new()
	for i: int in 42: legacy.add_bone("Legacy" + str(i))
	var unsupported = Helper.new(); unsupported.setup(legacy)
	check(not bool(unsupported.apply(1.0 / 60.0, null, 0.0, {}).valid), "Legacy rig was modified")
	legacy.free()
	# Dry fingers settle to calibrated relaxed; arms/wrists remain exactly untouched.
	set_clip("Idle")
	helper.setup(skeleton)
	var immutable: Array[Quaternion] = all_rotations()
	for frame: int in 180:
		set_clip("Idle", 0.2)
		helper.apply(1.0 / 60.0, null, 0.0, {"state": "Idle"})
	var relaxed_error: float = 0.0
	for bone: int in skeleton.get_bone_count():
		var name: String = skeleton.get_bone_name(bone)
		if contract.poses.relaxed.has(name):
			var expected: Quaternion = (skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * quat(contract.poses.relaxed[name].quaternion_wxyz)).normalized()
			relaxed_error = maxf(relaxed_error, distance(expected, skeleton.get_bone_pose_rotation(bone)))
	# Compare after identical authored sampling, excluding only the exact 30 finger names.
	var actual: Array[Quaternion] = all_rotations(); set_clip("Idle", 0.2)
	for bone: int in skeleton.get_bone_count():
		if not contract.poses.relaxed.has(skeleton.get_bone_name(bone)):
			check(distance(actual[bone], skeleton.get_bone_pose_rotation(bone)) < 0.0000002, "Non-finger bone changed")
	check(relaxed_error < 0.000002, "Relaxed pose failed to converge")
	report.relaxed_quaternion_error = relaxed_error
	# Radius changes are bounded, frame-rate invariant, and do not become a fist.
	var body := TestProp.new(); root.add_child(body)
	var outcomes: Dictionary = {}
	for fps: int in [30, 60, 120]:
		set_clip("Idle"); helper.setup(skeleton)
		var result: Dictionary = {}
		for frame: int in fps * 2:
			set_clip("Hold", 0.1)
			result = helper.apply(1.0 / float(fps), body, 1.0, {"state": "Idle"})
		outcomes[str(fps)] = {"grip_weight": result.grip_weight, "max_delta": result.maximum_finger_delta_radians, "curl_gain": result.curl_gain}
		check(float(result.maximum_finger_delta_radians) < 0.31, "Excessive claw-like finger rotation")
		check(int(result.written_bones) == 30, "Not all distal joints driven")
	check(absf(float(outcomes["30"].max_delta) - float(outcomes["120"].max_delta)) < 0.002, "Frame-rate dependent settled grip")
	report.frame_rate_grips = outcomes
	var radius_outcomes: Dictionary = {}
	for radius: float in [0.10, 0.17, 0.35]:
		body.radius = radius
		set_clip("Idle"); helper.setup(skeleton)
		var result: Dictionary = {}
		for frame: int in 120:
			set_clip("Hold", 0.1)
			result = helper.apply(1.0 / 60.0, body, 1.0, {"state": "Idle"})
		radius_outcomes[str(radius)] = {"gain": result.curl_gain, "max_delta": result.maximum_finger_delta_radians}
		check(float(result.curl_gain) >= 0.8199 and float(result.curl_gain) <= 1.1201, "Radius curl outside safe range")
		check(float(result.maximum_finger_delta_radians) < 0.30, "Small-radius grip became a claw")
	check(float(radius_outcomes["0.1"].max_delta) > float(radius_outcomes["0.35"].max_delta), "Radius adaptation had no effect")
	report.radius_grips = radius_outcomes
	# Ordinary drop starts continuously, settles to relaxed, and regrab cancels its release.
	var before_drop: Array[Quaternion] = all_rotations()
	set_clip("Idle", 0.2)
	var dropped: Dictionary = helper.apply(1.0 / 60.0, null, 0.0, {"state": "Idle"})
	check(float(dropped.release_blend_age) == 0.0, "Drop did not begin a bounded transition")
	var drop_start_error: float = 0.0
	for name: String in contract.poses.relaxed:
		var bone: int = skeleton.find_bone(name)
		drop_start_error = maxf(drop_start_error, distance(before_drop[bone], skeleton.get_bone_pose_rotation(bone)))
	check(drop_start_error < 0.0000002, "Drop finger pose jumped on its first frame")
	for frame: int in 90:
		set_clip("Idle", 0.2)
		dropped = helper.apply(1.0 / 60.0, null, 0.0, {"state": "Idle"})
	check(float(dropped.release_blend_age) >= 0.14, "Drop transition remained stuck")
	report.ordinary_drop = {"first_frame_error": drop_start_error, "settled_release_age": dropped.release_blend_age}
	for frame: int in 60:
		set_clip("Hold", 0.1)
		helper.apply(1.0 / 60.0, body, 1.0, {"state": "Idle"})
	helper.apply(1.0 / 60.0, null, 0.0, {"state": "Idle"})
	var regrab: Dictionary = helper.apply(1.0 / 60.0, body, 1.0, {"state": "Idle"})
	check(float(regrab.release_blend_age) >= 0.14 and bool(regrab.holding), "Regrab did not cancel drop transition")
	report.regrab_cleared_release = true
	# An authored throw-release hand pose must pass through even after a live hold.
	set_clip("ThrowRelease", 0.02)
	var before_release: Array[Quaternion] = all_rotations()
	var release_result: Dictionary = helper.apply(1.0 / 60.0, null, 0.0, {"state": "ThrowRelease", "throw_release_age": 0.02})
	check(int(release_result.written_bones) == 0, "Double-smoothed authored release")
	for i: int in before_release.size(): check(distance(before_release[i], skeleton.get_bone_pose_rotation(i)) < 0.0000002, "Authored release changed")
	report.release_passthrough = release_result.authored_passthrough
	# Zero-delta calls are observational, never a hidden second animation clock.
	var before_zero: Array[Quaternion] = all_rotations(); helper.apply(0.0, body, 1.0, {"state": "Idle"})
	for i: int in before_zero.size(): check(distance(before_zero[i], skeleton.get_bone_pose_rotation(i)) < 0.0000002, "Zero-delta changed pose")
	# Exact source-space anchors converted to Godot skeleton-rest coordinates.
	var anchors: Dictionary = {}
	for side: String in ["L", "R"]:
		var row: Dictionary = contract.hand_geometry[side]
		var a: Array = row.palm_anchor; var source_to_godot := Vector3(float(a[0]), float(a[2]), -float(a[1]))
		var hand: int = skeleton.find_bone("Hand_" + side)
		var local: Vector3 = skeleton.get_bone_global_rest(hand).affine_inverse() * source_to_godot
		anchors[side] = {"skeleton_rest": [source_to_godot.x, source_to_godot.y, source_to_godot.z], "hand_local": [local.x, local.y, local.z], "roundtrip_error_m": (skeleton.get_bone_global_rest(hand) * local - source_to_godot).length()}
	report.palm_anchors_godot = anchors
	body.queue_free(); model.queue_free()
	finish()

func finish() -> void:
	report.passed = errors.is_empty()
	report.errors = errors
	report.engine = Engine.get_version_info().string
	report.gpu_used = false
	FileAccess.open("res://tools/blender/water_hands/finger_helper_validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("FINGER_HELPER_TEST ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
