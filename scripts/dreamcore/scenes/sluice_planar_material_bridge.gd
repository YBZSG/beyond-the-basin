extends RefCounted
## Sluice-only caller hook. No mutation of outdoor/Meadow global materials.
const G=preload("res://scripts/dreamcore/scenes/outdoor_geometry.gd")
const Meadow=preload("res://scripts/dreamcore/scenes/wind_meadow.gd")
const OriginalShader=preload("res://assets/dreamcore/outdoor/weathered.gdshader")
const ClipShader=preload("res://assets/dreamcore/outdoor/sluice_weathered_planar_clip.gdshader")
const SOURCE_SHA="ecea55a1bb85c263dd768d8df6fc105a5a83be64a5ef4d791281d3bb771c001e"
const CLIP_SHA="36a3cf7d9a521c79d17a18ab28d0d14b67495468284ff33c25800d916ab3cf7f"
const UNIFORMS=["albedo_map","base_color","normal_map","roughness_map","surface_kind","wetness"]
static var _copies:Dictionary={}
static var _original_storage:Dictionary={}
static var _copy_storage:Dictionary={}
static func _storage(material:Material)->Dictionary:
 var result:Dictionary={}
 for property:Dictionary in material.get_property_list():
  if (int(property.usage)&PROPERTY_USAGE_STORAGE)!=0:result[str(property.name)]=material.get(str(property.name))
 return result.duplicate(true)
static func _meshes(root:Node)->Array[MeshInstance3D]:
 var result:Array[MeshInstance3D]=[]
 if root is MeshInstance3D:result.append(root)
 for child:Node in root.get_children():result.append_array(_meshes(child))
 return result
static func _failure(reason:String)->Dictionary:
 return {"accepted":false,"reason":reason,"matched":0,"assigned":0,"material_pairs":[]}
static func _valid_source(source:ShaderMaterial)->bool:
 if source.shader!=OriginalShader or source.get_script()!=null or source.next_pass!=null:return false
 var names:Array=[]
 for property:Dictionary in source.get_property_list():
  if str(property.name).begins_with("shader_parameter/"):names.append(str(property.name).trim_prefix("shader_parameter/"))
 names.sort()
 if names!=UNIFORMS:return false
 for name:String in ["albedo_map","normal_map","roughness_map"]:
  var texture:Variant=source.get_shader_parameter(name)
  if not texture is Texture2D or texture.resource_path.is_empty():return false
 return true
static func apply(root:Node3D)->Dictionary:
 if not is_instance_valid(root):return _failure("invalid_sluice_root")
 if FileAccess.get_sha256(OriginalShader.resource_path)!=SOURCE_SHA or FileAccess.get_sha256(ClipShader.resource_path)!=CLIP_SHA:return _failure("shader_file_hash_mismatch")
 if OriginalShader.code!=FileAccess.get_file_as_string(OriginalShader.resource_path) or ClipShader.code!=FileAccess.get_file_as_string(ClipShader.resource_path):return _failure("shader_memory_differs_from_frozen_file")
 var sources:Array[ShaderMaterial]=[]
 for candidate:Variant in [G.cache.get("tile"),Meadow.materials.get("ground")]:
  if candidate==null:continue
  if not candidate is ShaderMaterial or not _valid_source(candidate):return _failure("actual_source_material_contract_mismatch")
  sources.append(candidate)
 var pending:Array[Dictionary]=[]
 var matched:int=0
 for mesh:MeshInstance3D in _meshes(root):
  var source:ShaderMaterial=null
  for original:ShaderMaterial in sources:
   if mesh.material_override==original or (_copies.has(original) and mesh.material_override==_copies[original]):source=original;break
  if source==null:continue # Not grass blades, other materials, or other scene instances.
  if mesh.material_overlay!=null or mesh.mesh==null:return _failure("receiver_overlay_or_missing_mesh")
  for surface:int in range(mesh.mesh.get_surface_count()):
   if mesh.get_surface_override_material(surface)!=null:return _failure("receiver_surface_override")
  matched+=1
  if _copies.has(source):
   if _storage(source)!=_original_storage[source] or _storage(_copies[source])!=_copy_storage[source]:return _failure("cached_source_or_local_copy_changed")
  else:
   var before:Dictionary=_storage(source)
   var copied:ShaderMaterial=source.duplicate() as ShaderMaterial
   if copied==null or copied==source:return _failure("material_duplicate_failed")
   copied.shader=ClipShader
   var expected:Dictionary=before.duplicate(true);expected.shader=ClipShader
   if _storage(source)!=before or _storage(copied)!=expected:return _failure("copy_changed_nonshader_storage")
   for uniform:String in UNIFORMS:
    if copied.get_shader_parameter(uniform)!=source.get_shader_parameter(uniform):return _failure("copy_changed_uniform")
   _copies[source]=copied;_original_storage[source]=before;_copy_storage[source]=_storage(copied)
  pending.append({"node":mesh,"material":_copies[source]})
 # Preflight all eligible nodes before any scene material assignment.
 var assigned:int=0
 for row:Dictionary in pending:
  if row.node.material_override!=row.material:row.node.material_override=row.material;assigned+=1
 return {"accepted":true,"reason":"","matched":matched,"assigned":assigned,"material_pairs":bindings(root)}
static func bindings(root:Node3D)->Array[Dictionary]:
 ## Inspection-only resource references for coordinator tests; caller must not mutate them.
 var result:Array[Dictionary]=[]
 if not is_instance_valid(root):return result
 var meshes:Array[MeshInstance3D]=_meshes(root)
 for original:ShaderMaterial in _copies:
  var nodes:Array=[]
  for mesh:MeshInstance3D in meshes:
   if mesh.material_override==_copies[original]:nodes.append({"path":str(root.get_path_to(mesh)),"node_id":mesh.get_instance_id()})
  if not nodes.is_empty():result.append({"source":original,"copy":_copies[original],"source_id":original.get_instance_id(),"copy_id":_copies[original].get_instance_id(),"source_name":original.resource_name,"nodes":nodes})
 return result
