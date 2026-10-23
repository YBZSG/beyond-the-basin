class_name FacilityDevicesCandidate
extends Node3D
## Optional quiet authored-bath activity, enabled by the PC menu setting.
## No _input/_unhandled_input, autoload, process loop or original-room changes.
## Keep this owner above streamed rooms. Call advance once per physics frame.
## Source water owns all simulation; this code only admits weak push_wake inputs.

signal valve_changed(station_key: String, opened: bool)

const SOURCE_RUNTIME := "res://scripts/water/source_water_runtime.gd"
const VALVE_ASSET := "res://assets/models/facility_devices/pool_return_valve.glb"
const RETURN_ASSET := "res://assets/models/facility_devices/pool_return_fitting.glb"
const REACH := 2.1
const AIM_RADIUS := 0.15
const DEBOUNCE_SECONDS := 0.30
const PULSE_INTERVAL := 0.50
const PULSE_IMPULSE := 0.0015
const PULSE_SIGMA := 0.16
const SOURCE_SUPPORT := PULSE_SIGMA * 4.0 # Actual SWE shader truncates at +/-4 sigma.
const QUIET_PEAK_LIMIT := 0.006
const QUIET_FLOW_LIMIT := 0.04
const MIN_DEPTH := 0.20
const ROOM_SIZE := 32.0
const WATER_LEVEL := 0.32

var enabled := false
var _world_key := ""
var _world_seed := 0
var _clock := 0.0
var _next_emission := 0.0
var _rooms: Dictionary = {}
var _stations: Dictionary = {}
var _states: Dictionary = {}
var _source_water: WeakRef
var _asset_cache: Dictionary = {}
var _counts := {"toggles": 0, "debounced": 0, "pulses": 0, "blocked_water": 0}

## These are deliberately NOT a new catalog entry or changes to existing assets.
## Sidepool stair is north; bath stairs/doorways are south/east. Both new control
## stations are on existing solid perimeter walls, clear of those circulation axes.
static func station_spec(coord: Vector2i) -> Dictionary:
	if coord == Vector2i(-1, 0):
		return {"id": "east_return", "coord": coord,
			"geometry": "res://assets/models/formal/formal_sidepool.glb",
			"control": Vector3(6.8245, 1.70, 1.8), "normal": Vector3.LEFT,
			"return": Vector3(3.9195, -0.05, 1.8), "nozzle": Vector3(3.18, WATER_LEVEL, 1.8),
			"direction": Vector2.LEFT, "yaw": -PI * 0.5, "region": "sidepool"}
	if coord == Vector2i(-1, -2):
		return {"id": "north_return", "coord": coord,
			"geometry": "res://assets/models/formal/formal_bath.glb",
			"control": Vector3(0, 1.70, -8.7995), "normal": Vector3.BACK,
			"return": Vector3(0, -0.05, -4.7995), "nozzle": Vector3(0, WATER_LEVEL, -3.95),
			"direction": Vector2.DOWN, "yaw": 0.0, "region": "bath"}
	return {}

static func station_key(coord: Vector2i, station_id: String) -> String:
	return "%d,%d/%s" % [coord.x, coord.y, station_id]

## Explicitly call on every seed/world-mode change. A new session key permits
## resetting even when the same seed is regenerated. Normal room unload does not.
func configure_world(world_key: String, seed_value: int, opt_in: bool = false) -> void:
	if world_key != _world_key or seed_value != _world_seed:
		clear()
		_world_key = world_key
		_world_seed = seed_value
	set_enabled(opt_in and not world_key.is_empty())

func set_enabled(value: bool) -> void:
	enabled = value and not _world_key.is_empty()
	_next_emission = _clock + PULSE_INTERVAL
	for entry: Dictionary in _stations.values():
		for field in ["valve", "fitting"]:
			var node: Node3D = _node(entry.get(field))
			if node != null:
				node.visible = enabled
				if node is CollisionObject3D:
					node.collision_layer = 1 if enabled else 0

## Reject legacy fallback water and arbitrary lookalike APIs. A test subclass of
## the real source runtime is also legitimate; no wrapper gains a hidden emitter.
func bind_source_water(water: Node) -> bool:
	_source_water = null
	if not is_instance_valid(water):
		return false
	var script: Script = water.get_script()
	while script != null:
		if script.resource_path == SOURCE_RUNTIME:
			_source_water = weakref(water)
			return true
		script = script.get_base_script()
	return false

## geometry_only is a CPU-test seam. Production must keep its default false:
## missing real GLBs fail attachment rather than producing invisible controls.
func attach_formal_room(room: Node3D, coord: Vector2i, layout: Dictionary, geometry_only: bool = false) -> bool:
	var spec := station_spec(coord)
	if not enabled or not is_instance_valid(room) or not room.is_inside_tree() or spec.is_empty():
		return false
	if not bool(layout.get("formal", false)) or bool(layout.get("expanded", false)) or not bool(layout.get("water_enabled", true)):
		return false
	if str(layout.get("geometry_path", spec.geometry)) != str(spec.geometry):
		return false
	var expected_origin := Vector3(coord.x * ROOM_SIZE, 0, coord.y * ROOM_SIZE)
	if not room.global_position.is_equal_approx(expected_origin) or not room.global_basis.is_equal_approx(Basis.IDENTITY):
		return false # Placements/region contract is only for the real unrotated formal rooms.
	var valve_model: Node3D
	var fitting_model: Node3D
	if not geometry_only:
		valve_model = _instantiate_model(VALVE_ASSET)
		fitting_model = _instantiate_model(RETURN_ASSET)
		if valve_model == null or fitting_model == null:
			if valve_model != null: valve_model.free()
			if fitting_model != null: fitting_model.free()
			return false
	detach_room(coord)
	var key := station_key(coord, spec.id)
	if not _states.has(key):
		_states[key] = {"open": false, "last_toggle": -DEBOUNCE_SECONDS, "next_pulse": _clock + PULSE_INTERVAL}
	var valve := _mounted_body(room, "FacilityReturnValve", spec.control, spec.yaw, true)
	var fitting := _mounted_body(room, "FacilityReturnFitting", spec["return"], spec.yaw, false)
	var handle: Node3D
	if valve_model != null:
		valve.add_child(valve_model)
		handle = valve_model.find_child("ValveHandle", true, false) as Node3D
		fitting.add_child(fitting_model)
		if handle == null:
			valve.queue_free(); fitting.queue_free()
			return false
	_rooms[coord] = {"room": weakref(room), "identity": room.get_instance_id(), "key": key}
	_stations[key] = {"spec": spec, "room": weakref(room), "valve": weakref(valve), "fitting": weakref(fitting), "handle": weakref(handle) if handle != null else null}
	_states[key].next_pulse = _clock + PULSE_INTERVAL # Reload never catches up old pulses.
	if handle != null:
		handle.rotation.z = PI * 0.5 if bool(_states[key].open) else 0.0
	var exit_callback := _room_exiting.bind(coord, room.get_instance_id())
	if not room.tree_exiting.is_connected(exit_callback):
		room.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)
	return true

func _instantiate_model(path: String) -> Node3D:
	if not _asset_cache.has(path):
		var resource := load(path) as PackedScene
		if resource == null:
			push_warning("Facility candidate asset is not imported: " + path)
			return null
		_asset_cache[path] = resource
	return (_asset_cache[path] as PackedScene).instantiate() as Node3D

func _mounted_body(room: Node3D, node_name: String, at: Vector3, yaw: float, valve: bool) -> RigidBody3D:
	# Frozen RigidBody3D is intentional: existing source terrain snapshot code
	# excludes dynamic/frozen prop bodies, preserving immutable formal cache keys.
	# Main-view rendering and small real collisions remain. No grab group is added.
	var body := RigidBody3D.new()
	body.name = node_name
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	body.rotation.y = yaw
	body.add_to_group("facility_fixed_devices")
	room.add_child(body)
	var collision := CollisionShape3D.new()
	if valve:
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.20, 0.27, 0.105)
		collision.shape = shape
		collision.position = Vector3(0, 0.035, 0.0525)
	else:
		var shape := CylinderShape3D.new()
		shape.radius = 0.053
		shape.height = 0.035
		collision.shape = shape
		collision.rotation.x = PI * 0.5
		collision.position.z = 0.0175
	body.add_child(collision)
	return body

func _room_exiting(coord: Vector2i, identity: int) -> void:
	if _rooms.has(coord) and int(_rooms[coord].identity) == identity:
		detach_room(coord)

func detach_room(coord: Vector2i) -> void:
	if not _rooms.has(coord):
		return
	var room_entry: Dictionary = _rooms[coord]
	var room: Node3D = _node(room_entry.room)
	if room != null:
		var exit_callback := _room_exiting.bind(coord, int(room_entry.identity))
		if room.tree_exiting.is_connected(exit_callback):
			room.tree_exiting.disconnect(exit_callback)
	var key: String = _rooms[coord].key
	if _stations.has(key):
		for field in ["valve", "fitting"]:
			var body: Node = _node(_stations[key].get(field))
			if body != null and not body.is_queued_for_deletion():
				body.queue_free()
		_stations.erase(key)
	_rooms.erase(coord)
	# Deliberately retain only tiny room/station keyed state, never room objects.

## Owner calls this only after held-release/aimed-prop priority is determined.
## Return true also for a debounce, so E cannot fall through to a nearby ladder.
func try_interact(camera: Camera3D, prop_has_priority: bool, player_busy: bool = false, exclude: Array[RID] = []) -> bool:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	return try_interact_ray(camera.global_position, -camera.global_basis.z, prop_has_priority, player_busy,
		func(from: Vector3, to: Vector3, key: String) -> bool:
			return _clear_line(camera, from, to, key, exclude))

func interaction_hint(camera: Camera3D, prop_has_priority: bool, player_busy: bool = false, exclude: Array[RID] = []) -> String:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return ""
	var key := target_from_ray(camera.global_position, -camera.global_basis.z, prop_has_priority, player_busy,
		func(from: Vector3, to: Vector3, station: String) -> bool:
			return _clear_line(camera, from, to, station, exclude))
	if key.is_empty():
		return ""
	return "E 关闭回水阀" if bool(_states[key].open) else "E 开启回水阀"

func _clear_line(camera: Camera3D, from: Vector3, to: Vector3, key: String, exclude: Array[RID]) -> bool:
	var ignored: Array[RID] = exclude.duplicate()
	var body := _node(_stations[key].valve) as CollisionObject3D
	if body == null:
		return false
	ignored.append(body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, ignored)
	return camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Test/alternative-owner seam; visibility is required and fails closed if absent.
## Do not supply an unconditional true callback in production.
func target_from_ray(origin: Vector3, forward: Vector3, prop_has_priority: bool, player_busy: bool, visible: Callable) -> String:
	if not enabled or prop_has_priority or player_busy or not origin.is_finite() or not forward.is_finite() or forward.length_squared() < 0.5 or not visible.is_valid():
		return ""
	var direction := forward.normalized()
	var closest := REACH + 1.0
	var result := ""
	for key: String in _stations:
		var entry: Dictionary = _stations[key]
		var room: Node3D = _node(entry.room)
		var body: Node3D = _node(entry.valve)
		if room == null or body == null or room.is_queued_for_deletion() or body.is_queued_for_deletion():
			continue
		var spec: Dictionary = entry.spec
		var center: Vector3 = room.global_position + spec.control + spec.normal * 0.087
		var offset := center - origin
		var distance := offset.length()
		var along := offset.dot(direction)
		if distance > REACH or along <= 0.0 or distance >= closest or (origin - center).dot(spec.normal) <= 0.02:
			continue
		if (offset - direction * along).length_squared() > AIM_RADIUS * AIM_RADIUS:
			continue
		if not bool(visible.call(origin, center, key)):
			continue
		closest = distance
		result = key
	return result

func try_interact_ray(origin: Vector3, forward: Vector3, prop_has_priority: bool, player_busy: bool, visible: Callable) -> bool:
	var key := target_from_ray(origin, forward, prop_has_priority, player_busy, visible)
	if key.is_empty():
		return false
	var state: Dictionary = _states[key]
	if _clock - float(state.last_toggle) < DEBOUNCE_SECONDS:
		_counts.debounced += 1
		return true
	state.open = not bool(state.open)
	state.last_toggle = _clock
	state.next_pulse = _clock + PULSE_INTERVAL
	_counts.toggles += 1
	valve_changed.emit(key, bool(state.open))
	return true

## Source support fits wholly inside the real wet contour, not the catalog's
## bath bounding rectangle. 4 cm margin excludes curved-wall polygon chords.
static func point_in_station_region(spec: Dictionary, local: Vector3) -> bool:
	if not local.is_finite():
		return false
	if spec.get("region", "") == "sidepool":
		return absf(local.x) <= 3.88 and absf(local.z) <= 3.88 and not (absf(local.x) <= 2.44 and local.z < -0.06)
	if spec.get("region", "") == "bath":
		return Vector2(local.x, local.z).length_squared() <= 4.76 * 4.76 and local.z < 1.60
	return false

func _source_is_ready(water: Node) -> bool:
	if not is_instance_valid(water) or not bool(water.get("enabled")) or bool(water.get("_terrain_paused")):
		return false
	var settings: Dictionary = water.get("settings")
	if not bool(settings.get("simulation", false)) or not bool(water.call("is_terrain_ready")):
		return false
	var solver: RefCounted = water.get("solver")
	return solver != null and is_finite(float(solver.get("peak"))) and float(solver.get("peak")) < QUIET_PEAK_LIMIT

func _admit_pulse(entry: Dictionary, water: Node) -> bool:
	var spec: Dictionary = entry.spec
	var room: Node3D = _node(entry.room)
	if room == null or room.is_queued_for_deletion():
		return false
	var coord: Vector2i = spec.coord
	if not room.global_position.is_equal_approx(Vector3(coord.x * ROOM_SIZE, 0, coord.y * ROOM_SIZE)) or not room.global_basis.is_equal_approx(Basis.IDENTITY):
		return false
	# 5x5 checks cover interior + exact square edges/corners. The source itself
	# also rejects dry cells and source-to-cell dry crossings in swe_source.glsl.
	for x in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for z in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var local: Vector3 = spec.nozzle + Vector3(x * SOURCE_SUPPORT, 0, z * SOURCE_SUPPORT)
			if not point_in_station_region(spec, local):
				return false
			var at := room.global_position + local
			var depth := float(water.call("depth_at", at))
			if not bool(water.call("is_water_at", at)) or not is_finite(depth) or depth < MIN_DEPTH:
				return false
	var at: Vector3 = room.global_position + spec.nozzle
	var flow: Vector2 = water.call("current_velocity_at", at)
	return flow.is_finite() and flow.length() < QUIET_FLOW_LIMIT

func advance(delta: float, active_room: Vector2i, gameplay_active: bool = true) -> int:
	if not is_finite(delta) or delta <= 0.0:
		return 0
	_clock += delta
	_animate_handles(minf(delta, 0.10))
	if not enabled or not gameplay_active:
		_next_emission = _clock + PULSE_INTERVAL
		return 0
	if _clock < _next_emission:
		return 0
	# Set a fresh deadline, not += interval: no burst catch-up after hitch/pause.
	_next_emission = _clock + PULSE_INTERVAL
	if not _rooms.has(active_room):
		return 0
	var key: String = _rooms[active_room].key
	if not _stations.has(key) or not bool(_states[key].open) or _clock < float(_states[key].next_pulse):
		return 0
	_states[key].next_pulse = _clock + PULSE_INTERVAL
	var water: Node = _node(_source_water)
	var entry: Dictionary = _stations[key]
	if not _source_is_ready(water) or water.get("_requested_coord") != active_room or not _admit_pulse(entry, water):
		_counts.blocked_water += 1
		return 0
	var room: Node3D = _node(entry.room)
	var spec: Dictionary = entry.spec
	# This sole water write is the existing SOURCE SWE momentum route. Never call
	# splash, impact, crest, player_impact, MPM, whitewater or caustic APIs here.
	water.call("push_wake", room.global_position + spec.nozzle, spec.direction * PULSE_IMPULSE, PULSE_SIGMA)
	_counts.pulses += 1
	return 1

func _animate_handles(delta: float) -> void:
	for key: String in _stations:
		var handle: Node3D = _node(_stations[key].handle)
		if handle != null:
			var target := PI * 0.5 if bool(_states[key].open) else 0.0
			if not is_equal_approx(handle.rotation.z, target):
				handle.rotation.z = move_toward(handle.rotation.z, target, delta * PI * 2.5)

func station_state(key: String) -> Dictionary:
	return _states.get(key, {}).duplicate(true)

func debug_status() -> Dictionary:
	return {"enabled": enabled, "world": _world_key, "seed": _world_seed,
		"loaded_rooms": _rooms.size(), "loaded_stations": _stations.size(),
		"retained_states": _states.size(), "clock": _clock, "counts": _counts.duplicate()}

static func _node(reference: Variant) -> Node3D:
	if reference is WeakRef:
		var value: Object = reference.get_ref()
		return value as Node3D if is_instance_valid(value) else null
	return null

func clear() -> void:
	for coord: Vector2i in _rooms.keys():
		detach_room(coord)
	_states.clear()
	_source_water = null
	_asset_cache.clear()
	enabled = false
	_world_key = ""
	_world_seed = 0
	_clock = 0.0
	_next_emission = 0.0
	_counts = {"toggles": 0, "debounced": 0, "pulses": 0, "blocked_water": 0}

func _exit_tree() -> void:
	clear()
