extends Node3D
## Isolated base lifecycle double. Never copied into the production checkout.
const TerrainIdentity = preload("res://tests/reference_wing/water_scheduler_identity.gd")
const LEVEL = 0.32
class SolverDouble extends RefCounted:
	var size := 64
var solver := SolverDouble.new()
var _layouts := {}
var _surfaces := {}
var _materials := {}
var _room_light_refs: Dictionary = {}
var _liquid_surface: Variant = null
var _camera: Camera3D
var domain_origin := Vector2.ZERO
var _terrain_keys := {}
var _terrain_snapshot := {"complete": true}
var _terrain_force_revision := 0
var _terrain_metrics := {"stale_results": 0}
var _prepare_suspended := false
var _disposed := false
var enabled := true
var quality := "Low"
var quality_levels := {"Low": {"surface": 96, "simulation": 64}, "High": {"surface": 384, "simulation": 128}, "Ultra": {"surface": 512, "simulation": 160}}
var source_results: Array = []
var source_cache := {}
var source_accepts: Array = []
var source_errors: Array = []
var duplicate_launches := 0
var source_quality_calls := 0
var source_arraymesh_seen := false
var visibility_refreshes := 0
var source_dispose_calls := 0

func add_room(room: Node3D, coord: Vector2i, layout: Dictionary) -> void:
	_layouts[coord] = layout
	var group := Node3D.new(); room.add_child(group); _surfaces[coord] = group
	var material := ShaderMaterial.new(); _materials[coord] = material
	var surface := MeshInstance3D.new(); surface.mesh = PlaneMesh.new(); group.add_child(surface)

func _effective_lamps(_coord: Vector2i) -> Array: return []

func _terrain_key(coord: Vector2i) -> String:
	var lookup := "%d:%d:%d:%s" % [coord.x, coord.y, solver.size, TerrainIdentity.digest(_effective_lamps(coord))]
	if not _terrain_keys.has(lookup):
		_terrain_keys[lookup] = {"depth_key": "base-depth", "bvh_key": "base-bvh", "mask_key": "base-mask", "key": "base-key"}
	return _terrain_keys[lookup].key

func _advance_terrain() -> void:
	var incoming := source_results; source_results = []
	for job: Dictionary in incoming: _accept_terrain_result(job.value, job.key, job.identity, job.force)
	if _prepare_suspended: return
	# A duplicate would be launched here if the just-reaped demand were neither
	# cached nor protected by the adapter's one-pass suspension latch.
	for job: Dictionary in incoming:
		if not source_cache.has(job.key): duplicate_launches += 1

func _accept_terrain_result(value: Variant, key: String, identity: Dictionary, force: int) -> void:
	if not value is Dictionary or not value.has("coord") or not value.has("size"):
		_failed("Incomplete payload"); return
	if force != _terrain_force_revision or value.size != solver.size:
		_terrain_metrics.stale_results += 1; return
	source_accepts.append({"value": value, "key": key, "identity": identity, "force": force})
	source_cache[key] = value

func _valid_terrain_payload(value: Dictionary) -> bool:
	return value.get("origin") is Vector2 and value.get("size", 0) == solver.size and value.get("domain", 0.0) == 96.0 and value.get("depth_data") is PackedFloat32Array and value.depth_data.size() == solver.size * solver.size

func _failed(message: String) -> void: source_errors.append(message)
func suspend_preparation(value: bool) -> void: _prepare_suspended = value
func preparation_pending() -> bool: return not source_results.is_empty()
func get_preparation_status() -> Dictionary: return {"stage": "source", "pending": preparation_pending(), "worker_count": 0}

func set_quality(value: String) -> void:
	if not quality_levels.has(value) or value == quality: return
	source_quality_calls += 1
	for group: Node3D in _surfaces.values():
		for child: MeshInstance3D in group.get_children(): source_arraymesh_seen = source_arraymesh_seen or not child.mesh is PlaneMesh
	quality = value; solver.size = quality_levels[value].simulation

func _refresh_surface_visibility() -> void: visibility_refreshes += 1
func dispose() -> void:
	if _disposed: return
	_disposed = true; source_dispose_calls += 1
