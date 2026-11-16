extends "res://scripts/world/pool_world.gd"
## 32 m collision-first terrain chunks; distant architecture is independent of
## resident water chunks. Source controller, water and terrain collector untouched.
const Dreams = preload("res://scripts/dreamcore/dream_catalog.gd")
const MirrorTiles = preload("res://scripts/dreamcore/dream_mirror_tiles.gd")
var scene_id := "lime_gallery"
var definition: Dictionary = {}
var scene_builder: Script
var finite_coords: Array[Vector2i] = []
var pinned_water_coords: Array[Vector2i] = []
var _interactive_player: CharacterBody3D
var _interactive_playable := false
var _interactive_initialized := false
var _scene_effects: Array[Node] = []
var _effect_values: Dictionary = {}
var _effect_observed: Dictionary = {}
var _effect_reduced := true
var _effect_state_initialized := false
var _effect_audio_enabled := false
func initialize(world_seed: int, materials: RefCounted) -> void:
	release_scene_interactions()
	_scene_effects.clear(); _effect_values.clear(); _effect_observed.clear()
	_effect_state_initialized = false; _effect_reduced = true
	_effect_audio_enabled = false
	finite_coords.clear(); pinned_water_coords.clear()
	var old_horizon := get_node_or_null("PersistentHorizon")
	if old_horizon != null: remove_child(old_horizon); old_horizon.queue_free()
	scene_builder = Dreams.builder(scene_id)
	assert(scene_builder != null, "Dreamcore scene unavailable: " + scene_id)
	definition = scene_builder.definition()
	var bounds: Rect2i = definition.bounds
	for z in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x): finite_coords.append(Vector2i(x,z))
	assert(Vector2i.ZERO in finite_coords)
	assert(not definition.get("retain_full_finite_scene", false) or finite_coords.size() <= 25, "Full-scene retention exceeds the finite 25-chunk budget")
	for coord: Vector2i in finite_coords:
		if not scene_builder.layout(coord).get("water_rects",[]).is_empty(): pinned_water_coords.append(coord)
	assert(pinned_water_coords.size() <= 25, "Authored water footprint exceeds expansion proxy budget")
	var horizon := Node3D.new(); horizon.name = "PersistentHorizon"; add_child(horizon)
	scene_builder.build_horizon(horizon, materials)
	_collect_scene_effects()
	super.initialize(world_seed, materials)
func get_layout(coord: Vector2i) -> Dictionary:
	if not _layouts.has(coord):
		var data := Dreams.base_layout(coord, definition)
		data.merge(scene_builder.layout(coord), true)
		data.coord = coord; data.seed = seed_value
		_layouts[coord] = data
	return _layouts[coord]
func _request_stream(center: Vector2i) -> void:
	_desired.clear(); _queue.clear()
	var candidates: Array[Vector2i] = []
	# An opted-in compact indoor hall must remain visible across its void.
	# Keep the same finite chunk owners (including collision and lights), not
	# duplicated horizon meshes. Other scenes keep radius-based streaming.
	if definition.get("retain_full_finite_scene", false):
		candidates.assign(finite_coords)
	else:
		for z in range(center.y-stream_radius,center.y+stream_radius+1):
			for x in range(center.x-stream_radius,center.x+stream_radius+1):
				var coord := Vector2i(x,z)
				if coord in finite_coords: candidates.append(coord)
	for coord: Vector2i in pinned_water_coords:
		if coord not in candidates: candidates.append(coord)
	candidates.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return (a-center).length_squared() < (b-center).length_squared())
	for coord: Vector2i in candidates:
		_desired[coord] = true
		if not resident_rooms.has(coord): _create_shell(coord)
		if not is_room_ready(coord): _queue.append(coord)
	if _queue.is_empty(): _retire_old_rooms()
func current_room_ready() -> bool:
	if not super.current_room_ready(): return false
	# This is the DreamRuntime loading/resume/playable authority. Shells still
	# build collision-first; details keep their normal incremental queue. Do
	# not release player input while the retained far hall is still missing.
	if definition.get("retain_full_finite_scene", false):
		for coord: Vector2i in finite_coords:
			if not is_room_ready(coord): return false
	return true
func _create_shell(coord: Vector2i) -> void:
	assert(coord in finite_coords)
	var room := Node3D.new(); room.name = "DreamChunk_%d_%d" % [coord.x,coord.y]
	room.position = Vector3(coord.x*ROOM,0,coord.y*ROOM)
	room.set_meta("coord",coord); room.set_meta("complete",false); room.set_meta("far",false)
	add_child(room); resident_rooms[coord] = room
	var data := get_layout(coord)
	room.set_meta("layout",data); room.set_meta("variant",data.variant)
	scene_builder.build_shell(room,data,material_library)
	MirrorTiles.apply(room, data)
	profile_counters.shell_builds += 1
func _finish_room(coord: Vector2i) -> void:
	if is_room_ready(coord): return
	var room: Node3D = resident_rooms[coord]
	scene_builder.build_detail(room,get_layout(coord),material_library)
	MirrorTiles.apply(room, get_layout(coord))
	room.set_meta("complete",true); _queue.erase(coord)
	room_loaded.emit(room,coord,get_layout(coord)); profile_counters.interior_builds += 1
func get_spawn_position(coord: Vector2i = Vector2i.ZERO) -> Vector3:
	if coord not in finite_coords: coord = Vector2i.ZERO
	ensure_room_ready(coord)
	if coord == Vector2i.ZERO: return definition.spawn
	return get_layout(coord).spawn_local + Vector3(coord.x*ROOM,0,coord.y*ROOM)
func update_player_position(point: Vector3) -> void:
	if get_room_coord(point) not in finite_coords: return
	super.update_player_position(point)
func teleport_to_room(coord: Vector2i) -> Vector3:
	if coord not in finite_coords: coord = Vector2i.ZERO
	return super.teleport_to_room(coord)

## Persistent actors belong to this world, never individual streamed chunks.
## Gate them on the coordinator's readiness, not merely on player input.
func set_scene_playable(value: bool, player: CharacterBody3D = null) -> void:
	if _interactive_initialized and value == _interactive_playable and player == _interactive_player: return
	_interactive_initialized = true
	_interactive_playable = value
	_interactive_player = player
	if not is_inside_tree(): return
	for actor: Node in get_tree().get_nodes_in_group("dream_ball_pit"):
		if not is_ancestor_of(actor) or actor.is_queued_for_deletion(): continue
		actor.bind_player(player)
		actor.set_playable(value)
	for actor: Node in _scene_effects:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion():
			actor.set_playable(value and _effect_state_initialized)

## Explicit new-room opt-in. The actor has no main/player/water/save authority;
## it receives primitive, read-only snapshots, never the authoritative State.
func has_scene_effects() -> bool:
	return not _scene_effects.is_empty()
func _collect_scene_effects() -> void:
	_scene_effects.clear()
	if not is_inside_tree(): return
	for actor: Node in get_tree().get_nodes_in_group("dream_scene_effect"):
		if not is_ancestor_of(actor) or actor.is_queued_for_deletion(): continue
		assert(actor.has_method("apply_state") and actor.has_method("set_playable"), "Scene effect must implement the bounded presentation interface")
		_scene_effects.append(actor)
		actor.set_playable(false)
		if actor.has_method("set_audio_enabled"): actor.set_audio_enabled(false)
func set_scene_audio_enabled(value: bool) -> void:
	if _effect_audio_enabled == value: return
	_effect_audio_enabled = value
	for actor: Node in _scene_effects:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.has_method("set_audio_enabled"):
			actor.set_audio_enabled(value)
func apply_scene_state(values: Dictionary, observed: Dictionary, reduced_effects: bool) -> void:
	if _scene_effects.is_empty(): return
	var next_values := _bounded_snapshot(values,true)
	var next_observed := _bounded_snapshot(observed,false)
	if _effect_state_initialized and next_values == _effect_values and next_observed == _effect_observed and reduced_effects == _effect_reduced: return
	_effect_values = next_values; _effect_observed = next_observed; _effect_reduced = reduced_effects
	var first_snapshot := not _effect_state_initialized
	_effect_state_initialized = true
	for actor: Node in _scene_effects:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion(): continue
		var value_copy := _effect_values.duplicate(true)
		var observed_copy := _effect_observed.duplicate(true)
		value_copy.make_read_only(); observed_copy.make_read_only()
		actor.apply_state(value_copy,observed_copy,_effect_reduced)
		# Restored pose precedes activation, including a delayed first snapshot.
		if first_snapshot: actor.set_playable(_interactive_playable)
static func _bounded_snapshot(source: Dictionary, integer_values: bool) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		if result.size() >= 16: break
		if not key is String or key.length() > 80: continue
		var value: Variant = source[key]
		if not (value is int or value is float) or not is_finite(float(value)): continue
		if integer_values:
			if float(value) != floorf(float(value)) or int(value) < 0 or int(value) > 3: continue
			result[key] = int(value)
		else:
			if float(value) < 0.0 or float(value) > 3600.0: continue
			result[key] = float(value)
	return result
func release_scene_interactions() -> void:
	# Called before old player/world retirement and before horizon replacement.
	set_scene_audio_enabled(false)
	_interactive_initialized = false
	set_scene_playable(false,null)
	_interactive_initialized = false
func _exit_tree() -> void:
	release_scene_interactions()
