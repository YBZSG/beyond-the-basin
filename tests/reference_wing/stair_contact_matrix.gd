extends SceneTree
## Isolated regression fixtures; all adaptation stays in the test-only subclass.
const Player = preload("res://tests/reference_wing/stair_contact_player.gd")
var results: Array = []
class DryWater extends Node:
	func is_water_at(_p: Vector3) -> bool: return false
	func depth_at(_p: Vector3) -> float: return 0.0
	func surface_height_at(_p: Vector3) -> float: return -.5

func _initialize() -> void: call_deferred("run")

func box(host: Node3D, title: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = title
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.position = center
	body.add_child(collision)
	host.add_child(body)

func fixture(mode: String, hz: int, kind: String) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var host := Node3D.new()
	root.add_child(host)
	box(host, "BaseFloor", Vector3(0, -.2, 0), Vector3(10, .4, 8))
	var height := .18
	if kind == "max_step": height = .32
	if kind == "too_high": height = .45
	box(host, "Step", Vector3(1.5, height * .5, 0), Vector3(3, height, 3))
	if kind == "low_ceiling": box(host, "Ceiling", Vector3(1, 1.82, 0), Vector3(6, .2, 4))
	var water := DryWater.new()
	host.add_child(water)
	var player := Player.new()
	host.add_child(player)
	player.mode = mode
	player.set_water(water)
	var start := Vector3(-1.5, .002, 0)
	var target := Vector3(1.5, 0, 0)
	if kind == "diagonal":
		start.z = -.65
		target.z = .65
	if kind == "edge":
		start.z = 1.65
		target.z = 1.65
	if kind == "reverse":
		start = Vector3(1.5, height + .002, 0)
		target = Vector3(-1.5, 0, 0)
	player.warp_to(start, target + Vector3.UP * 1.6)
	player.set_enabled(true)
	await physics_frame
	await physics_frame
	var lowest := player.position.y
	var highest := player.position.y
	var stopped_drift := 0.0
	var stop_done := false
	Input.action_press("move_forward")
	var ticks := 0
	for i in hz * 5:
		var direction := target - player.position
		if kind == "edge": direction.z = 0.0
		player.rotation.y = atan2(-direction.x, -direction.z)
		await physics_frame
		lowest = minf(lowest, player.position.y)
		highest = maxf(highest, player.position.y)
		ticks += 1
		if kind == "stop_restart" and player.position.x > -.6 and not stop_done:
			Input.action_release("move_forward")
			for j in ceili(hz * .5): await physics_frame
			var stopped := player.position
			for j in ceili(hz * .5): await physics_frame
			stopped_drift = Vector2(player.position.x - stopped.x, player.position.z - stopped.z).length()
			stop_done = true
			Input.action_press("move_forward")
		if Vector2(player.position.x - target.x, player.position.z - target.z).length() < .16 or (kind == "edge" and player.position.x > 1.35): break
	Input.action_release("move_forward")
	var reached := Vector2(player.position.x - target.x, player.position.z - target.z).length() < .16 or (kind == "edge" and player.position.x > 1.35)
	var passed := false
	if kind in ["too_high", "low_ceiling"]:
		passed = not reached and player.accepted == 0 and highest < .05 and player.position.x < 0
	elif kind == "edge":
		passed = player.accepted == 0 and highest < .05
	else:
		passed = reached and lowest > -.02
		if kind == "reverse": passed = passed and player.position.y < .02
		if kind == "stop_restart": passed = passed and stopped_drift < .001
	for event: Dictionary in player.step_events:
		if float(event.rise) > .32501 or not event.grounded: passed = false
	var result := {"mode": mode, "hz": hz, "fixture": kind, "passed": passed, "reached": reached, "position": player.vector(player.position), "lowest": lowest, "highest": highest, "accepted": player.accepted, "recovery_steps": player.recovery_steps, "steps": player.step_events, "stopped_drift": stopped_drift, "ticks": ticks}
	host.queue_free()
	await process_frame
	return result

func run() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "interact", "throw", "drop"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for mode: String in ["baseline", "fallback"]:
		for hz: int in [15, 60, 120]:
			for kind: String in ["ordinary", "max_step", "too_high", "low_ceiling", "edge", "reverse", "diagonal", "stop_restart"]:
				var result: Dictionary = await fixture(mode, hz, kind)
				results.append(result)
				print("STAIR_MATRIX ", JSON.stringify(result))
	var failures := 0
	for result: Dictionary in results:
		if not result.passed: failures += 1
	var file := FileAccess.open("/tmp/poolcore-reference-contact/output/matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": results, "failures": failures}, "\t"))
	file.close()
	print("STAIR_MATRIX_DONE cases=", results.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)
