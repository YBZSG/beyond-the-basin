extends SceneTree
const Transition = preload("res://scripts/campaign/campaign_transition.gd")
func _initialize() -> void: call_deferred("run")
func vec(v: Vector3) -> Array: return [v.x,v.y,v.z]
func transform_rows(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]
func run() -> void:
	var frames := []
	for mode in range(6):
		var stage := Transition.new(); stage.configure(mode); root.add_child(stage)
		for progress in [0.0,0.55,1.0]:
			stage._sample(progress)
			var frame := {"mode":stage.mode_id,"progress":progress,"camera":transform_rows(stage.camera.global_transform),"fov":stage.camera.fov,"meshes":[],"lights":[]}
			for mesh: MeshInstance3D in stage.find_children("*","MeshInstance3D",true,false):
				var mat := mesh.material_override as StandardMaterial3D
				frame.meshes.append({"name":mesh.name,"matrix":transform_rows(mesh.global_transform),"size":vec((mesh.mesh as BoxMesh).size),"color":[mat.albedo_color.r,mat.albedo_color.g,mat.albedo_color.b,1],"roughness":mat.roughness,"metallic":mat.metallic,"emission":mat.emission_energy_multiplier if mat.emission_enabled else 0.0,"albedo_texture":ProjectSettings.globalize_path(mat.albedo_texture.resource_path) if mat.albedo_texture != null else "", "normal_texture":ProjectSettings.globalize_path(mat.normal_texture.resource_path) if mat.normal_texture != null else "", "orm_texture":ProjectSettings.globalize_path(mat.roughness_texture.resource_path) if mat.roughness_texture != null else "", "repeat_metres":float(mat.get_meta("campaign_repeat_metres",1.0)), "normal_strength":mat.normal_scale})
			for light: OmniLight3D in stage.find_children("*","OmniLight3D",true,false):
				frame.lights.append({"position":vec(light.global_position),"color":[light.light_color.r,light.light_color.g,light.light_color.b],"energy":light.light_energy})
			frames.append(frame)
		stage.free()
	DirAccess.make_dir_recursive_absolute("/tmp/campaign-presentation-preview")
	var output := FileAccess.open("/tmp/campaign-presentation-preview/frames.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(frames)); output.close(); print("PRESENTATION_PREVIEW_EXPORTED ",frames.size()); quit()
