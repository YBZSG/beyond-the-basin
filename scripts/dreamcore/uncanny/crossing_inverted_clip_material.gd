extends RefCounted
## Pure, bounded material maker/installer. Never writes shared G._mats or caches.
## Clones live only on their owning room meshes and are released with those nodes.
const OWNED={"crossing_channels":["crossing_channels_concrete","crossing_channels_basin_tile","crossing_channels_tile"],"inverted_pool":["inverted_pool_basin_tile","inverted_pool_tile","inverted_pool_pier_tile","inverted_pool_blue"]}
const SHADER_SHA256="47dd052017699c110bb6907691395f81850e6238a37c8ef3fd71edddbf3c3d1d"
const COPIED_FIELDS=["resource_name","resource_local_to_scene","render_priority","next_pass","albedo_color","albedo_texture","normal_enabled","normal_texture","normal_scale","roughness","roughness_texture","roughness_texture_channel","metallic","metallic_specular","ao_enabled","ao_light_affect","ao_texture","ao_texture_channel","uv1_scale","uv1_offset","texture_filter"]
const PARAM_FIELDS={"base_albedo":"albedo_texture","base_normal":"normal_texture","base_orm":"roughness_texture","base_tint":"albedo_color","base_uv_scale":"uv1_scale","base_uv_offset":"uv1_offset","base_normal_strength":"normal_scale","base_roughness":"roughness","base_metallic":"metallic","base_specular":"metallic_specular","base_ao_light_affect":"ao_light_affect"}
static func compatibility(base:StandardMaterial3D,owner:String,shader:Shader)->Dictionary:
 if base==null or not OWNED.has(owner) or base.resource_name not in OWNED[owner]:return {"passed":false,"reason":"null or unowned material","default_fields_checked":0}
 if shader==null or shader.code.sha256_text()!=SHADER_SHA256:return {"passed":false,"reason":"unowned shader code","default_fields_checked":0}
 if base.next_pass!=null:return {"passed":false,"reason":"unsupported next_pass; original retained","default_fields_checked":0}
 if base.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or base.emission_enabled:return {"passed":false,"reason":"nonopaque or emissive base","default_fields_checked":0}
 if base.albedo_texture==null or not base.normal_enabled or base.normal_texture==null or base.roughness_texture==null:return {"passed":false,"reason":"missing mapped PBR/normal","default_fields_checked":0}
 if not base.ao_enabled or base.ao_texture!=base.roughness_texture or base.metallic_texture!=null:return {"passed":false,"reason":"unsupported AO/metal texture binding","default_fields_checked":0}
 if base.roughness_texture_channel!=BaseMaterial3D.TEXTURE_CHANNEL_GREEN or base.ao_texture_channel!=BaseMaterial3D.TEXTURE_CHANNEL_RED:return {"passed":false,"reason":"unsupported ORM channels","default_fields_checked":0}
 if base.texture_filter!=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:return {"passed":false,"reason":"unsupported sampler filter","default_fields_checked":0}
 # Every nontranslated stored rendering feature must still match the actual
 # engine StandardMaterial default. This includes cull/depth/blend/repeat,
 # AO-UV2/triplanar, vertex color, fog/shadows, coats, detail and normal modes.
 # Metadata/resource identity is not shader behavior. Never approximate a new
 # material feature silently; decline wrapping and retain the original material.
 var defaults=StandardMaterial3D.new();var default_fields:int=0
 for property:Dictionary in base.get_property_list():
  var name:String=str(property.name)
  if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0 or name in COPIED_FIELDS or name.begins_with("metadata/"):continue
  if base.get(name)!=defaults.get(name):return {"passed":false,"reason":"unsupported nondefault feature: "+name,"default_fields_checked":default_fields}
  default_fields+=1
 return {"passed":true,"reason":"","default_fields_checked":default_fields}
static func make(base:StandardMaterial3D,owner:String,shader:Shader)->ShaderMaterial:
 var guard:Dictionary=compatibility(base,owner,shader)
 if not guard.passed:return null
 var material=ShaderMaterial.new();material.shader=shader;material.resource_name=base.resource_name
 material.resource_local_to_scene=base.resource_local_to_scene;material.render_priority=base.render_priority;material.next_pass=base.next_pass
 for parameter:String in PARAM_FIELDS:material.set_shader_parameter(parameter,base.get(PARAM_FIELDS[parameter]))
 material.set_meta("crossing_inverted_clip_owner",owner);material.set_meta("crossing_inverted_clip_base",base);material.set_meta("crossing_inverted_clip_default_fields_checked",guard.default_fields_checked)
 return material
static func owned_clone(material:Material,owner:String)->bool:
 if not material is ShaderMaterial or str(material.get_meta("crossing_inverted_clip_owner",""))!=owner:return false
 var base:StandardMaterial3D=material.get_meta("crossing_inverted_clip_base",null) as StandardMaterial3D
 return base!=null and OWNED.has(owner) and base.resource_name in OWNED[owner] and material.shader.code.sha256_text()==SHADER_SHA256
static func has_below_plane(node:MeshInstance3D)->bool:
 if node.mesh==null:return false
 for surface in node.mesh.get_surface_count():
  for vertex:Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
   if (node.global_transform*vertex).y<.318:return true
 return false
static func install(room:Node3D,owner:String,shader:Shader)->Dictionary:
 var counts={"installed":0,"already_owned":0,"rejected":0,"untouched":0};var clones:Dictionary={}
 # Seed from already installed live room owners, so shell/detail and repeated
 # installs share the same clone without retaining any static material cache.
 for child:Node in room.get_children():
  if child is MeshInstance3D and owned_clone(child.material_override,owner):
   var base:StandardMaterial3D=child.material_override.get_meta("crossing_inverted_clip_base");clones[base.get_instance_id()]=child.material_override
 for child:Node in room.get_children():
  if not child is MeshInstance3D:continue
  if owned_clone(child.material_override,owner):counts.already_owned+=1;continue
  var base:StandardMaterial3D=child.material_override as StandardMaterial3D
  if base==null or not OWNED.has(owner) or base.resource_name not in OWNED[owner] or not has_below_plane(child):counts.untouched+=1;continue
  var identity:int=base.get_instance_id()
  if not clones.has(identity):clones[identity]=make(base,owner,shader)
  if clones[identity]==null:
   counts.rejected+=1;push_error("Owned clip receiver rejected: "+str(compatibility(base,owner,shader).reason));continue
  child.material_override=clones[identity];counts.installed+=1
 return counts
static func describe_binding(material:ShaderMaterial)->Dictionary:
 var base:StandardMaterial3D=material.get_meta("crossing_inverted_clip_base",null) as StandardMaterial3D
 var owner:String=str(material.get_meta("crossing_inverted_clip_owner",""));var exact:bool=owned_clone(material,owner) and base!=null;var values:Dictionary={}
 if not exact:return {"parameter_identity_verified":false}
 for parameter:String in PARAM_FIELDS:
  var value:Variant=material.get_shader_parameter(parameter);exact=exact and value==base.get(PARAM_FIELDS[parameter])
  if value is Texture2D:values[parameter]={"resource_path":value.resource_path,"file_sha256":FileAccess.get_sha256(value.resource_path)}
  elif value is Vector3:values[parameter]=[value.x,value.y,value.z]
  elif value is Color:values[parameter]=[value.r,value.g,value.b,value.a]
  else:values[parameter]=value
 exact=exact and material.render_priority==base.render_priority and material.next_pass==base.next_pass and material.resource_local_to_scene==base.resource_local_to_scene
 return {"owner":owner,"base_key":base.resource_name,"shader_path":material.shader.resource_path,"shader_code_sha256":material.shader.code.sha256_text(),"marker":524288,"discard_world_y_below":.318,"main_view_retained":true,"parameters":values,"render_priority":material.render_priority,"next_pass_is_null":material.next_pass==null,"resource_local_to_scene":material.resource_local_to_scene,"default_features_checked":material.get_meta("crossing_inverted_clip_default_fields_checked"),"parameter_identity_verified":exact}
