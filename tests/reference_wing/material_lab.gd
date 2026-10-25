extends SceneTree
## Real production PBR materials; render only with an authorized graphical device.
## No gameplay, water solver, custom RT APIs, NR, display filters or saved settings.
const Family = preload("res://scripts/reference_wing/reference_materials.gd")
const LegacyArt = preload("res://scripts/art_pass/art_pass_materials.gd")
var out := ""
var ssr := false
var stage: Node3D
var camera: Camera3D
var probe: ReflectionProbe
var surfaces: Array[MeshInstance3D] = []
var report := {"errors": [], "captures": [], "nr": "off", "visual_acceptance": false,
	"scope": "NR-off stock raster PBR material fixture only. Images require visual review; not native NVIDIA RT/RR/NR or gameplay evidence."}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--reference-material-out="): out = argument.trim_prefix("--reference-material-out=")
		if argument == "--reference-material-ssr": ssr = true
	if out.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Reference material lab requires Forward+, a graphical device, and --reference-material-out.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("POOLCORE_DLSS_NR", "0")
	root.size = Vector2i(1280, 720)
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_4X
	root.use_taa = false
	report.engine = Engine.get_version_info()
	report.device = RenderingServer.get_video_adapter_name()
	report.ssr = ssr
	report.probe_face_size = ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_size", 256)
	report.roughness_limiter = ProjectSettings.get_setting("rendering/anti_aliasing/screen_space_roughness_limiter/enabled", true)
	_build_stage()
	var legacy := LegacyArt.new()
	for variant: String in ["legacy_art_pearl", "control", "shape_only", "roughness_only", "combined", "scoped_ref5_crown"]:
		var family := Family.new()
		var material: ShaderMaterial
		if variant == "legacy_art_pearl":
			material = legacy.resolve("art_pass_tile_pearl", null)
		elif variant == "scoped_ref5_crown":
			material = family.resolve(Family.REF5_CROWN_ROLE) as ShaderMaterial
		else:
			family.set_diagnostic_variant(variant)
			material = family.resolve("ref_tile_pearl") as ShaderMaterial
		material.set_shader_parameter("causticGain", 0.0)
		material.set_shader_parameter("planar_clip_enabled", false)
		for surface: MeshInstance3D in surfaces: surface.material_override = material
		_replace_probe()
		for frame in 30: await process_frame
		for view: String in ["close", "grazing", "distant"]:
			var positions := {"close": Vector3(0.70,1.55,0.4), "grazing":Vector3(0.50,1.7,1.0), "distant":Vector3(0,1.7,3.8)}
			var targets := {"close": Vector3(1.4,1.45,-0.5), "grazing":Vector3(1.3,1.3,-4.8), "distant":Vector3(0.8,1.3,-3.2)}
			camera.position = positions[view]
			camera.look_at(targets[view], Vector3.UP)
			await _capture(variant, view, material)
		for step in 8:
			camera.position = Vector3(-0.35+0.1*step,1.65,0.8)
			camera.look_at(Vector3(1.4,1.4,-3.0), Vector3.UP)
			await _capture(variant, "lateral_%02d" % step, material)
	report.execution_completed = report.errors.is_empty()
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("REFERENCE_MATERIAL_LAB ",JSON.stringify(report))
	quit(0 if report.errors.is_empty() else 1)

func _capture(variant: String, view: String, material: ShaderMaterial) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var name := "%s_%s.png" % [variant,view]
	var result := root.get_texture().get_image().save_png(out.path_join(name))
	if result != OK: report.errors.append("Could not save " + name)
	report.captures.append({"file":name,"variant":variant,"view":view,
		"camera":str(camera.global_transform),"shader":material.shader.resource_path,
		"material_role":material.resource_name,"face_profile":material.get_shader_parameter("face_profile"),
		"face_shape_strength":material.get_shader_parameter("face_shape_strength"),
		"face_roughness":material.get_shader_parameter("face_roughness")})

func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025,0.03,0.035)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85,0.88,0.86)
	environment.ambient_light_energy = 0.15
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = false
	environment.ssr_enabled = ssr
	environment.ssr_max_steps = 128
	var environment_node := WorldEnvironment.new()
	environment_node.environment = environment
	stage.add_child(environment_node)
	_add_plane(Vector2(2.8,7),Vector3(0,0,-2.5),Vector3.ZERO)
	_add_plane(Vector2(3,7),Vector3(1.4,1.5,-2.5),Vector3(0,0,PI/2))
	_add_plane(Vector2(3,7),Vector3(-1.4,1.5,-2.5),Vector3(0,0,-PI/2))
	_add_plane(Vector2(2.8,3),Vector3(0,1.5,-6),Vector3(PI/2,0,0))
	for z in [-0.8,-2.8,-4.8]:
		var strip := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.095,0.045,1.1)
		strip.mesh = mesh
		strip.position = Vector3(0,2.7,z)
		var opal := StandardMaterial3D.new()
		opal.albedo_color = Color(0.94,0.96,0.92)
		opal.emission_enabled = true
		opal.emission = Color(1.0,0.98,0.92)
		opal.emission_energy_multiplier = 5.0
		strip.material_override = opal
		stage.add_child(strip)
		var light := OmniLight3D.new()
		light.position = Vector3(0,2.45,z)
		light.light_energy = 1.2
		light.light_specular = 0.0
		light.omni_range = 7.0
		stage.add_child(light)
	var subject := MeshInstance3D.new()
	var subject_mesh := BoxMesh.new()
	subject_mesh.size = Vector3(0.45,0.85,0.45)
	subject.mesh = subject_mesh
	subject.position = Vector3(-0.65,0.425,-2.6)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.9,0.12,0.025)
	orange.roughness = 0.4
	subject.material_override = orange
	stage.add_child(subject)
	camera = Camera3D.new()
	camera.fov = 62
	camera.near = 0.05
	stage.add_child(camera)
	camera.current = true

func _replace_probe() -> void:
	if is_instance_valid(probe): probe.free()
	probe = ReflectionProbe.new()
	probe.position = Vector3(0,1.4,-2.5)
	probe.size = Vector3(3.0,3.2,7.2)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	stage.add_child(probe)

func _add_plane(size: Vector2, at: Vector3, rotation: Vector3) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var arrays := plane.get_mesh_arrays()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index in uv.size(): uv[index] *= size
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rotation
	stage.add_child(instance)
	surfaces.append(instance)
