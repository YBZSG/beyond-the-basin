extends "res://scripts/world/pool_world.gd"
## Finite complete-room wing. Ordinary source generator/cache identity untouched.
const ReferenceCatalog=preload("res://scripts/reference_wing/reference_catalog.gd")
const ReferenceBuilder=preload("res://scripts/reference_wing/reference_room_builder.gd")

func get_layout(coord: Vector2i) -> Dictionary:
	if not _layouts.has(coord):_layouts[coord]=ReferenceCatalog.room_layout(coord,seed_value)
	return _layouts[coord]

func _request_stream(_center: Vector2i) -> void:
	_desired.clear();_queue.clear()
	for coord: Vector2i in ReferenceCatalog.COORDS:
		_desired[coord]=true
		if not resident_rooms.has(coord):_create_shell(coord)
		if not is_room_ready(coord):_queue.append(coord)

func _create_shell(coord: Vector2i) -> void:
	var started:=Time.get_ticks_usec()
	var room:=Node3D.new();room.name="Reference_"+ReferenceCatalog.IDS[ReferenceCatalog.COORDS.find(coord)]
	room.position=Vector3(coord.x*ROOM,0,coord.y*ROOM)
	room.set_meta("coord",coord);room.set_meta("complete",false);room.set_meta("far",false)
	add_child(room);resident_rooms[coord]=room
	var layout:=get_layout(coord);layout["far"]=false
	room.set_meta("layout",layout);room.set_meta("variant",layout.variant)
	var builder:=ReferenceBuilder.new(room,layout,material_library)
	_builders[coord]=builder;builder.build_shell()
	profile_counters.shell_builds+=1
	profile_counters.last_shell_ms=float(Time.get_ticks_usec()-started)/1000.0

func get_spawn_position(coord: Vector2i = Vector2i.ZERO) -> Vector3:
	if coord not in ReferenceCatalog.COORDS:coord=ReferenceCatalog.COORDS[0]
	ensure_room_ready(coord)
	return get_layout(coord).spawn_local+Vector3(coord.x*ROOM,0,coord.y*ROOM)

func update_player_position(position: Vector3) -> void:
	if get_room_coord(position) not in ReferenceCatalog.COORDS:return
	super.update_player_position(position)
