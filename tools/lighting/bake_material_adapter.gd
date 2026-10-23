extends RefCounted
## Offline bake inputs only. Never substitute these for the live material
## library in gameplay: the runtime must rebind exact shared caustic receivers.
const CERAMIC="res://shaders/ceramic_world.gdshader"
const PLAIN="res://shaders/source_architecture.gdshader"

static func make_bake_material(live:Material)->Material:
 if live is ShaderMaterial:
  var source:=live as ShaderMaterial
  if source.shader.resource_path==CERAMIC:
   var baked:=source.duplicate(false) as ShaderMaterial
   baked.set_shader_parameter("causticGain",0.0)
   baked.set_shader_parameter("planar_clip_enabled",false)
   baked.resource_name="Bake input / "+live.resource_name
   return baked
  if source.shader.resource_path==PLAIN:
   # Same texture-free PBR inputs, without a camera-dependent discard or
   # disabled dynamic water samplers. The original source shader is untouched.
   var baked:=StandardMaterial3D.new()
   baked.resource_name="Bake input / "+live.resource_name
   baked.albedo_color=_color(source,"pigment",Color(.79,.81,.77,1.0))
   baked.roughness=_scalar(source,"roughness_value",.84)
   baked.metallic=_scalar(source,"metallic_value",0.0)
   baked.metallic_specular=_scalar(source,"specular_value",.5)
   var emission:=_color(source,"light_emission",Color.BLACK)
   var energy:=_scalar(source,"light_energy",0.0)
   baked.emission_enabled=energy>0.0
   baked.emission=emission
   baked.emission_energy_multiplier=energy
   baked.diffuse_mode=BaseMaterial3D.DIFFUSE_BURLEY
   baked.specular_mode=BaseMaterial3D.SPECULAR_SCHLICK_GGX
   baked.cull_mode=BaseMaterial3D.CULL_BACK
   return baked
  push_error("Unsupported bake shader: "+source.shader.resource_path)
  return null
 if live is StandardMaterial3D:return live.duplicate(false) as Material
 push_error("Unsupported bake material type: "+str(live))
 return null

static func _scalar(material:ShaderMaterial,key:String,fallback:float)->float:
 var value=material.get_shader_parameter(key)
 return fallback if value==null else float(value)

static func _color(material:ShaderMaterial,key:String,fallback:Color)->Color:
 var value=material.get_shader_parameter(key)
 if value is Color:return value
 if value is Vector3:return Color(value.x,value.y,value.z,1.0)
 return fallback
