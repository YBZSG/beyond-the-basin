extends "res://scripts/reference_wing/reference_water_runtime.gd"
## Isolated extension adapter. Native solver, terrain, update cadence and
## controller APIs retain their default behavior. Glasswell near materials use
## their finite-path derivative; only Soffit far materials mirror source optics.
## Shared source/near-field shader resources and all other room defaults stay exact.
## Far proxies are visual-only, only where the exact source surface is hidden.
const Calm = preload("res://shaders/dreamcore/distant_calm_water.gdshader")
const MIRRORED := ["poolSurface","poolDepth","poolDetail","poolCell","detailCell","poolTime","waveHeight","rippleGain","simulationOn","ripplesOn","domain_origin","mirrorSampler","textureMatrix","reflectionReady","reflectionSize","reflectionOn"]
var _distant: Dictionary = {}
var _distant_materials: Dictionary = {}
var _source_material_coords: Dictionary = {}
var _glasswell_materials: Dictionary = {}
var _glasswell_optics: Script
var _soffit_far_materials: Dictionary = {}
var _soffit_far_optics: Script
func add_room(room: Node3D, coord: Vector2i, layout: Dictionary) -> void:
	super.add_room(room,coord,layout)
	if not layout.get("dreamcore",false) or layout.get("water_rects",[]).is_empty(): return
	var group := Node3D.new(); group.name = "DistantCalmWater_NONINTERACTIVE"
	group.set_meta("noninteractive",true); group.set_meta("source_solver",false)
	room.add_child(group); _distant[coord] = group
	var material := ShaderMaterial.new(); material.shader = Calm
	material.set_shader_parameter("calm_color",Color(.29,.48,.47,.52))
	_distant_materials[coord] = material
	_source_material_coords[_materials[coord].get_instance_id()] = coord
	if str(layout.get("dream_id","")) == "glasswell_bath":
		# super.add_room has already created/bound this material once while the
		# map was absent. Install the opt-in before the new world is playable.
		if _glasswell_optics == null: _glasswell_optics = load("res://scripts/dreamcore/uncanny/glasswell_water_optics.gd") as Script
		_glasswell_materials[_materials[coord].get_instance_id()] = coord
		_apply_reference_surface(_materials[coord])
	if str(layout.get("dream_id","")) == "soffit_reservoir":
		if _soffit_far_optics == null: _soffit_far_optics = load("res://scripts/dreamcore/uncanny/soffit_far_optics.gd") as Script
		_soffit_far_materials[_materials[coord].get_instance_id()] = coord
	_build_proxy_meshes(coord)
	_sync_material(coord)
	_refresh_surface_visibility()
func remove_room(coord: Vector2i) -> void:
	if _soffit_far_optics != null and _materials.has(coord) and _soffit_far_materials.has(_materials[coord].get_instance_id()) and _distant_materials.has(coord):
		_soffit_far_optics.detach(_distant_materials[coord])
	if _materials.has(coord):
		_source_material_coords.erase(_materials[coord].get_instance_id())
		_glasswell_materials.erase(_materials[coord].get_instance_id())
		_soffit_far_materials.erase(_materials[coord].get_instance_id())
	if _distant.has(coord) and is_instance_valid(_distant[coord]): _distant[coord].queue_free()
	_distant.erase(coord); _distant_materials.erase(coord)
	super.remove_room(coord)
func _refresh_surface_visibility() -> void:
	super._refresh_surface_visibility()
	for coord: Vector2i in _distant:
		var group: Node3D = _distant[coord]
		var source: Node3D = _surfaces.get(coord)
		if is_instance_valid(group): group.visible = enabled and is_instance_valid(source) and not source.visible
func set_reference_wave_settings(values: Dictionary) -> void:
	super.set_reference_wave_settings(values)
	# Parent selects/applies reference modes once; merely mirror its result.
	for identity: int in _soffit_far_materials:
		_sync_material(_soffit_far_materials[identity])
func _apply_reference_surface(material: ShaderMaterial) -> void:
	# Both normal _apply_surface and explicit reference-wave toggles dispatch
	# through this inherited selector. Source time/texture binding still occurs
	# once in the unchanged parent. No per-frame extra solver/wave-controller tick.
	super._apply_reference_surface(material)
	if material == null or _glasswell_optics == null or not _glasswell_materials.has(material.get_instance_id()): return
	# Preserve unrelated diagnostic/experimental shaders just like the parent.
	if material.shader not in [Surface,ReferenceSurface,_glasswell_optics.ORIGINAL,_glasswell_optics.REFERENCE]: return
	_glasswell_optics.apply(material,_reference_requested(),reference_waves)
func glasswell_optics_status() -> Dictionary:
	var rows: Array = []
	for identity: int in _glasswell_materials:
		var coord: Vector2i = _glasswell_materials[identity]
		var material: ShaderMaterial = _materials.get(coord)
		if material == null or material.get_instance_id() != identity: continue
		var role := "unrelated_preserved"
		if _glasswell_optics != null:
			if material.shader == _glasswell_optics.ORIGINAL: role = "glasswell_source"
			elif material.shader == _glasswell_optics.REFERENCE: role = "glasswell_reference"
		rows.append({"coord":str(coord),"role":role})
	return {"scene_opt_in":"glasswell_bath","materials":rows,"reference_requested":_reference_requested(),"shared_solver_modified":false,"gpu_appearance_verified":false}
func _apply_surface(material: ShaderMaterial) -> void:
	super._apply_surface(material)
	material.set_shader_parameter("dreamWaterOptics",1.0)
	var identity := material.get_instance_id()
	if _source_material_coords.has(identity): _sync_material(_source_material_coords[identity])
func _sync_material(coord: Vector2i) -> void:
	if not _materials.has(coord) or not _distant_materials.has(coord): return
	var source: ShaderMaterial = _materials[coord]
	var target: ShaderMaterial = _distant_materials[coord]
	for parameter: String in MIRRORED: target.set_shader_parameter(parameter,source.get_shader_parameter(parameter))
	if _soffit_far_optics != null and _soffit_far_materials.has(source.get_instance_id()):
		_soffit_far_optics.apply(source,target)
func _build_proxy_meshes(coord: Vector2i) -> void:
	var group: Node3D = _distant[coord]
	for child: Node in group.get_children(): group.remove_child(child); child.queue_free()
	var source: Node3D = _surfaces.get(coord)
	if not is_instance_valid(source): return
	for near: MeshInstance3D in source.get_children():
		var plane := near.mesh as PlaneMesh
		if plane == null: continue
		var mesh := MeshInstance3D.new(); mesh.name = "CalmBorderMatched"
		mesh.mesh = border_fan(plane.size,plane.subdivide_width+1,plane.subdivide_depth+1)
		mesh.position = near.position; mesh.material_override = _distant_materials[coord]
		mesh.layers = 2; mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED; mesh.extra_cull_margin = .4
		group.add_child(mesh)
func set_quality(value: String) -> void:
	super.set_quality(value)
	for coord: Vector2i in _distant: _build_proxy_meshes(coord)
static func border_fan(size: Vector2, x_segments: int, z_segments: int) -> ArrayMesh:
	# Same perimeter vertex grid as native PlaneMesh; O(perimeter), not its
	# O(area) tessellation. Exact shared vertex positions, no overlapping planes.
	var points := PackedVector3Array([Vector3.ZERO])
	for index in range(x_segments): points.append(Vector3(-size.x*.5+size.x*index/x_segments,0,-size.y*.5))
	for index in range(z_segments): points.append(Vector3(size.x*.5,0,-size.y*.5+size.y*index/z_segments))
	for index in range(x_segments): points.append(Vector3(size.x*.5-size.x*index/x_segments,0,size.y*.5))
	for index in range(z_segments): points.append(Vector3(-size.x*.5,0,size.y*.5-size.y*index/z_segments))
	var normals := PackedVector3Array(); normals.resize(points.size()); normals.fill(Vector3.UP)
	var indices := PackedInt32Array()
	for index in range(1,points.size()): indices.append_array(PackedInt32Array([0,index,(index+1) if index+1<points.size() else 1]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=points; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_INDEX]=indices
	var result := ArrayMesh.new(); result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return result
func distant_stats() -> Dictionary:
	var visible := 0; var triangles := 0; var overlap := false
	for coord: Vector2i in _distant:
		var group: Node3D = _distant[coord]
		if not is_instance_valid(group): continue
		if group.visible: visible += 1
		var near: Node3D = _surfaces.get(coord)
		if is_instance_valid(near): overlap = overlap or (group.visible and near.visible)
		for mesh: MeshInstance3D in group.get_children(): triangles += mesh.mesh.surface_get_array_index_len(0)/3
	return {"proxy_groups":_distant.size(),"visible_groups":visible,"proxy_triangles":triangles,"overlap":overlap,"interactive":false,"gpu_appearance_verified":false}

func dispose() -> void:
	if _disposed: return
	# Retire extension aliases BEFORE the source owner frees RD textures.
	if _soffit_far_optics != null:
		for coord: Vector2i in _soffit_far_materials.values():
			if _distant_materials.has(coord): _soffit_far_optics.detach(_distant_materials[coord])
	for material: ShaderMaterial in _distant_materials.values():
		for parameter: String in ["poolSurface","poolDepth","poolDetail"]: material.set_shader_parameter(parameter,null)

	for value: Variant in _distant.values():
		if is_instance_valid(value): value.hide(); value.queue_free()
	_distant.clear(); _distant_materials.clear(); _source_material_coords.clear()
	_glasswell_materials.clear(); _glasswell_optics = null
	_soffit_far_materials.clear(); _soffit_far_optics = null
	super.dispose()
