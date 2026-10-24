extends SceneTree
## Functional and controlled CPU-headless evidence, never target-GPU/FPS proof.
const Refresh = preload("res://scripts/rendering/rt_material_refresh.gd")
const EXISTING_NODES := 5000
const NEW_NODES := 40
const BATCHES := 12

class ReceiverLibrary extends RefCounted:
	var receivers: Array = []
	func _receiver_materials() -> Array: return receivers

class Host extends Node3D:
	var materials := ReceiverLibrary.new()

var failures: Array[String] = []
var checks: Array[Dictionary] = []
var shader_resources: Dictionary = {}
var raster_paths: Array = Refresh.SHADER_PAIRS.keys()

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"pass": ok, "label": label, "detail": detail})
	if not ok: failures.append(label)

func _material(pair: int = 0, enabled: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var path: String = Refresh.SHADER_PAIRS[raster_paths[pair]] if enabled else raster_paths[pair]
	material.shader = shader_resources[path]
	material.set_shader_parameter("source_domain_origin", Vector2(32, -64))
	return material

func _mesh(parent: Node, material: Material = null, shared_mesh: Mesh = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = shared_mesh if shared_mesh != null else BoxMesh.new()
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _path_is(material: ShaderMaterial, pair: int, enabled: bool) -> bool:
	var expected: String = Refresh.SHADER_PAIRS[raster_paths[pair]] if enabled else raster_paths[pair]
	return material.shader.resource_path == expected

func _functional() -> Dictionary:
	var host := Host.new()
	root.add_child(host)
	var refresh := Refresh.new()
	refresh.configure(host)
	var all_materials: Array[ShaderMaterial] = []
	for pair in 4:
		var material := _material(pair)
		all_materials.append(material)
		host.materials.receivers.append(material)
		_mesh(host, material)
	var receiver_only := _material(0)
	host.materials.receivers.append(receiver_only)
	refresh.refresh_all(true)
	for pair in 4: _check(_path_is(all_materials[pair], pair, true), "full toggle converts shader pair %d" % pair)
	_check(_path_is(receiver_only, 0, true), "full toggle includes uninstanced library receiver")
	_check(refresh.get_stats().last.shader_changes == 5 and refresh.get_stats().last.unique_materials == 5, "full toggle deduplicates library and geometry material references", refresh.get_stats().last)
	refresh.refresh_all(true)
	_check(refresh.get_stats().last.shader_changes == 0 and refresh.get_stats().last.shader_loads == 0, "repeated same-state full refresh performs no loads or assignments")

	# Materials assigned after enqueue are deliberately read only by the flush.
	var late := _mesh(host)
	refresh.queue_node(late)
	var late_material := _material(1)
	var retained_texture := GradientTexture2D.new()
	late_material.set_shader_parameter("scan_albedo", retained_texture)
	late.material_override = late_material
	refresh.queue_node(late)
	var overlay := _material(2)
	late.material_overlay = overlay
	var clone := late_material.duplicate(false) as ShaderMaterial
	var clone_node := _mesh(host, clone)
	refresh.queue_node(clone_node)
	var shared := _mesh(host, late_material)
	refresh.queue_node(shared)
	refresh.refresh_pending(true)
	_check(_path_is(late_material, 1, true) and _path_is(overlay, 2, true) and _path_is(clone, 1, true), "deferred override overlay shared and cloned materials convert")
	_check(refresh.get_stats().last.geometry_visited == 3 and refresh.get_stats().last.unique_materials == 3 and refresh.get_stats().last.shader_changes == 3, "pending refresh visits only unique queued nodes and materials", refresh.get_stats().last)
	_check(clone.get_shader_parameter("source_domain_origin") == Vector2(32, -64), "conversion retains shader parameter values")
	_check(clone.get_shader_parameter("scan_albedo") == retained_texture and late.material_override == late_material, "conversion preserves texture and material resource identity")

	var surface_material := _material(3)
	var mesh_resource := BoxMesh.new()
	mesh_resource.material = surface_material
	var surface_node := _mesh(host, null, mesh_resource)
	refresh.queue_node(surface_node)
	var surface_override := _material(0)
	var override_node := _mesh(host, null, BoxMesh.new())
	override_node.set_surface_override_material(0, surface_override)
	refresh.queue_node(override_node)
	var multimesh_material := _material(2)
	var multi_resource := MultiMesh.new()
	var multi_mesh := BoxMesh.new()
	multi_mesh.material = multimesh_material
	multi_resource.mesh = multi_mesh
	var multi_node := MultiMeshInstance3D.new()
	multi_node.multimesh = multi_resource
	var multi_overlay := _material(1)
	var multi_override := _material(3)
	multi_node.material_overlay = multi_overlay
	multi_node.material_override = multi_override
	host.add_child(multi_node)
	refresh.queue_node(multi_node)
	refresh.refresh_pending(true)
	_check(_path_is(surface_material, 3, true) and _path_is(surface_override, 0, true), "MeshInstance base and surface override materials convert")
	_check(_path_is(multimesh_material, 2, true) and _path_is(multi_overlay, 1, true), "MultiMesh surface and overlay materials convert")
	_check(_path_is(multi_override, 3, true), "MultiMesh material override converts without replacing its surface material")

	var unrelated := ShaderMaterial.new()
	unrelated.shader = Shader.new()
	unrelated.shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(0.5); }"
	var unrelated_shader := unrelated.shader
	var plain := StandardMaterial3D.new()
	var unrelated_node := _mesh(host, unrelated)
	unrelated_node.material_overlay = plain
	refresh.queue_node(unrelated_node)
	refresh.refresh_pending(true)
	_check(unrelated.shader == unrelated_shader and unrelated_node.material_overlay == plain, "non-target shader and standard materials remain unchanged")

	var outsider := _mesh(root, _material(0))
	var freed := _mesh(host, _material(0))
	var detached := _mesh(host, _material(0))
	var pending_delete := _mesh(host, _material(0))
	for node: GeometryInstance3D in [outsider, freed, detached, pending_delete]: refresh.queue_node(node)
	freed.free()
	host.remove_child(detached)
	pending_delete.queue_free()
	refresh.refresh_pending(true)
	_check(refresh.get_stats().last.discarded_nodes == 4 and refresh.get_stats().last.geometry_visited == 0, "freed detached queued-for-deletion and outside-host nodes are ignored", refresh.get_stats().last)
	_check(_path_is(outsider.material_override, 0, false) and _path_is(detached.material_override, 0, false), "discarded live nodes retain their original shaders")
	outsider.free()
	detached.free()

	var queued_before_toggle := _mesh(host, _material(0))
	refresh.queue_node(queued_before_toggle)
	refresh.refresh_all(false)
	_check(refresh.get_stats().pending_nodes == 0 and _path_is(queued_before_toggle.material_override, 0, false), "full disable consumes pending work and restores raster materials")
	refresh.refresh_pending(false)
	_check(refresh.get_stats().last.geometry_visited == 0, "stale deferred callback after full refresh is harmless")
	refresh.refresh_all(true)
	refresh.refresh_all(false)
	_check(_path_is(receiver_only, 0, false) and _path_is(multimesh_material, 2, false) and _path_is(surface_override, 0, false), "rapid on-off toggles restore every supported route")
	_check(_path_is(multi_override, 3, false) and _path_is(multi_overlay, 1, false), "rapid toggles restore MultiMesh override and overlay")
	var new_while_off := _mesh(host, _material(2, true))
	refresh.queue_node(new_while_off)
	refresh.refresh_pending(false)
	_check(_path_is(new_while_off.material_override, 2, false), "deferred flush honors latest enabled state")

	var old_world := Node3D.new()
	host.add_child(old_world)
	var old_world_node := _mesh(old_world, _material(3))
	refresh.queue_node(old_world_node)
	host.remove_child(old_world)
	var new_world := Node3D.new()
	host.add_child(new_world)
	var new_world_node := _mesh(new_world, _material(3))
	refresh.queue_node(new_world_node)
	refresh.refresh_pending(true)
	_check(refresh.get_stats().last.discarded_nodes == 1 and _path_is(new_world_node.material_override, 3, true) and _path_is(old_world_node.material_override, 3, false), "world replacement rejects detached old geometry and handles new geometry")
	old_world.free()
	refresh.queue_node(new_world_node)
	var next_host := Host.new()
	root.add_child(next_host)
	refresh.configure(next_host)
	refresh.refresh_pending(true)
	_check(refresh.get_stats().pending_nodes == 0 and refresh.get_stats().last.geometry_visited == 0, "configure replacement clears pending references")
	next_host.free()
	refresh.refresh_all(true)
	_check(refresh.get_stats().last.geometry_visited == 0, "freed host is safe")
	var stats := refresh.get_stats()
	_check(stats.cached_shaders <= 8 and stats.shader_load_failures == 0, "at most eight shader resources cached with no load failures", stats.cached_shaders)
	host.free()
	return stats

static func _baseline_exact(host: Node, enabled: bool) -> Dictionary:
	# Same operations as 4876a68 DesktopQuality._set_rt_materials(). Only timing
	# and counters are added. Do not deduplicate, skip matches, or cache loads here.
	var started := Time.get_ticks_usec()
	var pairs := {"res://shaders/art_pass_pbr.gdshader":"res://shaders/art_pass_pbr_rt.gdshader", "res://shaders/ceramic_world.gdshader":"res://shaders/ceramic_world_rt.gdshader", "res://shaders/pc_source_ceramic.gdshader":"res://shaders/pc_source_ceramic_rt.gdshader", "res://shaders/source_architecture.gdshader":"res://shaders/source_architecture_rt.gdshader"}
	var materials: Array = []
	var library := host.get("materials") as RefCounted
	if library and library.has_method("_receiver_materials"):
		materials.append_array(library.call("_receiver_materials"))
	var geometry_visited := 0
	for node in host.find_children("*", "GeometryInstance3D", true, false):
		geometry_visited += 1
		materials.append_array([node.material_override, node.material_overlay])
		if node is MeshInstance3D and node.mesh:
			for index in node.mesh.get_surface_count(): materials.append(node.get_active_material(index))
		elif node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
			for index in node.multimesh.mesh.get_surface_count(): materials.append(node.multimesh.mesh.surface_get_material(index))
	var collect_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var apply_started := Time.get_ticks_usec()
	var setter_attempts := 0
	for material in materials:
		if material is ShaderMaterial and material.shader:
			for raster: String in pairs:
				if material.shader.resource_path in [raster, pairs[raster]]:
					material.shader = load(pairs[raster] if enabled else raster)
					setter_attempts += 1
	return {"geometry_visited": geometry_visited, "material_array_entries": materials.size(), "shader_load_and_setter_attempts": setter_attempts, "collect_ms": collect_ms, "apply_ms": float(Time.get_ticks_usec() - apply_started) / 1000.0, "total_ms": float(Time.get_ticks_usec() - started) / 1000.0}

func _reset_materials(materials: Array[ShaderMaterial]) -> void:
	for index in materials.size(): materials[index].shader = shader_resources[raster_paths[index % 4]]

func _summary(rows: Array, key: String) -> Dictionary:
	var values: Array[float] = []
	var total := 0.0
	for row: Dictionary in rows:
		var value := float(row[key])
		values.append(value)
		total += value
	values.sort()
	return {"samples": values.size(), "min_ms": values[0], "median_ms": values[values.size() / 2], "mean_ms": total / values.size(), "max_ms": values[-1]}

func _benchmark() -> Dictionary:
	var host := Host.new()
	root.add_child(host)
	var shared_mesh := BoxMesh.new()
	for index in 32: host.materials.receivers.append(_material(index % 4, true))
	for index in EXISTING_NODES: _mesh(host, host.materials.receivers[index % 32], shared_mesh)
	var refresh := Refresh.new()
	refresh.configure(host)
	refresh.refresh_all(true)
	var baseline_rows: Array = []
	var candidate_rows: Array = []
	var queue_rows: Array = []
	for batch_index in BATCHES:
		var entrants := Node3D.new()
		host.add_child(entrants)
		var entrants_materials: Array[ShaderMaterial] = []
		var entrants_nodes: Array[MeshInstance3D] = []
		for index in 8: entrants_materials.append(_material(index % 4))
		for index in NEW_NODES: entrants_nodes.append(_mesh(entrants, entrants_materials[index % 8], shared_mesh))
		var baseline: Dictionary
		var candidate: Dictionary
		var queue_ms := 0.0
		# Alternate order; reset only the same eight new materials before each run.
		for order in 2:
			_reset_materials(entrants_materials)
			if (batch_index + order) % 2 == 0:
				baseline = _baseline_exact(host, true)
			else:
				var queue_started := Time.get_ticks_usec()
				for node: MeshInstance3D in entrants_nodes: refresh.queue_node(node)
				queue_ms = float(Time.get_ticks_usec() - queue_started) / 1000.0
				refresh.refresh_pending(true)
				candidate = refresh.get_stats().last
				candidate.queue_ms = queue_ms
				candidate.queue_and_flush_ms = queue_ms + float(candidate.total_ms)
			for index in entrants_materials.size(): _check(_path_is(entrants_materials[index], index % 4, true), "benchmark batch %d order %d material %d is correct" % [batch_index, order, index])
		_check(baseline.geometry_visited == EXISTING_NODES + NEW_NODES, "baseline visits every resident geometry in batch %d" % batch_index)
		_check(candidate.geometry_visited == NEW_NODES and candidate.unique_materials == 8 and candidate.shader_changes == 8, "candidate visits only entrant geometry and eight unique materials in batch %d" % batch_index, candidate)
		baseline_rows.append(baseline)
		candidate_rows.append(candidate)
		queue_rows.append({"total_ms": queue_ms})
		entrants.free()
	var result := {"existing_nodes": EXISTING_NODES, "new_nodes_per_batch": NEW_NODES, "batches": BATCHES, "base_shared_materials": 32, "new_unique_materials": 8, "ordering": "Alternating baseline/candidate, same eight new shaders reset before each timed call", "baseline": baseline_rows, "candidate": candidate_rows, "baseline_total": _summary(baseline_rows, "total_ms"), "candidate_flush_total": _summary(candidate_rows, "total_ms"), "candidate_queue_and_flush_total": _summary(candidate_rows, "queue_and_flush_ms"), "queue_total": _summary(queue_rows, "total_ms"), "helper_stats": refresh.get_stats()}
	host.free()
	return result

func _run() -> void:
	for raster: String in Refresh.SHADER_PAIRS:
		for path: String in [raster, Refresh.SHADER_PAIRS[raster]]:
			shader_resources[path] = load(path) as Shader
			_check(shader_resources[path] != null, "production shader loads: " + path)
	var functional := _functional()
	var benchmark := _benchmark()
	var report := {"pass": failures.is_empty(), "checks": checks.size(), "failures": failures, "engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "scope": "Controlled Godot CPU-headless scene traversal/material dispatch only. No game frame-time, rendering, hardware RT, DLSS/FG, Windows GPU, collision or source-water execution acceptance.", "functional": functional, "benchmark": benchmark, "assertions": checks, "source_sha256": {"helper": FileAccess.get_sha256("res://scripts/rendering/rt_material_refresh.gd"), "fixture": FileAccess.get_sha256("res://tests/room_transition/rt_material_refresh_contract.gd")}}
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "\t") + "\n")
			file.close()
		else:
			push_error("Cannot write contract report: " + output)
			quit(2)
			return
	print("RT_MATERIAL_REFRESH_CONTRACT ", JSON.stringify({"pass": report.pass, "checks": checks.size(), "failures": failures, "baseline_total": benchmark.baseline_total, "candidate_queue_and_flush_total": benchmark.candidate_queue_and_flush_total, "report": output, "scope": report.scope}))
	quit(0 if failures.is_empty() else 1)
