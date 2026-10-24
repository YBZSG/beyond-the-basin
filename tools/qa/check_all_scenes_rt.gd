extends SceneTree
var destination := ""
var mode := "expanded"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--playable-out="): destination=arg.trim_prefix("--playable-out=")
		if arg=="--poolrooms-wing": mode="poolrooms"
	var game=load("res://scenes/main.tscn").instantiate()
	game.qa_capture_hook=_inspect
	root.add_child(game)
func _inspect(game: Node3D) -> int:
	var panel=game.get_node("DesktopQuality")
	panel.set_option("nr",true)
	panel.set_option("dlss","Quality")
	panel.set_option("raytracing",true)
	game.set_menu(false)
	game.player.set_enabled(false)
	# Finish one genuinely new imported room after RT is active, exercising the
	# node-added/material-clone path rather than reusing only startup resources.
	var late_coord:=Vector2i(5,-3)
	for x in range(5,12):
		var candidate:=Vector2i(x,-3)
		if bool(game.world.get_layout(candidate).get("expanded",false)):
			late_coord=candidate
			break
	game.world.ensure_room_ready(late_coord)
	for frame in 60: await process_frame
	print("RT_ENV_ACTUAL ", game.environment.environment.get("pathtracing_enabled"))
	var raster_materials: Array[String]=[]
	var variants: Dictionary={}
	for node in game.world.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree(): continue
		for surface in node.mesh.get_surface_count():
			var material=node.get_active_material(surface)
			var bounds: AABB=node.global_transform*node.mesh.get_aabb()
			if bounds.position.x<0 and bounds.end.x>0 and bounds.position.z<6 and bounds.end.z>6 and bounds.size.y<.5:
				print("FLOOR ",node.name," ",bounds," ",material.resource_name," ", material.get_shader_parameter("glazed_ceramic") if material is ShaderMaterial else "std")
			if material is ShaderMaterial and material.shader:
				var path: String=material.shader.resource_path
				variants[path]=int(variants.get(path,0))+1
				if path in ["res://shaders/art_pass_pbr.gdshader","res://shaders/ceramic_world.gdshader","res://shaders/source_architecture.gdshader","res://shaders/pc_source_ceramic.gdshader"]: raster_materials.append(path)
	# Only a diagnostic subject is added. The reflecting dry ceramic floor is
	# the actual production geometry/material, above the .32m water level.
	var x:=7.0 if mode=="poolrooms" else 0.0
	var subject:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(1.2,1.4,1.2)
	subject.mesh=mesh
	subject.gi_mode=GeometryInstance3D.GI_MODE_STATIC
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/source_architecture_rt.gdshader")
	material.set_shader_parameter("pigment",Color(0.95,0.25,0.025))
	material.set_shader_parameter("roughness_value",.32)
	material.set_shader_parameter("light_emission",Vector3(.95,.25,.025))
	material.set_shader_parameter("light_energy",.3)
	subject.material_override=material
	subject.position=Vector3(x,1.22,4.2)
	game.add_child(subject)
	game.player.warp_to(Vector3(x+2.0,-.55,8.0),Vector3(x,.7,4.2))
	for frame in 180: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/dry-tile-reflection.png")
	game.set_menu(true)
	panel.open_panel()
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/settings.png")
	var result={"mode":mode,"rt":panel.raytracing_status,"nr_requested":panel.settings.nr,"fg":panel.settings.frame_generation,"late_room":str(late_coord),"shader_variants":variants,"unconverted_raster_materials":raster_materials,"water_error":game.water.last_error,"reflection_subject":"test-only orange cube; actual production dry tiles at y=.52; water remains y=.32"}
	FileAccess.open(destination+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	return 0 if game.water.last_error.is_empty() and bool(panel.raytracing_status.active) and raster_materials.is_empty() else 1
