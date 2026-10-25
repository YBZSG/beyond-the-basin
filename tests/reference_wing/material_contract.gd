extends SceneTree
## Resource/binding validation on a dummy headless renderer, not shader GPU QA.
const Family = preload("res://scripts/reference_wing/reference_materials.gd")
var errors: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _run() -> void:
	var family := Family.new()
	for shader: Shader in [Family.RASTER_SHADER, Family.RT_SHADER]:
		var names: Array[String] = []
		for uniform: Dictionary in shader.get_shader_uniform_list(): names.append(uniform.name)
		for required: String in ["base_color", "bevel_slope", "orm", "face_color_gain", "grout_color_gain", "face_shape_strength", "face_profile", "face_roughness", "tile_scale", "causticGain"]:
			_check(required in names, "Shader frontend did not expose " + required + " in " + shader.resource_path)
	_check(family.resolve("tile") == null, "Must not replace legacy source role")
	_check(family.resolve("art_pass_tile_pearl") == null, "Must not replace legacy art role")
	for role: String in Family.TILE_ROLES:
		var material := family.resolve(role) as ShaderMaterial
		_check(material != null, "Missing shader material " + role)
		_check(material == family.resolve(role), "Role should share its cached resource")
		_check(material.shader == Family.RASTER_SHADER, "Wrong initial raster shader")
		for uniform: String in ["base_color", "bevel_slope", "orm"]:
			_check(material.get_shader_parameter(uniform) is Texture2D, "Unbound map " + role + "/" + uniform)
		_check(is_equal_approx(material.get_shader_parameter("causticGain"), 0.0), "Unregistered receiver must be disabled")
		var expected_roughness := 0.26 if Family.DRY_PALETTES.has(role) else 0.075
		var expected_scale := 1.0
		if Family.SATIN_ROLES.has(role):
			expected_roughness = Family.SATIN_ROLES[role].face_roughness
			expected_scale = Family.SATIN_ROLES[role].tile_scale
		_check(is_equal_approx(material.get_shader_parameter("face_roughness"), expected_roughness), "Unexpected initial roughness")
		_check(is_equal_approx(material.get_shader_parameter("tile_scale"), expected_scale), "Wrong physical tile scale")
		_check(material.get_shader_parameter("face_profile") == (1 if role == Family.REF5_CROWN_ROLE else 0), "Crown profile leaked across roles")
		var preset: Dictionary = Family.SATIN_ROLES.get(role,{})
		var face_gain: Vector3 = material.get_shader_parameter("face_color_gain")
		var grout_gain: Vector3 = material.get_shader_parameter("grout_color_gain")
		_check(face_gain.is_equal_approx(preset.get("face_color_gain",Vector3.ONE)), "Face palette gain leaked")
		_check(grout_gain.is_equal_approx(preset.get("grout_color_gain",Vector3.ONE)), "Grout palette gain leaked")
	var pearl := family.resolve("ref_tile_pearl") as ShaderMaterial
	var texture: Texture2D = pearl.get_shader_parameter("orm")
	var decoded := texture.get_image()
	if decoded.is_compressed(): _check(decoded.decompress() == OK, "Imported ORM CPU decoder failed")
	_check(decoded.get_pixel(128,128).a > 0.98, "Imported face coverage was lost")
	_check(decoded.get_pixel(0,128).a < 0.05, "Imported grout coverage was lost")
	_check(absf(decoded.get_pixel(2,128).a - 199.0/255.0) < 0.045, "Imported bevel coverage differs")
	_check(decoded.get_mipmap_count() == 11, "Imported ORM mip chain incomplete")
	_check(decoded.get_format() == Image.FORMAT_RGBA8, "Unexpected decoded ORM format")
	var bytes := decoded.get_data()
	var last_mip := decoded.get_mipmap_offset(decoded.get_mipmap_count())
	_check(absf(float(bytes[last_mip+3])/255.0 - 0.9656297871) < 0.012, "Imported smallest mip lost mean face coverage")
	var bevel_texture: Texture2D = pearl.get_shader_parameter("bevel_slope")
	var decoded_bevel := bevel_texture.get_image()
	if decoded_bevel.is_compressed(): _check(decoded_bevel.decompress() == OK, "Imported slope CPU decoder failed")
	var flat := decoded_bevel.get_pixel(128,128)
	_check(absf(flat.r - 128.0/255.0) < 1.5/255.0 and absf(flat.g - 128.0/255.0) < 1.5/255.0, "Imported neutral bevel slope changed")
	family.set_raytracing_enabled(true)
	_check(pearl.shader == Family.RT_SHADER, "RT pair did not switch")
	_check(pearl.get_shader_parameter("orm") == texture, "Switch lost texture binding")
	family.set_raytracing_enabled(false)
	_check(pearl.shader == Family.RASTER_SHADER, "Raster restoration failed")
	for variant: String in Family.VARIANTS:
		_check(family.set_diagnostic_variant(variant), "Diagnostic variant rejected")
		var values: Vector2 = Family.VARIANTS[variant]
		_check(is_equal_approx(pearl.get_shader_parameter("face_shape_strength"), values.x), "Wrong shape ablation")
		_check(is_equal_approx(pearl.get_shader_parameter("face_roughness"), values.y), "Wrong roughness ablation")
		var crowned := family.resolve(Family.REF5_CROWN_ROLE) as ShaderMaterial
		_check(crowned.get_shader_parameter("face_profile") == 1, "Dedicated crown profile lost")
		_check(is_equal_approx(crowned.get_shader_parameter("face_roughness"),0.075), "Scoped crown roughness must stay .075")
		_check(crowned.get_shader_parameter("base_color") == pearl.get_shader_parameter("base_color"), "Scoped crown changed pearl palette")
		for dry_role: String in Family.DRY_PALETTES:
			_check(is_equal_approx(family.resolve(dry_role).get_shader_parameter("face_roughness"), 0.26), "Dry walkway became wall glaze")
		for satin_role: String in Family.SATIN_ROLES:
			var satin := family.resolve(satin_role) as ShaderMaterial
			var preset: Dictionary = Family.SATIN_ROLES[satin_role]
			_check(is_equal_approx(satin.get_shader_parameter("face_roughness"),preset.face_roughness), "Satin role became ref-5 glaze")
			_check(is_equal_approx(satin.get_shader_parameter("tile_scale"),preset.tile_scale), "Satin metric scale changed in diagnostic")
			_check(satin.get_shader_parameter("base_color").resource_path == Family.ROOT+preset.palette+"_albedo_2k.png", "Satin palette mismatch")
	_check(not family.set_diagnostic_variant("strong_face"), "Rejected QA trial must not be selectable at runtime")
	_check(not family.set_diagnostic_variant("legacy"), "Unknown variant must not silently become a candidate")
	family.set_diagnostic_variant("combined")
	var dimensions: Dictionary = family.get_stats().tile_pitch_metres_by_role
	_check(is_equal_approx(dimensions.ref_tile_pearl,0.10), "Ref-5 pitch changed")
	_check(is_equal_approx(dimensions.ref_tile_dark_teal,0.10), "Colonnade pitch changed")
	_check(is_equal_approx(dimensions.ref_tile_teal_satin,0.15), "Reported cyan pitch is false")
	_check(is_equal_approx(dimensions.ref_tile_pink_satin,0.20), "Reported pink pitch is false")
	var physical: Dictionary = family.get_stats().physical_dimensions_by_role
	_check(is_equal_approx(physical.ref_tile_teal_satin.grout_width_metres,0.0027), "Reported cyan grout is false")
	_check(is_equal_approx(physical.ref_tile_pink_satin.grout_width_metres,0.0036), "Reported pink grout is false")
	_check(is_equal_approx(physical.ref_tile_pearl.grout_width_metres,0.0018), "Ref-5 grout changed")
	var grout := family.resolve("ref_grout") as StandardMaterial3D
	_check(grout != null and is_equal_approx(grout.roughness,0.82), "Grout role invalid")
	var root_node := Node3D.new()
	var recognized := MeshInstance3D.new()
	recognized.mesh = BoxMesh.new()
	var imported := StandardMaterial3D.new()
	imported.resource_name = "ref_tile_teal"
	recognized.mesh.surface_set_material(0, imported)
	root_node.add_child(recognized)
	var unknown := MeshInstance3D.new()
	unknown.mesh = BoxMesh.new()
	var legacy := StandardMaterial3D.new()
	legacy.resource_name = "tile"
	unknown.mesh.surface_set_material(0, legacy)
	root_node.add_child(unknown)
	_check(family.apply_to_imported(root_node) == 1, "Must replace exactly one recognized surface")
	_check(recognized.get_active_material(0) == family.resolve("ref_tile_teal"), "Replacement not bound")
	_check(unknown.get_active_material(0) == legacy, "Legacy material was changed")
	_check(imported.resource_name == "ref_tile_teal", "Imported source resource was mutated")
	root_node.free()
	var report := {"passed":errors.is_empty(), "errors":errors, "stats":family.get_stats(),
		"engine":Engine.get_version_info(), "display":DisplayServer.get_name(),
		"scope":"Headless resources/bindings and imported texture CPU decoding only. No GPU shader/sampling, visual or native RT acceptance."}
	print("REFERENCE_MATERIAL_CONTRACT ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
