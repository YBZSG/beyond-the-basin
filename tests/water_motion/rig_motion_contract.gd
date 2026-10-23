extends RefCounted
## CPU skin readback of the production rig. No physics/animation mutations.
const ORIGINAL_BONES: Array[String] = ["Root","Hips","Spine","Chest","Neck","Head","Shoulder_R","UpperArm_R","Forearm_R","Hand_R","Index1_R","Index2_R","Middle1_R","Middle2_R","Ring1_R","Ring2_R","Little1_R","Little2_R","Thumb1_R","Thumb2_R","Shoulder_L","UpperArm_L","Forearm_L","Hand_L","Index1_L","Index2_L","Middle1_L","Middle2_L","Ring1_L","Ring2_L","Little1_L","Little2_L","Thumb1_L","Thumb2_L","UpperLeg_R","LowerLeg_R","Foot_R","Toe_R","UpperLeg_L","LowerLeg_L","Foot_L","Toe_L"]
var skeleton: Skeleton3D
var probes: Dictionary = {"sole_L": [], "sole_R": [], "hand_L": [], "hand_R": [], "body": [], "head": []}
var previous: Array[Quaternion] = []
var previous_epoch: int = -1
var samples: int = 0
var finite_errors: int = 0
var max_scale_error: float = 0.0
var max_link_length_error: float = 0.0
var max_rotation_step_deg: float = 0.0
var min_grounded_sole_clearance: float = INF
var max_supported_sole_clearance: float = -INF
var grounded_samples: int = 0
var unsupported_grounded_samples: int = 0
var torso_overlap_probes: int = 0
var wall_penetration_samples: int = 0
var max_wall_penetration: float = 0.0
var max_head_wall_penetration: float = 0.0
var max_body_wall_penetration: float = 0.0
var max_wall_envelope: Dictionary = {}
var worst_rotation: Dictionary = {}
var max_rotation_by_mode: Dictionary = {}
var worst_rotation_by_mode: Dictionary = {}
var max_steady_swim_rotation_step: float = 0.0
var flat_min_sole: float = INF
var ramp_min_sole: float = INF
var worst_sole: Dictionary = {}
var missing: Array[String] = []
var extra_missing: Array[String] = []
var mesh_vertex_count: int = 0
var skin_probe_count: int = 0
var bind_errors: Array[String] = []

func setup(model: Node3D, rig: Skeleton3D) -> void:
	skeleton = rig
	for name: String in ORIGINAL_BONES:
		if rig.find_bone(name) < 0: missing.append(name)
	for side: String in ["L", "R"]:
		for part: String in ["Index3_", "Middle3_", "Ring3_", "Little3_", "Thumb3_", "WristSupport_"]:
			if rig.find_bone(part + side) < 0: extra_missing.append(part + side)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		if String(instance.name).begins_with("Shadow_") or instance.mesh == null or instance.skin == null: continue
		var skin: Skin = instance.skin
		var bone_map: Array[int] = []
		for bind: int in skin.get_bind_count():
			var bone_name: String = skin.get_bind_name(bind)
			var bone: int = rig.find_bone(bone_name) if not bone_name.is_empty() else skin.get_bind_bone(bind)
			bone_map.append(bone)
			if bone < 0 or bone >= rig.get_bone_count(): bind_errors.append(String(instance.name) + ":" + bone_name)
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			mesh_vertex_count += vertices.size()
			if vertices.is_empty() or bones.is_empty(): continue
			var influences: int = bones.size() / vertices.size()
			for index: int in vertices.size():
				var links: Array[Dictionary] = []
				var categories: Dictionary = {"sole_L": 0.0, "sole_R": 0.0, "hand_L": 0.0, "hand_R": 0.0}
				for influence: int in influences:
					var offset: int = index * influences + influence
					var weight: float = weights[offset]
					if weight <= 0.0001: continue
					var bind: int = bones[offset]
					if bind < 0 or bind >= bone_map.size(): continue
					var bone: int = bone_map[bind]
					if bone < 0: continue
					var name: String = rig.get_bone_name(bone)
					links.append({"bone": bone, "point": skin.get_bind_pose(bind) * vertices[index], "weight": weight})
					for side: String in ["L", "R"]:
						if name in ["Foot_" + side, "Toe_" + side]: categories["sole_" + side] += weight
						if name.ends_with("_" + side) and (name.begins_with("Hand") or name.begins_with("Index") or name.begins_with("Middle") or name.begins_with("Ring") or name.begins_with("Little") or name.begins_with("Thumb")):
							categories["hand_" + side] += weight
				var total_hand: float = float(categories.hand_L) + float(categories.hand_R)
				if total_hand < 0.4 and index % 2 == 0:
					var head_weight: float = 0.0
					for link: Dictionary in links:
						if rig.get_bone_name(link.bone) in ["Head", "Neck"]: head_weight += link.weight
					probes["head" if head_weight > 0.6 else "body"].append(links)
				var rest_point := Vector3.ZERO
				for link: Dictionary in links: rest_point += rig.get_bone_global_rest(link.bone) * link.point * link.weight
				for category: String in categories:
					# Actual lowest rest mesh patch, not ankle joint or guessed offset.
					if categories[category] > 0.65 and (not category.begins_with("sole") or rest_point.y < 0.045):
						if not category.begins_with("hand") or index % 3 == 0:
							probes[category].append(links)
							skin_probe_count += 1

func bone_position(name: String) -> Vector3:
	var bone: int = skeleton.find_bone(name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin if bone >= 0 else Vector3.ZERO

func _skin_points(category: String, pose: Array[Transform3D]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for links: Array in probes[category]:
		var point := Vector3.ZERO
		for link: Dictionary in links: point += pose[link.bone] * link.point * link.weight
		result.append(skeleton.global_transform * point)
	return result

func sample(state: Dictionary, floor_at: Callable, detailed: bool = false) -> Dictionary:
	samples += 1
	var poses: Array[Transform3D] = []
	var rotations: Array[Quaternion] = []
	var epoch: int = int(state.get("epoch", 0))
	var frame_rotation_step: float = 0.0
	for bone: int in skeleton.get_bone_count():
		var pose: Transform3D = skeleton.get_bone_global_pose(bone)
		poses.append(pose)
		var local_rotation: Quaternion = skeleton.get_bone_pose_rotation(bone)
		rotations.append(local_rotation)
		if not pose.is_finite() or not local_rotation.is_finite(): finite_errors += 1
		var scale: Vector3 = skeleton.get_bone_pose_scale(bone)
		max_scale_error = maxf(max_scale_error, maxf(absf(scale.x-1), maxf(absf(scale.y-1), absf(scale.z-1))))
		var parent: int = skeleton.get_bone_parent(bone)
		var name: String = skeleton.get_bone_name(bone)
		if parent >= 0 and name not in ["Root", "Hips"]:
			var expected: float = skeleton.get_bone_global_rest(bone).origin.distance_to(skeleton.get_bone_global_rest(parent).origin)
			max_link_length_error = maxf(max_link_length_error, absf(pose.origin.distance_to(skeleton.get_bone_global_pose(parent).origin) - expected))
		if previous.size() == skeleton.get_bone_count() and previous_epoch == epoch:
			var rotation_step: float = rad_to_deg(previous[bone].angle_to(local_rotation))
			frame_rotation_step = maxf(frame_rotation_step, rotation_step)
			var mode: String=str(state.get("mode", "unknown"))
			if rotation_step > float(max_rotation_by_mode.get(mode, 0.0)):
				worst_rotation_by_mode[mode]={"bone":name,"physical_time":state.get("time",0.0),"stroke_phase":state.get("stroke_phase",0.0),"angle_deg":rotation_step,"swim_blend":state.get("review_swim_blend",0.0),"swim_forward":state.get("review_swim_forward",0.0),"jump_phase":state.get("jump_phase", ""),"throw_phase":state.get("throw_phase", "")}
			max_rotation_by_mode[mode]=maxf(float(max_rotation_by_mode.get(mode, 0.0)),rotation_step)
			if mode=="swim" and float(state.get("review_swim_blend",0.0))>.99 and float(state.get("review_swim_forward",0.0))>.99:
				max_steady_swim_rotation_step=maxf(max_steady_swim_rotation_step,rotation_step)
			if rotation_step > max_rotation_step_deg:
				worst_rotation = {"bone": name, "physical_time": state.get("time",0.0), "mode": state.get("mode",""), "angle_deg": rotation_step, "stroke_phase": state.get("stroke_phase",0.0)}
				max_rotation_step_deg = rotation_step
	previous = rotations
	previous_epoch = epoch
	max_rotation_step_deg = maxf(max_rotation_step_deg, frame_rotation_step)
	if not detailed: return {}
	var row: Dictionary = {"max_pose_rotation_step_deg": frame_rotation_step, "feet": {}, "hands": {}, "wall_penetration_m": 0.0}
	var chest: Transform3D = skeleton.global_transform * poses[skeleton.find_bone("Chest")]
	var min_any_sole: float = INF
	var min_sole_clearance: float = INF
	for side: String in ["L", "R"]:
		var points: Array[Vector3] = _skin_points("sole_" + side, poses)
		var minimum: float = INF
		var maximum: float = -INF
		var minimum_world_y: float = INF
		var min_point := Vector3.ZERO
		var slope_degrees: float = 0.0
		for point: Vector3 in points:
			var clearance: float = point.y - float(floor_at.call(point))
			if clearance < minimum:
				minimum = clearance; min_point = point
				slope_degrees = rad_to_deg(atan2(float(floor_at.call(point+Vector3(0,0,.01)))-float(floor_at.call(point-Vector3(0,0,.01))),.02))
			maximum = maxf(maximum, clearance)
			minimum_world_y = minf(minimum_world_y, point.y)
		min_any_sole = minf(min_any_sole, minimum)
		min_sole_clearance = minf(min_sole_clearance, minimum)
		if bool(state.get("grounded", false)):
			if absf(slope_degrees) < .1: flat_min_sole = minf(flat_min_sole, minimum)
			else: ramp_min_sole = minf(ramp_min_sole, minimum)
			if minimum < float(worst_sole.get("clearance_m", INF)):
				worst_sole = {"clearance_m": minimum, "side": side, "floor_slope_degrees": slope_degrees, "physical_time": state.get("time", 0.0), "mode": state.get("mode", ""), "point": vector(min_point), "gait_phase": state.get("review_gait_phase", 0.0)}
		row.feet[side] = {"sole_min_clearance_m": minimum if is_finite(minimum) else null, "sole_max_clearance_m": maximum if is_finite(maximum) else null, "sole_world_y": minimum_world_y if is_finite(minimum_world_y) else null, "vertices": points.size(), "lowest_point": vector(min_point), "floor_slope_degrees": slope_degrees, "ankle": vector(bone_position("Foot_" + side))}
		var hand_points: Array[Vector3] = _skin_points("hand_" + side, poses)
		var overlaps: int = 0
		var wall: float = 0.0
		for point: Vector3 in hand_points:
			# Conservative torso ellipsoid, a screen for inspection, not mesh/mesh collision.
			var torso_local: Vector3 = chest.affine_inverse() * point
			var ellipsoid: Vector3 = (torso_local - Vector3(0, -0.12, 0)) / Vector3(0.19, 0.30, 0.12)
			if ellipsoid.length_squared() < 1.0: overlaps += 1
			wall = maxf(wall, maxf(0.0, absf(point.x) - 2.65))
		row.hands[side] = {"vertices": hand_points.size(), "torso_ellipsoid_overlap_probes": overlaps, "wrist": vector(bone_position("Hand_" + side)), "wall_penetration_m": wall}
		torso_overlap_probes += overlaps
		row.wall_penetration_m = maxf(row.wall_penetration_m, wall)
	if bool(state.get("grounded", false)) and str(state.get("jump_phase", "")) not in ["takeoff", "land"]:
		grounded_samples += 1
		min_grounded_sole_clearance = minf(min_grounded_sole_clearance, min_any_sole)
		max_supported_sole_clearance = maxf(max_supported_sole_clearance, min_sole_clearance)
		if min_sole_clearance > 0.06: unsupported_grounded_samples += 1
	row.head_wall_penetration_m = 0.0
	row.body_wall_penetration_m = 0.0
	if absf(bone_position("Head").x) > 1.5:
		for category: String in ["head", "body"]:
			for point: Vector3 in _skin_points(category, poses):
				var wall: float = maxf(0.0, absf(point.x)-2.65)
				row[category+"_wall_penetration_m"] = maxf(row[category+"_wall_penetration_m"], wall)
	max_head_wall_penetration = maxf(max_head_wall_penetration, row.head_wall_penetration_m)
	max_body_wall_penetration = maxf(max_body_wall_penetration, row.body_wall_penetration_m)
	if float(row.wall_penetration_m) > max_wall_penetration:
		max_wall_envelope = {"physical_time": state.get("time", 0.0), "hand_m": row.wall_penetration_m, "head_m": row.head_wall_penetration_m, "body_m": row.body_wall_penetration_m}
	if float(row.wall_penetration_m) > 0.0: wall_penetration_samples += 1
	max_wall_penetration = maxf(max_wall_penetration, row.wall_penetration_m)
	row.head = vector(bone_position("Head"))
	row.hips = vector(bone_position("Hips"))
	return row

func result() -> Dictionary:
	return {"bone_count": skeleton.get_bone_count(), "original_42_missing": missing, "added_12_missing": extra_missing,
		"finite_transform_errors": finite_errors, "max_pose_scale_error": max_scale_error, "max_link_length_error_m": max_link_length_error,
		"max_rotation_change_deg_per_60hz_tick_excluding_warp": max_rotation_step_deg, "evaluated_skeleton_samples_including_capture_probes": samples,
		"mesh_vertex_count": mesh_vertex_count, "skin_probe_count": skin_probe_count, "bind_errors": bind_errors,
		"sole_probe_counts": {"L": probes.sole_L.size(), "R": probes.sole_R.size()}, "grounded_detailed_samples": grounded_samples,
		"min_grounded_sole_clearance_m": min_grounded_sole_clearance if is_finite(min_grounded_sole_clearance) else null,
		"max_minimum_sole_clearance_m": max_supported_sole_clearance if is_finite(max_supported_sole_clearance) else null,
		"both_soles_over_6cm_while_grounded_samples": unsupported_grounded_samples,
		"hand_torso_ellipsoid_overlap_probes": torso_overlap_probes, "wall_penetration_samples": wall_penetration_samples,
		"max_visible_hand_wall_penetration_m": max_wall_penetration, "max_head_wall_penetration_m": max_head_wall_penetration, "max_body_wall_penetration_m": max_body_wall_penetration, "worst_wall": max_wall_envelope, "worst_rotation": worst_rotation, "max_rotation_step_degrees_by_mode": max_rotation_by_mode, "worst_rotation_by_mode": worst_rotation_by_mode, "max_steady_forward_swim_rotation_step_degrees": max_steady_swim_rotation_step, "worst_sole": worst_sole, "flat_sample_point_minimum_sole_m_including_ramp_edge_reach": flat_min_sole, "ramp_minimum_sole_m": ramp_min_sole,
		"limitations": "Skin soles are actual weighted vertices; support heights use controlled analytic collision floor. Hand/torso uses conservative ellipsoid, not exact mesh collision. Native horizontal limbs are not capsule-protected. No target-PC FPS claim."}

static func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
