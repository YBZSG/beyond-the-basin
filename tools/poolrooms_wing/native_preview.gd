extends SceneTree
## One-room native asset/optics check. Not the main game or a target-GPU benchmark.
const Catalog = preload("res://scripts/poolrooms_wing/poolrooms_catalog.gd")
const SeededCatalog = preload("res://scripts/world/room_catalog.gd")
const Builder = preload("res://scripts/world/room_builder.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const Lighting = preload("res://scripts/rendering/pool_lighting.gd")

class SurfaceOpticsOnly extends "res://scripts/water/source_water_runtime.gd":
	# Diagnostic allocation boundary only. Production runtime is not changed.
	# Real source SWE/detail/caustics/planar optics, without MPM/cubemap/avatar.
	func configure(library: RefCounted) -> void:
		_library = library
		if _configured: return
		_configured = true
		_configure_initial_fields()
	func configure_camera(camera: Camera3D, environment: Environment) -> void:
		_camera = camera
		planar = Planar.new()
		add_child(planar)
		planar.configure(camera, environment)
		planar.set_quality(quality_levels[quality].reflection)

var errors: Array[String] = []
var index := 0
var with_water := false
var motion := false
var context_rooms := false
var native_gi := false
var context_nodes: Array[Node3D] = []
var context_builders: Array[RefCounted] = []
var output := "res://output/poolrooms_wing/native"
var view: SubViewport
var stage: Node3D
var room: Node3D
var library: RefCounted
var lighting: RefCounted
var builder: RefCounted
var water: Node3D
var camera: Camera3D
var environment: WorldEnvironment
var started := 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wing-index="): index = clampi(argument.get_slice("=",1).to_int(),0,2)
		if argument == "--with-source-water": with_water = true
		if argument == "--motion": motion = true
		if argument == "--context-rooms": context_rooms = true
		if argument == "--with-native-gi": native_gi = true
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	_run.call_deferred()

func draw_frames(count: int) -> void:
	for frame: int in count:
		await process_frame
		await RenderingServer.frame_post_draw

func _run() -> void:
	started = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(output)
	root.title = "Poolrooms Wing | controlled native review"
	view = SubViewport.new()
	view.size = Vector2i(1024,640)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_4X
	view.use_taa = false
	root.add_child(view)
	var presentation := TextureRect.new()
	presentation.texture = view.get_texture()
	presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	presentation.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(presentation)
	stage = Node3D.new()
	view.add_child(stage)
	var coord: Vector2i = [Vector2i.ZERO,Vector2i.UP,Vector2i.RIGHT][index]
	var layout: Dictionary = Catalog.room_layout(coord,250821)
	layout.poolrooms_mode = true
	var origin := Vector3(coord.x*32,0,coord.y*32)
	room = Node3D.new()
	room.position = origin
	room.set_meta("coord",coord)
	room.set_meta("layout",layout)
	stage.add_child(room)
	library = Materials.new()
	builder = Builder.new(room,layout,library)
	builder.build_shell()
	builder.build_interior()
	environment = WorldEnvironment.new()
	lighting = Lighting.new()
	lighting._materials = library
	lighting.configure_environment(environment)
	# Explicit manageable diagnostic: same authored light recipe, no full-world GI.
	environment.environment.sdfgi_enabled = native_gi
	stage.add_child(environment)
	lighting.add_room_lights(room,layout.variant)
	if context_rooms:
		for offset: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var other_coord := coord+offset
			var other_layout: Dictionary = Catalog.room_layout(other_coord,250821) if Catalog.ANCHORS.has(other_coord) else SeededCatalog.room_layout(other_coord,250821,true)
			other_layout.poolrooms_mode = true
			var other := Node3D.new()
			other.position = Vector3(other_coord.x*32,0,other_coord.y*32)
			other.set_meta("coord",other_coord)
			other.set_meta("layout",other_layout)
			stage.add_child(other)
			var other_builder := Builder.new(other,other_layout,library)
			other_builder.build_shell()
			other_builder.build_interior()
			context_nodes.append(other)
			context_builders.append(other_builder)
			lighting.add_room_lights(other,other_layout.variant)
	lighting.update_active_room(coord,layout)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = .08
	camera.far = 100.0
	stage.add_child(camera)
	var positions: Array[Vector3] = [Vector3(8,2.1,8),Vector3(0,2.1,10.5),Vector3(9.3,2.15,0)]
	var targets: Array[Vector3] = [Vector3(-3,1.5,-3),Vector3(0,2,-8),Vector3(-5,1.7,0)]
	camera.position = origin + positions[index]
	camera.look_at(origin + targets[index])
	camera.current = true
	lighting.update_source_view(camera)
	if lighting._mood_tween != null and lighting._mood_tween.is_running():
		# Match production Main._settle_created_world_lighting on explicit creation.
		lighting._mood_tween.custom_step(2.0)
	print("POOLROOMS_STAGE geometry_ready ",Time.get_ticks_msec()-started)
	await draw_frames(12 if native_gi else 4)
	if with_water:
		water = SurfaceOpticsOnly.new()
		water.quality = "Medium"
		stage.add_child(water)
		print("POOLROOMS_STAGE source_water_configure ",Time.get_ticks_msec()-started)
		water.configure(library)
		water.configure_camera(camera,environment.environment)
		water.add_room(room,coord,layout)
		for other: Node3D in context_nodes:
			water.add_room(other,other.get_meta("coord"),other.get_meta("layout"))
		water.set_active_room(coord)
		var deadline := Time.get_ticks_msec() + 150000
		var impact_sent := false
		while not water.is_terrain_ready() or not water.planar.capture_ready or water.caustics.caustic_frames < 2:
			if water.is_terrain_ready() and not impact_sent:
				water.wave_impact(origin+Vector3(-4,.32,-2),.25)
				impact_sent = true
			if Time.get_ticks_msec() > deadline:
				errors.append("Source optics readiness timed out")
				break
			await process_frame
		print("POOLROOMS_STAGE source_water_ready ",Time.get_ticks_msec()-started)
		# Actual current-room native probe recapture after source terrain readiness.
		for probe: ReflectionProbe in room.find_children("*","ReflectionProbe",true,false):
			probe.update_mode = ReflectionProbe.UPDATE_ONCE
		await draw_frames(3)
	else:
		library.set_source_water_uniforms(null,null,Vector2.ZERO,0.0)
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var label: String = Catalog.FILES[index] + ("-source-water" if with_water else "-dry-geometry")
	var saved := image.save_png(output.path_join(label+".png"))
	if saved != OK: errors.append("PNG save failed")
	if motion and with_water and errors.is_empty():
		DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
		var start_position := camera.position
		water.wave_impact(origin+Vector3(-4,.32,-2),.35)
		for frame: int in 12:
			camera.position = start_position + Vector3(-float(frame)*.025,0,-float(frame)*.015)
			camera.look_at(origin+targets[index])
			await draw_frames(1)
			view.get_texture().get_image().save_png(output.path_join("frames/%04d.png"%frame))
	var report := {"pass":errors.is_empty(),"errors":errors,"room":Catalog.FILES[index],"context_rooms":context_nodes.size(),"capture_motion_frames":12 if motion else 0,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"environment_state":{"sdfgi_enabled":environment.environment.sdfgi_enabled,"sdfgi_cascades":environment.environment.sdfgi_cascades,"fog_density":environment.environment.volumetric_fog_density,"exposure":environment.environment.tonemap_exposure,"ambient":environment.environment.ambient_light_energy},"image_size":[image.get_width(),image.get_height()],"wall_seconds":float(Time.get_ticks_msec()-started)/1000.0,"source_water":with_water,"source_water_stats":water.debug_stats() if with_water else {},"geometry":room.get_meta("expanded_geometry_stats"),"scope":"Actual Godot 4.6.3 bounded current-room Forward+ rendering, optionally four adjoining production-built rooms. See environment_state for SDFGI (six cascades when enabled); source water Medium when requested. No avatar, MPM splash, cubemap, whole-world streaming, custom 4.8, Windows or hardware FPS acceptance."}
	FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("POOLROOMS_NATIVE_RESULT ",JSON.stringify({"pass":errors.is_empty(),"room":Catalog.FILES[index],"water":with_water,"wall_seconds":report.wall_seconds}))
	if is_instance_valid(water): water.dispose()
	await draw_frames(2)
	quit(0 if errors.is_empty() else 1)
