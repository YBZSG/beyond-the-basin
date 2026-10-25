extends Node3D
## All authored balls remain selectable; only a bounded nearby set is simulated.
## Resting balls share two render batches and spatially grouped static colliders.
const Prop = preload("res://scripts/reference_wing/lounge_prop.gd")
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const MAX_ACTIVE_BALLS := 64
const STATIC_BALL_LAYER := 8
var player: CharacterBody3D
var water: Node
var entries: Array[Dictionary] = []
var batches: Dictionary = {}
var active: Dictionary = {}
var cushions: Array[RigidBody3D] = []
var sphere: SphereMesh
var _elapsed := 0.0
var _running := false

func configure(room: Node3D, layout: Dictionary, view_player: CharacterBody3D, water_node: Node) -> void:
	player = view_player; water = water_node
	name = "LoungeInteractions"
	room.add_child(self)
	player.lounge_interactions = self
	sphere = SphereMesh.new(); sphere.radius = 1.0; sphere.height = 2.0
	sphere.radial_segments = 12; sphere.rings = 7
	var architecture: Node = room.get_node("ReferenceAuthoredArchitecture")
	var data: Array = layout.geometry_contract.ball_instances
	for role: String in ["ref_ball_blue", "ref_ball_ivory"]:
		var original := architecture.find_child("Static_ball_batch_" + role, true, false) as MeshInstance3D
		var mesh := MultiMesh.new(); mesh.transform_format = MultiMesh.TRANSFORM_3D; mesh.mesh = sphere
		mesh.instance_count = data.size(); mesh.visible_instance_count = 0
		var visual := MultiMeshInstance3D.new(); visual.multimesh = mesh
		visual.material_override = original.get_active_material(0); visual.name = "Resting_" + role
		add_child(visual)
		batches[role] = {"mesh":mesh, "indices":[], "material":visual.material_override}
		original.hide(); original.set_meta("source_exclude_optics", true)
	var cells: Dictionary = {}
	for item: Dictionary in data:
		var center := Catalog.vec3(item.center)
		var cell := Vector2i(floori(center.x), floori(center.z))
		if not cells.has(cell):
			# Frozen compound cells behave as static supports. The source-water
			# snapshot already excludes rigid props, so this dry fill is not baked
			# into the terrain cache every time a ball is moved.
			var body := RigidBody3D.new(); body.freeze = true
			body.collision_layer = STATIC_BALL_LAYER; body.collision_mask = 0
			add_child(body); cells[cell] = body
		var collider := CollisionShape3D.new(); var shape := SphereShape3D.new(); shape.radius = float(item.radius)
		collider.shape = shape; collider.position = center; collider.set_meta("lounge_ball", entries.size())
		cells[cell].add_child(collider)
		entries.append({"position":center,"radius":float(item.radius),"role":str(item.material),"collider":collider,"slot":-1})
		_show_static(entries.size()-1)
	for contact: Dictionary in layout.geometry_contract.support_contacts:
		if "coral_cushion" not in str(contact.object): continue
		var visual := architecture.find_child(str(contact.object), true, false) as MeshInstance3D
		if visual == null: continue
		var center := visual.get_aabb().get_center()
		var size := visual.get_aabb().size
		var body := _body("cushion", center, minf(maxf(size.x,size.z)*0.5,0.6), 1.2)
		body.soft = true; body.display_name = "珊瑚色软垫"
		var collision := body.get_child(0) as CollisionShape3D
		collision.shape = visual.mesh.create_convex_shape(true, true); collision.position = -center
		visual.reparent(body, false); visual.position = -center
		var piping := architecture.find_child(str(contact.object)+"_attached_fabric_piping", true, false) as Node3D
		if piping != null: piping.reparent(body, false); piping.position = -center
		cushions.append(body)
	process_physics_priority = -10

func _body(kind: String, center: Vector3, radius: float, mass: float) -> RigidBody3D:
	var body := Prop.new()
	body.configure(kind, {"radius":radius,"mass":mass,"name":"球池小球","float_bias":0.02}, water)
	body.collision_mask |= STATIC_BALL_LAYER
	body.can_sleep = true; body.freeze = true
	body._physics_material.friction = 0.65
	body._physics_material.bounce = 0.38
	body.position = center
	add_child(body)
	return body

func _show_static(index: int) -> void:
	var entry: Dictionary = entries[index]; var batch: Dictionary = batches[entry.role]
	entry.slot = batch.indices.size(); batch.indices.append(index)
	batch.mesh.set_instance_transform(entry.slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*entry.radius),entry.position))
	batch.mesh.visible_instance_count = batch.indices.size()
	entry.collider.position = entry.position; entry.collider.disabled = false

func _hide_static(index: int) -> void:
	var entry: Dictionary = entries[index]; var batch: Dictionary = batches[entry.role]
	var last: int = batch.indices.back(); var slot: int = entry.slot
	batch.indices[slot] = last; entries[last].slot = slot
	batch.mesh.set_instance_transform(slot, batch.mesh.get_instance_transform(batch.indices.size()-1))
	batch.indices.pop_back(); batch.mesh.visible_instance_count = batch.indices.size()
	entry.slot = -1; entry.collider.disabled = true

func _retire(index: int) -> void:
	var body: RigidBody3D = active[index]
	entries[index].position = body.position
	active.erase(index)
	body.collision_layer = 0; body.collision_mask = 0; body.freeze = true
	body.queue_free()
	_show_static(index)

func activate(index: int, simulate: bool = false) -> RigidBody3D:
	if active.has(index):
		if simulate: active[index].wake()
		return active[index]
	if active.size() >= MAX_ACTIVE_BALLS:
		for previous: int in active.keys():
			var candidate: RigidBody3D = active[previous]
			if not candidate.held and (not candidate.simulating or candidate.sleeping) and candidate.global_position.distance_to(player.global_position)>1.4:
				_retire(previous); break
		if active.size() >= MAX_ACTIVE_BALLS: return null
	var entry: Dictionary = entries[index]
	_hide_static(index)
	var body := _body("ball", entry.position, entry.radius, 0.16)
	var visual := MeshInstance3D.new(); visual.mesh = sphere
	visual.scale = Vector3.ONE * entry.radius; visual.material_override = batches[entry.role].material
	body.add_child(visual); active[index] = body
	if simulate: body.wake()
	return body

func pick_prop(camera: Camera3D, exclude: RID, distance: float) -> RigidBody3D:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*distance,1|2|STATIC_BALL_LAYER,[exclude])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return null
	var body: CollisionObject3D = hit.collider
	if body is RigidBody3D and body.is_in_group("pool_interactable"): return body
	var owner: Object = body.shape_owner_get_owner(body.shape_find_owner(hit.shape))
	if owner is Node and owner.has_meta("lounge_ball"): return activate(int(owner.get_meta("lounge_ball")))
	return null

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player): return
	var running: bool = player.enabled
	if running != _running:
		_running = running
		for body: RigidBody3D in active.values()+cushions: body.freeze = not running or not body.simulating
	if not running: return
	_elapsed += delta
	if _elapsed < 0.12: return
	_elapsed = 0.0
	for index: int in active.keys():
		var body: RigidBody3D = active[index]
		if not body.held and (body.sleeping or not body.simulating) and body.global_position.distance_to(player.global_position)>4.0: _retire(index)
	if Vector2(player.velocity.x,player.velocity.z).length()<0.12: return
	var feet := to_local(player.global_position)
	var kicked := 0
	for index in entries.size():
		if active.has(index): continue
		var point: Vector3 = entries[index].position
		var offset := Vector2(point.x-feet.x,point.z-feet.z)
		if offset.length_squared()>0.55*0.55 or point.y<feet.y-0.2 or point.y>feet.y+0.95: continue
		var body := activate(index,true)
		if body == null: break
		body.apply_central_impulse(Vector3(offset.x,0.08,offset.y).normalized()*0.12)
		kicked += 1
		if kicked >= 10: break
	for body: RigidBody3D in cushions:
		if body.global_position.distance_to(player.global_position+Vector3.UP*0.4)<1.25 and not body.simulating: body.wake()

func get_stats() -> Dictionary:
	return {"balls":entries.size(),"active_balls":active.size(),"limit":MAX_ACTIVE_BALLS,"cushions":cushions.size(),"resting":entries.size()-active.size()}
