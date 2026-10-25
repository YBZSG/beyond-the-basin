class_name ReferenceMaterials
extends RefCounted
## Explicit new-wing roles only. No old material resource or shader is modified.
const RASTER_SHADER: Shader = preload("res://shaders/reference_wing/reference_glaze.gdshader")
const RT_SHADER: Shader = preload("res://shaders/reference_wing/reference_glaze_rt.gdshader")
const ROOT := "res://assets/materials/reference_wing/"
const TILE_ROLES := ["ref_tile_pearl", "ref_tile_teal", "ref_tile_pink", "ref_tile_dark_teal", "ref_tile_dry", "ref_tile_teal_dry", "ref_tile_pink_dry", "ref_tile_dark_teal_dry", "ref_tile_teal_satin", "ref_tile_teal_satin_dry", "ref_tile_pink_satin", "ref_tile_pink_satin_dry", "ref_tile_pearl_ref5_crown", "ref_tile_cyan_satin", "ref_tile_cyan_satin_dry"]
const DRY_PALETTES := {"ref_tile_dry":"ref_tile_pearl", "ref_tile_teal_dry":"ref_tile_teal", "ref_tile_pink_dry":"ref_tile_pink", "ref_tile_dark_teal_dry":"ref_tile_dark_teal"}
const SATIN_ROLES := {
	"ref_tile_teal_satin": {"palette":"ref_tile_teal", "face_roughness":0.085, "tile_scale":1.5},
	"ref_tile_teal_satin_dry": {"palette":"ref_tile_teal", "face_roughness":0.14, "tile_scale":1.5},
	"ref_tile_pink_satin": {"palette":"ref_tile_pink", "face_roughness":0.09, "tile_scale":2.0},
	"ref_tile_pink_satin_dry": {"palette":"ref_tile_pink", "face_roughness":0.14, "tile_scale":2.0},
	"ref_tile_cyan_satin": {"palette":"ref_tile_teal", "face_roughness":0.085, "tile_scale":1.5,
		"face_color_gain":Vector3(0.7277824105632494,1.2876645545294547,1.2503012218572187),
		"grout_color_gain":Vector3(0.5702749165149684,1.0518171825646274,1.0180007269627296)},
	"ref_tile_cyan_satin_dry": {"palette":"ref_tile_teal", "face_roughness":0.14, "tile_scale":1.5,
		"face_color_gain":Vector3(0.7277824105632494,1.2876645545294547,1.2503012218572187),
		"grout_color_gain":Vector3(0.5702749165149684,1.0518171825646274,1.0180007269627296)},
}
const DRY_FACE_ROUGHNESS := 0.14
const REF5_CROWN_ROLE := "ref_tile_pearl_ref5_crown"
const VARIANTS := {
	"control": Vector2(0.0, 0.115),
	"shape_only": Vector2(1.0, 0.115),
	"roughness_only": Vector2(0.0, 0.055),
	"combined": Vector2(1.25, 0.055),
}
var _materials: Dictionary = {}
var _rt_enabled := false
var _variant := "combined"

func resolve(role: String, material_library: RefCounted = null) -> Material:
	var key := role.strip_edges().to_lower().get_slice(".", 0)
	if key != "ref_grout" and key not in TILE_ROLES: return null
	if _materials.has(key): return _materials[key] as Material
	if key == "ref_grout":
		var grout := StandardMaterial3D.new()
		grout.resource_name = key
		grout.albedo_color = Color("879188")
		grout.roughness = 0.82
		grout.metallic = 0.0
		grout.metallic_specular = 0.34
		_materials[key] = grout
		return grout
	var material := ShaderMaterial.new()
	material.resource_name = key
	material.shader = RT_SHADER if _rt_enabled else RASTER_SHADER
	var palette: String = DRY_PALETTES.get(key, key)
	if SATIN_ROLES.has(key): palette = SATIN_ROLES[key].palette
	if key == REF5_CROWN_ROLE: palette = "ref_tile_pearl"
	material.set_shader_parameter("base_color", load(ROOT + palette + "_albedo_2k.png"))
	material.set_shader_parameter("bevel_slope", load(ROOT + "bevel_slope_rg_2k.png"))
	material.set_shader_parameter("orm", load(ROOT + "glaze_orm_2k.png"))
	material.set_shader_parameter("grout_roughness", 0.82)
	material.set_shader_parameter("causticGain", 0.0)
	_apply_variant(material)
	if material_library != null and material_library.has_method("register_local_receiver") and material_library.has_method("get_material"):
		var source: Variant = material_library.call("get_material", "formal_basin")
		if source is ShaderMaterial:
			material_library.call("register_local_receiver", material, source)
			if source.get_shader_parameter("causticGain") == null:
				material.set_shader_parameter("causticGain", 0.0)
	_materials[key] = material
	return material

func apply_to_imported(root: Node, material_library: RefCounted = null) -> int:
	var applied := 0
	if root is MeshInstance3D and root.mesh != null:
		var instance := root as MeshInstance3D
		for index in instance.mesh.get_surface_count():
			var previous: Material = instance.get_active_material(index)
			if previous == null: continue
			var replacement := resolve(previous.resource_name, material_library)
			if replacement != null:
				instance.set_surface_override_material(index, replacement)
				applied += 1
	for child in root.get_children(): applied += apply_to_imported(child, material_library)
	return applied

func set_raytracing_enabled(enabled: bool) -> void:
	_rt_enabled = enabled
	for material: Material in _materials.values():
		if material is ShaderMaterial: material.shader = RT_SHADER if enabled else RASTER_SHADER

func set_diagnostic_variant(variant: String) -> bool:
	if not VARIANTS.has(variant): return false
	_variant = variant
	for material: Material in _materials.values():
		if material is ShaderMaterial: _apply_variant(material)
	return true

func _apply_variant(material: ShaderMaterial) -> void:
	var settings: Vector2 = VARIANTS[_variant]
	var shape_strength := settings.x
	material.set_shader_parameter("face_shape_strength", shape_strength)
	material.set_shader_parameter("face_roughness", DRY_FACE_ROUGHNESS if DRY_PALETTES.has(material.resource_name) else settings.y)
	material.set_shader_parameter("face_profile", 1)
	if material.resource_name == REF5_CROWN_ROLE:
		material.set_shader_parameter("face_roughness", 0.055)
	material.set_shader_parameter("tile_scale", 1.0)
	material.set_shader_parameter("face_color_gain", Vector3.ONE)
	material.set_shader_parameter("grout_color_gain", Vector3.ONE)
	if SATIN_ROLES.has(material.resource_name):
		var preset: Dictionary = SATIN_ROLES[material.resource_name]
		material.set_shader_parameter("face_roughness", preset.face_roughness)
		material.set_shader_parameter("tile_scale", preset.tile_scale)
		material.set_shader_parameter("face_color_gain", preset.get("face_color_gain",Vector3.ONE))
		material.set_shader_parameter("grout_color_gain", preset.get("grout_color_gain",Vector3.ONE))
	# Deeper ceramic body under a smooth dielectric glaze, without tinting the
	# reflected light or adding surface noise. Preserve each room's palette.
	var face_gain: Vector3 = material.get_shader_parameter("face_color_gain")
	var grout_gain: Vector3 = material.get_shader_parameter("grout_color_gain")
	material.set_shader_parameter("face_color_gain", face_gain * 0.68)
	material.set_shader_parameter("grout_color_gain", grout_gain * 0.85)
	material.set_shader_parameter("resolved_shape_strength", 1.0)
	material.set_shader_parameter("bevel_strength", 1.0)

func get_stats() -> Dictionary:
	var pitches := {}
	var dimensions := {}
	for role: String in _materials:
		if role in TILE_ROLES:
			var material := _materials[role] as ShaderMaterial
			var scale: float = material.get_shader_parameter("tile_scale")
			var shape_strength: float = material.get_shader_parameter("face_shape_strength")
			var profile: int = material.get_shader_parameter("face_profile")
			var crown := 0.00030 if profile == 1 else 0.00005
			var face_gain: Vector3 = material.get_shader_parameter("face_color_gain")
			var grout_gain: Vector3 = material.get_shader_parameter("grout_color_gain")
			pitches[role] = 0.1*scale
			dimensions[role] = {"tile_scale":scale, "tile_pitch_metres":0.1*scale, "repeat_metres":0.8*scale,
				"grout_width_metres":0.0018*scale, "bevel_width_metres":0.0006*scale,
				"joint_relief_metres":0.00028*scale, "crown_metres":crown*scale*shape_strength,
				"face_profile":profile, "crown_radius_metres":0.04*scale if profile == 1 else 0.0,
				"face_color_gain":[face_gain.x,face_gain.y,face_gain.z], "grout_color_gain":[grout_gain.x,grout_gain.y,grout_gain.z],
				"face_roughness":material.get_shader_parameter("face_roughness"),
				"face_shape_strength":shape_strength, "centre_tilt_limit_degrees_per_axis":rad_to_deg(atan(tan(deg_to_rad(0.35))*shape_strength))}
	return {"materials": _materials.size(), "roles": _materials.keys(), "rt_requested": _rt_enabled,
		"variant": _variant, "base_tile_pitch_metres": 0.1, "tile_pitch_metres_by_role": pitches, "scope": "reference_wing_only",
		"physical_dimensions_by_role":dimensions,
		"visual_acceptance": false}
