extends SceneTree
## Actual imported five-room surfaces and production RT refresh, without a GPU.
const Catalog=preload("res://scripts/reference_wing/reference_catalog.gd")
const World=preload("res://scripts/reference_wing/reference_world.gd")
const Family=preload("res://scripts/reference_wing/reference_materials.gd")
const Refresh=preload("res://scripts/rendering/rt_material_refresh.gd")
class Host extends Node3D:
	var materials: RefCounted
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host)
	var world:=World.new();host.add_child(world);world.initialize(250821,null);world.complete_pending_streaming()
	var unique:Dictionary={};var surface_roles:Dictionary={};var per_room:Dictionary={}
	for coord:Vector2i in Catalog.COORDS:
		var room:Node=world.resident_rooms[coord];var id:String=world.get_layout(coord).reference_id
		var roles:Dictionary={}
		for child:Node in room.find_children("*","MeshInstance3D",true,false):
			var mesh:=child as MeshInstance3D
			if mesh.name.begins_with("COLLISION_"):
				check(not mesh.visible,id+": collider proxy rendered");continue
			for index in mesh.mesh.get_surface_count():
				var original:Material=mesh.mesh.surface_get_material(index)
				if original==null:continue
				var role:String=original.resource_name.to_lower().get_slice(".",0)
				var applied:Material=mesh.get_active_material(index)
				if role not in Family.TILE_ROLES:continue
				check(applied is ShaderMaterial,id+": imported tile lacks authored shader "+role)
				if not applied is ShaderMaterial:continue
				check(applied.resource_name==role,id+": wrong resolved role "+role)
				check(applied.shader==Family.RASTER_SHADER,id+": unexpected initial shader")
				check(applied.get_shader_parameter("face_profile")==int(role==Family.REF5_CROWN_ROLE),id+": crown profile mismatch")
				check(not(role==Family.REF5_CROWN_ROLE)or id=="stair_gallery",id+": crown escaped reference5")
				roles[role]=int(roles.get(role,0))+1;surface_roles[role]=int(surface_roles.get(role,0))+1
				if not unique.has(applied.get_instance_id()):
					var values:Dictionary={}
					for key:String in ["base_color","bevel_slope","orm","face_shape_strength","face_profile","face_roughness","tile_scale","face_color_gain","grout_color_gain"]:
						values[key]=applied.get_shader_parameter(key)
					unique[applied.get_instance_id()]={"material":applied,"values":values}
		per_room[id]=roles
		check(roles.is_empty()if id=="ball_lounge"else not roles.is_empty(),id+": tiled/untiled role boundary changed")
	check(surface_roles.has(Family.REF5_CROWN_ROLE),"Actual imported stair has no scoped crown surface")
	var refresh:=Refresh.new();refresh.configure(host)
	for enabled:bool in [true,false,true,false]:
		refresh.refresh_all(enabled)
		for record:Dictionary in unique.values():
			var material:ShaderMaterial=record.material
			check(material.shader==(Family.RT_SHADER if enabled else Family.RASTER_SHADER),"Production refresh failed shader pair")
			for key:String in record["values"]:
				check(material.get_shader_parameter(key)==record["values"][key],"Production refresh changed "+key+" in "+material.resource_name)
	check(refresh.get_stats().shader_load_failures==0,"Production refresh shader load failure")
	var report:={"passed":errors.is_empty(),"checks":checks,"errors":errors,"surface_roles":surface_roles,"per_room_roles":per_room,"unique_tile_materials":unique.size(),"refresh":refresh.get_stats(),"scope":"Actual imported GLBs plus production room builder and RT material refresher on Godot4.6.3 headless dummy renderer. Shader frontend/binding only, no GPU RT/NR image or performance proof."}
	var file:=FileAccess.open("res://output/reference_wing/integration/imported-world-materials.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("REFERENCE_IMPORTED_MATERIALS ",checks," checks / ",errors.size()," failures / ",unique.size()," unique tile materials")
	for message:String in errors:push_error(message)
	host.queue_free();await process_frame;quit(0 if errors.is_empty()else 1)
