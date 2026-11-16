extends RefCounted
## Hollow-local, scene-owned material overrides. Shared cache/resources stay immutable.
## Only the existing mirror marker/world-plane discard differs from Standard PBR.
const SHADER=preload("res://shaders/dreamcore/uncanny/hollow_visage_tile_receiver.gdshader")
const MATERIAL_KEYS=["hollow_visage_tile","hollow_visage_pool_tile"]
static func apply_chunk(chunk:Node3D)->int:
 var changed=0
 for child:Node in chunk.get_children():
  if not child is MeshInstance3D or not child.material_override is StandardMaterial3D:continue
  var source:StandardMaterial3D=child.material_override
  if not str(source.resource_name) in MATERIAL_KEYS:continue
  child.material_override=_from_standard(source);changed+=1
 return changed
static func _from_standard(source:StandardMaterial3D)->ShaderMaterial:
 var material=ShaderMaterial.new();material.shader=SHADER
 material.resource_name=source.resource_name;material.render_priority=source.render_priority;material.next_pass=source.next_pass
 var values={"albedo":source.albedo_color,"texture_albedo":source.albedo_texture,"roughness":source.roughness,"texture_metallic":source.metallic_texture,"metallic_texture_channel":Vector4(0,0,1,0),"texture_roughness":source.roughness_texture,"specular":source.metallic_specular,"metallic":source.metallic,"texture_normal":source.normal_texture,"normal_scale":source.normal_scale,"texture_ambient_occlusion":source.ao_texture,"ao_texture_channel":Vector4(1,0,0,0),"ao_light_affect":source.ao_light_affect,"uv1_scale":source.uv1_scale,"uv1_offset":source.uv1_offset,"uv2_scale":source.uv2_scale,"uv2_offset":source.uv2_offset}
 for key:String in values:material.set_shader_parameter(key,values[key])
 for key:StringName in source.get_meta_list():material.set_meta(key,source.get_meta(key))
 material.set_meta("hollow_planar_receiver",true)
 return material
