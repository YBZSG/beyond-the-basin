class_name PoolMaterials
extends RefCounted
## Material translation of the Three source. Shared resources are never edited
## per imported instance. Geometry, normals and GLB provenance stay untouched.

const CERAMIC_SHADER: Shader = preload("res://shaders/ceramic_world.gdshader")
const ALBEDO_PATH := "res://assets/textures/formal_ceramic/pool_ceramic_albedo_4k.png"
const NORMAL_PATH := "res://assets/textures/formal_ceramic/pool_ceramic_normal_gl_4k.png"
const ROUGHNESS_PATH := "res://assets/textures/formal_ceramic/pool_ceramic_surface_4k.png"
const CERAMIC_REPEAT_METRES := 1.6
const CERAMIC_TILES_PER_AXIS := 16
const CERAMIC_TEXTURE_SIZE := 4096
const CERAMIC_JOINT_METRES := 0.0018

var _materials: Dictionary = {}
var _maps: Dictionary = {}
# Weak references: module-local finish clones must follow the existing dynamic
# receiver atlas/domain uniforms without retaining unloaded streamed rooms.
var _local_receiver_refs: Array[WeakRef] = []

func register_local_receiver(material: ShaderMaterial, source: ShaderMaterial) -> void:
	assert(material != null and source != null)
	# Adopt the source's current receiver state even if registration happens
	# after the most recent atlas replacement / domain rebase. Finish values
	# (roughness, coat and local masks) are deliberately not copied here.
	for uniform: String in ["poolCaustics", "poolCausticsWalls", "source_domain_origin", "causticGain", "reflectedWallExtents", "transmittedWallExtents"]:
		material.set_shader_parameter(uniform, source.get_shader_parameter(uniform))
	for reference: WeakRef in _local_receiver_refs:
		if reference.get_ref() == material: return
	_local_receiver_refs.append(weakref(material))

func _receiver_materials() -> Array:
	var result: Array = _materials.values()
	for index in range(_local_receiver_refs.size() - 1, -1, -1):
		var local: ShaderMaterial = _local_receiver_refs[index].get_ref() as ShaderMaterial
		if local == null:
			_local_receiver_refs.remove_at(index)
		else:
			result.append(local)
	return result

func _init() -> void:
	_maps = {
		"scan_albedo": load(ALBEDO_PATH),
		"scan_normal": load(NORMAL_PATH),
		"scan_roughness": load(ROUGHNESS_PATH),
	}
	_materials["tile"] = _source_ceramic("Source / blue tile",Color("63899d"))
	_materials["pale"] = _source_ceramic("Source / pale tile",Color("aab6b0"))
	_materials["daylight_tile"] = _source_ceramic("Source / daylight tile",Color("75adb2"),true)
	_materials["daylight_pale"] = _source_ceramic("Source / daylight pale",Color("dbddd0"),true)
	# Original analytic PBR atlas, not a scan. 16 tiles / 1.6 m = 100 mm
	# ceramic with narrow grout and almost-flat glazed faces. Source roles above
	# keep their independent original shader and exact pigment values.
	_materials["formal_dry_deck"] = _ceramic("Formal / pearl dry ceramic deck", Color("d6dcd8"), 0.53, 0.02)
	_materials["formal_wainscot"] = _ceramic("Formal / turquoise glazed wainscot", Color("73adb2"), 0.30, 0.18)
	# Calibrated after the actual no-caustic floor capture: blue ceramic, not
	# a white receiver whose shallow water has to manufacture its colour.
	_materials["formal_basin"] = _ceramic("Formal / pale blue submerged ceramic", Color("83b4c7"), 0.31, 0.75)
	_materials["formal_coping"] = _ceramic("Formal / ivory large-format coping", Color("e0e3dc"), 0.40, 0.32)
	_materials["formal_dry_deck"].set_shader_parameter("coat_strength",0.06)
	_materials["formal_wainscot"].set_shader_parameter("coat_strength",0.22)
	_materials["formal_basin"].set_shader_parameter("coat_strength",0.21)
	_materials["formal_coping"].set_shader_parameter("coat_strength",0.11)
	_materials["formal_dry_deck"].set_shader_parameter("grout_pigment",Color("a7b5b0"))
	_materials["formal_wainscot"].set_shader_parameter("grout_pigment",Color("a4bbb8"))
	_materials["formal_basin"].set_shader_parameter("grout_pigment",Color("7d969d"))
	# Coping has actual metre-scale recessed joints in its geometry. A second
	# 100 mm grid here would contradict that construction and shrink its scale.
	_materials["formal_coping"].set_shader_parameter("tile_face_only",true)
	_materials["formal_arcade_tile"] = _ceramic("Formal / arcade turquoise",Color("80b4b8"),.34,.45)
	_materials["formal_arcade_coping"] = _ceramic("Formal / arcade ivory",Color("e0e3dc"),.38,.15)
	_materials["formal_arcade_coping"].set_shader_parameter("tile_face_only",true)
	_materials["formal_plaster"] = _plain("Formal / neutral mineral plaster",Color("e4e3de"),0.84)
	_materials["formal_plaster"].set_shader_parameter("specular_value",0.32)
	_materials["formal_glazing"] = _formal_glazing()
	_materials["grim_tile"] = _source_ceramic("Source / aged green",Color("4f6b64"))
	_materials["grim_pale"] = _source_ceramic("Source / aged pale",Color("828b7a"))
	_materials["floor"] = _ceramic("Tile / submerged basin", Color("aebfb4"), 0.38, 0.65)
	_materials["wall"] = _ceramic("Wall / glazed dado and matte plaster", Color("75adb2"), 0.36, 0.35, true)
	_materials["plaster"] = _plain("Warm lime plaster", Color("c9cec4"), 0.84)
	_materials["ivory"] = _plain("Ivory mouldings and furniture", Color("b9b398"), 0.23)
	_materials["metal"] = _plain("Aged painted metal", Color("6e6a51"), 0.40, 0.78)
	_materials["brushed stainless"] = _plain("Brushed stainless steel", Color("a8b7b6"), 0.28, 0.95)
	_materials["chrome"] = _plain("Polished chrome", Color("b1c5c9"), 0.12, 1.0)
	_materials["service"] = _plain("Service green enamel", Color("708b83"), 0.42, 0.12)
	_materials["black"] = _plain("Dark lane marking", Color("151713"), 0.27)
	_materials["orange"] = _plain("Rescue orange", Color("d36a24"), 0.35)
	_materials["yellow"] = _plain("Duck yellow", Color("f2c32c"), 0.30)
	_materials["red"] = _plain("Oxide red", Color("75443d"), 0.22, 0.35)
	_materials["dark sign board"] = _plain("Dark sign board", Color("17252b"), 0.70)
	_materials["light sign board"] = _plain("Light sign board", Color("c4c8bd"), 0.70)
	_materials["lamp_housing"] = _plain("Luminaire housing", Color("667474"), 0.48, 0.65)
	_materials["lamp"] = _emissive("Warm opal lamp", Color("fff2d5"), 2.8)
	_materials["skylight"] = _emissive("Diffuse skylight glazing", Color("c4d6d8"), 0.65)
	_materials["skylight_dim"] = _emissive("Clouded skylight glazing", Color("566a70"), 0.08)
	_materials["exit_glow"] = _emissive("Red exit lamp", Color("ee523a"), 2.1)

func get_material(role: String) -> Material:
	var key := _normalize_role(role)
	if _materials.has(key):
		return _materials[key] as Material
	match key:
		"ceiling", "arch", "upper_wall": return _materials["plaster"] as Material
		"deck", "ceramic", "pale_tile": return _materials["pale"] as Material
		"stainless", "rail": return _materials["brushed stainless"] as Material
		"glow", "light": return _materials["lamp"] as Material
		_: return _materials["pale"] as Material

func apply_to_imported(root: Node3D) -> void:
	var daylit := _is_daylit(root)
	_apply_recursive(root, daylit)

func _apply_recursive(node: Node, daylit: bool) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh:
			instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			for surface in range(instance.mesh.get_surface_count()):
				var original := instance.get_active_material(surface)
				if original == null:
					continue
				var role := _normalize_role(original.resource_name)
				# Unknown materials (including imported sign glyphs) remain intact.
				if not _materials.has(role):
					continue
				if daylit and role in ["tile", "pale"]:
					role = "daylight_" + role
				instance.set_surface_override_material(surface, get_material(role))
	for child in node.get_children():
		_apply_recursive(child, daylit)

func _is_daylit(node: Node) -> bool:
	var current := node
	while current:
		if current.has_meta("variant"):
			return int(current.get_meta("variant")) in [3, 5, 6, 8]
		if "oculus" in String(current.name).to_lower():
			return true
		current = current.get_parent()
	return false

func _normalize_role(role: String) -> String:
	return role.trim_prefix("Quiet Wing / ").strip_edges().to_lower()

func _source_ceramic(label:String,pigment:Color,two_tone:bool=false)->ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.resource_name=label
	material.shader=preload("res://shaders/source_ceramic.gdshader")
	material.set_shader_parameter("pigment",pigment)
	material.set_shader_parameter("two_tone",two_tone)
	return material

func _ceramic(label: String, pigment: Color, roughness: float, exposure: float, upper: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = label
	material.shader = CERAMIC_SHADER
	for uniform in _maps:
		material.set_shader_parameter(uniform, _maps[uniform])
	material.set_shader_parameter("pigment", pigment)
	material.set_shader_parameter("face_roughness", roughness)
	material.set_shader_parameter("water_exposure", exposure)
	material.set_shader_parameter("repeat_metres", CERAMIC_REPEAT_METRES)
	material.set_shader_parameter("upper_plaster", upper)
	return material

func _plain(label: String, color: Color, roughness: float, metallic: float = 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name=label
	material.shader=preload("res://shaders/source_architecture.gdshader")
	material.set_shader_parameter("pigment",color)
	material.set_shader_parameter("roughness_value",roughness)
	material.set_shader_parameter("metallic_value",metallic)
	return material

func _emissive(label: String, color: Color, energy: float) -> ShaderMaterial:
	var material := _plain(label,color,.32)
	material.set_shader_parameter("light_emission",color)
	material.set_shader_parameter("light_energy",energy)
	return material

func _formal_glazing() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Formal / clear architectural glazing"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.79,0.88,0.89,0.10)
	material.roughness = 0.16
	material.metallic_specular = 0.5
	# Thin authored panes provide a restrained sky reflection, not refraction
	# or an emissive screen. Their mesh shadow/GI policy is set by the builder.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = false
	return material

func set_source_water_uniforms(floor_atlas:Texture2D,wall_atlas:Texture2D,origin:Vector2,gain:float) -> void:
	for material in _receiver_materials():
		if material is ShaderMaterial:
			material.set_shader_parameter("poolCaustics",floor_atlas)
			material.set_shader_parameter("poolCausticsWalls",wall_atlas)
			material.set_shader_parameter("source_domain_origin",origin)
			material.set_shader_parameter("causticGain",gain)

func set_source_wall_extents(reflected:Vector2,transmitted:Vector2)->void:
	for material in _receiver_materials():
		if material is ShaderMaterial:
			material.set_shader_parameter("reflectedWallExtents",reflected)
			material.set_shader_parameter("transmittedWallExtents",transmitted)

func set_formal_projection_fast_path_enabled(enabled: bool) -> void:
	# Explicit PC candidate only. No production caller enables it before native
	# same-camera equivalence and timing checks. Source materials stay exact.
	for role: String in _materials:
		var material := _materials[role] as ShaderMaterial
		if role.begins_with("formal_") and material != null and material.shader == CERAMIC_SHADER:
			material.set_shader_parameter("projection_fast_path", enabled)
