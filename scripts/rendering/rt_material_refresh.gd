class_name PoolRTMaterialRefresh
extends RefCounted
## Preserve the four existing raster/RT material conversions without rescanning
## the resident world for each streamed batch. The caller owns deferred timing.
const SHADER_PAIRS := {
	"res://shaders/art_pass_pbr.gdshader": "res://shaders/art_pass_pbr_rt.gdshader",
	"res://shaders/ceramic_world.gdshader": "res://shaders/ceramic_world_rt.gdshader",
	"res://shaders/pc_source_ceramic.gdshader": "res://shaders/pc_source_ceramic_rt.gdshader",
	"res://shaders/source_architecture.gdshader": "res://shaders/source_architecture_rt.gdshader",
}

var _host: WeakRef
var _pending: Dictionary = {}
var _shaders: Dictionary = {}
var _stats: Dictionary = {
	"full_refreshes": 0, "pending_refreshes": 0, "queue_requests": 0,
	"duplicate_queue_requests": 0, "pending_cleared": 0,
	"geometry_visited": 0, "discarded_nodes": 0,
	"material_occurrences": 0, "unique_materials": 0,
	"duplicate_materials": 0, "shader_changes": 0,
	"already_correct": 0, "unmatched_materials": 0,
	"shader_loads": 0, "shader_load_failures": 0,
	"last_total_ms": 0.0, "max_total_ms": 0.0, "total_ms": 0.0,
	"last": {},
}

func configure(host: Node) -> void:
	_clear_pending()
	_host = weakref(host) if is_instance_valid(host) else null

func queue_node(node: GeometryInstance3D) -> void:
	if not is_instance_valid(node): return
	_stats.queue_requests += 1
	var identity := node.get_instance_id()
	if _pending.has(identity):
		_stats.duplicate_queue_requests += 1
		return
	# Materials may be assigned after add_child(), so do not inspect them here.
	_pending[identity] = weakref(node)

func refresh_all(enabled: bool) -> void:
	var started := Time.get_ticks_usec()
	_clear_pending()
	var batch := _new_batch("full", enabled)
	var materials: Array = []
	var host := _live_host()
	if host != null:
		var library: Variant = host.get("materials")
		if library is RefCounted and library.has_method("_receiver_materials"):
			materials.append_array(library.call("_receiver_materials"))
		for node: Node in host.find_children("*", "GeometryInstance3D", true, false):
			_collect_geometry(node as GeometryInstance3D, materials, batch)
	batch.collect_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_apply_materials(materials, enabled, batch)
	_finish_batch(batch, started)

func refresh_pending(enabled: bool) -> void:
	var started := Time.get_ticks_usec()
	var batch := _new_batch("pending", enabled)
	# Swap ownership before processing. Later node-added events belong to a new
	# batch, and cannot be discarded when this batch completes.
	var pending: Dictionary = _pending
	_pending = {}
	batch.queued_nodes = pending.size()
	var materials: Array = []
	var host := _live_host()
	for reference: WeakRef in pending.values():
		var node := reference.get_ref() as GeometryInstance3D
		if host == null or not is_instance_valid(node) or node.is_queued_for_deletion() or not host.is_ancestor_of(node):
			batch.discarded_nodes += 1
			continue
		_collect_geometry(node, materials, batch)
	batch.collect_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_apply_materials(materials, enabled, batch)
	_finish_batch(batch, started)

func get_stats() -> Dictionary:
	var result := _stats.duplicate(true)
	result.pending_nodes = _pending.size()
	result.cached_shaders = _shaders.size()
	return result

func _live_host() -> Node:
	if _host == null: return null
	var host := _host.get_ref() as Node
	return host if is_instance_valid(host) and not host.is_queued_for_deletion() else null

func _clear_pending() -> void:
	_stats.pending_cleared += _pending.size()
	_pending.clear()

func _new_batch(kind: String, enabled: bool) -> Dictionary:
	return {"kind": kind, "enabled": enabled, "queued_nodes": 0,
		"geometry_visited": 0, "discarded_nodes": 0,
		"material_occurrences": 0, "unique_materials": 0,
		"duplicate_materials": 0, "shader_changes": 0,
		"already_correct": 0, "unmatched_materials": 0,
		"shader_loads": 0, "shader_load_failures": 0,
		"collect_ms": 0.0, "apply_ms": 0.0, "total_ms": 0.0}

func _collect_geometry(node: GeometryInstance3D, materials: Array, batch: Dictionary) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		batch.discarded_nodes += 1
		return
	batch.geometry_visited += 1
	materials.append_array([node.material_override, node.material_overlay])
	if node is MeshInstance3D and node.mesh:
		for index in node.mesh.get_surface_count():
			materials.append(node.get_active_material(index))
	elif node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
		for index in node.multimesh.mesh.get_surface_count():
			materials.append(node.multimesh.mesh.surface_get_material(index))

func _apply_materials(materials: Array, enabled: bool, batch: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var seen: Dictionary = {}
	for value: Variant in materials:
		if not value is Material: continue
		batch.material_occurrences += 1
		var identity: int = value.get_instance_id()
		if seen.has(identity):
			batch.duplicate_materials += 1
			continue
		seen[identity] = true
		batch.unique_materials += 1
		var material := value as ShaderMaterial
		if material == null or material.shader == null:
			batch.unmatched_materials += 1
			continue
		var current_path := material.shader.resource_path
		var target_path := ""
		for raster: String in SHADER_PAIRS:
			if current_path == raster or current_path == SHADER_PAIRS[raster]:
				target_path = SHADER_PAIRS[raster] if enabled else raster
				break
		if target_path.is_empty():
			batch.unmatched_materials += 1
			continue
		if current_path == target_path:
			batch.already_correct += 1
			continue
		if not _shaders.has(target_path):
			var shader := load(target_path) as Shader
			batch.shader_loads += 1
			if shader == null:
				batch.shader_load_failures += 1
				push_error("RT material shader unavailable: " + target_path)
				continue
			_shaders[target_path] = shader
		if material.shader != _shaders[target_path]:
			material.shader = _shaders[target_path]
			batch.shader_changes += 1
		else:
			batch.already_correct += 1
	batch.apply_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _finish_batch(batch: Dictionary, started: int) -> void:
	batch.total_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_stats["full_refreshes" if batch.kind == "full" else "pending_refreshes"] += 1
	for key: String in ["geometry_visited", "discarded_nodes", "material_occurrences", "unique_materials", "duplicate_materials", "shader_changes", "already_correct", "unmatched_materials", "shader_loads", "shader_load_failures"]:
		_stats[key] += batch[key]
	_stats.last_total_ms = batch.total_ms
	_stats.max_total_ms = maxf(float(_stats.max_total_ms), float(batch.total_ms))
	_stats.total_ms += batch.total_ms
	_stats.last = batch
