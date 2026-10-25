extends SceneTree
## Exact authored physics only: no GLB, renderer, import pass, or fluid solver.
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const Depth = preload("res://scripts/reference_wing/reference_depth_field.gd")
const Player = preload("res://tests/reference_wing/stair_contact_player.gd")
class StaticWater extends Node:
	var profiles: Array = []
	func depth_at(p: Vector3) -> float:
		for profile: Dictionary in profiles:
			var point := Vector2(p.x, p.z) - Vector2(profile.offset)
			if profile.bounds.grow(.001).has_point(point): return Depth.point_depth(point, profile)
		return 0.0
	func is_water_at(p: Vector3) -> bool: return depth_at(p) > 0
	func surface_height_at(_p: Vector3) -> float: return .32
	func player_impact(_p: Vector3, _power: float) -> void: pass
	func splash(_p: Vector3, _power: float, _direction: Dictionary = {}) -> void: pass
	func wave_impact(_p: Vector3, _power: float) -> void: pass
	func push(_p: Vector3, _impulse: Vector2, _radius: float) -> void: pass
	func wake_dipole(_p: Vector3, _direction: Vector2, _speed: float, _radius: float) -> void: pass
	func crest(_p: Vector3, _power: float) -> void: pass

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var mode := "baseline"
	var route := "full"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--route="): route = arg.trim_prefix("--route=")
		if arg.begins_with("--hz="): Engine.physics_ticks_per_second = int(arg.trim_prefix("--hz="))
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "interact", "throw", "drop"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var host := Node3D.new()
	root.add_child(host)
	var layouts := {}
	var shape_count := 0
	for coord: Vector2i in Catalog.COORDS:
		if route.begins_with("stalled") and coord != Vector2i(0, -2): continue
		var layout := Catalog.room_layout(coord, 250821)
		layouts[coord] = layout
		var body := StaticBody3D.new()
		body.name = layout.reference_id
		body.position = Vector3(coord.x * 32.0, 0.0, coord.y * 32.0)
		body.collision_layer = 1
		body.collision_mask = 0
		host.add_child(body)
		for proxy: Dictionary in layout.geometry_contract.collision_proxies:
			var shape_node := CollisionShape3D.new()
			shape_node.name = proxy.name
			if str(proxy.type) == "BOX":
				var shape := BoxShape3D.new()
				shape.size = Catalog.vec3(proxy.size)
				shape_node.shape = shape
				shape_node.position = Catalog.vec3(proxy.center)
			else:
				var shape := ConvexPolygonShape3D.new()
				var points := PackedVector3Array()
				for value: Array in proxy.vertices: points.append(Catalog.vec3(value))
				shape.points = points
				shape_node.shape = shape
			body.add_child(shape_node)
			shape_count += 1
	var water := StaticWater.new()
	host.add_child(water)
	water.profiles = Depth.profiles(layouts)
	var player := Player.new()
	host.add_child(player)
	player.mode = "baseline" if mode == "late-fallback" else mode
	player.set_water(water)
	player.depth_wading_response_enabled = true
	var start: Vector3 = Catalog.room_layout(Vector2i.ZERO, 250821).spawn_local
	var path := [Vector2(1.4, .2), Vector2(1.4, -4.5), Vector2(0, -16), Vector2(0, -30.8), Vector2(0, -46), Vector2(0, -50), Vector2(0, -73.8), Vector2(5.4, -73.8)]
	if route == "short":
		start = Vector3(-.0888330861926079, -.218033581972122, -73.6736297607422)
		path = [Vector2(5.4, -73.8)]
	elif route == "cyan":
		start = Vector3(.0000000670697772875428, .521217405796051, -49.8457870483398)
		path = [Vector2(0, -73.8), Vector2(5.4, -73.8)]
	elif route in ["stalled", "stalled-seeded"]:
		start = Vector3(.706195294857025, .151229724287987, -73.7639007568359)
		path = [Vector2(5.4, -73.8)]
	player.warp_to(start, Vector3(1.4, 1, -4))
	player.set_enabled(true)
	await physics_frame
	await physics_frame
	if route == "stalled-seeded":
		player.global_position = start
		player._move_velocity = Vector2(1.24995219707489, -.00961399544030428)
		player.velocity = Vector3(1.24995219707489, 0.0, -.00961399544030428)
	var legs := []
	var passed := true
	var recovery_activated := {}
	for target: Vector2 in path:
		var ticks := 0
		var stalled := 0
		var max_ticks := ceili(Vector2(player.position.x, player.position.z).distance_to(target) / .6 * Engine.physics_ticks_per_second) + 180
		Input.action_press("move_forward")
		while Vector2(player.position.x, player.position.z).distance_to(target) > .16 and ticks < max_ticks:
			var direction := target - Vector2(player.position.x, player.position.z)
			player.rotation.y = atan2(-direction.x, -direction.y)
			var before := player.position
			await physics_frame
			stalled = stalled + 1 if player.position.distance_to(before) < .00001 else 0
			ticks += 1
			if stalled > 45:
				if mode == "late-fallback" and recovery_activated.is_empty():
					recovery_activated = {"position": player.vector(player.position), "tick": ticks, "leg": legs.size()}
					player.mode = "fallback"
					stalled = 0
				else: break
			if target.x > 5.3 and player.position.x > 2.4: break
		Input.action_release("move_forward")
		var reached := Vector2(player.position.x, player.position.z).distance_to(target) <= .16 or (target.x > 5.3 and player.position.x > 2.4)
		var leg := {"target": [target.x, target.y], "position": player.vector(player.position), "reached": reached, "ticks": ticks}
		legs.append(leg)
		print("STAIR_CONTACT_LEG ", JSON.stringify(leg))
		if not reached:
			passed = false
			break
	var report := {"mode": mode, "route": route, "passed": passed, "physics_hz": Engine.physics_ticks_per_second, "shapes": shape_count, "recovery_activated": recovery_activated, "legs": legs, "accepted": player.accepted, "recovery_steps": player.recovery_steps, "steps": player.step_events, "samples": player.samples}
	var file := FileAccess.open("/tmp/poolcore-reference-contact/output/" + route + "-" + mode + "-" + str(Engine.physics_ticks_per_second) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("STAIR_CONTACT_DONE ", route, " ", mode, " passed=", passed)
	host.queue_free()
	await process_frame
	quit(0 if passed else 1)
