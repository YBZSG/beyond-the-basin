extends SceneTree
## Bounded native proof: ONE final exported Lanes room, real PoolPlayer movement.
## Run with --fixed-fps 8 to record retimed frames. This is NOT real-time FPS.
const Catalog = preload("res://scripts/poolrooms_wing/poolrooms_catalog.gd")
const Builder = preload("res://scripts/world/room_builder.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const Lighting = preload("res://scripts/rendering/pool_lighting.gd")
const Player = preload("res://scripts/player/pool_player.gd")
const Preview = preload("res://tools/poolrooms_wing/native_preview.gd")
const InputBridge = preload("res://tests/architecture_contact/contact_input_bridge.gd")
const Driver = preload("res://tests/architecture_contact/contact_walk_driver.gd")
var output := "res://output/contact-walk/native"
var manual := false
var with_water := true
var record_frames := true
var width := 768
var height := 480
var view: SubViewport
var stage: Node3D
var room: Node3D
var player: CharacterBody3D
var driver: Node
var water: Node3D
var library: RefCounted
var lighting: RefCounted
var environment: WorldEnvironment
var builder: RefCounted
var camera: Camera3D
var caption: Label
var errors: Array[String] = []
var started := 0
var capture_count := 0
var snapshots: Array[String] = []
var frame_trace: Array = []
var room_origin := Vector3(0,0,-32)

func _initialize() -> void:
	Engine.physics_ticks_per_second=120
	# Explicit diagnostic override prevents the default 8-tick catch-up clamp.
	Engine.max_physics_steps_per_frame=32
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument=="--interactive":manual=true
		if argument=="--dry-contact-geometry":with_water=false
		if argument=="--no-frame-sequence":record_frames=false
		if argument.begins_with("--width="):width=clampi(argument.trim_prefix("--width=").to_int(),320,1280);height=roundi(width*.625)
	_run.call_deferred()

func input_map() -> void:
	var keys:Dictionary={"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E,"pause":KEY_ESCAPE}
	for action:String in keys:
		if not InputMap.has_action(action):InputMap.add_action(action)
		var event:=InputEventKey.new();event.physical_keycode=keys[action];InputMap.action_add_event(action,event)
		Input.action_release(action)
	for action:String in ["throw_prop","grab_prop"]:
		if not InputMap.has_action(action):InputMap.add_action(action)

func draw_frames(count:int) -> void:
	for i:int in count:
		await process_frame
		await RenderingServer.frame_post_draw

func capture(label:String) -> void:
	var result:=view.get_texture().get_image().save_png(output.path_join(label+".png"))
	if result!=OK:errors.append("Failed to save "+label)
	else:snapshots.append(label+".png")

func _run() -> void:
	started=Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(output)
	if record_frames:DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	input_map()
	root.title="Poolrooms contact repair | real controller / bounded diagnostic"
	root.size=Vector2i(width,height)
	view=SubViewport.new();view.size=Vector2i(width,height);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.msaa_3d=Viewport.MSAA_4X;view.use_taa=false
	root.add_child(view)
	var presentation:=TextureRect.new();presentation.texture=view.get_texture();presentation.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	presentation.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;presentation.mouse_filter=Control.MOUSE_FILTER_IGNORE
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(presentation)
	caption=Label.new();caption.position=Vector2(10,8);caption.add_theme_font_size_override("font_size",13)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK);caption.add_theme_constant_override("shadow_offset_x",1);caption.add_theme_constant_override("shadow_offset_y",1)
	view.add_child(caption)
	stage=Node3D.new();view.add_child(stage)
	var layout:Dictionary=Catalog.room_layout(Vector2i.UP,250821);layout.poolrooms_mode=true
	room=Node3D.new();room.position=room_origin;room.set_meta("coord",Vector2i.UP);room.set_meta("layout",layout);stage.add_child(room)
	library=Materials.new();builder=Builder.new(room,layout,library);builder.build_shell();builder.build_interior()
	environment=WorldEnvironment.new();lighting=Lighting.new();lighting._materials=library;lighting.configure_environment(environment)
	# Exact native-preview allocation boundary, not a production setting change.
	environment.environment.sdfgi_enabled=false;stage.add_child(environment)
	lighting.add_room_lights(room,layout.variant);lighting.update_active_room(Vector2i.UP,layout)
	player=Player.new();stage.add_child(player);player.set_physics_process(false)
	player.water_motion_actions_enabled=true;player.depth_wading_response_enabled=true
	player.warp_to(room_origin+Vector3(-4,.54,-9.6),room_origin+Vector3(-4,2.14,-6.5))
	camera=player.get_view_camera();camera.current=true
	lighting.update_source_view(camera)
	if lighting._mood_tween!=null and lighting._mood_tween.is_running():lighting._mood_tween.custom_step(2.0)
	caption.text="One room / actual exported mesh and capsule / preparing source optics"
	print("CONTACT_WALK_STAGE geometry_ready")
	await draw_frames(3)
	if with_water:
		# Inherits the existing diagnostic source SWE/detail/photons/planar pipeline.
		# No MPM, splash compositor, avatar or cubemap allocation.
		water=Preview.SurfaceOpticsOnly.new();water.quality="Medium";stage.add_child(water)
		water.configure(library);water.configure_camera(camera,environment.environment);water.add_room(room,Vector2i.UP,layout);water.set_active_room(Vector2i.UP)
		var deadline:=Time.get_ticks_msec()+180000
		var readiness_impact_sent:=false
		while not water.is_terrain_ready() or not water.planar.capture_ready or water.caustics.caustic_frames<2:
			if water.is_terrain_ready() and not readiness_impact_sent:
				water.wave_impact(room_origin+Vector3(-4,.32,-6),.25)
				readiness_impact_sent=true
			if Time.get_ticks_msec()>deadline:errors.append("Source optics readiness timed out");break
			await process_frame
		player.set_water(water)
		for probe:ReflectionProbe in room.find_children("*","ReflectionProbe",true,false):probe.update_mode=ReflectionProbe.UPDATE_ONCE
	else:library.set_source_water_uniforms(null,null,Vector2.ZERO,0.0)
	if not errors.is_empty():await _finish();return
	player.enabled=true;player.set_physics_process(true)
	await draw_frames(2)
	print("CONTACT_WALK_STAGE real_controller_ready")
	if manual:
		var bridge:=InputBridge.new();bridge.player=player;root.add_child(bridge);bridge.finish_requested.connect(_finish)
		player.set_enabled(true)
		caption.text="WASD + mouse: real PoolPlayer | Esc: release mouse | click: resume | F10: save + exit\nOne-room diagnostic, no avatar/MPM/cubemap; production settings unchanged"
		return
	driver=Driver.new();driver.player=player;driver.room_origin=room_origin;stage.add_child(driver);driver.start()
	while not driver.completed:
		await process_frame
		lighting.update_source_view(camera)
		caption.text="REAL CONTROLLER / RETIMED DIAGNOSTIC, NOT REAL-TIME FPS\n"+driver.current_label()+" | simulated %.2f s | eye 1.6 m"%driver.elapsed
		await RenderingServer.frame_post_draw
		frame_trace.append({"frame":capture_count,"simulation_seconds":driver.elapsed,"actual_physics_ticks":driver.physical_ticks,"feet":driver.vec(player.global_position-room_origin)})
		if record_frames:
			var saved:=view.get_texture().get_image().save_png(output.path_join("frames/%04d.png"%capture_count))
			if saved!=OK:errors.append("Frame save failed")
		capture_count+=1
		while not driver.pending_snapshots.is_empty():capture(driver.pending_snapshots.pop_front())
		if Time.get_ticks_msec()-started>1800000:driver.fail("Native capture exceeded 30-minute wall-time guard")
	for error:String in driver.errors:errors.append(error)
	# Exterior verification camera is explicitly separate from the walked player.
	# It does not move the controller, alter terrain or masquerade as first person.
	player.set_physics_process(false);Input.action_release("move_forward")
	var contact_camera:=Camera3D.new();contact_camera.fov=68;contact_camera.near=.035;stage.add_child(contact_camera)
	contact_camera.position=room_origin+Vector3(-4.4,.45,-6.45)
	contact_camera.look_at(room_origin+Vector3(-2.4,-.12,-7.5));contact_camera.current=true
	if with_water:water._camera=contact_camera;water.planar.source_camera=contact_camera
	lighting.update_source_view(contact_camera)
	caption.text="EXTERNAL LOW CONTACT ANGLE / camera y = 0.45 m / not player eye\nReal submerged footing and basin floor; single-room diagnostic"
	await draw_frames(3);capture("10-external-low-contact")
	await _finish()

func _finish() -> void:
	Input.action_release("move_forward")
	if is_instance_valid(player):player.set_physics_process(false)
	var report:Dictionary={"pass":errors.is_empty(),"errors":errors,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"room":"vaulted_lanes","glb_sha256":FileAccess.get_sha256("res://assets/models/poolrooms_wing/vaulted_lanes.glb"),"controller_sha256":FileAccess.get_sha256("res://scripts/player/pool_player.gd"),"image_size":[width,height],"interactive":manual,"source_water":with_water,"source_water_stats":water.debug_stats() if is_instance_valid(water) else {},"physics_hz":Engine.physics_ticks_per_second,"max_physics_steps_per_frame":Engine.max_physics_steps_per_frame,"frame_count":capture_count,"frame_trace":frame_trace,"snapshots":snapshots,"wall_seconds":float(Time.get_ticks_msec()-started)/1000.0,"route":driver.result() if is_instance_valid(driver) else {},"scope":"Single-room actual imported GLB, production RoomBuilder/materials/lights, unchanged PoolPlayer at real 1.6m eye with collision and automatic 120Hz physics. Source SWE/detail/photons/planar Medium, SDFGI disabled only in diagnostic. No avatar, MPM, splash compositor, cubemap, connected-room spatial acceptance, whole-world streaming, hardware FPS, Android, or production setting change. Fixed-fps frame sequence is RETIMED, NOT REAL-TIME PERFORMANCE."}
	FileAccess.open(output.path_join("native-contact-walk.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CONTACT_WALK_RESULT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"frames":capture_count,"wall_seconds":report.wall_seconds}))
	if is_instance_valid(water):water.dispose()
	await draw_frames(2)
	quit(0 if errors.is_empty() else 1)
