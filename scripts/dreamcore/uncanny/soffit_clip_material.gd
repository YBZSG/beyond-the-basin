extends RefCounted
## Pure maker only; never mutates source/cache or other room materials.
static func make(base:StandardMaterial3D,shader:Shader)->ShaderMaterial:
 if base==null or shader==null or base.resource_name not in ["soffit_reservoir_concrete","soffit_reservoir_tile","soffit_reservoir_tile_damp","soffit_reservoir_joint"]:return null
 if base.emission_enabled or base.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or base.shading_mode!=BaseMaterial3D.SHADING_MODE_PER_PIXEL:return null
 var m=ShaderMaterial.new();m.shader=shader;m.resource_name=base.resource_name
 var uniforms={"mapped":base.albedo_texture!=null,"normal_enabled":base.normal_enabled,"ao_enabled":base.ao_enabled,"base_map":base.albedo_texture,"normal_map":base.normal_texture,"orm_map":base.roughness_texture,"uv_scale":base.uv1_scale,"uv_offset":base.uv1_offset,"base_color":base.albedo_color,"base_roughness":base.roughness,"base_metallic":base.metallic,"base_specular":base.metallic_specular,"normal_strength":base.normal_scale,"ao_light_affect":base.ao_light_affect,"base_clearcoat":base.clearcoat if base.clearcoat_enabled else 0.,"base_coat_roughness":base.clearcoat_roughness}
 for key:String in uniforms:m.set_shader_parameter(key,uniforms[key])
 m.set_meta("soffit_clip_only",true);return m

static func install(room:Node3D,shader:Shader)->void:
 var clones={}
 for child:Node in room.get_children():
  if not (child is MeshInstance3D) or child.mesh==null:continue
  var base:StandardMaterial3D=child.material_override as StandardMaterial3D
  if base==null or base.resource_name not in ["soffit_reservoir_concrete","soffit_reservoir_tile","soffit_reservoir_tile_damp","soffit_reservoir_joint"]:continue
  var crosses_plane=false
  for surface:int in child.mesh.get_surface_count():
   var vertices:PackedVector3Array=child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
   for vertex:Vector3 in vertices:
    if (child.global_transform*vertex).y<.318:crosses_plane=true;break
   if crosses_plane:break
  if not crosses_plane:continue
  var identity:int=base.get_instance_id()
  if not clones.has(identity):clones[identity]=make(base,shader)
  if clones[identity]!=null:child.material_override=clones[identity]
