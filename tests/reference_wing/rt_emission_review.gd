extends SceneTree
## Native RT regression using the authored colonnade and production material router.
## No gameplay/water solver or saved preferences. Use --review-out=... to relocate evidence.
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const Builder = preload("res://scripts/reference_wing/reference_room_builder.gd")
const Lighting = preload("res://scripts/reference_wing/reference_lighting.gd")
const Refresh = preload("res://scripts/rendering/rt_material_refresh.gd")
class Host extends Node3D:
	var materials = null
var destination := "res://output/rt-emission-review"
var checks: Array = []
var failures: Array = []
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks.append({"pass": value, "label": label})
	if not value: failures.append(label)
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--review-out="): destination = argument.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(destination)
	var graphical := DisplayServer.get_name() != "headless"
	var host := Host.new()
	root.add_child(host)
	var router := Refresh.new()
	router.configure(host)
	var room := Node3D.new()
	host.add_child(room)
	var layout: Dictionary = Catalog.room_layout(Catalog.COORDS[1], 250821)
	room.set_meta("layout", layout)
	room.set_meta("coord", layout.coord)
	var builder := Builder.new(room, layout, null)
	builder.build_shell()
	var emitters: Array[BaseMaterial3D] = []
	var seen: Dictionary = {}
	for node in room.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material is BaseMaterial3D and material.emission_enabled and material.emission_texture == null and not seen.has(material):
				seen[material] = true
				emitters.append(material)
	check(not emitters.is_empty(), "Authored colonnade contains constant emissive materials")
	var authored: Array = []
	for material in emitters:
		authored.append([material.emission, material.emission_energy_multiplier, material.emission_operator])
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.position = Vector3(0, 1.65, 10.8)
	camera.look_at(Vector3(0, 3.0, -8.0))
	camera.fov = 64
	camera.cull_mask = 1
	camera.current = true
	var environment_node := WorldEnvironment.new()
	host.add_child(environment_node)
	var lighting := Lighting.new()
	lighting.configure_environment(environment_node)
	lighting.add_room_lights(room, layout.variant)
	lighting.update_active_room(layout.coord, layout)
	lighting.update_source_view(camera)
	var environment: Environment = environment_node.environment
	if graphical:
		root.size = Vector2i(960, 720)
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.use_taa = false
		root.scaling_3d_scale = 1.0
		root.set("scaling_3d_mode", ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_DLSS"))
		await create_timer(2.0).timeout
		await capture("raster")
		builder.reference_materials.set_raytracing_enabled(true)
		environment.set("pathtracing_samples_per_pixel", 1)
		environment.set("pathtracing_max_bounces", 3)
		environment.set("pathtracing_denoiser", 1)
		environment.set("pathtracing_enabled", true)
		await capture("rt_before")
	router.refresh_all(true)
	for index in emitters.size():
		var material := emitters[index]
		check(material.emission_texture != null, "RT texture present: " + material.resource_name)
		check(material.emission == authored[index][0] and material.emission_energy_multiplier == authored[index][1], "Authored radiance retained: " + material.resource_name)
		check(material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "Neutral multiplication: " + material.resource_name)
	if graphical: await capture("rt_fixed")
	router.refresh_all(false)
	for index in emitters.size():
		check(emitters[index].emission_texture == null and emitters[index].emission_operator == authored[index][2], "Raster state restored: " + emitters[index].resource_name)
	if graphical:
		environment.set("pathtracing_enabled", false)
		await capture("raster_restored")
	var report := {"passed": failures.is_empty(), "graphical": graphical, "checks": checks, "errors": failures, "constant_emitters": emitters.size(), "samples": 1, "bounces": 3, "engine": Engine.get_version_info(), "device": RenderingServer.get_video_adapter_name()}
	FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("RT_EMISSION_REVIEW ", JSON.stringify(report))
	host.free()
	quit(0 if failures.is_empty() else 1)
func capture(label: String) -> void:
	for frame in 90: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(destination.path_join(label + ".png")) == OK, "Capture " + label)
	print("RT_EMISSION_CAPTURE ", label)