extends Node3D
## Resident-only progressive gate controls. No retirement/water/story entry points.
const Safety = preload("./resident_collision_sampler.gd")
var player: CharacterBody3D
var gates: Dictionary = {}
var playable := false
var _down := false
var _dirty := true
var _objects_cache: Array[CollisionObject3D] = []
var _known_static: Dictionary = {}
var _sampler := Safety.new()
var _commands: Dictionary = {}
var _last_open_goal: Dictionary = {}
var _leaf_records: Dictionary = {}
var last_result: Dictionary = {}
var sweep_measurements: Array = []
var inventory_scans := 0
var _static_records: Array = []
var _static_changed := false
var max_static_audit_usec := 0

func install(actual_player: CharacterBody3D, actual_gates: Dictionary) -> void:
	player = actual_player
	gates = actual_gates
	get_tree().node_added.connect(_tree_changed)
	get_tree().node_removed.connect(_tree_changed)
	_scan(true)
	_capture_static()
	for id: String in gates:
		_last_open_goal[id] = not is_zero_approx(gates[id].angle)
		_leaf_records[gates[id].get_instance_id()] = {"owners":gates[id].body.get_shape_owners(),"shape":gates[id].leaf_shape.shape,"node":gates[id].leaf_shape.get_instance_id()}

func _tree_changed(_node: Node) -> void: _dirty = true

func _scan(initial := false) -> void:
	_objects_cache = _sampler._objects(get_tree().root)
	inventory_scans += 1
	if initial:
		for object: CollisionObject3D in _objects_cache:
			if object is StaticBody3D: _known_static[object.get_instance_id()] = true
	_dirty = false

func _static_resource_changed() -> void: _static_changed = true

func _capture_static() -> void:
	for object: CollisionObject3D in _objects_cache:
		if not object is StaticBody3D: continue
		if object in [gates["hanging_hand"].body,gates["aquarium_atrium"].body]: continue
		var record := {"body":object,"id":object.get_instance_id(),"rid":object.get_rid(),"transform":object.global_transform,"layer":object.collision_layer,"mask":object.collision_mask,"owners":[]}
		for owner_id: int in object.get_shape_owners():
			var row := {"id":owner_id,"transform":object.shape_owner_get_transform(owner_id),"disabled":object.is_shape_owner_disabled(owner_id),"shapes":[]}
			for index in object.shape_owner_get_shape_count(owner_id):
				var shape: Shape3D = object.shape_owner_get_shape(owner_id,index)
				row.shapes.append(shape)
				if not shape.changed.is_connected(_static_resource_changed): shape.changed.connect(_static_resource_changed)
			record.owners.append(row)
		_static_records.append(record)

func _static_audit() -> String:
	var started := Time.get_ticks_usec()
	for record: Dictionary in _static_records:
		var reference: Variant = record.body
		if not is_instance_valid(reference): return "static_body_freed"
		var object: CollisionObject3D = reference
		if object.get_instance_id()!=record.id or object.get_rid()!=record.rid or object.global_transform!=record.transform or object.collision_layer!=record.layer or object.collision_mask!=record.mask: return "static_body_changed"
		if object.get_shape_owners().size()!=record.owners.size(): return "static_shape_owners_changed"
		for row: Dictionary in record.owners:
			if row.id not in object.get_shape_owners(): return "static_owner_replaced"
			if object.shape_owner_get_transform(row.id)!=row.transform or object.is_shape_owner_disabled(row.id)!=row.disabled or object.shape_owner_get_shape_count(row.id)!=row.shapes.size(): return "static_owner_changed"
			for index in row.shapes.size():
				if object.shape_owner_get_shape(row.id,index)!=row.shapes[index]: return "static_shape_replaced"
	if _static_changed: return "static_shape_resource_changed"
	max_static_audit_usec = maxi(max_static_audit_usec,Time.get_ticks_usec()-started)
	return ""

func set_playable(value: bool) -> void:
	playable = value
	if not value:
		_down = false
		_commands.clear()
		for id: String in gates:
			if is_instance_valid(gates[id]) and gates[id].state in ["OPENING","CLOSING"]: gates[id].state = "STOPPED"

func target(camera: Camera3D) -> String:
	if not playable or not is_instance_valid(camera) or not is_instance_valid(player): return ""
	if is_instance_valid(player.held) or is_instance_valid(player.climbing): return ""
	var nearest := 2.2
	var result := ""
	for id: String in gates:
		var gate = gates[id]
		if not is_instance_valid(gate) or not is_instance_valid(gate.body) or not gate.body.is_inside_tree(): continue
		for side in [-1.0,1.0]:
			var point: Vector3 = gate.body.to_global(Vector3(side*.092,1.10,1.98))
			var offset: Vector3 = point-camera.global_position
			var distance := offset.length()
			if distance < .05 or distance > nearest: continue
			if (-camera.global_basis.z).normalized().dot(offset/distance) < .965925826: continue
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position,point,0xffffffff,[player.get_rid()])
			ray.hit_from_inside = true
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
			nearest = distance
			result = id
	return result

func handle_event(event: InputEvent, camera: Camera3D) -> bool:
	if event.is_action_released("interact"):
		_down = false
		return false
	if not playable or not event.is_action_pressed("interact"): return false
	if event is InputEventKey and event.echo: return false
	var id := target(camera)
	if id.is_empty(): return false
	if not _down:
		_down = true
		_commands[id] = not bool(_last_open_goal[id])
	return true

func _integrity(gate: Node3D) -> String:
	if not is_instance_valid(gate.body) or not is_instance_valid(gate.hinge) or not is_instance_valid(gate.leaf_shape): return "gate_part_missing"
	if not gate.is_inside_tree() or not gate.hinge.is_inside_tree() or not gate.body.is_inside_tree() or not gate.leaf_shape.is_inside_tree(): return "gate_part_detached"
	if gate.hinge.get_parent()!=gate or gate.body.get_parent()!=gate.hinge or gate.leaf_shape.get_parent()!=gate.body: return "gate_parent_chain_changed"
	if not global_transform.is_equal_approx(Transform3D.IDENTITY): return "controller_transform_changed"
	if not gate.transform.is_equal_approx(gate._authored_transform): return "gate_transform_changed"
	if not gate.body.transform.is_equal_approx(Transform3D.IDENTITY): return "leaf_body_transform_changed"
	if not gate.leaf_shape.shape is BoxShape3D or gate.leaf_shape.shape.size != gate.LEAF_SIZE: return "leaf_shape_changed"
	if not _leaf_records.has(gate.get_instance_id()): return "unknown_gate"
	var record: Dictionary = _leaf_records[gate.get_instance_id()]
	if gate.leaf_shape.get_instance_id()!=record.node or gate.leaf_shape.shape!=record.shape: return "leaf_shape_identity_changed"
	if not gate.leaf_shape.transform.is_equal_approx(Transform3D(Basis.IDENTITY,gate.LEAF_CENTER)): return "leaf_shape_transform_changed"
	if gate.body.get_shape_owners()!=record.owners or record.owners.size()!=1: return "leaf_shape_owner_inventory_changed"
	var owner_id: int = record.owners[0]
	if gate.body.shape_owner_get_shape_count(owner_id)!=1 or gate.body.shape_owner_get_shape(owner_id,0)!=record.shape: return "leaf_shape_count_or_identity_changed"
	if not gate.body.shape_owner_get_transform(owner_id).is_equal_approx(gate.leaf_shape.transform) or gate.body.is_shape_owner_disabled(owner_id): return "leaf_owner_transform_or_disabled_changed"
	if gate.leaf_shape.position != gate.LEAF_CENTER or gate.leaf_shape.disabled or gate.body.collision_layer != 1: return "leaf_collision_changed"
	if not gate.hinge.transform.is_equal_approx(Transform3D(Basis(Vector3.UP,gate.angle),Vector3.ZERO)): return "hinge_transform_changed"
	if is_instance_valid(player.held): return "held_object"
	if is_instance_valid(player.climbing): return "climbing"
	return ""

func sweep(gate: Node3D, next_angle: float) -> Dictionary:
	var points := PackedVector3Array()
	var radius := 0.0
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			for z in [-1.0,1.0]:
				var point: Vector3 = gate.LEAF_CENTER+gate.LEAF_SIZE*Vector3(x,y,z)*.5
				radius = maxf(radius,Vector2(point.x,point.z).length())
				for angle in [gate.angle,next_angle]: points.append(Basis(Vector3.UP,angle)*point)
	var delta_angle: float = absf(next_angle-gate.angle)
	var margin: float = radius*(1.0-cos(delta_angle*.5))+.001
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var bounds := AABB(points[0],Vector3.ZERO)
	for point: Vector3 in points: bounds = bounds.expand(point)
	return {"shape":shape,"margin":margin,"bounds":gate.global_transform*bounds.grow(margin),"radius":radius,"delta_angle":delta_angle}

func _obstruction(gate: Node3D, next_angle: float) -> String:
	var reason := _integrity(gate)
	if not reason.is_empty(): return reason
	if _dirty: _scan()
	reason = _static_audit()
	if not reason.is_empty(): return reason
	var sample := sweep(gate,next_angle)
	for object: CollisionObject3D in _objects_cache:
		if not is_instance_valid(object): return "stale_collision_inventory"
		if object.get_world_3d() != get_world_3d(): continue
		if object is StaticBody3D and _known_static.has(object.get_instance_id()): continue
		if object != player and not object is RigidBody3D: return "unknown_collision_object"
		var occupant: Dictionary = _sampler._body_bounds(object,get_physics_process_delta_time())
		if not occupant.ok: return str(occupant.reason)
		# Conservative supplement includes disabled/layer-zero bodies and two-frame motion.
		if occupant.bounds.intersects(sample.bounds): return "predicted_player_or_rigid_occupancy"
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sample.shape
	query.transform = gate.global_transform
	query.margin = sample.margin
	query.exclude = [gate.body.get_rid()]
	query.collision_mask = 0xffffffff
	query.collide_with_areas = true
	if not get_world_3d().direct_space_state.intersect_shape(query,64).is_empty(): return "actual_convex_sweep_occupancy"
	if sweep_measurements.size() < 256: sweep_measurements.append({"angle":gate.angle,"next":next_angle,"arc_margin":sample.margin,"radius":sample.radius})
	return ""

func _physics_process(delta: float) -> void:
	if not playable: return
	if not is_instance_valid(player):
		set_playable(false)
		last_result = {"accepted":false,"reason":"player_missing"}
		return
	for id: String in gates:
		if not is_instance_valid(gates[id]):
			set_playable(false)
			last_result = {"accepted":false,"reason":"gate_missing"}
			return
	if not is_finite(delta) or delta <= 0.0 or delta > .05:
		set_playable(false)
		last_result = {"accepted":false,"reason":"invalid_or_long_physics_step"}
		return
	for id: String in _commands:
		var open: bool = _commands[id]
		_last_open_goal[id] = open
		gates[id].request(open)
	_commands.clear()
	for id: String in gates:
		var gate = gates[id]
		if gate.state not in ["OPENING","CLOSING"]: continue
		var next_angle: float = move_toward(gate.angle,gate.goal,gate.ANGULAR_SPEED*delta)
		var reason := _obstruction(gate,next_angle)
		if not reason.is_empty():
			gate.state = "STOPPED"
			last_result = {"accepted":false,"reason":reason,"door":id,"angle":gate.angle,"auto_resume":false}
			continue
		gate.advance(delta,"")
		last_result = {"accepted":true,"door":id,"angle":gate.angle,"state":gate.state}

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_tree_changed): get_tree().node_added.disconnect(_tree_changed)
	if get_tree().node_removed.is_connected(_tree_changed): get_tree().node_removed.disconnect(_tree_changed)
	_sampler = null
