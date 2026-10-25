extends RefCounted
## Deterministic visual-only throw poses derived from this rig's rest geometry.
## Not source motion capture, not a retarget of the 54-bone explorer. Player
## release timing, velocity, contact and physics remain entirely unchanged.
const Rig = preload("res://scripts/player/ithappy_rig.gd")

static func _frame(direction: Vector3, normal: Vector3) -> Basis:
	var y: Vector3 = direction.normalized()
	var z: Vector3 = (normal - y * normal.dot(y)).normalized()
	return Basis(y.cross(z).normalized(), y, z).orthonormalized()

static func _pose(skeleton: Skeleton3D, extension: float) -> Dictionary:
	var result: Dictionary = {}
	for side: String in ["L", "R"]:
		var sign_side: float = 1.0 if side == "L" else -1.0
		var upper: int = skeleton.find_bone("UpperArm_" + side)
		var lower: int = skeleton.find_bone("Forearm_" + side)
		var hand: int = skeleton.find_bone("Hand_" + side)
		var shoulder_rest: Transform3D = skeleton.get_bone_global_rest(upper)
		var elbow_rest: Transform3D = skeleton.get_bone_global_rest(lower)
		var hand_rest: Transform3D = skeleton.get_bone_global_rest(hand)
		var l1: float = shoulder_rest.origin.distance_to(elbow_rest.origin)
		var l2: float = elbow_rest.origin.distance_to(hand_rest.origin)
		var reach: float = l1 + l2
		# Two-hand forward push, hands above waist, elbows down and out.
		var wrist := Vector3(sign_side * 0.14, shoulder_rest.origin.y - reach * lerpf(0.35, 0.12, extension), shoulder_rest.origin.z - reach * lerpf(0.40, 0.91, extension))
		var to_wrist: Vector3 = wrist - shoulder_rest.origin
		var distance: float = clampf(to_wrist.length(), absf(l1-l2)+0.005, reach-0.012)
		var direction: Vector3 = to_wrist.normalized()
		wrist = shoulder_rest.origin + direction * distance
		var pole := Vector3(sign_side * 0.35, -0.9, 0.1)
		pole = (pole - direction * pole.dot(direction)).normalized()
		var along: float = (l1*l1-l2*l2+distance*distance)/(2.0*distance)
		var elbow: Vector3 = shoulder_rest.origin + direction*along + pole*sqrt(maxf(0.0,l1*l1-along*along))
		var upper_basis: Basis = Basis(Quaternion((elbow_rest.origin-shoulder_rest.origin).normalized(), (elbow-shoulder_rest.origin).normalized())) * shoulder_rest.basis.orthonormalized()
		var lower_basis: Basis = Basis(Quaternion((hand_rest.origin-elbow_rest.origin).normalized(), (wrist-elbow).normalized())) * elbow_rest.basis.orthonormalized()
		var geometry: Dictionary = Rig.palm_geometry(skeleton, side)
		var local_frame: Basis = _frame(hand_rest.basis.inverse() * (geometry.long as Vector3), hand_rest.basis.inverse() * (geometry.normal as Vector3))
		var hand_basis: Basis = _frame(Vector3.FORWARD, Vector3(-sign_side, 0.0, 0.0)) * local_frame.inverse()
		var parent: int = skeleton.get_bone_parent(upper)
		var parent_basis: Basis = skeleton.get_bone_global_rest(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		result[upper] = (parent_basis.inverse()*upper_basis).get_rotation_quaternion().normalized()
		result[lower] = (upper_basis.inverse()*lower_basis).get_rotation_quaternion().normalized()
		result[hand] = (lower_basis.inverse()*hand_basis).get_rotation_quaternion().normalized()
	return result

static func build_action_library(skeleton: Skeleton3D, skeleton_track_path: NodePath, idle: Animation = null) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	if Rig.validate(skeleton) != "ready": return library
	var charge: Dictionary = _pose(skeleton, 0.0)
	var extended: Dictionary = _pose(skeleton, 1.0)
	var resting: Dictionary = {}
	for index: int in charge:
		resting[index] = skeleton.get_bone_rest(index).basis.orthonormalized().get_rotation_quaternion()
	# Recover to the actual idle pose when available, not an A-pose snap.
	if idle != null:
		for track: int in idle.get_track_count():
			if idle.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
			var path: NodePath = idle.track_get_path(track)
			if path.get_subname_count() == 0: continue
			var index: int = skeleton.find_bone(String(path.get_subname(0)))
			if resting.has(index): resting[index] = idle.rotation_track_interpolate(track, 0.0)
	for clip: String in ["ThrowCharge", "ThrowRelease", "ThrowRecover"]:
		var animation := Animation.new()
		animation.length = 0.45 if clip == "ThrowCharge" else (0.25 if clip == "ThrowRelease" else 0.35)
		animation.loop_mode = Animation.LOOP_NONE
		var start: Dictionary = resting if clip == "ThrowCharge" else (charge if clip == "ThrowRelease" else extended)
		var end: Dictionary = charge if clip == "ThrowCharge" else (extended if clip == "ThrowRelease" else resting)
		for index: int in charge:
			var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, NodePath(String(skeleton_track_path)+":"+skeleton.get_bone_name(index)))
			animation.rotation_track_insert_key(track, 0.0, start[index])
			animation.rotation_track_insert_key(track, animation.length, end[index])
		library.add_animation(StringName(clip), animation)
	return library
