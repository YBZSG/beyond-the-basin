extends SceneTree
## CPU preparation of bounded causal bake controls. Never launches a renderer
## and never replaces the preserved failed full-hall study.
const Materials=preload("res://scripts/rendering/pool_materials.gd")
const Lighting=preload("res://scripts/rendering/pool_lighting.gd")
const Catalog=preload("res://scripts/world/formal_rooms.gd")
var reports:Array[Dictionary]=[]
func _initialize()->void:_run.call_deferred()
func _run()->void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/lighting/tiny_diagnostic"))
 for authored in [false,true]:
  for denoise in [false,true]:_prepare(authored,denoise)
 var file:=FileAccess.open("res://docs/verification/eight-hour/material-lighting/tiny-lightmap-preparation.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify({"scope":"CPU preparation only. All four variants remain unbaked.","variants":reports},"  ")+"\n")
 print("TINY_LIGHTMAP_PREPARATION ",JSON.stringify(reports));quit()
func _prepare(authored:bool,denoise:bool)->void:
 var stem:="tiny_%s_%s"%["authored" if authored else "standard","denoised" if denoise else "raw"]
 var scene:=Node3D.new();scene.name=stem;root.add_child(scene)
 var materials:=Materials.new()
 for material in materials._materials.values():
  if material is ShaderMaterial:
   material.set_shader_parameter("causticGain",0.0)
   if material.shader==Materials.CERAMIC_SHADER:material.set_shader_parameter("planar_clip_enabled",false)
 var hints:=0
 var specifications=[
  ["Floor",Vector3(0,.42,0),Vector3(4,.2,4),"formal_dry_deck"],
  ["West",Vector3(-2.1,1.82,0),Vector3(.2,2.6,4.4),"formal_wainscot"],
  ["North",Vector3(0,1.82,-2.1),Vector3(4,.2,4),"formal_plaster"],
  ["RoofWest",Vector3(-1.5,3.22,0),Vector3(1.0,.2,4.4),"formal_plaster"],
  ["RoofEast",Vector3(1.5,3.22,0),Vector3(1.0,.2,4.4),"formal_plaster"]]
 # North is a vertical wall; keep the table's named dimensions explicit.
 specifications[2][2]=Vector3(4,2.6,.2)
 for spec:Array in specifications:
  var mesh:=BoxMesh.new();mesh.size=spec[2]
  var array:=ArrayMesh.new();array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.get_mesh_arrays())
  var instance:=MeshInstance3D.new();instance.name=spec[0];instance.position=spec[1];instance.gi_mode=GeometryInstance3D.GI_MODE_STATIC;scene.add_child(instance)
  var original:Material=materials.get_material(spec[3])
  var chosen:Material=original
  if not authored:
   var standard:=StandardMaterial3D.new()
   standard.albedo_color=original.get_shader_parameter("pigment")
   standard.roughness=.8;chosen=standard
  array.surface_set_material(0,chosen)
  assert(array.lightmap_unwrap(instance.global_transform,.25)==OK)
  instance.mesh=array;hints+=array.lightmap_size_hint.x*array.lightmap_size_hint.y
 var environment:=WorldEnvironment.new();environment.name="Environment";scene.add_child(environment)
 var lighting:=Lighting.new();lighting.configure_environment(environment)
 lighting.update_active_room(Vector2i(-1,-1),Catalog.layout(Vector2i(-1,-1),250821));lighting._mood_tween.custom_step(2)
 environment.environment.sdfgi_enabled=false;environment.environment.ssil_enabled=false;environment.environment.volumetric_fog_enabled=false
 var map:=LightmapGI.new();map.name="Bake_Tiny";scene.add_child(map)
 map.quality=LightmapGI.BAKE_QUALITY_LOW;map.bounces=2;map.directional=true;map.use_denoiser=denoise
 # Engine minimum is 2048; this is an upper bound, not a forced allocation.
 # The actual packed atlas is driven by just 4,052 native hinted pixels.
 map.denoiser_strength=.1;map.denoiser_range=10;map.max_texture_size=2048
 map.environment_mode=LightmapGI.ENVIRONMENT_MODE_CUSTOM_SKY;map.environment_custom_sky=environment.environment.sky;map.environment_custom_energy=1
 map.generate_probes_subdiv=LightmapGI.GENERATE_PROBES_DISABLED
 for at:Vector3 in [Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(0,1,1),Vector3(0,2.5,0)]:
  var probe:=LightmapProbe.new();probe.position=at;scene.add_child(probe)
 var data_path:="res://assets/lighting/tiny_diagnostic/"+stem+".lmbake"
 assert(not FileAccess.file_exists(data_path),"Refusing to overwrite an existing tiny bake: "+data_path)
 map.light_data=LightmapGIData.new();assert(ResourceSaver.save(map.light_data,data_path)==OK);map.light_data.take_over_path(data_path)
 var camera:=Camera3D.new();camera.name="Camera";camera.position=Vector3(4,3,5);camera.cull_mask=1;camera.current=true;scene.add_child(camera);camera.look_at(Vector3(0,1.4,0))
 _own(scene,scene)
 var packed:=PackedScene.new();assert(packed.pack(scene)==OK)
 var path:="res://scenes/lighting_lab/"+stem+".tscn";assert(ResourceSaver.save(packed,path)==OK)
 reports.append({"scene":path,"data":data_path,"authored_materials":authored,"denoiser":denoise,"receivers":5,"triangles":60,"hint_pixels":hints,"native_bake_run":false})
 scene.free()
func _own(node:Node,owner_node:Node)->void:
 for child in node.get_children():child.owner=owner_node;_own(child,owner_node)
