extends SceneTree
## Isolated, editor-bakeable native LightmapGI study. CPU preparation only.
## This does NOT alter the runtime architecture or enable unvalidated bake data.
## godot --headless --path . --script tools/lighting/prepare_formal_lightmap_lab.gd
const Builder=preload("res://scripts/world/formal_room_builder.gd")
const Catalog=preload("res://scripts/world/formal_rooms.gd")
const Materials=preload("res://scripts/rendering/pool_materials.gd")
const Lighting=preload("res://scripts/rendering/pool_lighting.gd")
const OUTPUT="res://scenes/lighting_lab/formal_mainhall_lightmap_lab.tscn"
var mesh_count:=0
var errors:Array[String]=[]
var hint_pixels:=0
var dynamic_metal_count:=0

func _initialize()->void:
 _run.call_deferred()

func _run()->void:
 var existing_path:="res://assets/lighting/formal_mainhall/study_indirect.lmbake"
 if FileAccess.file_exists(existing_path):
  var existing:=load(existing_path) as LightmapGIData
  if existing and existing.get_user_count()>0:
   push_error("Refusing to overwrite a populated native study, including failed evidence. Prepare a distinct new study path.");quit(2);return
 var scene:=Node3D.new();scene.name="FormalMainhallLightingStudy";root.add_child(scene)
 var layout:Dictionary=Catalog.layout(Catalog.COORDS[0],250821)
 var materials:=Materials.new()
 var builder=Builder.new(scene,layout,materials)
 builder.build_shell()
 # Serialize a standalone mesh scene, not a modified imported instance whose
 # deleted collision children could reappear when the PackedScene reloads.
 scene.get_node("FormalAuthoredArchitecture").scene_file_path=""
 for material in materials._materials.values():
  if material is ShaderMaterial:
   material.set_shader_parameter("causticGain",0.0)
   if material.shader==Materials.CERAMIC_SHADER:material.set_shader_parameter("planar_clip_enabled",false)
 var collisions:=scene.get_node("ArchitectureCollision")
 scene.remove_child(collisions);collisions.free()
 var meshes:=scene.find_children("*","MeshInstance3D",true,false)
 for mesh:MeshInstance3D in meshes:
  if String(mesh.name).begins_with("COLLISION_"):
   mesh.get_parent().remove_child(mesh);mesh.free();continue
  if mesh.get_meta("source_transmissive",false):
   # Editor lightmapper treats alpha as cutout, not a dielectric window.
   # The transmissive pane is retained for actual reflection but excluded GI.
   mesh.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
   continue
  var visible_material:=mesh.get_active_material(0) as ShaderMaterial
  if visible_material and visible_material.get_shader_parameter("metallic_value")!=null and float(visible_material.get_shader_parameter("metallic_value"))>0.9:
   # Thin metallic fittings have negligible diffuse albedo. They receive the
   # study's dynamic probes and real reflections instead of spending UV charts
   # on disconnected grating/fastener faces. Architecture remains fully baked.
   mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
   dynamic_metal_count+=1
   continue
  var copy:=ArrayMesh.new()
  for surface in mesh.mesh.get_surface_count():
   copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.mesh.surface_get_arrays(surface))
   copy.surface_set_material(surface,mesh.get_active_material(surface))
  var result:=copy.lightmap_unwrap(mesh.global_transform,0.18)
  if result!=OK:
   errors.append(str(mesh.name)+": "+str(result));continue
  mesh.mesh=copy
  mesh.gi_mode=GeometryInstance3D.GI_MODE_STATIC
  var hint:=copy.lightmap_size_hint
  hint_pixels+=hint.x*hint.y;mesh_count+=1
  print("LIGHTMAP_UNWRAPPED ",mesh.name," ",hint)
 var environment:=WorldEnvironment.new();environment.name="LightingEnvironment";scene.add_child(environment)
 var lighting:=Lighting.new();lighting.configure_environment(environment)
 lighting.update_active_room(Vector2i(-1,-1),layout);lighting._mood_tween.custom_step(2.0)
 environment.environment.sdfgi_enabled=false
 environment.environment.ssil_enabled=false
 environment.environment.volumetric_fog_enabled=false
 # The study deliberately has no artist fill proxies: sky and directional
 # sun supply diffuse paths. Dynamic bake mode stores INDIRECT sun only.
 var sun:=environment.get_node("ApertureSun") as DirectionalLight3D
 sun.light_bake_mode=Light3D.BAKE_DYNAMIC
 var lightmap:=LightmapGI.new();lightmap.name="Bake_Mainhall_Indirect";scene.add_child(lightmap)
 lightmap.quality=LightmapGI.BAKE_QUALITY_MEDIUM
 lightmap.bounces=4
 lightmap.directional=true
 lightmap.interior=false
 lightmap.environment_mode=LightmapGI.ENVIRONMENT_MODE_CUSTOM_SKY
 lightmap.environment_custom_sky=environment.environment.sky
 lightmap.environment_custom_energy=1.0
 lightmap.generate_probes_subdiv=LightmapGI.GENERATE_PROBES_SUBDIV_8
 lightmap.max_texture_size=4096
 lightmap.use_denoiser=true
 lightmap.denoiser_strength=0.1
 lightmap.light_data=LightmapGIData.new()
 # Seed a real save path so the editor Bake button does not require a dialog.
 var data_error:=ResourceSaver.save(lightmap.light_data,"res://assets/lighting/formal_mainhall/study_indirect.lmbake",ResourceSaver.FLAG_CHANGE_PATH)
 if data_error!=OK:errors.append("Light data resource save: "+str(data_error))
 else:lightmap.light_data.take_over_path("res://assets/lighting/formal_mainhall/study_indirect.lmbake")
 for z in [-7.0,0.0,7.0]:
  for x in [-9.0,0.0,9.0]:
   var probe:=LightmapProbe.new();probe.name="DynamicProbe_%s_%s"%[str(x),str(z)]
   probe.position=Vector3(x,1.6,z);scene.add_child(probe)
 var camera:=Camera3D.new();camera.name="StudyCamera";camera.position=Vector3(0,2.15,8.3)
 camera.rotation_degrees=Vector3(-2.252,9.051,0);camera.current=true;camera.fov=62;camera.cull_mask=1;scene.add_child(camera)
 _own(scene,scene)
 var packed:=PackedScene.new()
 var packed_error:=packed.pack(scene)
 var save_error:=ResourceSaver.save(packed,OUTPUT) if packed_error==OK else packed_error
 var reload:PackedScene=ResourceLoader.load(OUTPUT,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
 var check_scene:Node3D=reload.instantiate() if reload else null
 if check_scene:
  if not check_scene.get_node("Bake_Mainhall_Indirect").light_data.resource_path.ends_with("study_indirect.lmbake"):
   errors.append("Reloaded study does not reference the external baked-data path")
  var collision_nodes:=check_scene.find_children("COLLISION_*","MeshInstance3D",true,false)
  if not collision_nodes.is_empty():errors.append("Reload resurrected "+str(collision_nodes.size())+" hidden collision meshes")
  for receiver:MeshInstance3D in check_scene.find_children("*","MeshInstance3D",true,false):
   for surface in receiver.mesh.get_surface_count():
    var mat:=receiver.get_active_material(surface) as ShaderMaterial
    if mat and not is_zero_approx(float(mat.get_shader_parameter("causticGain"))):
     errors.append("Dynamic water emission is not disabled during bake: "+str(receiver.name))
  check_scene.free()
 else:errors.append("Unable to reload saved native study")
 var report={"mesh_count":mesh_count,"dynamic_metal_count":dynamic_metal_count,"lightmap_hint_pixels":hint_pixels,"texel_size_metres":0.18,"errors":errors,"save_error":save_error,"scene":OUTPUT,"native_bake_run":false,"runtime_integrated":false}
 var file:=FileAccess.open("res://docs/verification/eight-hour/material-lighting/lightmap-preparation.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(report,"  ")+"\n")
 print("LIGHTMAP_LAB_PREPARATION ",JSON.stringify(report))
 scene.free()
 quit(0 if errors.is_empty() and save_error==OK else 1)

func _own(node:Node,scene:Node)->void:
 for child in node.get_children():
  child.owner=scene
  _own(child,scene)
