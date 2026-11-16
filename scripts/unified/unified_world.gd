extends "res://scripts/world/pool_world.gd"
## Opt-in continuous two-hall prototype, not the final fifteen-region streamer.
const Composite = preload("res://scripts/unified/composite_builder.gd")
var composite := Composite.new()
var definition: Dictionary = Composite.definition()
var finite_coords: Array[Vector2i] = []
var pinned_water_coords: Array[Vector2i] = []

func initialize(world_seed: int, materials: RefCounted) -> void:
	finite_coords.clear()
	pinned_water_coords.clear()
	finite_coords.assign(composite.occupied_coords())
	for coord: Vector2i in finite_coords:
		if not composite.layout(coord,world_seed).water_rects.is_empty(): pinned_water_coords.append(coord)
	assert(finite_coords.size() <= 25,"First slice exceeds compact-scene residency budget; implement sector streaming first")
	assert(pinned_water_coords.size() <= 25,"Do not enlarge the source water residency budget")
	super.initialize(world_seed,materials)

func get_layout(coord: Vector2i) -> Dictionary:
	if not _layouts.has(coord): _layouts[coord] = composite.layout(coord,seed_value)
	return _layouts[coord]

func _request_stream(_center: Vector2i) -> void:
	# Finite validation slice: collision-first, then one detailed chunk/frame.
	# This explicitly does NOT claim full-map sector streaming/eviction acceptance.
	_desired.clear()
	_queue.clear()
	for coord: Vector2i in finite_coords:
		_desired[coord] = true
		if not resident_rooms.has(coord): _create_shell(coord)
		if not is_room_ready(coord): _queue.append(coord)

func _create_shell(coord: Vector2i) -> void:
	assert(coord in finite_coords)
	var room := Node3D.new()
	room.name = "UnifiedChunk_%d_%d" % [coord.x,coord.y]
	room.position = Vector3(coord.x*ROOM,0,coord.y*ROOM)
	room.set_meta("coord",coord)
	room.set_meta("complete",false)
	room.set_meta("far",false)
	room.set_meta("variant",3)
	add_child(room)
	resident_rooms[coord] = room
	var data := get_layout(coord)
	room.set_meta("layout",data)
	composite.build_shell(room,data,material_library)
	profile_counters.shell_builds += 1

func _finish_room(coord: Vector2i) -> void:
	if is_room_ready(coord): return
	var room: Node3D = resident_rooms[coord]
	composite.build_detail(room,get_layout(coord),material_library)
	room.set_meta("complete",true)
	_queue.erase(coord)
	# One aggregate room and one publication per global key, even with two owners.
	room_loaded.emit(room,coord,get_layout(coord))
	profile_counters.interior_builds += 1

func current_room_ready() -> bool:
	for coord: Vector2i in finite_coords:
		if not is_room_ready(coord): return false
	return true

func get_spawn_position(_coord: Vector2i = Vector2i.ZERO) -> Vector3:
	ensure_room_ready(get_room_coord(definition.spawn))
	return definition.spawn

func update_player_position(point: Vector3) -> void:
	if get_room_coord(point) not in finite_coords: return
	super.update_player_position(point)

func region_at(point: Vector3) -> String:
	# Region is physical space, not a 32 m chunk label. Thresholds are real sills.
	if point.x >= 32.0 and point.x <= 61.0: return "检修连廊 / MAINTENANCE LINK"
	return "悬手浅池 / HANGING HAND" if point.x < 32.0 else "水族中庭 / AQUARIUM ATRIUM"
