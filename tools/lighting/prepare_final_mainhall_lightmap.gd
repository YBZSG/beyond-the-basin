extends SceneTree
## CPU-only preparation of the final-geometry hall. Quarantined and never
## selected by runtime builders. Does not overwrite any populated native bake.
const Builder=preload("res://scripts/world/formal_room_builder.gd")
const Catalog=preload("res://scripts/world/formal_rooms.gd")
const Materials=preload("res://scripts/rendering/pool_materials.gd")
const Lighting=preload("res://scripts/rendering/pool_lighting.gd")
const Adapter=preload("res://tools/lighting/bake_material_adapter.gd")
const Identity=preload("res://tools/lighting/bake_geometry_identity.gd")
const PackedAttributes=preload("res://tools/lighting/preserve_packed_mesh_attributes.gd")
const SOURCE="res://assets/models/formal/formal_mainhall.glb"
const SOURCE_HASH="3d4089cf0fb3a265765f923d445369a4c086727b782bbbba58c3569c61564bf1"
const OUTPUT="res://scenes/lighting_lab/final_mainhall_native.tscn"
const DATA="res://assets/lighting/final_mainhall/native_indirect.lmbake"
const MANIFEST="res://assets/lighting/final_mainhall/preparation_manifest.json"
var errors:Array[String]=[]
var rows:Array[Dictionary]=[]
func _initialize()->void:_run.call_deferred()
func _run()->void:
 if FileAccess.get_sha256(SOURCE)!=SOURCE_HASH:push_error("Final geometry changed; explicitly review the source checkpoint before preparing another bake.");quit(2);return
 if FileAccess.file_exists(DATA):
  var existing:=load(DATA) as LightmapGIData
  if existing and existing.get_user_count()>0:push_error("Refusing to overwrite populated native bake data.");quit(2);return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA.get_base_dir()))
 var scene:=Node3D.new();scene.name="FinalMainhallLightingStudy";root.add_child(scene)
 var layout:Dictionary=Catalog.layout(Vector2i(-1,-1),250821)
 var library:=Materials.new();var builder=Builder.new(scene,layout,library);builder.build_shell()
 var architecture:=scene.get_node("FormalAuthoredArchitecture") as Node3D
 architecture.scene_file_path=""
 var collision:=scene.get_node("ArchitectureCollision");scene.remove_child(collision);collision.free()
 var roles_by_id:Dictionary={}
 for key:String in library._materials:roles_by_id[library._materials[key].get_instance_id()]=key
 var baked_by_role:Dictionary={};var static_count:=0;var metal_count:=0;var glass_count:=0;var hint_pixels:=0
 for mesh:MeshInstance3D in architecture.find_children("*","MeshInstance3D",true,false):
  if String(mesh.name).begins_with("COLLISION_"):
   mesh.get_parent().remove_child(mesh);mesh.free();continue
  var original:Dictionary=Identity.inspect(mesh)
  var roles:=PackedStringArray()
  for surface in mesh.mesh.get_surface_count():
   var live:=mesh.get_active_material(surface)
   var role:String=roles_by_id.get(live.get_instance_id(),"")
   if role.is_empty():errors.append("Unknown live material role on "+str(mesh.name));continue
   roles.append(role)
   if not baked_by_role.has(role):baked_by_role[role]=Adapter.make_bake_material(live)
   if baked_by_role[role]==null:errors.append("Unsupported bake material: "+role);continue
   mesh.set_surface_override_material(surface,baked_by_role[role])
  mesh.set_meta("formal_live_material_roles",roles)
  var classification:="static_architecture"
  if mesh.get_meta("source_transmissive",false):
   mesh.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;classification="transmissive_glazing";glass_count+=1
  elif "brushed stainless" in roles or "chrome" in roles:
   mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;classification="dynamic_metal";metal_count+=1
  else:
   var copy:=ArrayMesh.new()
   for surface in mesh.mesh.get_surface_count():copy.add_surface_from_arrays(mesh.mesh.surface_get_primitive_type(surface),mesh.mesh.surface_get_arrays(surface))
   var unwrap_error:=copy.lightmap_unwrap(mesh.global_transform,.18)
   if unwrap_error!=OK:errors.append("Native unwrap failed: "+str(mesh.name));continue
   var restored:Dictionary=PackedAttributes.apply_native_uv2(mesh.mesh,copy)
   if not restored.errors.is_empty():errors.append(str(mesh.name)+" packed restoration failed: "+str(restored.errors));continue
   mesh.mesh=restored.mesh;mesh.set_meta("bake_uv2_quantization_error",restored.max_uv2_quantization_error);mesh.gi_mode=GeometryInstance3D.GI_MODE_STATIC
   static_count+=1;hint_pixels+=copy.lightmap_size_hint.x*copy.lightmap_size_hint.y
  var baked:Dictionary=Identity.inspect(mesh)
  var differences:=Identity.compare(original,baked)
  if not differences.is_empty():errors.append(str(mesh.name)+" strict geometry/attributes changed: "+str(differences))
  if classification=="static_architecture" and (baked.uv2_outside_unit_square!=0 or baked.lightmap_size_hint[0]<=0 or baked.lightmap_size_hint[1]<=0):errors.append(str(mesh.name)+" has invalid native UV2/hint")
  rows.append({"path":str(scene.get_path_to(mesh)),"live_material_roles":Array(roles),"classification":classification,"original":original,"native":baked,"exact_identity":differences.is_empty(),"cast_shadow":mesh.cast_shadow,"layers":mesh.layers,"visible":mesh.visible,"source_transmissive":mesh.get_meta("source_transmissive",false),"uv2_quantization_error":mesh.get_meta("bake_uv2_quantization_error",0.0)})
 if static_count!=147:errors.append("Expected final 147 architectural receivers, found "+str(static_count))
 var world_environment:=WorldEnvironment.new();world_environment.name="LightingEnvironment";scene.add_child(world_environment)
 var lighting:=Lighting.new();lighting.set_formal_physical_sky_enabled(true);lighting.configure_environment(world_environment);lighting.update_active_room(Vector2i(-1,-1),layout);lighting._mood_tween.custom_step(2.0)
 world_environment.environment.sdfgi_enabled=false;world_environment.environment.ssil_enabled=false;world_environment.environment.volumetric_fog_enabled=false
 var sun:=world_environment.get_node("ApertureSun") as DirectionalLight3D;sun.light_bake_mode=Light3D.BAKE_DYNAMIC
 var lightmap:=LightmapGI.new();lightmap.name="Bake_Mainhall_Indirect";scene.add_child(lightmap)
 lightmap.quality=LightmapGI.BAKE_QUALITY_MEDIUM;lightmap.bounces=4;lightmap.directional=true;lightmap.interior=false
 lightmap.environment_mode=LightmapGI.ENVIRONMENT_MODE_CUSTOM_SKY;lightmap.environment_custom_sky=world_environment.environment.sky;lightmap.environment_custom_energy=1.0
 lightmap.generate_probes_subdiv=LightmapGI.GENERATE_PROBES_SUBDIV_8;lightmap.max_texture_size=4096
 # The paired tiny native bake/camera study proves finite SH and smooth
 # radiance with these exact denoiser settings. No exposure/ambient lift.
 lightmap.use_denoiser=true;lightmap.denoiser_strength=.1;lightmap.denoiser_range=10
 lightmap.light_data=LightmapGIData.new()
 var data_error:=ResourceSaver.save(lightmap.light_data,DATA,ResourceSaver.FLAG_CHANGE_PATH)
 if data_error!=OK:errors.append("Could not save empty native data path: "+str(data_error))
 else:lightmap.light_data.take_over_path(DATA)
 for z in [-7.0,0.0,7.0]:
  for x in [-9.0,0.0,9.0]:
   var probe:=LightmapProbe.new();probe.name="DynamicProbe_%s_%s"%[str(x),str(z)];probe.position=Vector3(x,1.6,z);scene.add_child(probe)
 var camera:=Camera3D.new();camera.name="StudyCamera";camera.position=Vector3(0,2.15,8.3);camera.rotation_degrees=Vector3(-2.252,9.051,0);camera.current=true;camera.fov=62;camera.cull_mask=1;scene.add_child(camera)
 _own(scene,scene)
 var save_error:=ERR_INVALID_DATA
 if errors.is_empty():
  var packed:=PackedScene.new();save_error=packed.pack(scene)
  if save_error==OK:save_error=ResourceSaver.save(packed,OUTPUT)
  if save_error!=OK:errors.append("Packed scene save failed: "+str(save_error))
 if errors.is_empty():
  var check_scene:Node3D=ResourceLoader.load(OUTPUT,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate();root.add_child(check_scene)
  for row:Dictionary in rows:
   var reloaded:=check_scene.get_node_or_null(row.path) as MeshInstance3D
   if reloaded==null:errors.append("Saved receiver disappeared: "+row.path);continue
   var mismatch:=Identity.compare(row.native,Identity.inspect(reloaded),true)
   if not mismatch.is_empty():errors.append(row.path+" saved attributes/UV2 changed: "+str(mismatch))
   if Array(reloaded.get_meta("formal_live_material_roles",PackedStringArray()))!=row.live_material_roles:errors.append("Saved live role mapping changed: "+row.path)
  if not check_scene.find_children("COLLISION_*","MeshInstance3D",true,false).is_empty():errors.append("Hidden GLB collision proxies resurrected in visual-only study")
  if not check_scene.find_children("*","CollisionObject3D",true,false).is_empty():errors.append("Physics entered visual-only study")
  if check_scene.get_node("Bake_Mainhall_Indirect").light_data.resource_path!=DATA:errors.append("Saved scene changed native data path")
  check_scene.free()
 var hashes:Dictionary={}
 for path:String in [SOURCE,"res://scripts/rendering/pool_materials.gd","res://scripts/rendering/pool_lighting.gd","res://scripts/world/formal_room_builder.gd","res://shaders/ceramic_world.gdshader","res://shaders/source_architecture.gdshader","res://shaders/source_water/caustic_receiver.gdshaderinc","res://tools/lighting/bake_material_adapter.gd","res://tools/lighting/prepare_final_mainhall_lightmap.gd","res://tools/lighting/preserve_packed_mesh_attributes.gd","res://tools/lighting/bake_geometry_identity.gd"]:hashes[path]=FileAccess.get_sha256(path)
 var report={"pass":errors.is_empty(),"errors":errors,"status":"prepared_unbaked_quarantined","godot":Engine.get_version_info().string,"source_glb":SOURCE,"source_sha256":SOURCE_HASH,"input_sha256":hashes,"scene":OUTPUT,"scene_sha256":FileAccess.get_sha256(OUTPUT) if FileAccess.file_exists(OUTPUT) else "","data":DATA,"visible_meshes":rows.size(),"static_receivers":static_count,"dynamic_metals":metal_count,"transmissive_glazing":glass_count,"lightmap_hint_pixels":hint_pixels,"visible_meshes_expected":223,"max_atlas_dimension":4096,"quality_sample_counts":_quality_sample_counts(),"texel_size_metres":.18,"quality":"medium","bounces":4,"directional":true,"denoiser":true,"denoiser_strength":.1,"denoiser_range":10,"sky_type":"PhysicalSkyMaterial","sky_material_energy":Lighting.FORMAL_PHYSICAL_SKY_ENERGY,"sun_bake_mode":"dynamic_indirect_only","sky_energy":1.0,"native_bake_run":false,"runtime_integrated":false,"lod_policy":"Native-UV2 receivers use full original-detail triangles, not original lower-detail indices","source_optics_runtime_queries_tested":false,"receivers":rows}
 var file:=FileAccess.open(MANIFEST,FileAccess.WRITE);if file:file.store_string(JSON.stringify(report,"  ")+"\n")
 var evidence:=FileAccess.open("res://docs/verification/eight-hour/material-lighting/final-mainhall-preparation.json",FileAccess.WRITE);if evidence:evidence.store_string(JSON.stringify(report,"  ")+"\n")
 print("FINAL_MAINHALL_PREPARATION ",JSON.stringify({"pass":report.pass,"errors":errors,"scene":OUTPUT,"manifest":MANIFEST,"static_receivers":static_count,"visible_meshes":rows.size(),"hint_pixels":hint_pixels,"native_bake_run":false,"runtime_integrated":false}))
 scene.free();quit(0 if errors.is_empty() else 1)
func _own(node:Node,scene:Node)->void:
 for child in node.get_children():child.owner=scene;_own(child,scene)

func _quality_sample_counts()->Dictionary:
 var values:Dictionary={}
 for setting:Dictionary in ProjectSettings.get_property_list():
  var key:=str(setting.name)
  if key.begins_with("rendering/lightmapping/") and ("ray_count" in key or "samples" in key):values[key]=ProjectSettings.get_setting(key)
 return values
