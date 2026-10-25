extends "res://scripts/world/pool_world.gd"
## Campaign-only finite regions. Legacy worlds and their random stream are untouched.
const CampaignCatalog = preload("res://scripts/campaign/campaign_catalog.gd")
const ReferenceCatalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const ReferenceBuilder = preload("res://scripts/reference_wing/reference_room_builder.gd")
const Expanded = preload("res://scripts/world/expanded_room_catalog.gd")
const CampaignBuilder = preload("res://scripts/campaign/campaign_room_builder.gd")
var chapter_index := 0
var chapter: Dictionary = {}
var finite_coords: Array[Vector2i] = []

func initialize(world_seed: int, materials: RefCounted) -> void:
	chapter = CampaignCatalog.chapter(chapter_index, world_seed)
	finite_coords.clear()
	for spec: Dictionary in chapter.room_specs: finite_coords.append(spec.coord)
	if chapter.mode == "original" and chapter.id != "quiet_archive":
		var minimum := finite_coords[0]; var maximum := finite_coords[0]
		for coord: Vector2i in finite_coords:
			minimum = Vector2i(mini(minimum.x, coord.x), mini(minimum.y, coord.y))
			maximum = Vector2i(maxi(maximum.x, coord.x), maxi(maximum.y, coord.y))
		for z in range(minimum.y, maximum.y+1):
			for x in range(minimum.x, maximum.x+1):
				if Vector2i(x,z) not in finite_coords: finite_coords.append(Vector2i(x,z))
	super.initialize(world_seed, materials)

func get_layout(coord: Vector2i) -> Dictionary:
	if _layouts.has(coord): return _layouts[coord]
	var result: Dictionary
	if chapter.mode == "reference": result = ReferenceCatalog.room_layout(coord, seed_value)
	elif chapter.mode == "formal": result = Formal.layout(coord, seed_value)
	elif chapter.mode == "poolrooms": result = PoolroomsWing.room_layout(coord, seed_value)
	elif chapter.mode == "expanded": result = Expanded.room_layout(coord, seed_value, Expanded.ANCHORS[coord])
	elif chapter.id == "quiet_archive":
		var index := finite_coords.find(coord)
		result = Catalog.ATMOSPHERES[8+index].duplicate(true)
		result.merge({"coord":coord,"seed":seed_value,"variant":8+index,"tint":0.0,"ducks":2,"corrupt":0})
	else: result = Catalog.room_layout(coord, seed_value)
	result["campaign_region"] = str(chapter.id)
	_layouts[coord] = result
	return result

func _request_stream(_center: Vector2i) -> void:
	_desired.clear(); _queue.clear()
	for coord: Vector2i in finite_coords:
		_desired[coord] = true
		if not resident_rooms.has(coord): _create_shell(coord)
		if not is_room_ready(coord): _queue.append(coord)

func _create_shell(coord: Vector2i) -> void:
	var room := Node3D.new()
	room.name = "CampaignRoom_%d_%d" % [coord.x, coord.y]
	room.position = Vector3(coord.x*ROOM,0,coord.y*ROOM)
	room.set_meta("coord",coord); room.set_meta("complete",false); room.set_meta("far",false)
	add_child(room); resident_rooms[coord] = room
	var layout := get_layout(coord)
	layout["far"] = false
	room.set_meta("layout",layout); room.set_meta("variant",layout.variant)
	var builder: RefCounted
	if chapter.mode == "reference": builder = ReferenceBuilder.new(room, layout, material_library)
	elif chapter.mode == "formal": builder = FormalBuilder.new(room, layout, material_library)
	else:
		builder = CampaignBuilder.new(room, layout, material_library)
		builder.campaign_world = self
	_builders[coord] = builder
	builder.build_shell()
	if chapter.mode not in ["formal","reference"]: _seal_perimeter(room,coord,layout)
	profile_counters.shell_builds += 1

func _seal_perimeter(room: Node3D, coord: Vector2i, layout: Dictionary) -> void:
	# Source rooms own only N/W walls. A finite region needs explicit E/S closure.
	# Place backing beyond original exterior faces: no coplanar visible duplicate.
	var floor_y := -.82
	var ceiling_y := float(layout.ceiling)+.5
	for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		if coord+direction in finite_coords: continue
		var size := Vector3(.4,ceiling_y-floor_y,32.8) if direction.x else Vector3(32.8,ceiling_y-floor_y,.4)
		var center := Vector3(direction.x*16.1,(floor_y+ceiling_y)*.5,direction.y*16.1)
		var solid := StaticBody3D.new(); solid.name = "OpaquePerimeter"; solid.collision_layer=1;solid.collision_mask=0
		var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size=size
		mesh.mesh=box;mesh.material_override=material_library.get_material("pale");mesh.gi_mode=GeometryInstance3D.GI_MODE_STATIC
		var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape
		solid.position=center; solid.add_child(mesh);solid.add_child(collision);room.add_child(solid)
		layout.get_or_add("campaign_backing_solids",[]).append(AABB(center-size*.5,size))

func get_spawn_position(coord: Vector2i = Vector2i.ZERO) -> Vector3:
	if coord not in finite_coords: coord = finite_coords[0]
	ensure_room_ready(coord)
	if chapter.mode == "reference": return get_layout(coord).spawn_local + Vector3(coord.x*ROOM,0,coord.y*ROOM)
	if chapter.mode == "formal": return Formal.spawn(coord)
	return super.get_spawn_position(coord)

func update_player_position(point: Vector3) -> void:
	if get_room_coord(point) not in finite_coords: return
	super.update_player_position(point)
