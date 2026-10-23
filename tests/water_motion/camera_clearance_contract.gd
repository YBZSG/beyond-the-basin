extends SceneTree
## Actual skinned body samples through swim/start/stop, without GPU claims.
const Player = preload("res://scripts/player/pool_player.gd")
const Avatar = preload("res://scripts/player/pool_avatar.gd")
const RigProbe = preload("res://tests/water_motion/rig_motion_contract.gd")
var report: Dictionary = {"errors": [], "rates": []}
class SwimWater extends Node3D:
	func is_water_at(_p: Vector3) -> bool: return true
	func surface_height_at(_p: Vector3) -> float: return 0.32
	func depth_at(_p: Vector3) -> float: return 2.20
	func current_velocity_at(_p: Vector3) -> Vector2: return Vector2.ZERO
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump", "throw_prop", "grab_prop", "interact", "pause"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for hz in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		var water := SwimWater.new()
		root.add_child(water)
		var player := Player.new()
		root.add_child(player)
		player.set_physics_process(false)
		player.collision_mask = 0
		player.set_water(water)
		player.warp_to(Vector3(0,-1.16,0), Vector3(0,0.44,-10))
		player.enabled = true
		var avatar := Avatar.new()
		avatar.model_path = "res://assets/water_motion/explorer_water_motion.scn"
		avatar.setup(player)
		avatar.set_process(false)
		var probe := RigProbe.new()
		probe.setup(avatar._model, avatar._skeleton)
		var min_body_distance: float = INF
		var max_head_height: float = -INF
		var swims: int = 0
		for frame in hz * 7:
			var t: float = float(frame)/hz
			if t >= 1.0 and t < 3.0 or t >= 4.0 and t < 5.0: Input.action_press("move_forward")
			else: Input.action_release("move_forward")
			player.camera.rotation.x = -1.3 if t >= 2.0 and t < 4.0 else 0.0
			await physics_frame
			player._physics_process(1.0/hz)
			avatar._process(1.0/hz)
			if player._swimming: swims += 1
			if player.camera.position.distance_to(Vector3(0,1.6,0)) > 0.001:
				report.errors.append("Camera displaced at %d Hz" % hz)
			max_head_height = maxf(max_head_height, player.to_local(probe.bone_position("Head")).y)
			if frame % 5 == 0:
				var poses: Array[Transform3D] = []
				for bone in avatar._skeleton.get_bone_count(): poses.append(avatar._skeleton.get_bone_global_pose(bone))
				for point in probe._skin_points("body", poses):
					min_body_distance = minf(min_body_distance, point.distance_to(player.camera.global_position))
		if swims < hz * 6: report.errors.append("Swim state was not exercised at %d Hz" % hz)
		if min_body_distance < 0.10: report.errors.append("Body enters the 10 cm eye clearance at %d Hz" % hz)
		if max_head_height > 1.54: report.errors.append("Swim transition raises head above the eye target at %d Hz" % hz)
		report.rates.append({"hz": hz, "swim_frames": swims, "min_sampled_body_distance": min_body_distance, "max_head_height": max_head_height})
		Input.action_release("move_forward")
		player.free()
		water.free()
	report.pass = report.errors.is_empty()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): FileAccess.open(arg.trim_prefix("--out="),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CAMERA_CLEARANCE ",JSON.stringify(report))
	quit(0 if report.pass else 1)
