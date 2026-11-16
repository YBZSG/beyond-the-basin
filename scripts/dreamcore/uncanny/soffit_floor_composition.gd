extends Node
## EXTERNAL proposal: compose exact promoted clip receivers, not G._mats.
## No process, source solver, clock, capture, atlas allocation or asset import.
const CLIP_SHADER=preload("res://shaders/dreamcore/uncanny/soffit_clip_base.gdshader")
const SOURCE_LIBRARY=preload("res://scripts/rendering/pool_materials.gd")
# In-memory resource code guards, not runtime raw-file/PCK reads. A later
# shader/aging edit must receive a new explicit review, never lose extra fields.
const BASE_SHADER_SHA256="952edfac991c573823184ea07aae753a79d8319a13bb21913fdd089e4eebcfbd"
const COMPOSED_SHADER_SHA256="336b04480dfed94fc3ac82c2ed1ee2a65f9019d53dc83f5131d6611b2bc9b0e0"
const BASE_FIELDS=["mapped","normal_enabled","ao_enabled","base_map","normal_map","orm_map","uv_scale","uv_offset","base_color","base_roughness","base_metallic","base_specular","normal_strength","ao_light_affect","base_clearcoat","base_coat_roughness"]
var owned:Array[ShaderMaterial]=[]
var _base_clones:Dictionary={}
var _closed:bool=false
var _library_ref:WeakRef
static func supports_library(library:RefCounted)->bool:
 # Exact actual implementation also guarantees the typed weak registry. Do not
 # call an arbitrary duck-typed get_material or read its private fields.
 return library!=null and library.get_script()==SOURCE_LIBRARY
static func is_composed_shader(shader:Shader)->bool:
 return shader!=null and shader.code.sha256_text()==COMPOSED_SHADER_SHA256
static func is_current_clip_tile(material:Material)->bool:
 if not(material is ShaderMaterial):return false
 var source:ShaderMaterial=material
 return source.resource_name=="soffit_reservoir_tile" and source.shader==CLIP_SHADER and source.shader.code.sha256_text()==BASE_SHADER_SHA256 and bool(source.get_meta("soffit_clip_only",false))
static func is_wet_floor_mesh(child:MeshInstance3D)->bool:
 if child==null or child.mesh==null or not is_current_clip_tile(child.material_override):return false
 var normal_basis:Basis=child.global_transform.basis.inverse().transposed()
 var plane:float=PackedFloat32Array([.32])[0];var bed:float=PackedFloat32Array([.1199])[0];var edge:float=PackedFloat32Array([37.2])[0]
 # Current actual source inventory independently clips every upward triangle:
 # nine positive-area batches, including the Y=.26 step. This predicate must be
 # retested if geometry changes; it is not a general arbitrary-mesh intersection.
 for surface:int in child.mesh.get_surface_count():
  var arrays=child.mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  for index in vertices.size():
   var p:Vector3=child.global_transform*vertices[index];var n:Vector3=(normal_basis*normals[index]).normalized()
   if n.y>.5 and p.y>=bed and p.y<plane and p.x>=-edge and p.x<=edge and p.z>=-54. and p.z<=-2.:return true
 return false
static func compose(base:ShaderMaterial,shader:Shader)->ShaderMaterial:
 if not is_current_clip_tile(base) or not is_composed_shader(shader):return null
 var values={}
 for field:String in BASE_FIELDS:
  var value:Variant=base.get_shader_parameter(field)
  if value==null and field not in ["base_map","normal_map","orm_map"]:return null
  values[field]=value
 var local:ShaderMaterial=base.duplicate(false) as ShaderMaterial
 local.shader=shader
 for field:String in values:local.set_shader_parameter(field,values[field])
 local.render_priority=base.render_priority;local.next_pass=base.next_pass
 local.set_meta("soffit_scene_owned_receiver",true);local.set_meta("soffit_floor_composed_from_current_clip",true)
 local.set_shader_parameter("causticGain",0.);local.set_shader_parameter("poolCaustics",null);local.set_shader_parameter("poolCausticsWalls",null)
 return local
func configure(room:Node3D,library:RefCounted,scene_id:String,shader:Shader)->bool:
 if _closed or scene_id!="soffit_reservoir" or room==null or not supports_library(library) or not is_composed_shader(shader):return false
 if _library_ref!=null and _library_ref.get_ref()!=library:return false
 var source:ShaderMaterial=library.get_material("formal_basin") as ShaderMaterial
 if source==null:return false
 _library_ref=weakref(library)
 # Deliberately rescan each build phase. Existing owned instances are skipped;
 # newly clipped detail materials are discovered without a one-frame delay.
 for child:Node in room.get_children():
  if not(child is MeshInstance3D) or not(child.material_override is ShaderMaterial):continue
  var current:ShaderMaterial=child.material_override
  if current in owned or not is_wet_floor_mesh(child):continue
  var base:ShaderMaterial=child.material_override;var identity:int=base.get_instance_id()
  if not _base_clones.has(identity):
   var local=compose(base,shader)
   if local==null:continue
   library.register_local_receiver(local,source)
   var gain:Variant=local.get_shader_parameter("causticGain")
   if source.get_shader_parameter("poolCaustics")==null or typeof(gain) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(gain)) or float(gain)<0. or float(gain)>3.:local.set_shader_parameter("causticGain",0.)
   _base_clones[identity]=local;owned.append(local)
  child.material_override=_base_clones[identity]
 return not owned.is_empty()
func detach()->void:
 if _closed:return
 _closed=true
 # Existing library has weak registration but no unregister method. Remove
 # only own identities before nulling aliases; never clear a foreign registry.
 var library:RefCounted=_library_ref.get_ref() as RefCounted if _library_ref!=null else null
 if supports_library(library):
  for index in range(library._local_receiver_refs.size()-1,-1,-1):
   if library._local_receiver_refs[index].get_ref() in owned:library._local_receiver_refs.remove_at(index)
 _library_ref=null
 for material:ShaderMaterial in owned:
  material.set_shader_parameter("causticGain",0.);material.set_shader_parameter("poolCaustics",null);material.set_shader_parameter("poolCausticsWalls",null)
 owned.clear();_base_clones.clear()
func _exit_tree()->void:detach()
