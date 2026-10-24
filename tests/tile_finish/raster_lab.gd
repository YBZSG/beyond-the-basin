extends SceneTree
## Isolated material laboratory, not the game and never hardware-RT evidence.
## Uses production materials, metric UVs, an orange subject and raster SSR/probe.
const ArtMaterials = preload("res://scripts/art_pass/art_pass_materials.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
var destination := ""
var baseline_dir := ""
var report := {"errors": [], "captures": [], "coverage_gpu": [], "scope": "Official Godot raster material laboratory only. No game, water, hardware RT, DLSS, NR, gameplay or performance acceptance."}
var stage: Node3D
var camera: Camera3D
var surfaces: Array[MeshInstance3D] = []
var label: Label

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tile-out="): destination = argument.trim_prefix("--tile-out=")
		if argument.begins_with("--tile-baseline-dir="): baseline_dir = argument.trim_prefix("--tile-baseline-dir=")
	if destination.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Tile raster lab requires --tile-out and a real Forward+ rendering device.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	root.size = Vector2i(960, 640)
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_4X
	root.use_taa = false
	report.engine = Engine.get_version_info()
	report.device = RenderingServer.get_video_adapter_name()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.variant = "candidate" if baseline_dir.is_empty() else "handoff"
	await _check_gpu_coverage()
	_build_stage()
	var library := Materials.new()
	var art := ArtMaterials.new()
	var cases := {
		"art_pearl": art.resolve("art_pass_tile_pearl", null),
		"art_blue": art.resolve("art_pass_tile_blue", null),
		"formal_deck": library.get_material("formal_dry_deck"),
		"source_blue": library.get_material("tile"),
	}
	for case_name: String in cases:
		var material: ShaderMaterial = cases[case_name].duplicate(false)
		material.set_shader_parameter("causticGain", 0.0)
		material.set_shader_parameter("planar_clip_enabled", false)
		if not baseline_dir.is_empty():
			var path := baseline_dir.path_join(material.shader.resource_path.get_file())
			if not FileAccess.file_exists(path):
				report.errors.append("Missing baseline shader: " + path)
				continue
			var baseline := Shader.new()
			baseline.code = FileAccess.get_file_as_string(path)
			material.shader = baseline
		# The art-pass atlas uses 0.8 m; formal and source shaders project world metres.
		for surface: MeshInstance3D in surfaces: surface.material_override = material
		for view: String in ["close", "grazing", "distant"]:
			camera.position = {"close":Vector3(1.25, 1.20, 2.65), "grazing":Vector3(1.15, 0.40, 2.95), "distant":Vector3(3.0, 2.0, 7.0)}[view]
			camera.look_at(Vector3(0.0, 0.10, -0.35), Vector3.UP)
			label.text = "RASTER MATERIAL LAB | %s | %s | %s\nProduction tile shader, controlled SSR + reflection probe. Not hardware RT." % [report.variant, case_name, view]
			for frame in 16: await process_frame
			await RenderingServer.frame_post_draw
			var filename := case_name + "_" + view + ".png"
			var result := root.get_texture().get_image().save_png(destination.path_join(filename))
			if result != OK: report.errors.append("Capture failed: " + filename)
			report.captures.append({"file": filename, "camera": str(camera.global_transform), "shader": material.shader.resource_path, "variant": report.variant})
	report.pass = report.errors.is_empty()
	FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("TILE_RASTER_LAB ", JSON.stringify(report))
	quit(0 if report.pass else 1)

func _check_gpu_coverage() -> void:
	# These are real imported/compressed texture samples through the renderer.
	# Use a small 2D viewport to avoid tonemapping/lighting changing the scalar.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 16)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(16, 16)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D source_map : filter_nearest, repeat_enable; uniform vec2 sample_uv; void fragment(){float face=textureLod(source_map,sample_uv,0.0).a; COLOR=vec4(vec3(face),1.0);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	viewport.add_child(rect)
	for name: String in ["tile_blue", "tile_pearl", "tile_blue_wet", "tile_pearl_wet"]:
		material.set_shader_parameter("source_map", load("res://assets/materials/art_pass/textures/" + name + "_orm_2k.png"))
		for sample: Dictionary in [{"name":"joint", "x":0.5, "expected":0.0}, {"name":"edge", "x":2.5, "expected":199.0/255.0}, {"name":"face", "x":128.5, "expected":1.0}]:
			material.set_shader_parameter("sample_uv", Vector2(float(sample.x), 128.5) / 2048.0)
			for frame in 2: await process_frame
			await RenderingServer.frame_post_draw
			var observed := viewport.get_texture().get_image().get_pixel(8, 8).r
			var valid := absf(observed - float(sample.expected)) < 0.045
			report.coverage_gpu.append({"map": name, "sample":sample.name, "expected": sample.expected, "observed": observed, "pass":valid})
			if not valid: report.errors.append("Imported GPU alpha differs: " + name + "/" + str(sample.name))
	viewport.queue_free()
	await process_frame

func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.07, 0.085)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.84, 0.88)
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssr_enabled = true
	environment.ssr_max_steps = 96
	var environment_node := WorldEnvironment.new()
	environment_node.environment = environment
	stage.add_child(environment_node)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(4.8, 6.0)
	floor.mesh = _metric_plane(floor_mesh)
	floor.position.z = -0.5
	stage.add_child(floor)
	surfaces.append(floor)
	var wall := MeshInstance3D.new()
	var wall_mesh := PlaneMesh.new()
	wall_mesh.size = Vector2(4.8, 1.6)
	wall.mesh = _metric_plane(wall_mesh)
	wall.rotation.x = PI / 2.0
	wall.position = Vector3(0, 0.8, -3.5)
	stage.add_child(wall)
	surfaces.append(wall)
	var subject := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.48, 0.75, 0.48)
	subject.mesh = box
	subject.position = Vector3(-0.1, 0.375, -0.45)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.85, 0.16, 0.025)
	orange.roughness = 0.38
	subject.material_override = orange
	stage.add_child(subject)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -28, 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.96, 0.90)
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 2.8, 0.7)
	fill.light_energy = 2.5
	fill.omni_range = 8.0
	stage.add_child(fill)
	# A real bright reflected strip makes the finite highlight width legible.
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(0.12, 0.05, 1.6)
	strip.mesh = strip_mesh
	strip.position = Vector3(0.85, 2.4, -0.4)
	var light_material := StandardMaterial3D.new()
	light_material.albedo_color = Color(0.96, 0.96, 0.9)
	light_material.emission_enabled = true
	light_material.emission = Color(1.0, 0.97, 0.9)
	light_material.emission_energy_multiplier = 2.0
	strip.material_override = light_material
	stage.add_child(strip)
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 0.7, -0.5)
	probe.size = Vector3(7, 6, 9)
	probe.interior = true
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	stage.add_child(probe)
	camera = Camera3D.new()
	camera.fov = 58
	camera.near = 0.05
	stage.add_child(camera)
	camera.current = true
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(label)

func _metric_plane(source: PlaneMesh) -> ArrayMesh:
	var arrays := source.get_mesh_arrays()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index in uv.size(): uv[index] *= source.size
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
