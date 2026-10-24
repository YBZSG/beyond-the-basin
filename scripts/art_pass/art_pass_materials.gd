extends RefCounted
## Only new art-pass roles. Existing source/formal materials are never replaced.
const PBR_SHADER: Shader = preload("res://shaders/art_pass_pbr.gdshader")
const ROOT := "res://assets/materials/art_pass/textures/"
const ROLES := {
  "art_pass_tile_blue": {
    "albedo": "tile_blue_albedo_2k.png",
    "normal_gl": "tile_normal_gl_2k.png",
    "orm": "tile_blue_orm_2k.png",
    "repeat_metres": 0.8,
    "normal_strength": 1.0,
    "specular": 0.5
  },
  "art_pass_tile_blue_wet": {
    "albedo": "tile_blue_albedo_2k.png",
    "normal_gl": "tile_normal_gl_2k.png",
    "orm": "tile_blue_wet_orm_2k.png",
    "repeat_metres": 0.8,
    "normal_strength": 0.85,
    "specular": 0.35683669
  },
  "art_pass_tile_pearl": {
    "albedo": "tile_pearl_albedo_2k.png",
    "normal_gl": "tile_normal_gl_2k.png",
    "orm": "tile_pearl_orm_2k.png",
    "repeat_metres": 0.8,
    "normal_strength": 1.0,
    "specular": 0.5
  },
  "art_pass_tile_pearl_wet": {
    "albedo": "tile_pearl_albedo_2k.png",
    "normal_gl": "tile_normal_gl_2k.png",
    "orm": "tile_pearl_wet_orm_2k.png",
    "repeat_metres": 0.8,
    "normal_strength": 0.85,
    "specular": 0.35683669
  },
  "art_pass_plaster_oyster": {
    "albedo": "plaster_oyster_albedo_2k.png",
    "normal_gl": "plaster_normal_gl_2k.png",
    "orm": "plaster_orm_2k.png",
    "repeat_metres": 2.0,
    "normal_strength": 1.0,
    "specular": 0.5
  },
  "art_pass_storage_green": {
    "albedo": "storage_green_albedo_512.png",
    "normal_gl": "storage_normal_gl_512.png",
    "orm": "storage_orm_512.png",
    "repeat_metres": 0.5,
    "normal_strength": 1.0,
    "specular": 0.5
  },
  "art_pass_coping_ivory": {
    "albedo": "coping_ivory_albedo_1k.png",
    "normal_gl": "coping_normal_gl_1k.png",
    "orm": "coping_orm_1k.png",
    "repeat_metres": 1.0,
    "normal_strength": 1.0,
    "specular": 0.5
  },
  "art_pass_coping_ivory_wet": {
    "albedo": "coping_ivory_albedo_1k.png",
    "normal_gl": "coping_normal_gl_1k.png",
    "orm": "coping_wet_orm_1k.png",
    "repeat_metres": 1.0,
    "normal_strength": 1.0,
    "specular": 0.35683669
  },
  "art_pass_steel_brushed": {
    "albedo": "steel_brushed_albedo_512.png",
    "normal_gl": "steel_normal_gl_512.png",
    "orm": "steel_orm_512.png",
    "repeat_metres": 0.25,
    "normal_strength": 1.0,
    "specular": 0.5
  }
}
const SOLID_ROLES := {"art_pass_joint": {"color":"707C77", "roughness":0.85}, "art_pass_inlet_dark": {"color":"25302F", "roughness":0.72}}
# Finite glossy ceramic, with the existing pigment/normal/tile scale untouched.
# The second value is the old authored ORM face baseline, not a grout threshold.
const CERAMIC_FINISH := {
	"art_pass_tile_blue": Vector3(0.105, 0.33, 0.82),
	"art_pass_tile_blue_wet": Vector3(0.085, 0.235, 0.68),
	"art_pass_tile_pearl": Vector3(0.115, 0.52, 0.82),
	"art_pass_tile_pearl_wet": Vector3(0.085, 0.235, 0.68),
	"art_pass_coping_ivory": Vector3(0.12, 0.425, 0.82),
	"art_pass_coping_ivory_wet": Vector3(0.09, 0.27, 0.68),
}
var _materials: Dictionary = {}

func resolve(role: String, material_library: RefCounted) -> ShaderMaterial:
	if not ROLES.has(role) and not SOLID_ROLES.has(role): return null
	if _materials.has(role): return _materials[role]
	var spec: Dictionary = ROLES.get(role,{})
	var material := ShaderMaterial.new()
	material.shader = PBR_SHADER
	material.resource_name = role
	material.set_shader_parameter("glazed_ceramic", CERAMIC_FINISH.has(role))
	if CERAMIC_FINISH.has(role):
		var finish: Vector3 = CERAMIC_FINISH[role]
		material.set_shader_parameter("glaze_roughness", finish.x)
		material.set_shader_parameter("glaze_reference_roughness", finish.y)
		material.set_shader_parameter("grout_roughness", finish.z)
	if SOLID_ROLES.has(role):
		material.set_shader_parameter("mapped", false)
		material.set_shader_parameter("constant_color", Color(SOLID_ROLES[role].color))
		material.set_shader_parameter("constant_roughness", SOLID_ROLES[role].roughness)
	else:
		material.set_shader_parameter("base_color", load(ROOT + spec.albedo))
		material.set_shader_parameter("normal_gl", load(ROOT + spec.normal_gl))
		material.set_shader_parameter("orm", load(ROOT + spec.orm))
		material.set_shader_parameter("repeat_metres", spec.repeat_metres)
		material.set_shader_parameter("normal_strength", spec.normal_strength)
		material.set_shader_parameter("dielectric_specular", spec.specular)
	# Existing library owns atlas updates/domain rebases. Its weak receiver list
	# does not retain a streamed room after the room and this adapter are freed.
	if material_library != null:
		var source: ShaderMaterial = material_library.get_material("formal_basin")
		material_library.register_local_receiver(material, source)
		if source.get_shader_parameter("causticGain") == null:
			material.set_shader_parameter("causticGain", 0.0)
	else:
		material.set_shader_parameter("causticGain", 0.0)
	_materials[role] = material
	return material
