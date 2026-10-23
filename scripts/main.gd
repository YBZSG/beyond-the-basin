extends Node3D
## Integration for the source-based native port. No browser/WebGL runtime remains.
const WorldScript = preload("res://scripts/world/pool_world.gd")
const PlayerScript = preload("res://scripts/player/pool_player.gd")
const AvatarScript = preload("res://scripts/player/pool_avatar.gd")
const AvatarFinishScript = preload("res://scripts/player/avatar_finish_candidate.gd")
const FacilityDevicesScript = preload("res://scripts/world/facility_devices_candidate.gd")
const SPAWN_MODES := ["original", "formal", "expanded"]
const SEED_INPUT_GUARD_REVISION := 1
const PropsScript = preload("res://scripts/player/pool_props.gd")
const WaterScript = preload("res://scripts/water/source_water_runtime.gd")
const WaterSettingsScript = preload("res://scripts/water/source_port/source_water_settings.gd")
const MaterialsScript = preload("res://scripts/rendering/pool_materials.gd")
const LightingScript = preload("res://scripts/rendering/pool_lighting.gd")
const AudioScript = preload("res://scripts/audio/pool_audio.gd")
const Catalog = preload("res://scripts/world/room_catalog.gd")
const MainhallPreview = preload("res://scripts/rendering/pc_mainhall_lightmap_preview.gd")
const SourceFog = preload("res://scripts/rendering/source_volumetric_fog.gd")
const SourceDistanceFogScript = preload("res://scripts/rendering/source_distance_fog.gd")
var materials: RefCounted
var lighting: RefCounted
var world: Node3D
# Local, optional quiet exploration record; no HUD notifications.
var _exploration_notes: Node
var water: Node3D
var player: CharacterBody3D
var avatar: Node3D
var _avatar_finish: RefCounted
var _avatar_finish_status: Dictionary = {}
var _facility_devices: Node3D
var _facility_world_epoch := 0
var _avatar_enabled := true
var _avatar_fabric_enabled := true
var _facility_enabled := true
var _depth_wading_enabled := true
var props: Node3D
var pool_audio: Node3D
var environment: WorldEnvironment
var source_fog: CompositorEffect
var distance_fog: CompositorEffect
var _capture_distance_fogs:Array[CompositorEffect]=[]
var _fog_on := true
var world_seed := 250821
var _spawn_mode := "original"
var _spawn_select: OptionButton
var _switching_spawn:=false
var _world_restart := preload("res://scripts/app/world_restart.gd").new()
var _world_restart_status: Label
var _world_restart_button: Button
# Keep _booted true while replacing a world: DesktopQuality treats false as shutdown.
var _retiring_world := false
class WorldRetirementBarrier extends RefCounted:
	var mutex := Mutex.new()
	var complete := false
	func mark() -> void:
		mutex.lock(); complete = true; mutex.unlock()
	func ready() -> bool:
		mutex.lock(); var value := complete; mutex.unlock(); return value
var menu_open := true
var hud_hidden := false
var diagnostic_open := false
var _booted := false
var _qa := false
var qa_capture_hook: Callable
var _quality := "High"
var _audio_on := true
var _ambience_on := true
# Requested/saved GI remains independent of the explicit preview override.
var _gi_on := true
var _pc_mainhall_preview := false
var _pc_preview_return_spawn := "original"
var _pc_preview_pending := -1
var _pc_preview_target_spawn := ""
var _pc_preview_result: Dictionary = {}
var _pc_preview_check: CheckButton
var _pc_preview_status: Label
var _caustics_on := true
var _ccd_on := false
var _filter_mode := 0
var _advanced: PanelContainer
var _water_settings: Dictionary = WaterSettingsScript.sanitize_wind_settings({})
var _wind_controls: Dictionary = {}
var _water_visible := true
var _gi_check: CheckButton
var _caustics_check: CheckButton
var _looks: OptionButton
var _crosshair: Label
var _charge_bar: ProgressBar
var _renderer_warning: Label
var _status_interval := 0.0
var _menu: PanelContainer
var _status: Label
var _room_title: Label
var _hint: Label
var _diag: Label
var _seed_edit: LineEdit
var _seed_input_status: Label
var _destination: OptionButton
var _resume: Button
var _loading_status: Label
var _copy_diagnostics_button: Button
var _overlay: CanvasLayer
var _film_rect: ColorRect
var _destinations: Array[Vector2i] = []
var _last_layout: Dictionary = {}
var _gi_refresh_tracker := preload("res://scripts/diagnostics/geometry_refresh_tracker.gd").new()
var _gi_refresh_ticket:=0
var _frame_metrics := preload("res://scripts/diagnostics/frame_metrics.gd").new()

func _ready() -> void:
	# Window close uses the same ordered render-thread shutdown as the menu.
	get_tree().auto_accept_quit = false
	_setup_inputs()
	_load_settings()
	if "--formal-hall" in OS.get_cmdline_user_args(): _spawn_mode="formal"
	if "--expanded-world" in OS.get_cmdline_user_args(): _spawn_mode="expanded"
	if "--legacy-world" in OS.get_cmdline_user_args() or "--original-world" in OS.get_cmdline_user_args(): _spawn_mode="original"
	_pc_preview_return_spawn = _spawn_mode
	_pc_mainhall_preview = MainhallPreview.requested()
	if _pc_mainhall_preview: _spawn_mode = "formal"
	_qa = "--qa" in OS.get_cmdline_user_args()
	if not _configure_qa_capture_resolution(OS.get_cmdline_user_args()):
		get_tree().quit(2)
		return
	if _qa:
		world_seed = 250821
		_ccd_on = false
		if "--qa-user-water" not in OS.get_cmdline_user_args(): _water_settings.clear()
		_water_visible=true
	if MainhallPreview.desktop_allowed() and "--no-exploration-notes" not in OS.get_cmdline_user_args():
		_exploration_notes = preload("res://scripts/gameplay/exploration_notes.gd").new()
		_exploration_notes.name = "ExplorationNotes"
		add_child(_exploration_notes)
		_exploration_notes.initialize_store(true)
	_build_interface()
	materials = MaterialsScript.new()
	lighting = LightingScript.new()
	# PC candidates remain explicit until native same-camera acceptance.
	if _qa and "--qa-distributed-basin-return" in OS.get_cmdline_user_args():
		lighting.set_formal_basin_return_distribution_enabled(true)
	if _qa and "--qa-formal-projection-fast-path" in OS.get_cmdline_user_args():
		materials.set_formal_projection_fast_path_enabled(true)
	# Authored-sky comparison is opt-in until its actual room image is accepted.
	# It never changes the original-room palette or saved user settings.
	if _pc_mainhall_preview or (_qa and "--qa-formal-physical-sky" in OS.get_cmdline_user_args()):
		lighting.set_formal_physical_sky_enabled(true)
	lighting.capture_lighting_changed.connect(_capture_lighting_changed)
	environment = WorldEnvironment.new()
	environment.name = "PoolEnvironment"
	add_child(environment)
	lighting.configure_environment(environment)
	if _pc_mainhall_preview: environment.environment.sdfgi_enabled = false
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-sdfgi-cascades="):
			environment.environment.sdfgi_cascades=clampi(int(argument.trim_prefix("--qa-sdfgi-cascades=")),4,8)
	pool_audio = AudioScript.new()
	pool_audio.name = "OriginalSoundscape"
	add_child(pool_audio)
	pool_audio.set_enabled(_audio_on)
	pool_audio.set_ambience(_ambience_on)
	_create_world()
	_booted = true
	_apply_quality(_quality)
	_set_gi(_gi_on)
	set_menu(true)
	var renderer := RenderingServer.get_current_rendering_method()
	print("POOLCORE_NATIVE_BOOT ",JSON.stringify({"version":str(ProjectSettings.get_setting("application/config/version","development")),"seed":world_seed,"seed_input_guard_revision":SEED_INPUT_GUARD_REVISION,"renderer":renderer,"device":RenderingServer.get_video_adapter_name()}))
	if renderer != "forward_plus":
		_renderer_warning.text = "当前不是 Forward+，光照与水体效果不完整。
请检查本机 Godot 渲染设备与 Vulkan / Direct3D 12 支持。"
		_renderer_warning.show()
	if _qa:
		call_deferred("_run_qa_capture")
	preload("res://scripts/mobile/pool_mobile_runtime.gd").install(self)
	if "--qa-legacy-quality" not in OS.get_cmdline_user_args():
		preload("res://scripts/rendering/desktop_quality_panel.gd").install(self)
	preload("res://scripts/ui/pool_interface_presentation.gd").install(self)

func _initial_water_quality() -> String:
	if preload("res://scripts/mobile/pool_mobile_profile.gd").is_mobile_session():
		return preload("res://scripts/mobile/pool_mobile_profile.gd").initial_water_quality()
	# Startup settings are already loaded. An installed desktop owner also
	# carries independently customized water precision when rebuilding a world.
	var requested := _quality.capitalize()
	var desktop := get_node_or_null("DesktopQuality")
	if desktop != null:
		var graphics: Variant = desktop.get("settings")
		if graphics is Dictionary: requested = str(graphics.get("water", requested))
	return requested if WaterScript.QUALITY.has(requested) else "High"

func _settle_created_world_lighting() -> void:
	# A new world must not begin captures with the previous room's tween values.
	# The longest existing room curve is 1.6 seconds. Ordinary walking retains
	# those curves; only explicit world construction finishes them synchronously.
	var mood:Tween=lighting.get("_mood_tween")
	if is_instance_valid(mood) and mood.is_valid() and mood.is_running():mood.custom_step(2.0)

func _create_world() -> void:
	_trace_world_lifecycle("construct_begin")
	# Retirement is an awaited phase owned by regenerate(), never constructor overlap.
	assert(not is_instance_valid(world) and not is_instance_valid(water))
	lighting.invalidate_active_room()
	water = WaterScript.new()
	water.name = "NativeWater"
	add_child(water)
	water.quality = _initial_water_quality()
	water.configure(materials)
	water.set_caustics(_caustics_on)
	water.set_enabled(_water_visible)
	for parameter: String in _water_settings: water.set_tuning(parameter,_water_settings[parameter])
	_prepare_facility_devices()
	props = PropsScript.new()
	props.name = "FloatingProps"
	add_child(props)
	props.initialize(materials,water)
	props.water_impact.connect(_water_impact)
	props.interaction.connect(_interaction)
	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.set_water(water)
	player.depth_wading_response_enabled = _depth_wading_enabled
	player.facility_devices = _facility_devices if is_instance_valid(_facility_devices) and _facility_devices.enabled else null
	player.water_impact.connect(_water_impact)
	player.interaction.connect(_interaction)
	player.pause_requested.connect(func(): set_menu(true))
	props.attach_player(player)
	avatar = null
	avatar = AvatarScript.new()
	if "--legacy-avatar-model" not in OS.get_cmdline_user_args():
		avatar.model_path = AvatarFinishScript.CANDIDATE_PATH
		if not preload("res://scripts/mobile/pool_mobile_profile.gd").is_mobile_session() and "--legacy-water-actions" not in OS.get_cmdline_user_args():
			avatar.model_path = "res://assets/water_motion/explorer_water_motion.scn"
	avatar.setup(player)
	_avatar_finish = AvatarFinishScript.new() if "--legacy-avatar-model" not in OS.get_cmdline_user_args() else null
	_avatar_finish_status = _avatar_finish.apply_to(avatar,_avatar_fabric_enabled and "--no-avatar-fabric-finish" not in OS.get_cmdline_user_args()) if _avatar_finish != null else {"enabled":false}
	if _avatar_finish != null and int(_avatar_finish_status.get("applied_surfaces",0)) != 2:
		push_warning("Avatar fabric surfaces were not both applied: " + str(_avatar_finish_status))
	avatar.visible = _avatar_enabled
	avatar.process_mode = Node.PROCESS_MODE_INHERIT if _avatar_enabled else Node.PROCESS_MODE_DISABLED
	# Native SSR is not the source water reflection. Its late separate-specular
	# merge conflicts with the exact opaque FogExp2 pass; formal rooms retain it.
	lighting.set_source_fog_model(_spawn_mode!="formal")
	if _pc_mainhall_preview:
		# Set the tested sky/sun/ambient rig BEFORE either capture is constructed.
		lighting._last_coord = Vector2i(2147483647,2147483647)
		lighting.update_active_room(Vector2i(-1,-1),preload("res://scripts/world/formal_rooms.gd").layout(Vector2i(-1,-1),world_seed))
		_settle_created_world_lighting()
		environment.environment.sdfgi_enabled = false
		_pc_preview_result = MainhallPreview.failure("Native mainhall installation pending")
	water.configure_camera(player.camera,environment.environment)
	distance_fog=_attach_distance_fog(player.camera)
	if is_instance_valid(water.planar) and is_instance_valid(water.planar.mirror):
		_capture_distance_fogs.append(_attach_distance_fog(water.planar.mirror))
	if is_instance_valid(water._probe) and is_instance_valid(water._probe._camera):
		_capture_distance_fogs.append(_attach_distance_fog(water._probe._camera))
	source_fog=SourceFog.new()
	source_fog.configure(player.camera)
	source_fog.enabled=_fog_on
	# Preserve source liquid/whitewater, append source shafts before native tonemap.
	var effects:Array[CompositorEffect]=player.camera.compositor.compositor_effects
	effects.append(source_fog)
	player.camera.compositor.compositor_effects=effects
	world = WorldScript.new()
	world.formal_mode = _spawn_mode == "formal"
	world.expanded_mode = _spawn_mode == "expanded"
	world.name = "SeededPoolWorld"
	add_child(world)
	world.room_loaded.connect(_on_room_loaded)
	world.room_changed.connect(_on_room_changed)
	world.streaming_completed.connect(_on_world_streamed)
	world.initialize(world_seed, materials)
	_settle_created_world_lighting()
	if world.formal_mode:
		player.warp_to(world.get_spawn_position(world.current_room),Vector3(-32,1,-35))
	elif world.expanded_mode:
		var spawn: Vector3 = world.get_spawn_position(world.current_room)
		player.warp_to(spawn,Vector3(0,1.8,-8))
	else:
		# 66a4543 engine.ts initial camera, translated into a feet-root body.
		player.camera.near=.08;player.camera.far=100.0
		player.warp_to(Vector3(10,1.5-PlayerScript.EYE_HEIGHT,12),Vector3(-4,1.9,-10))
	pool_audio.attach_player(player,water)
	player.set_enabled(false)
	_rebuild_destinations()
	if is_instance_valid(_exploration_notes):
		_exploration_notes.begin_world(world_seed, _spawn_mode)
		_exploration_notes.observe_player_room(world, player.global_position)

	_trace_world_lifecycle("construct_end")

func _trace_world_lifecycle(phase: String) -> void:
	# Event-only local engine log, not a GPU readback or per-frame telemetry.
	# Kept for diagnosing real live-switch reports; no automatic upload.
	if not is_inside_tree(): return
	var viewport := get_viewport()
	var current_world := viewport.find_world_3d()
	print("POOLCORE_WORLD_LIFECYCLE ", JSON.stringify({
		"phase": phase, "ticks_ms": Time.get_ticks_msec(), "pid": OS.get_process_id(),
		"selected_mode": _spawn_mode, "seed": world_seed,
		"world3d_id": current_world.get_instance_id() if current_world != null else 0,
		"scenario_id": current_world.scenario.get_id() if current_world != null else 0,
		"method": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"quality": _quality, "msaa_3d": viewport.msaa_3d, "taa": viewport.use_taa,
		"filter": _filter_mode, "gi_preference": _gi_on,
		"retiring": _retiring_world, "switching": _switching_spawn
	}))

func _retire_world() -> void:
	_trace_world_lifecycle("retire_begin")
	_retiring_world = true
	_gi_refresh_ticket += 1
	# Freeze the old scene; UI and DesktopQuality remain alive across all awaits.
	if is_instance_valid(world): world.set_process(false)
	if is_instance_valid(water): water.set_process(false)
	_dispose_distance_fog()
	if source_fog != null:
		source_fog.dispose()
		source_fog = null
	# dispose() detaches compositor/material aliases before it queues RD frees.
	if is_instance_valid(water): water.dispose()
	if is_instance_valid(_facility_devices): _facility_devices.clear()
	# Audio survives world replacement; detach before the old player leaves the tree.
	if is_instance_valid(pool_audio): pool_audio.attach_player(null, null)
	for old_node in [world, water, props, player]:
		if is_instance_valid(old_node):
			old_node.process_mode = Node.PROCESS_MODE_DISABLED
			if old_node.get_parent() == self: remove_child(old_node)
			old_node.queue_free()
	world = null
	water = null
	props = null
	player = null
	avatar = null
	_avatar_finish = null
	_avatar_finish_status.clear()
	# process_frame fires BEFORE node processing. Two boundaries safely include
	# the deferred deletion flush even when called from another process_frame.
	await get_tree().process_frame
	if not _booted: return
	await get_tree().process_frame
	if not _booted: return
	# This orders queued release callbacks, not a promise of reclaimed GPU/OS RAM.
	# Dummy headless rendering does not emit frame_post_draw.
	if DisplayServer.get_name() != "headless":
		var barrier := WorldRetirementBarrier.new()
		RenderingServer.call_on_render_thread(barrier.mark)
		while not barrier.ready():
			await get_tree().process_frame
			if not _booted: return
		await RenderingServer.frame_post_draw
	_trace_world_lifecycle("retire_end")

func _apply_live_water(method: StringName, arguments: Array) -> void:
	# UI callbacks still retain/save intent while no live water instance exists.
	if not _retiring_world and is_instance_valid(water): water.callv(method, arguments)

func _prepare_facility_devices() -> void:
	_facility_world_epoch += 1
	var opt_in := _spawn_mode == "formal" and not OS.has_feature("android") and not OS.has_feature("ios") and "--no-formal-return-valves" not in OS.get_cmdline_user_args()
	if not opt_in:
		if is_instance_valid(_facility_devices): _facility_devices.clear()
		return
	if not is_instance_valid(_facility_devices):
		_facility_devices = FacilityDevicesScript.new()
		_facility_devices.name = "OptionalFormalReturnValves"
		add_child(_facility_devices)
	# A new generation resets state even if the user regenerates the same seed.
	_facility_devices.configure_world("formal/%d" % _facility_world_epoch, world_seed, _facility_enabled)
	if not _facility_devices.bind_source_water(water):
		push_warning("Return valves remain mechanical only: source water was not bound")

func _on_room_loaded(room: Node3D,coord: Vector2i,layout: Dictionary) -> void:
	if _retiring_world: return
	lighting.add_formal_lights(room,layout) if layout.get("formal",false) else lighting.add_room_lights(room,int(layout.variant))
	if _pc_mainhall_preview and coord == Vector2i(-1,-1) and layout.get("formal",false):
		_pc_preview_result = MainhallPreview.install(room,materials,environment.environment,environment.get_node_or_null("ApertureSun"))
		_refresh_pc_preview_interface()
		print("PC_MAINHALL_LIGHTMAP_PREVIEW ",JSON.stringify(_pc_preview_result))
	water.add_room(room,coord,layout)
	props.spawn_for_room(room,coord,layout,world_seed)
	if is_instance_valid(_facility_devices) and _facility_devices.enabled:
		_facility_devices.attach_formal_room(room,coord,layout)

func _on_room_changed(coord: Vector2i,layout: Dictionary) -> void:
	if _retiring_world: return
	_last_layout = layout
	water.set_active_room(coord)
	_room_title.text = "%s   /   %s" % [layout.get("name","泳池"),layout.get("subtitle","")]
	pool_audio.set_room(layout)
	if lighting.has_method("update_active_room"):
		lighting.call("update_active_room",coord,layout)

func _capture_lighting_changed() -> void:
	if _retiring_world: return
	# Called by room palette changes and DesktopQuality. Never change requested GI.
	if _pc_mainhall_preview and is_instance_valid(environment): environment.environment.sdfgi_enabled = false
	if is_instance_valid(water):
		water.refresh_capture_lighting()
		if _pc_mainhall_preview:
			# Normal source-cube invalidation can defer its deep snapshot until terrain
			# commits. Synchronize now so even its idle first environment is correct.
			if is_instance_valid(water._probe): water._probe._copy_capture_environment()
			if is_instance_valid(water.planar) and is_instance_valid(water.planar.mirror): water.planar.mirror.environment.sdfgi_enabled = false
			if is_instance_valid(water._probe) and is_instance_valid(water._probe._camera): water._probe._camera.environment.sdfgi_enabled = false

func effective_gi_requested(value: bool) -> bool:
	return value and not _pc_mainhall_preview

func _set_pc_mainhall_preview(enabled: bool, target_spawn: String = "") -> void:
	if not MainhallPreview.desktop_allowed() or _switching_spawn:
		_refresh_pc_preview_interface()
		return
	if enabled == _pc_mainhall_preview and target_spawn.is_empty(): return
	_pc_preview_pending = 1 if enabled else 0
	_pc_preview_target_spawn = target_spawn
	regenerate(world_seed)

func _refresh_pc_preview_interface() -> void:
	if is_instance_valid(_pc_preview_check):
		_pc_preview_check.set_pressed_no_signal(_pc_mainhall_preview)
		_pc_preview_check.disabled = _switching_spawn
	if not is_instance_valid(_pc_preview_status): return
	_pc_preview_status.visible = _pc_mainhall_preview
	if _pc_mainhall_preview:
		_pc_preview_status.text = "实验预览：仅主池厅有原生烘焙，SDFGI 暂停；其余 4 厅保留直接光/环境光，但间接光不等价。退出恢复所选 GI。\n" + ("MAINHALL BAKE ACTIVE · EXPERIMENTAL" if _pc_preview_result.get("installed",false) else "BAKE UNAVAILABLE · 原场景保留：" + str(_pc_preview_result.get("reason","loading")))
		_pc_preview_status.tooltip_text = MainhallPreview.SCOPE


func _physics_process(_delta: float) -> void:
	if not _booted or _switching_spawn: return
	world.update_player_position(player.global_position)
	if is_instance_valid(_exploration_notes):
		_exploration_notes.observe_player_room(world, player.global_position)
	if is_instance_valid(_facility_devices):
		_facility_devices.advance(_delta,world.current_room,not menu_open and player.enabled)
	if player.global_position.y < -12.0:
		travel_to(world.current_room)

func _process(delta: float) -> void:
	if not _booted or _retiring_world: return
	_frame_metrics.push_tick(Time.get_ticks_usec())
	if source_fog != null:source_fog.frame(delta,world.current_room,_last_layout)
	if distance_fog != null:
		distance_fog.frame(delta,world.current_room,_last_layout)
		if is_instance_valid(water) and water.has_method("set_source_fog"):water.set_source_fog(distance_fog.density,not bool(_last_layout.get("formal",false) or _last_layout.get("expanded",false)))
		for capture:CompositorEffect in _capture_distance_fogs:
			capture.set_density(distance_fog.density,bool(_last_layout.get("formal",false) or _last_layout.get("expanded",false)))
	if is_instance_valid(player) and lighting.has_method("update_source_view"):lighting.update_source_view(player.camera)
	_status_interval += delta
	if _status_interval < 0.2: return
	_status_interval = 0.0
	if menu_open: _refresh_preparation_interface()
	var coord: Vector2i = world.current_room
	_status.text = "SECTOR %02d / %02d   ·   SEED %d   ·   %d ROOMS" % [coord.x,coord.y,world_seed,world.get_discovered_count()]
	if _pc_mainhall_preview:
		_status.text += " · EXPERIMENTAL MAINHALL BAKE" if _pc_preview_result.get("installed",false) else " · BAKE UNAVAILABLE / ORIGINAL VISUALS"
	var ps: Dictionary = player.get_status()
	_crosshair.visible = not hud_hidden and not menu_open
	_crosshair.text = "◉" if not str(ps.get("held","")).is_empty() else "·"
	_charge_bar.value=float(ps.get("charge",0.0))*100.0
	_charge_bar.visible=_charge_bar.value>0.0 and not hud_hidden and not menu_open
	_hint.visible = not hud_hidden and not menu_open
	_hint.text = str(ps.get("hint","WASD 移动 · Esc 菜单"))
	if diagnostic_open:
		_diag.text = "Godot %s · %s\n%s\n%.0f FPS · %d resident rooms · %d props\nDraw calls %d · triangles %d\nPosition %.2f, %.2f, %.2f\nNative GI %s · water caustics %s\nThis is a native port, not the HTML renderer." % [str(Engine.get_version_info().get("string","unknown")),RenderingServer.get_current_rendering_method(),RenderingServer.get_video_adapter_name(),Engine.get_frames_per_second(),world.resident_rooms.size(),props.bodies.size(),RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),player.position.x,player.position.y,player.position.z,str(_gi_on),str(_caustics_on)]
		if _pc_mainhall_preview: _diag.text += "\n" + MainhallPreview.SCOPE + "\nBake installed: " + str(_pc_preview_result.get("installed",false))
		var timing: Dictionary = _frame_metrics.summary()
		_diag.text += "\nFrame time p50 %.1f / p95 %.1f / p99 %.1f ms · G hides this panel" % [timing.p50_ms,timing.p95_ms,timing.p99_ms]
		var water_stats:Dictionary=water.debug_stats()
		_diag.text += "\nWater terrain: %s · cache hits %d · commit %.2f ms" % ["preparing" if water_stats.terrain_pending else "ready",water_stats.terrain_cache_hits,float(water_stats.terrain_stage_ms.commit_ms)]
		_diag.text += "\nHDR room cache: %d · async captures %d" % [int(water_stats.probe.get("cache_hits",0)),int(water_stats.probe.get("captures_completed",0))]

func _unhandled_input(event: InputEvent) -> void:
	if not _booted or _switching_spawn: return
	if event.is_action_pressed("pause"):
		set_menu(not menu_open)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_H:
				hud_hidden = not hud_hidden
				_room_title.visible = not hud_hidden
				_status.visible = not hud_hidden
			KEY_G:
				diagnostic_open = not diagnostic_open
				_diag.visible = diagnostic_open
			KEY_F:
				_set_filter((_filter_mode+1)%4)
			KEY_V:
				_set_gi(not _gi_on)
			KEY_C:
				_caustics_on=not _caustics_on
				water.set_caustics(_caustics_on)
			KEY_R:
				if not menu_open:
					player.release_prop()
					travel_to(Vector2i(-1,-1) if world.formal_mode else Vector2i.ZERO)
			KEY_F11:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _refresh_preparation_interface() -> void:
	# Menu reopening must not display the last cold-launch state for another
	# status polling interval. This reads readiness only; it never skips it.
	if not is_instance_valid(_resume): return
	if _switching_spawn:
		_resume.disabled = true
		_resume.text = "正在切换场景 / SWITCHING WORLD…"
		if is_instance_valid(_loading_status):
			_loading_status.text = "正在释放上一场景 / RELEASING PREVIOUS WORLD…"
			_loading_status.show()
		return
	if not is_instance_valid(water): return
	_resume.disabled = _switching_spawn or not water.is_terrain_ready()
	_resume.text = "正在准备水体 / PREPARING WATER…" if _resume.disabled else "继续探索 / CONTINUE"
	if is_instance_valid(_loading_status) and water.has_method("get_preparation_status"):
		_loading_status.text = preload("res://scripts/diagnostics/preparation_status.gd").describe(water.get_preparation_status())
		_loading_status.visible = not _loading_status.text.is_empty()

func set_menu(value: bool) -> void:
	# Initial static optical data prepares without freezing the menu. Do not let
	# floating actors fall through an unprepared depth field on a cold launch.
	if not value and (_switching_spawn or (is_instance_valid(water) and not water.is_terrain_ready())): value=true
	if value and is_instance_valid(_exploration_notes):
		_exploration_notes.flush()
		_exploration_notes.refresh_menu_summary()
	menu_open = value
	_menu.visible = value
	_refresh_pc_preview_interface()
	if is_instance_valid(_advanced): _advanced.visible=false
	if is_instance_valid(_gi_check): _gi_check.set_pressed_no_signal(_gi_on)
	if is_instance_valid(_caustics_check): _caustics_check.set_pressed_no_signal(_caustics_on)
	if is_instance_valid(_looks): _looks.select(_filter_mode)
	if is_instance_valid(player): player.set_enabled(not value)
	if is_instance_valid(props): props.set_enabled(not value)
	if is_instance_valid(water):
		if not _retiring_world: water.process_mode=Node.PROCESS_MODE_INHERIT
		water.set_paused(value)
	if is_instance_valid(pool_audio): pool_audio.set_active(not value)
	_resume.text = "进入泳池 / CONTINUE" if is_instance_valid(world) and world.get_discovered_count() <= 1 else "继续探索 / CONTINUE"
	if value: _refresh_preparation_interface()

func travel_to(coord: Vector2i) -> void:
	if _switching_spawn or not _booted: return
	if world.formal_mode and coord not in preload("res://scripts/world/formal_rooms.gd").COORDS: coord=Vector2i(-1,-1)
	player.set_enabled(false)
	var spawn: Vector3 = world.teleport_to_room(coord)
	player.warp_to(spawn,Vector3(coord.x*32,3.0,coord.y*32-8))
	if not water.is_terrain_ready():set_menu(true)
	player.set_enabled(not menu_open)

static func parse_seed_input(text: String) -> Dictionary:
	# Check decimal syntax and magnitude before int(); Godot conversions can wrap.
	var digits := text.strip_edges()
	var negative := digits.begins_with("-")
	if negative or digits.begins_with("+"): digits = digits.substr(1)
	var syntax_error := "请输入整数种子（不可含小数或字母）。 / Enter an integer seed (no decimals or letters)."
	if digits.is_empty(): return {"ok":false,"reason":syntax_error}
	for index: int in digits.length():
		var code := digits.unicode_at(index)
		if code < 48 or code > 57: return {"ok":false,"reason":syntax_error}
	var first_nonzero := 0
	while first_nonzero < digits.length() and digits.unicode_at(first_nonzero) == 48:
		first_nonzero += 1
	if first_nonzero == digits.length(): return {"ok":true,"seed":0}
	digits = digits.substr(first_nonzero)
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit):
		return {"ok":false,"reason":"种子超出有符号 64 位整数范围。 / Seed is outside the signed 64-bit range.\n-9223372036854775808 … 9223372036854775807"}
	if negative and digits == "9223372036854775808":
		return {"ok":true,"seed":-9223372036854775807 - 1}
	var value := int(digits)
	return {"ok":true,"seed":-value if negative else value}

func _read_seed_input() -> Dictionary:
	var result := parse_seed_input(_seed_edit.text if is_instance_valid(_seed_edit) else "")
	if is_instance_valid(_world_restart_status): _world_restart_status.text = ""
	if is_instance_valid(_seed_input_status):
		_seed_input_status.text = "" if result.ok else str(result.reason)
		_seed_input_status.visible = not result.ok
	return result

func _rebuild_seed_world() -> void:
	if _switching_spawn or not _booted: return
	var parsed := _read_seed_input()
	if not parsed.ok: return
	regenerate(parsed.seed)

func _choose_spawn(index:int)->void:
	if _switching_spawn or not _booted:
		if is_instance_valid(_spawn_select): _spawn_select.select(maxi(0,SPAWN_MODES.find(_spawn_mode)))
		return
	var parsed := _read_seed_input()
	if not parsed.ok: return
	var chosen: String = SPAWN_MODES[clampi(index,0,SPAWN_MODES.size()-1)]
	if _pc_mainhall_preview:
		_set_pc_mainhall_preview(false,chosen)
		return
	_spawn_mode=chosen
	# Explicit menu action, never a hidden teleport or a deletion of either world.
	regenerate(parsed.seed)

func _restart_into_selected_world() -> void:
	if not is_instance_valid(_spawn_select) or not is_instance_valid(_seed_edit): return
	var parsed := _read_seed_input()
	if not parsed.ok: return
	var selected := _spawn_select.selected
	if selected < 0 or selected >= SPAWN_MODES.size(): return
	var save_selection := func(mode: String, seed_value: int) -> Error:
		var desktop := get_node_or_null("DesktopQuality")
		if desktop != null:
			var graphics_saved: Error = desktop.save_settings()
			if graphics_saved != OK: return graphics_saved
		return _save_settings(mode, seed_value, true)
	var result: Dictionary = _world_restart.request(SPAWN_MODES[selected], parsed.seed, _switching_spawn or _retiring_world or not _booted, save_selection, _safe_quit)
	_world_restart_status.text = str(result.reason)
	if result.ok:
		_switching_spawn = true
		_world_restart_button.disabled = true
		_spawn_select.disabled = true
		set_menu(true)

func regenerate(seed_value: int) -> void:
	if _switching_spawn or not _booted:return
	_switching_spawn=true
	_gi_refresh_ticket+=1
	set_menu(true)
	if is_instance_valid(water):
		water.suspend_preparation(true)
		while water.preparation_pending():
			await get_tree().process_frame
			if not _booted: return
	await _retire_world()
	if not _booted: return # Quit may have won while retirement yielded.
	if _pc_preview_pending != -1:
		var enabled := _pc_preview_pending == 1
		if enabled and not _pc_mainhall_preview: _pc_preview_return_spawn = _spawn_mode
		_pc_mainhall_preview = enabled
		_spawn_mode = "formal" if enabled else (_pc_preview_target_spawn if not _pc_preview_target_spawn.is_empty() else _pc_preview_return_spawn)
		_pc_preview_pending = -1
		_pc_preview_target_spawn = ""
		lighting.set_formal_physical_sky_enabled(enabled or (_qa and "--qa-formal-physical-sky" in OS.get_cmdline_user_args()))
		lighting._last_coord = Vector2i(2147483647,2147483647)
		if is_instance_valid(_spawn_select): _spawn_select.select(maxi(0,SPAWN_MODES.find(_spawn_mode)))
	world_seed = seed_value
	_retiring_world = false
	_create_world()
	_apply_quality(_quality)
	_set_gi(_gi_on)
	_switching_spawn=false
	set_menu(true)
	_save_settings()
	_trace_world_lifecycle("switch_complete")

func _water_impact(at: Vector3,power: float) -> void:
	# Player/prop native physics already injects the water impulse.
	pool_audio.impact(at,power)

func _interaction(kind: String,at: Vector3,power: float) -> void:
	pool_audio.interaction(kind,at,power)

func _setup_inputs() -> void:
	var keys := {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E,"pause":KEY_ESCAPE}
	for action: String in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode=keys[action]
		InputMap.action_add_event(action,event)
	for action: String in {"grab_prop":MOUSE_BUTTON_LEFT,"throw_prop":MOUSE_BUTTON_RIGHT}:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT if action == "grab_prop" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action,event)

func _build_interface() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "NativeInterface"
	add_child(_overlay)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(ui)
	var theme := Theme.new()
	theme.default_font_size=16
	var font := SystemFont.new()
	font.font_names=PackedStringArray(["Noto Sans CJK SC","Microsoft YaHei","Noto Sans","Arial"])
	theme.default_font=font
	ui.theme=theme
	_crosshair=Label.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.position=Vector2(-10,-16)
	_crosshair.size=Vector2(20,32)
	_crosshair.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.add_theme_font_size_override("font_size",24)
	_crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(_crosshair)
	_charge_bar=ProgressBar.new()
	_charge_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_charge_bar.position=Vector2(-75,-80)
	_charge_bar.size=Vector2(150,5)
	_charge_bar.show_percentage=false
	_charge_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_charge_bar.visible=false
	ui.add_child(_charge_bar)
	_room_title = Label.new()
	_room_title.position=Vector2(28,25)
	_room_title.add_theme_color_override("font_color",Color(0.88,0.94,0.92))
	ui.add_child(_room_title)
	_status=Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position=Vector2(28,-43)
	_status.add_theme_font_size_override("font_size",13)
	ui.add_child(_status)
	_hint=Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.position=Vector2(-630,-43)
	_hint.size=Vector2(602,25)
	_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size",13)
	ui.add_child(_hint)
	_diag=Label.new()
	_diag.position=Vector2(28,72)
	_diag.add_theme_font_size_override("font_size",14)
	_diag.visible=false
	ui.add_child(_diag)
	_renderer_warning=Label.new()
	_renderer_warning.position=Vector2(28,52)
	_renderer_warning.add_theme_color_override("font_color",Color(1.0,0.75,0.25))
	_renderer_warning.add_theme_font_size_override("font_size",15)
	_renderer_warning.hide()
	ui.add_child(_renderer_warning)
	_menu=PanelContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.position=Vector2(-260,-285)
	_menu.custom_minimum_size=Vector2(520,570)
	_menu.size=Vector2(520,570)
	var panel := StyleBoxFlat.new()
	panel.bg_color=Color(0.025,0.045,0.05,0.96)
	panel.border_color=Color(0.37,0.54,0.52,0.65)
	panel.set_border_width_all(1)
	panel.content_margin_left=30
	panel.content_margin_right=30
	panel.content_margin_top=25
	panel.content_margin_bottom=24
	_menu.add_theme_stylebox_override("panel",panel)
	ui.add_child(_menu)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size=Vector2(460,520)
	_menu.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",9)
	scroll.add_child(column)
	var brand := Label.new()
	brand.text="BEYOND THE BASIN"
	brand.add_theme_font_size_override("font_size",28)
	column.add_child(brand)
	var sub := Label.new()
	sub.text="POOLCORE · PC EXPLORER EDITION\n原版 / 主池厅 / 扩展随机地图 · 骨骼角色 · 原水体交互"
	sub.add_theme_color_override("font_color",Color(0.66,0.79,0.76))
	sub.add_theme_font_size_override("font_size",14)
	column.add_child(sub)
	var spawn_label:=Label.new()
	spawn_label.text="出生地 / STARTING WORLD"
	column.add_child(spawn_label)
	var spawn_row:=HBoxContainer.new()
	_spawn_select=OptionButton.new()
	_spawn_select.name="StartingWorld"
	_spawn_select.add_item("原仓库场景 / ORIGINAL",0)
	_spawn_select.add_item("重做主池厅 / FORMAL HALL",1)
	_spawn_select.add_item("扩展随机地图 / EXPANDED",2)
	_spawn_select.select(maxi(0,SPAWN_MODES.find(_spawn_mode)))
	_spawn_select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	spawn_row.add_child(_spawn_select)
	spawn_row.add_child(_button("在此出生",func():_choose_spawn(_spawn_select.selected)))
	column.add_child(spawn_row)
	if MainhallPreview.desktop_allowed():
		_world_restart_button = _button("重启到所选世界 / RESTART INTO SELECTED WORLD", _restart_into_selected_world)
		_world_restart_button.add_theme_font_size_override("font_size", 13)
		_world_restart_button.tooltip_text = "完全退出后重新打开；可选兼容方式，不保证修复黑屏/绿屏。 / Optional fresh-process fallback, not a black/green-screen fix."
		column.add_child(_world_restart_button)
		_world_restart_status = Label.new()
		_world_restart_status.add_theme_font_size_override("font_size", 12)
		_world_restart_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(_world_restart_status)
	if MainhallPreview.desktop_allowed():
		_pc_preview_check = _add_check(column,"实验主池厅烘焙 / EXPERIMENTAL PC PREVIEW",_pc_mainhall_preview,_set_pc_mainhall_preview)
		_pc_preview_check.name = "PCMainhallLightmapPreview"
		_pc_preview_check.tooltip_text = "Rebuild into mainhall preview. Session only; saved graphics preferences are not overwritten. " + MainhallPreview.SCOPE
		_pc_preview_status = Label.new()
		_pc_preview_status.name = "PCMainhallPreviewStatus"
		_pc_preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pc_preview_status.add_theme_font_size_override("font_size",12)
		_pc_preview_status.add_theme_color_override("font_color",Color(1.0,.8,.4))
		column.add_child(_pc_preview_status)
		_refresh_pc_preview_interface()
	_resume=_button("进入泳池 / CONTINUE",func():set_menu(false))
	column.add_child(_resume)
	_loading_status=Label.new()
	_loading_status.name="PreparationStatus"
	_loading_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_loading_status.add_theme_font_size_override("font_size",12)
	_loading_status.add_theme_color_override("font_color",Color(0.73,0.83,0.8))
	_loading_status.hide()
	column.add_child(_loading_status)
	var travel_row := HBoxContainer.new()
	_destination=OptionButton.new()
	_destination.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	travel_row.add_child(_destination)
	travel_row.add_child(_button("前往",func():travel_to(_destinations[_destination.selected]);set_menu(false)))
	column.add_child(travel_row)
	var seed_row := HBoxContainer.new()
	_seed_edit=LineEdit.new()
	_seed_edit.text=str(world_seed)
	_seed_edit.placeholder_text="World seed"
	_seed_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	seed_row.add_child(_button("重建种子世界",_rebuild_seed_world))
	column.add_child(seed_row)
	_seed_input_status = Label.new()
	_seed_input_status.name = "SeedInputStatus"
	_seed_input_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seed_input_status.add_theme_font_size_override("font_size",12)
	_seed_input_status.add_theme_color_override("font_color",Color(1.0,.8,.4))
	_seed_input_status.hide()
	column.add_child(_seed_input_status)
	if is_instance_valid(_exploration_notes): _exploration_notes.add_menu_summary(column)
	_gi_check=_add_check(column,"原生间接光 / SDFGI",_gi_on,func(v):_set_gi(v);_save_settings())
	_caustics_check=_add_check(column,"水下焦散 / CAUSTICS",_caustics_on,func(v):_caustics_on=v;_apply_live_water("set_caustics",[v]);_save_settings())
	_add_check(column,"显示角色身体 / PLAYER BODY",_avatar_enabled,_set_avatar_enabled)
	_add_check(column,"衣物织纹 / CLOTH FINISH",_avatar_fabric_enabled,_set_avatar_fabric_enabled)
	if MainhallPreview.desktop_allowed():
		_add_check(column,"主厅设施互动 / QUIET VALVES",_facility_enabled,_set_facility_enabled)
		_add_check(column,"深水步行减速 / DEPTH RESPONSE",_depth_wading_enabled,func(v):
			_depth_wading_enabled=v
			if is_instance_valid(player): player.depth_wading_response_enabled=v
			_save_settings())
	_add_check(column,"声音 / ORIGINAL SOUND EFFECTS",_audio_on,func(v):_audio_on=v;pool_audio.set_enabled(v);_save_settings())
	_add_check(column,"空间底噪 / AMBIENCE",_ambience_on,func(v):_ambience_on=v;pool_audio.set_ambience(v);_save_settings())
	var looks:=OptionButton.new()
	_looks=looks
	for look_name in ["镜头：原始 / CLEAN","镜头：CCD 摄像机","镜头：VHS 录像","镜头：冷色纪实"]: looks.add_item(look_name)
	looks.item_selected.connect(_set_filter)
	column.add_child(looks)
	column.add_child(_button("水体与图层设置 / WATER",func():_menu.hide();_advanced.show()))
	var controls:=Label.new()
	controls.text="WASD 移动 · Shift 奔跑 · Space 跳跃 · E 扶梯/阀门\n左键抓取/拖动 · 右键蓄力投掷 · 滚轮：上推远 / 下拉近\nH 隐藏界面 · G 诊断 · F11 全屏 · Esc 暂停"
	controls.add_theme_font_size_override("font_size",13)
	controls.add_theme_color_override("font_color",Color(0.64,0.73,0.72))
	column.add_child(controls)
	_copy_diagnostics_button=_button("复制运行诊断 / COPY DIAGNOSTICS",_copy_diagnostics)
	column.add_child(_copy_diagnostics_button)
	column.add_child(_button("退出 / QUIT",func():_safe_quit()))
	var film_layer:=CanvasLayer.new()
	film_layer.layer=2
	add_child(film_layer)
	_film_rect=ColorRect.new()
	_film_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_film_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader:=Shader.new()
	shader.code="shader_type canvas_item; uniform sampler2D screen_tex:hint_screen_texture,filter_linear; uniform int look_mode=1; void fragment(){vec2 uv=SCREEN_UV;if(look_mode==2){uv.x+=sin(uv.y*370.0+TIME*8.0)*0.0006;}vec3 c=texture(screen_tex,uv).rgb;float grain=fract(sin(dot(FRAGCOORD.xy+TIME*53.0,vec2(12.9898,78.233)))*43758.5453)-0.5;vec2 v=SCREEN_UV-0.5;if(look_mode==1){c*=1.0-dot(v,v)*0.23;c+=grain*0.018;}else if(look_mode==2){c.r=texture(screen_tex,uv+vec2(0.0015,0)).r;c.b=texture(screen_tex,uv-vec2(0.0015,0)).b;c*=0.98+sin(FRAGCOORD.y*3.14)*0.02;c+=grain*0.025;}else if(look_mode==3){float l=dot(c,vec3(0.2126,0.7152,0.0722));c=mix(vec3(l),c,0.72)*vec3(0.94,1.01,1.07);}COLOR=vec4(c,1.0);}"
	var film_mat:=ShaderMaterial.new()
	film_mat.shader=shader
	_film_rect.material=film_mat
	film_layer.add_child(_film_rect)
	_film_rect.visible=_ccd_on
	_build_water_panel(ui)

func _set_avatar_fabric_enabled(value: bool) -> void:
	_avatar_fabric_enabled = value
	if _avatar_finish != null:
		_avatar_finish.set_enabled(value)
		_avatar_finish_status["enabled"] = value
	_save_settings()

func _set_facility_enabled(value: bool) -> void:
	_facility_enabled = value
	if is_instance_valid(_facility_devices) and _spawn_mode == "formal":
		_facility_devices.set_enabled(value)
		if value and is_instance_valid(world):
			for coord: Vector2i in world.resident_rooms:
				_facility_devices.attach_formal_room(world.resident_rooms[coord],coord,world.get_layout(coord))
	if is_instance_valid(player):
		player.facility_devices = _facility_devices if value and is_instance_valid(_facility_devices) and _facility_devices.enabled else null
	_save_settings()

func _set_avatar_enabled(value: bool) -> void:
	_avatar_enabled = value
	if is_instance_valid(avatar):
		avatar.visible = value
		avatar.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	_save_settings()

func _set_filter(index: int) -> void:
	_filter_mode=clampi(index,0,3)
	_ccd_on=_filter_mode!=0
	if is_instance_valid(_film_rect):
		_film_rect.visible=_ccd_on
		(_film_rect.material as ShaderMaterial).set_shader_parameter("look_mode",_filter_mode)

func _on_world_streamed() -> void:
	if _retiring_world: return
	# SDFGI does not continuously rebuild static geometry added during streaming.
	# Refresh after the atomic streaming batch, not once per newly created mesh.
	if not effective_gi_requested(_gi_on) or not environment.environment or RenderingServer.get_current_rendering_method() != "forward_plus": return
	if not is_instance_valid(world):return
	var source_world_id:=world.get_instance_id()
	if not _gi_refresh_tracker.request(source_world_id,world.profile_counters):return
	_gi_refresh_ticket+=1
	var ticket:=_gi_refresh_ticket
	environment.environment.sdfgi_enabled=false
	await get_tree().process_frame
	if ticket==_gi_refresh_ticket and is_instance_valid(world) and world.get_instance_id()==source_world_id and is_instance_valid(environment) and effective_gi_requested(_gi_on) and RenderingServer.get_current_rendering_method() == "forward_plus": environment.environment.sdfgi_enabled=true

func _build_water_panel(ui: Control) -> void:
	_advanced=PanelContainer.new()
	_advanced.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_advanced.position=Vector2(-280,-285)
	_advanced.size=Vector2(560,570)
	_advanced.custom_minimum_size=Vector2(560,570)
	_advanced.add_theme_stylebox_override("panel",_menu.get_theme_stylebox("panel"))
	ui.add_child(_advanced)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(500,520)
	_advanced.add_child(scroll)
	var list:=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	var title:=Label.new()
	title.text="原生水体 / WATER & LAYERS"
	title.add_theme_font_size_override("font_size",22)
	list.add_child(title)
	if MainhallPreview.desktop_allowed():
		# Keep the small independent wind group visible before the advanced controls.
		_wind_controls.clear()
		var wind_check := _add_check(list, WaterSettingsScript.LAYERS.windWaves, bool(_water_settings.get("windWaves", WaterSettingsScript.DEFAULT.windWaves)), func(value):
			_water_settings["windWaves"] = value
			_apply_live_water("set_tuning", ["windWaves", value])
			_save_settings())
		wind_check.name = "WindWaves"
		wind_check.tooltip_text = WaterSettingsScript.WIND_TOOLTIPS.windWaves
		_wind_controls["windWaves"] = wind_check
		var wind_note := Label.new()
		wind_note.name = "WindOpticsNote"
		wind_note.text = "轻微室内风纹 · 水面光学近似，非完整风场物理。\n关闭风纹仍保留脚步、涉水和物体交互。"
		wind_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wind_note.add_theme_font_size_override("font_size", 12)
		list.add_child(wind_note)
		for row: Dictionary in WaterSettingsScript.SLIDERS:
			if row.key in WaterSettingsScript.WIND_KEYS:
				_wind_controls[row.key] = _add_water_slider(list, row)
		var wind_reset := _button("恢复轻微室内风 / RESET WIND", _reset_wind_settings)
		wind_reset.name = "ResetWind"
		wind_reset.tooltip_text = "只恢复风纹开关、强度、方向和细密度，不改变其他水体、画质、阴影或交互设置。"
		list.add_child(wind_reset)
		list.add_child(HSeparator.new())
	for row: Dictionary in WaterSettingsScript.SLIDERS:
		if row.key == "refractionRefresh" or row.key in WaterSettingsScript.WIND_KEYS: continue
		_add_water_slider(list, row)
	_add_check(list,"平面反射（原仓库镜像相机）",bool(_water_settings.get("ssr_enabled",_water_settings.get("reflection",true))),func(v):_water_settings["ssr_enabled"]=v;_apply_live_water("set_tuning",["ssr_enabled",v]);_save_settings())
	_add_check(list,"深度折射",bool(_water_settings.get("refraction_enabled",_water_settings.get("refraction",true))),func(v):_water_settings["refraction_enabled"]=v;_apply_live_water("set_tuning",["refraction_enabled",v]);_save_settings())
	for key:String in ["simulation","ripples","microNormals","absorption","fresnel","waterline","foam"]:
		var parameter:String=key
		var label:String=WaterSettingsScript.LAYERS[key]
		_add_check(list,label,bool(_water_settings.get(key,true)),func(v):_water_settings[parameter]=v;_apply_live_water("set_tuning",[parameter,v]);_save_settings())
	_add_check(list,"原仓库体积光束 / SOURCE LIGHT SHAFTS",_fog_on,func(v):_set_source_fog(v);_save_settings())
	_add_check(list,"显示水面",_water_visible,func(v):_water_visible=v;_apply_live_water("set_enabled",[v]);_save_settings())
	var debug:=OptionButton.new()
	for label in ["完整水面","浅水高度","速度场","模拟法线","细波纹","最终法线","水深","Fresnel","折射","焦散","反射","浮沫"]:debug.add_item(label)
	debug.select(clampi(int(_water_settings.get("debug_view",_water_settings.get("debugView",0))),0,11))
	debug.item_selected.connect(func(index):_water_settings["debug_view"]=index;_apply_live_water("set_debug_view",[index]);_save_settings())
	list.add_child(debug)
	list.add_child(_button("返回 / BACK",func():_advanced.hide();_menu.show()))
	_advanced.hide()

func _water_value_text(value: float, step: float) -> String:
	return String.num(value, 4 if step < 0.001 else (3 if step < 0.01 else (0 if step >= 1.0 else 2)))

func _add_water_slider(parent: Control, entry: Dictionary) -> HSlider:
	var row := HBoxContainer.new()
	var parameter: String = entry.key
	var tooltip: String = WaterSettingsScript.WIND_TOOLTIPS.get(parameter, "")
	row.tooltip_text = tooltip
	var label := Label.new()
	label.text = entry.label
	label.custom_minimum_size.x = 110
	label.tooltip_text = tooltip
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "Water_" + parameter
	slider.tooltip_text = tooltip
	slider.min_value = entry.min
	slider.max_value = entry.max
	slider.step = entry.step
	slider.value = _water_settings.get(parameter, entry.defval)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value):
		_water_settings[parameter] = value
		_apply_live_water("set_tuning", [parameter, value])
		_save_settings())
	row.add_child(slider)
	var numeric_value := Label.new()
	numeric_value.name = "NumericValue"
	numeric_value.custom_minimum_size.x = 64
	numeric_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	numeric_value.text = _water_value_text(slider.value, slider.step)
	slider.value_changed.connect(func(value): numeric_value.text = _water_value_text(value, slider.step))
	row.add_child(numeric_value)
	parent.add_child(row)
	return slider

func _reset_wind_settings() -> void:
	# Reset only the wind layer, without touching unrelated saved preferences.
	for key: String in WaterSettingsScript.WIND_KEYS:
		var value: Variant = WaterSettingsScript.DEFAULT[key]
		_water_settings[key] = value
		_apply_live_water("set_tuning", [key, value])
		var control: Control = _wind_controls.get(key)
		if control is CheckButton:
			control.set_pressed_no_signal(value)
		elif control is HSlider:
			control.set_value_no_signal(value)
			control.get_parent().get_node("NumericValue").text = _water_value_text(value, control.step)
	_save_settings()

func _render_diagnostics_state() -> Dictionary:
	# Read-only facts for a user-invoked report. Do not repair or reset state here.
	var state:Dictionary={"film_mode":_filter_mode,"film_visible":is_instance_valid(_film_rect) and _film_rect.visible}
	var depth_prepass_key:="rendering/driver/depth_prepass/enable"
	var depth_prepass_registered:=ProjectSettings.has_setting(depth_prepass_key)
	state.depth_prepass={"enabled":bool(ProjectSettings.get_setting_with_override(depth_prepass_key)) if depth_prepass_registered else true,"default":true,"registered":depth_prepass_registered}
	var viewport:=get_viewport()
	if is_instance_valid(viewport):
		state.actual={"msaa":viewport.msaa_3d,"taa":viewport.use_taa,"scale":viewport.scaling_3d_scale,"scaling_mode":viewport.scaling_3d_mode,"debug_draw":viewport.debug_draw,"hdr_2d":viewport.use_hdr_2d}
	var desktop:=get_node_or_null("DesktopQuality")
	if desktop!=null:
		var saved:Dictionary=desktop.get("settings")
		var supported:Dictionary=desktop.supported_features(RenderingServer.get_current_rendering_method())
		state.desired={"preset":desktop.get("preset"),"msaa":saved.get("msaa"),"taa":saved.get("taa"),"effective_taa":bool(saved.get("taa",false)) and bool(supported.get("taa",false)),"scale":saved.get("scale"),"water":saved.get("water")}
	if is_instance_valid(environment) and environment.environment!=null:
		var env:=environment.environment
		state.environment={"tonemap":env.tonemap_mode,"exposure":env.tonemap_exposure,"agx_contrast":env.tonemap_agx_contrast,"white":env.tonemap_white,"glow":env.glow_enabled,"gi":env.sdfgi_enabled,"ssr":env.ssr_enabled,"ssao":env.ssao_enabled,"ssil":env.ssil_enabled,"volumetric_fog":env.volumetric_fog_enabled,"adjustment":env.adjustment_enabled,"adjustment_brightness":env.adjustment_brightness,"adjustment_contrast":env.adjustment_contrast,"adjustment_saturation":env.adjustment_saturation}
		state.environment.gi_parameters={"bounce_feedback":env.sdfgi_bounce_feedback,"energy":env.sdfgi_energy,"cascades":env.sdfgi_cascades,"min_cell_size":env.sdfgi_min_cell_size,"sky":env.sdfgi_read_sky_light,"occlusion":env.sdfgi_use_occlusion}
		state.tonemap_finite=is_finite(env.tonemap_exposure) and is_finite(env.tonemap_agx_contrast) and is_finite(env.tonemap_white)
	if is_instance_valid(world):state.coord=[world.current_room.x,world.current_room.y]
	if is_instance_valid(water):state.water_debug_view=int(water.settings.get("debugView",0))
	state.compositors=[]
	if is_instance_valid(player) and is_instance_valid(player.camera):
		var attributes:CameraAttributes=player.camera.attributes
		state.camera_attributes={"type":attributes.get_class(),"exposure_multiplier":attributes.exposure_multiplier,"exposure_sensitivity":attributes.exposure_sensitivity,"auto_exposure":attributes.auto_exposure_enabled} if attributes!=null else {"type":"none"}
		if player.camera.compositor!=null:
			for effect:CompositorEffect in player.camera.compositor.compositor_effects:
				if effect==null:continue
				var effect_script:Script=effect.get_script()
				state.compositors.append({"effect":effect_script.resource_path.get_file() if effect_script!=null else effect.get_class(),"enabled":effect.enabled,"callback":effect.effect_callback_type,"resolved_color":effect.access_resolved_color,"resolved_depth":effect.access_resolved_depth,"motion_vectors":effect.needs_motion_vectors,"normal_roughness":effect.needs_normal_roughness,"separate_specular":effect.needs_separate_specular})
	return state

func _diagnostics_payload() -> Dictionary:
	# Read-only runtime facts. Never includes local paths, account details or keys.
	var result:Dictionary={"format":1,"application_version":str(ProjectSettings.get_setting("application/config/version","development")),"engine":str(Engine.get_version_info().get("string","unknown")),"platform":OS.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"seed":world_seed,"spawn_mode":_spawn_mode,"quality":_quality,"frame_times":_frame_metrics.summary(),"gi_refreshes":_gi_refresh_tracker.accepted,"gi_duplicate_notifications":_gi_refresh_tracker.duplicates}
	result.render_state=_render_diagnostics_state()
	if is_instance_valid(world):result.resident_rooms=world.resident_rooms.size()
	if is_instance_valid(player):result.position=str(player.global_position)
	if is_instance_valid(water) and water.has_method("debug_stats"):
		var state:Dictionary=water.debug_stats()
		result.render_state.initialization=state.get("initialization",{})
		for key:String in ["error","last_error","source_commit","terrain_ready","terrain_pending","native_readback_available","readback_parser_backend","caustics_refresh","caustic_error","liquid_error","preparation","terrain_stage_ms","cpu_frame_stages_ms","cpu_frame_stage_max_ms"]:
			if state.has(key):result[key]=state[key]
		if state.has("liquid"):result.liquid_timing=state.liquid.get("timing",{})
		if state.has("caustic_diagnostics"):
			var caustic:Dictionary=state.caustic_diagnostics
			result.caustic={"frames":caustic.get("frames",0),"readback_bytes":caustic.get("readback_bytes",0),"last_render_submit_ms":caustic.get("last_render_submit_ms",0),"gpu_timing":caustic.get("gpu_timing",{})}
	return result

func _copy_diagnostics() -> void:
	DisplayServer.clipboard_set(JSON.stringify(_diagnostics_payload(),"  "))
	if is_instance_valid(_copy_diagnostics_button):_copy_diagnostics_button.text="已复制诊断 / COPIED"

func _button(text: String,callback: Callable) -> Button:
	var b:=Button.new()
	b.text=text
	b.custom_minimum_size.y=36
	b.pressed.connect(callback)
	return b

func _add_check(parent: Node,text: String,value: bool,callback: Callable) -> CheckButton:
	var check:=CheckButton.new()
	check.text=text
	check.button_pressed=value
	check.toggled.connect(callback)
	parent.add_child(check)
	return check

func _rebuild_destinations() -> void:
	_destination.clear()
	_destinations.clear()
	if world.formal_mode:
		for coord in preload("res://scripts/world/formal_rooms.gd").COORDS:
			_destinations.append(coord);_destination.add_item(world.get_layout(coord).name)
		return
	var variants: Array = [11,12,13,14,0,1,2,3,4,5,6,7] if world.expanded_mode else range(8)
	for variant in variants:
		var found:=false
		for radius in range(0,9):
			if found: break
			for z in range(-radius,radius+1):
				if found: break
				for x in range(-radius,radius+1):
					var coord:=Vector2i(x,z)
					if int(world.get_layout(coord).variant)==variant:
						_destinations.append(coord)
						_destination.add_item("%02d  %s" % [variant,world.get_layout(coord).name])
						found=true
						break

func _apply_quality(value: String) -> void:
	# The desktop panel owns independently saved AA, scale and water overrides.
	# Regeneration must not transiently replace them with legacy preset defaults.
	var desktop := get_node_or_null("DesktopQuality")
	if desktop != null:
		if value == str(desktop.get("preset")):
			desktop.call("apply_settings")
		else:
			# Preserve explicit API requests to change tier; ordinary rebuilds retain
			# the same tier and never reset custom overrides.
			desktop.call("select_preset", value)
		return
	_quality=value
	# Mobile cannot resolve main MSAA depth for source splash/fog compositors.
	# Its own quality panel supplies real post-AA/supersampling instead.
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED if RenderingServer.get_current_rendering_method()=="mobile" else (Viewport.MSAA_8X if value=="Ultra" else Viewport.MSAA_4X)
	get_viewport().use_taa=RenderingServer.get_current_rendering_method()=="forward_plus"
	if RenderingServer.get_current_rendering_method()=="mobile":
		# The source compositors operate on linear HDR scene color. This also
		# covers explicit desktop Mobile launches without the touch UI adapter.
		get_viewport().use_hdr_2d=true
	if is_instance_valid(water) and not preload("res://scripts/mobile/pool_mobile_profile.gd").is_mobile_session(): water.set_quality(value.capitalize())

func _attach_distance_fog(camera:Camera3D)->CompositorEffect:
	var effect:=SourceDistanceFogScript.new()
	effect.configure(true)
	if camera.compositor==null:camera.compositor=Compositor.new()
	var effects:Array[CompositorEffect]=camera.compositor.compositor_effects
	effects.append(effect);camera.compositor.compositor_effects=effects
	return effect

func _dispose_distance_fog()->void:
	if distance_fog!=null:distance_fog.dispose();distance_fog=null
	for capture:CompositorEffect in _capture_distance_fogs:capture.dispose()
	_capture_distance_fogs.clear()

func _set_source_fog(value:bool)->void:
	_fog_on=value
	if source_fog != null:source_fog.enabled=value

func _set_gi(value: bool) -> void:
	_gi_on=value
	var changed := false
	if is_instance_valid(environment) and environment.environment:
		var desired := effective_gi_requested(value) and RenderingServer.get_current_rendering_method()=="forward_plus"
		changed = environment.environment.sdfgi_enabled != desired
		if changed: environment.environment.sdfgi_enabled=desired
	# Repeating an already-applied setting must not discard six captured faces.
	if changed and is_instance_valid(water): _capture_lighting_changed()

func _load_settings() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")!=OK:return
	world_seed=int(config.get_value("game","seed",250821))
	var saved_spawn := str(config.get_value("game","spawn_mode","original"))
	_spawn_mode = saved_spawn if saved_spawn in SPAWN_MODES else "original"
	_avatar_enabled = bool(config.get_value("display","player_body",true))
	_avatar_fabric_enabled = bool(config.get_value("display","avatar_fabric",true))
	_facility_enabled = bool(config.get_value("game","quiet_valves",true))
	_depth_wading_enabled = bool(config.get_value("game","depth_wading_response",true))
	_quality=str(config.get_value("display","quality","High"))
	_audio_on=bool(config.get_value("audio","effects",true))
	_ambience_on=bool(config.get_value("audio","ambience",true))
	_gi_on=bool(config.get_value("display","gi",true))
	_caustics_on=bool(config.get_value("display","caustics",true))
	_fog_on=bool(config.get_value("display","source_shafts",true))
	_water_settings=WaterSettingsScript.sanitize_wind_settings(config.get_value("water","settings",{}))
	_water_visible=bool(config.get_value("water","visible",true))
	# Clean imagery is default on each launch; CCD is deliberately opt-in each session.
	_ccd_on=false

func _save_settings(restart_mode: String = "", restart_seed: int = 0, atomic: bool = false) -> Error:
	# A queued ordinary autosave must not undo the committed restart selection.
	if _world_restart._requested and restart_mode.is_empty(): return ERR_BUSY
	var config:=ConfigFile.new()
	# Preserve settings owned by other features on ordinary autosave too.
	var loaded := config.load("user://settings.cfg")
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND: return loaded
	config.set_value("game","seed",restart_seed if not restart_mode.is_empty() else world_seed)
	config.set_value("game","spawn_mode",restart_mode if not restart_mode.is_empty() else (_pc_preview_return_spawn if _pc_mainhall_preview else _spawn_mode))
	config.set_value("display","quality",_quality)
	config.set_value("display","player_body",_avatar_enabled)
	config.set_value("display","avatar_fabric",_avatar_fabric_enabled)
	config.set_value("game","quiet_valves",_facility_enabled)
	config.set_value("game","depth_wading_response",_depth_wading_enabled)
	config.set_value("display","gi",_gi_on)
	config.set_value("display","caustics",_caustics_on)
	config.set_value("display","source_shafts",_fog_on)
	config.set_value("audio","effects",_audio_on)
	config.set_value("audio","ambience",_ambience_on)
	_water_settings = WaterSettingsScript.sanitize_wind_settings(_water_settings)
	config.set_value("water","settings",_water_settings)
	config.set_value("water","visible",_water_visible)
	return _world_restart.save_config_atomic(config, "user://settings.cfg") if atomic else config.save("user://settings.cfg")

func inspect_state() -> Dictionary:
	if _retiring_world or not is_instance_valid(world) or not is_instance_valid(player) or not is_instance_valid(water):
		return {"spawn_mode":_spawn_mode,"seed":world_seed,"transitioning":_switching_spawn,"retiring":_retiring_world,"menu_open":menu_open,"renderer":RenderingServer.get_current_rendering_method(),"gi_requested":_gi_on,"pc_mainhall_lightmap_preview":_pc_mainhall_preview,"frame_metrics":_frame_metrics.summary()}
	return {"spawn_mode":_spawn_mode,"seed":world_seed,"coord":[world.current_room.x,world.current_room.y],"variant":world.get_layout(world.current_room).variant,"rooms":world.resident_rooms.size(),"visited":world.get_discovered_count(),"props":props.bodies.size(),"player":[player.position.x,player.position.y,player.position.z],"status":player.get_status(),"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"gi":environment.environment.sdfgi_enabled,"gi_requested":_gi_on,"pc_mainhall_lightmap_preview":_pc_mainhall_preview,"pc_mainhall_preview_result":_pc_preview_result,"ccd":_ccd_on,"frame_metrics":_frame_metrics.summary(),"source_fog":source_fog.debug_stats() if source_fog!=null else {},"distance_fog":distance_fog.debug_stats() if distance_fog!=null else {},"avatar":avatar.get_debug_state() if is_instance_valid(avatar) else {},"nearfield":water.nearfield_status()}

func _run_qa_capture() -> void:
	var args:=OS.get_cmdline_user_args()
	var destination_name:="oculus" if world.formal_mode else "arrival"
	var out:="res://output/native-oculus.png"
	var frames:=45
	for arg in args:
		if arg.begins_with("--qa-room="):destination_name=arg.trim_prefix("--qa-room=")
		if arg.begins_with("--qa-out="):out=arg.trim_prefix("--qa-out=")
		if arg.begins_with("--qa-frames="):frames=int(arg.trim_prefix("--qa-frames="))
	_set_gi("--qa-no-gi" not in args)
	var destinations:={"arrival":Vector2i(0,0),"oculus":Vector2i(-1,-1),"vault":Vector2i(1,-1),"changing":Vector2i(-1,1),"arches":Vector2i(0,-1),"pillars":Vector2i(1,1),"sidepool":Vector2i(-1,0),"terrace":Vector2i(0,-2),"bath":Vector2i(-1,-2)}
	travel_to(destinations.get(destination_name,Vector2i.ZERO))
	world.complete_pending_streaming()
	_settle_formal_qa_lighting()
	if "--qa-native-fog-off" in args and world.formal_mode:
		# Isolate native atmospheric veiling, not the original source fog model.
		# Settle the authored mood before overriding and refresh reflected lighting.
		environment.environment.volumetric_fog_enabled = false
		water.refresh_capture_lighting()
	if "--qa-no-shadows" in args:
		for node in find_children("*", "Light3D", true, false): node.shadow_enabled=false
	if "--qa-view=overview" in args:
		var center:=Vector3(world.current_room.x*32,0,world.current_room.y*32)
		player.warp_to(center+Vector3(10,0.54,12),center+Vector3(-3,4.8,-3))
	if not world.formal_mode:
		var source_center:=Vector3(world.current_room.x*32,0,world.current_room.y*32)
		player.warp_to(source_center+Vector3(10,1.5-PlayerScript.EYE_HEIGHT,12),source_center+Vector3(-4,1.9,-10))
	if world.formal_mode:
		var center:=Vector3(world.current_room.x*32,0,world.current_room.y*32)
		player.warp_to(center+Vector3(0,.55,8.3),center+Vector3(-1.8,1.7,-3.0))
		if "--qa-view=water" in args:player.warp_to(center+Vector3(2.1,-.94,4.2),center+Vector3(-1.8,.5,-4.0))
		if "--qa-view=steps" in args:player.warp_to(center+Vector3(2.2,.55,7.0),center+Vector3(.4,.15,4.5))
		# The authored arcade is dry deck at +0.52 m, not the legacy sunken hall.
		if destination_name=="arches":player.warp_to(center+Vector3(-9,.55,0),center+Vector3(8,1.2,0))
		if destination_name=="sidepool":player.warp_to(center+Vector3(0,.55,5.5),center+Vector3(-2,1.1,-3))
		if destination_name=="terrace":player.warp_to(center+Vector3(0,.55,7),center+Vector3(-2,1.4,-2))
		if destination_name=="bath":player.warp_to(center+Vector3(0,.55,7.4),center+Vector3(-1,2.6,-2))
		if destination_name=="arches" and "--qa-view=service" in args:
			player.warp_to(center+Vector3(-1.5,.55,-.5),center+Vector3(-4,1.1,2.6))
		if destination_name=="sidepool" and "--qa-view=bench" in args:
			player.warp_to(center+Vector3(-5.15,.55,4.6),center+Vector3(-6.52,1.1,0))
	for arg in args:
		if arg.begins_with("--qa-water-quality="):water.set_quality(arg.trim_prefix("--qa-water-quality="))
		if arg.begins_with("--qa-water-debug="):water.set_debug_view(int(arg.trim_prefix("--qa-water-debug=")))
	if "--qa-traverse" in args:
		travel_to(Vector2i(-1,-1) if world.formal_mode else Vector2i.ZERO)
		world.complete_pending_streaming()
		player.warp_to(Vector3(0,-0.60,15.60),Vector3(0,0.9,0))
		set_menu(false)
		Input.action_press("move_back")
		Input.action_press("sprint")
		for tick in range(24):await get_tree().physics_frame
		Input.action_release("move_back")
		Input.action_release("sprint")
		print("POOLCORE_NATIVE_TRAVERSAL ",JSON.stringify(inspect_state()))
		set_menu(true)
		world.complete_pending_streaming()
	water.process_mode=Node.PROCESS_MODE_INHERIT;water.set_paused(false)
	frames=clampi(frames,1,3600 if "--qa-benchmark" in args else 120)
	_menu.visible=false
	hud_hidden=true
	_room_title.visible=false
	_status.visible=false
	_hint.visible=false
	player.set_enabled(false)
	if "--qa-ui" in args:
		_menu.visible=true
		_room_title.visible=true
		_status.visible=true
	if "--qa-mobile-controls" in args and has_node("MobileRuntime"):
		menu_open=false
		get_node("MobileRuntime").controls.set_gameplay_enabled(true)
	if "--qa-mobile-quality" in args and has_node("MobileRuntime"):
		_menu.hide()
		get_node("MobileRuntime").quality._panel.show()
	if "--qa-finish-views" in args:
		await _capture_finish_views()
		_safe_quit()
		return
	if "--qa-record" in args:
		if not await _record_walkthrough():
			_safe_quit(2)
			return
	if "--qa-gallery" in args:
		await _capture_gallery()
	if "--qa-desktop-quality" in args and has_node("DesktopQuality"):
		get_node("DesktopQuality").open_panel()
	if "--qa-wait-ready" in args:
		var wait_start:=Time.get_ticks_msec()
		var last_progress:=wait_start
		var readiness_limit := 180000
		for argument in args:
			if argument.begins_with("--qa-ready-timeout="): readiness_limit = clampi(int(argument.trim_prefix("--qa-ready-timeout=")), 30, 600) * 1000
		while (not water.is_terrain_ready() or not water.debug_stats().cubemap_ready) and Time.get_ticks_msec()-wait_start<readiness_limit:
			await get_tree().process_frame
			if Time.get_ticks_msec()-last_progress>10000:
				last_progress=Time.get_ticks_msec()
				print("QA_WAIT_PROGRESS ",JSON.stringify(water.debug_stats()))
		if not water.is_terrain_ready() or not water.debug_stats().cubemap_ready:
			push_error("QA_READY_TIMEOUT: no complete terrain/probe publication")
			var failure_file:=FileAccess.open(out+".failure.json",FileAccess.WRITE)
			if failure_file:failure_file.store_string(JSON.stringify(water.debug_stats(),"  "))
			_safe_quit(2);return
		props.set_enabled(true)
	if "--qa-benchmark" in args:
		# Measure the exported executable, without the editor or screenshot readbacks.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		DisplayServer.window_move_to_foreground()
		props.set_enabled(false)
		for body in props.bodies: body.freeze = true
		for frame in 120: await get_tree().process_frame
	if "--qa-external-lighting-runner" in args:
		if not qa_capture_hook.is_valid():
			push_error("QA_LIGHTING_RUNNER: no capture hook was installed")
			_safe_quit(2)
			return
		var hook_result: int = await qa_capture_hook.call(self)
		_safe_quit(hook_result)
		return
	if "--qa-benchmark" in args: print("POOLCORE_MEASURE_BEGIN release")
	var focused_frames := 0
	var frame_times:Array[float]=[]
	var qa_impact_applied:=false
	var previous_tick:=Time.get_ticks_usec()
	for i in range(frames):
		await get_tree().process_frame
		if DisplayServer.window_is_focused(): focused_frames += 1
		var now:=Time.get_ticks_usec();frame_times.append(float(now-previous_tick)/1000.0);previous_tick=now
		if i>=6 and not qa_impact_applied and water.is_terrain_ready() and "--qa-impact" in args:
			qa_impact_applied=true
			var center:=Vector3(world.current_room.x*32,0,world.current_room.y*32)
			water.splash(center+Vector3(0,.32,3.2),.32,{"u":.7,"v":-1.0,"vertical":-2.0,"radius":.12})
		if i % 5 == 0: print("POOLCORE_QA_FRAME ",i," / ",frames)
	if "--qa-benchmark" in args: print("POOLCORE_MEASURE_END release")
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	var err:=image.save_png(out)
	var state:=inspect_state()
	state["water"]=water.debug_stats()
	state["qa_impact_applied"]=qa_impact_applied
	var sorted_times:=frame_times.duplicate();sorted_times.sort()
	var total_time:=0.0
	for value in frame_times:total_time+=value
	state["actual_wall_timing"]={"frames":frames,"mean_ms":total_time/maxi(1,frames),"p95_ms":sorted_times[mini(sorted_times.size()-1,floori(sorted_times.size()*.95))],"samples_ms":frame_times,"physics_frames":Engine.get_physics_frames(),"note":"Actual wall-clock frame intervals on the reported device; includes scene warmup, not a phone benchmark."}
	if "--qa-benchmark" in args:
		state.actual_wall_timing.note = "Release executable; uncapped wall-clock intervals after 120 warmup frames; original fixed camera, props frozen, no screenshot readback in measured interval."
	state["focused_frames"] = focused_frames
	if OS.has_feature("editor") and ClassDB.class_has_integer_constant("Viewport", "RENDER_INFO_RT_TLAS_INSTANCES"):
		state["rt_instances"] = get_viewport().call("get_render_info", 0, ClassDB.class_get_integer_constant("Viewport", "RENDER_INFO_RT_TLAS_INSTANCES"))
	state["dlss"] = get_node("DesktopQuality").dlss_status.duplicate() if has_node("DesktopQuality") else {}
	state["frame_generation"] = get_node("DesktopQuality").frame_generation_status.duplicate() if has_node("DesktopQuality") else {}
	state["raytracing"] = get_node("DesktopQuality").raytracing_status.duplicate() if has_node("DesktopQuality") else {}
	state["viewport_scaling"] = {"mode":get_viewport().scaling_3d_mode, "scale":get_viewport().scaling_3d_scale, "msaa":get_viewport().msaa_3d, "taa":get_viewport().use_taa}
	state["capture_error"]=err
	state["capture_size"]=[image.get_width(),image.get_height()]
	state["camera"]={"position":player.camera.global_position,"transform":player.camera.global_transform,"fov":player.camera.fov}
	state["quality"]=_quality
	state["quality_settings"]=get_node("DesktopQuality").settings.duplicate(true) if has_node("DesktopQuality") else {}
	var sky_material := environment.environment.sky.sky_material
	state["native_environment"]={"sky_material":sky_material.get_class(),
		"exposure":environment.environment.tonemap_exposure,
		"ambient_energy":environment.environment.ambient_light_energy,
		"volumetric_fog":environment.environment.volumetric_fog_enabled,
		"fog_density":environment.environment.volumetric_fog_density,
		"mood_tween_running":lighting._mood_tween.is_running() if is_instance_valid(lighting._mood_tween) else false,
		"physical_sky_requested":"--qa-formal-physical-sky" in args}
	var file:=FileAccess.open(out+".json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(state,"  "))
	print("POOLCORE_QA_CAPTURE ",JSON.stringify(state))
	if "--qa-optical-isolation" in args:
		await _capture_optical_isolation(out)
	if "--qa-sampler-comparison" in args:
		await _capture_sampler_comparison(out)
	_safe_quit()

func _configure_qa_capture_resolution(args: PackedStringArray) -> bool:
	# A window manager may clamp the outer window to its desktop. Render QA at
	# an explicit internal resolution instead of mislabelling a smaller image.
	# Normal gameplay and saved quality settings are never changed here.
	if not _qa:
		return true
	var requested := ""
	for arg: String in args:
		if arg.begins_with("--qa-capture-resolution="):
			if not requested.is_empty():
				push_error("QA_CAPTURE_RESOLUTION: duplicate request")
				return false
			requested = arg.trim_prefix("--qa-capture-resolution=")
	if requested.is_empty():
		return true
	var dimensions := requested.split("x")
	if dimensions.size() != 2 or not dimensions[0].is_valid_int() or not dimensions[1].is_valid_int():
		push_error("QA_CAPTURE_RESOLUTION: expected WIDTHxHEIGHT")
		return false
	var target := Vector2i(int(dimensions[0]), int(dimensions[1]))
	if target.x < 320 or target.y < 180 or target.x > 3840 or target.y > 2160:
		push_error("QA_CAPTURE_RESOLUTION: outside supported diagnostic bounds")
		return false
	var window := get_tree().root
	window.content_scale_size = target
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	return true

func _settle_formal_qa_lighting() -> void:
	# Match the settled gameplay rig without spending hundreds of software-GPU
	# frames in an exposure/fog transition. This advances only the authored
	# lighting tween, not physics, water time or the normal gameplay transition.
	if _qa and is_instance_valid(world) and world.formal_mode:
		if is_instance_valid(lighting._mood_tween) and lighting._mood_tween.is_valid():
			lighting._mood_tween.custom_step(2.0)

func _capture_sampler_comparison(base_path: String) -> void:
	# QA only. A-B-A separates the source sampler correction from residual
	# temporal lighting noise; all simulation, camera and optical math stay fixed.
	props.set_enabled(false)
	water.set_paused(true)
	var was_taa := get_viewport().use_taa
	get_viewport().use_taa = false
	var materials: Array[ShaderMaterial] = []
	var originals: Array[Shader] = []
	for material: ShaderMaterial in water._materials.values():
		materials.append(material)
		originals.append(material.shader)
	if materials.is_empty():
		push_error("SAMPLER_COMPARISON: no native water materials")
		return
	var source_code: String = originals[0].code
	source_code = source_code.replace("mirrorSampler : filter_linear_mipmap,", "mirrorSampler : filter_linear,")
	source_code = source_code.replace("sceneColor : hint_screen_texture, filter_linear_mipmap,", "sceneColor : hint_screen_texture, filter_linear,")
	var mip_code := source_code.replace("mirrorSampler : filter_linear,", "mirrorSampler : filter_linear_mipmap,")
	mip_code = mip_code.replace("sceneColor : hint_screen_texture, filter_linear,", "sceneColor : hint_screen_texture, filter_linear_mipmap,")
	var variants := [
		{"name":"sampler-mipmap-before", "code":mip_code},
		{"name":"sampler-source-linear", "code":source_code},
		{"name":"sampler-mipmap-repeat", "code":mip_code}]
	var initial_time: float = water._time
	var initial_camera: Transform3D = player.camera.global_transform
	var initial_caustic_frames: int = water.caustics.caustic_frames
	var initial_exposure: float = environment.environment.tonemap_exposure
	var initial_ambient: float = environment.environment.ambient_light_energy
	var initial_fog: float = environment.environment.volumetric_fog_density
	var report := {"diagnostic_only":true, "order":"A-B-A", "taa":false,
		"simulation_paused":true, "camera":initial_camera, "pool_time":initial_time,
		"source_math_unchanged":true, "variants":[]}
	for variant: Dictionary in variants:
		var shader := Shader.new()
		shader.code = variant.code
		for material in materials: material.shader = shader
		water._bind_all()
		for frame in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := base_path.get_basename() + "-" + str(variant.name) + ".png"
		var result := image.save_png(path)
		report.variants.append({"name":variant.name, "path":path, "save_error":result,
			"pool_time_unchanged":water._time == initial_time,
			"camera_unchanged":player.camera.global_transform == initial_camera,
			"caustic_frames_unchanged":water.caustics.caustic_frames == initial_caustic_frames,
			"exposure_unchanged":environment.environment.tonemap_exposure == initial_exposure,
			"ambient_unchanged":environment.environment.ambient_light_energy == initial_ambient,
			"fog_density_unchanged":environment.environment.volumetric_fog_density == initial_fog,
			"size":[image.get_width(),image.get_height()]})
		print("SAMPLER_COMPARISON_CAPTURE ", variant.name, " ", result)
	for index in materials.size(): materials[index].shader = originals[index]
	water._bind_all()
	get_viewport().use_taa = was_taa
	var file := FileAccess.open(base_path.get_basename() + "-sampler-comparison.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))

func _capture_optical_isolation(base_path: String) -> void:
	# Diagnostic-only, same-camera component isolation. Keep the original
	# simulation/optics untouched; use its existing debug branches and toggles.
	var was_taa := get_viewport().use_taa
	var original_caustics: bool = water.caustics_enabled
	var original_debug := int(water.settings.debugView)
	var original_enabled: bool = water.enabled
	props.set_enabled(false)
	water.set_paused(true)
	get_viewport().use_taa = false
	var variants := [
		{"name":"optical-base", "debug":0, "surface":true, "caustics":original_caustics},
		{"name":"transmission", "debug":8, "surface":true, "caustics":original_caustics},
		{"name":"fresnel", "debug":7, "surface":true, "caustics":original_caustics},
		{"name":"reflection", "debug":10, "surface":true, "caustics":original_caustics},
		{"name":"foam-density", "debug":11, "surface":true, "caustics":original_caustics},
		{"name":"opaque-floor", "debug":0, "surface":false, "caustics":original_caustics},
		{"name":"opaque-floor-no-caustics", "debug":0, "surface":false, "caustics":false}]
	var report := {"diagnostic_only":true, "camera_position":player.camera.global_position,
		"camera_transform":player.camera.global_transform, "fov":player.camera.fov,
		"taa":false, "simulation_paused":true, "variants":[]}
	for variant: Dictionary in variants:
		water.set_debug_view(variant.debug)
		water.set_enabled(variant.surface)
		water.set_caustics(variant.caustics)
		for frame in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path: String = base_path.get_basename() + "-" + str(variant.name) + ".png"
		var result := image.save_png(path)
		report.variants.append({"settings":variant, "path":path, "save_error":result,
			"size":[image.get_width(),image.get_height()]})
		print("OPTICAL_ISOLATION_CAPTURE ", variant.name, " ", result)
	water.set_debug_view(original_debug)
	water.set_caustics(original_caustics)
	water.set_enabled(original_enabled)
	get_viewport().use_taa = was_taa
	var file := FileAccess.open(base_path.get_basename() + "-optical-isolation.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))

func _capture_finish_views()->void:
	# Same authored poses as the delivered reference. Wait for actual static data
	# and probe publication rather than taking a frame during background startup.
	var start:=Time.get_ticks_msec()
	while (not water.is_terrain_ready() or not water.debug_stats().cubemap_ready) and Time.get_ticks_msec()-start<180000:
		await get_tree().process_frame
	if not water.is_terrain_ready():push_error("FINISH_CAPTURE: source terrain preparation did not finish");return
	props.set_enabled(true)
	var views:Array=[
		["main-wide",Vector3(0,.55,8.3),Vector3(-1.8,1.7,-3)],
		["steps-closeup",Vector3(2.2,.55,7),Vector3(.4,.15,4.5)],
		["water-level",Vector3(2.1,-.94,4.2),Vector3(-1.8,.5,-4)]]
	for view in views:
		var center:=Vector3(-32,0,-32)
		player.warp_to(center+view[1],center+view[2]);player.set_enabled(false)
		for i in 16:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image:=get_viewport().get_texture().get_image()
		var path:="res://output/fixed-"+str(view[0])+".png"
		image.save_png(path)
		var state:=inspect_state();state.water=water.debug_stats();state.capture_size=[image.get_width(),image.get_height()]
		state.camera={"position":player.camera.global_position,"transform":player.camera.global_transform,"fov":player.camera.fov}
		var file:=FileAccess.open(path+".json",FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(state,"  "))
		print("POOLCORE_FINISH_CAPTURE ",path," ",JSON.stringify({"terrain_ready":water.is_terrain_ready(),"probe_ready":state.water.cubemap_ready,"errors":[state.water.last_error,state.water.caustic_error,state.water.liquid_error]}))

func _capture_gallery()->void:
	var views:Array=[
		["main-wide",Vector2i(-1,-1),Vector3(0,.55,8.3),Vector3(-1.8,1.7,-3)],
		["water-level",Vector2i(-1,-1),Vector3(2.1,-.94,4.2),Vector3(-1.8,.5,-4)],
		["steps-closeup",Vector2i(-1,-1),Vector3(2.2,.55,7),Vector3(.4,.15,4.5)],
		["wading-disturbance",Vector2i(-1,-1),Vector3(0,-.10,3.5),Vector3(.4,.3,1.0)],
		["arcade-light",Vector2i(0,-1),Vector3(-9,.55,0),Vector3(8,1.2,0)]]
	set_menu(true);_menu.hide();hud_hidden=true;_room_title.hide();_status.hide();_hint.hide();water.process_mode=Node.PROCESS_MODE_INHERIT;water.set_paused(false)
	for view in views:
		if world.current_room!=view[1]:travel_to(view[1]);world.complete_pending_streaming();_menu.hide()
		var center:=Vector3(view[1].x*32,0,view[1].y*32)
		player.warp_to(center+view[2],center+view[3]);player.set_enabled(false)
		for frame in 18:
			if frame==10 and view[0]=="wading-disturbance":water.splash(center+Vector3(.4,.32,1.0),.32,{"u":.7,"v":-1.0,"vertical":-2.0,"radius":.12})
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image:=get_viewport().get_texture().get_image()
		var path:="res://output/source-"+str(view[0])+".png"
		image.save_png(path)
		var file:=FileAccess.open(path+".json",FileAccess.WRITE)
		var state:=inspect_state();state["water"]=water.debug_stats();state["capture_size"]=[image.get_width(),image.get_height()]
		state["prop_poses"]=[]
		for body in props.bodies:state["prop_poses"].append({"kind":body.prop_kind,"position":body.global_position,"basis":body.global_basis})
		file.store_string(JSON.stringify(state,"  "))
		print("SOURCE_GALLERY_CAPTURE ",path)

func _record_walkthrough() -> bool:
	if not world.formal_mode:
		push_error("SOURCE_WALK_RECORD: this authored stair route requires --formal-hall")
		return false
	var center:=Vector3(-32,0,-32)
	player.warp_to(center+Vector3(0,.55,6.8),center+Vector3(0,1.2,-4))
	# Startup cannot be assumed complete after a fixed number of frames. Wait
	# for the real source terrain, source cubemap and mirror publication first.
	_settle_formal_qa_lighting()
	var start_usec := Time.get_ticks_usec()
	while not water.is_terrain_ready() or not water.debug_stats().cubemap_ready or not water.debug_stats().planar_ready:
		if Time.get_ticks_usec() - start_usec > 600000000:
			push_error("SOURCE_WALK_RECORD: source water readiness timed out")
			return false
		await get_tree().process_frame
	set_menu(false);hud_hidden=true;_room_title.hide();_status.hide();_hint.hide()
	var folder:="res://output/eight-hour/walk-frames"
	DirAccess.make_dir_recursive_absolute(folder)
	var samples:Array=[]
	var first_water_time: float = water._time
	var initial_impulses: int = water.interaction_count
	var water_contact_frames := 0
	var save_errors: Array[int] = []
	var first_wall_usec := Time.get_ticks_usec()
	var previous_wall_usec := first_wall_usec
	Input.action_press("move_forward")
	for i in 144:
		if i==65:Input.action_release("move_forward")
		if i>=65 and i<91:player.rotate_y(deg_to_rad(.65))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var now_usec := Time.get_ticks_usec()
		var image := get_viewport().get_texture().get_image()
		var save_error := image.save_png(folder+"/%04d.png"%i)
		if save_error != OK: save_errors.append(save_error)
		if player._in_water: water_contact_frames += 1
		var prop_poses:Array=[]
		for body in props.bodies:
			prop_poses.append({"kind":body.prop_kind,"position":body.global_position,"wet":water.is_water_at(body.global_position),"surface":water.surface_height_at(body.global_position)})
		samples.append({"frame":i,"position":player.global_position,"eye":player.camera.global_position,"status":player.get_status(),"water":water.debug_stats(),"prop_poses":prop_poses,
			"process_frame":Engine.get_process_frames(),"water_time":water._time,"wall_interval_ms":(now_usec-previous_wall_usec)/1000.0,"capture_size":[image.get_width(),image.get_height()]})
		previous_wall_usec = now_usec
		if i%24==0:print("SOURCE_WALK_RECORD ",i,"/144 position=",player.global_position)
	Input.action_release("move_forward");set_menu(true);_menu.hide()
	var water_seconds: float = water._time - first_water_time
	var report := {"frames":144,"playback_fps":24,
		"method":"Actual Godot runtime with --fixed-fps 24. Continuous input walk down the stairs, wade, turn and stop. No injected splash. Offline fixed-step capture, not a realtime performance claim.",
		"movie_writer_requested":not Engine.get_write_movie_path().is_empty(),"audio_method":"Native fixed-step MovieWriter mix when requested; otherwise these PNG captures are silent.",
		"water_contact_frames":water_contact_frames,"player_and_prop_impulses":water.interaction_count-initial_impulses,
		"water_seconds":water_seconds,"wall_seconds":(Time.get_ticks_usec()-first_wall_usec)/1000000.0,
		"fixed_step_verified":absf(water_seconds-6.0)<.05,"save_errors":save_errors,"samples":samples}
	report["pass"] = save_errors.is_empty() and report.fixed_step_verified and water_contact_frames > 0 and player.global_position.y >= -.14
	var file:=FileAccess.open("res://output/eight-hour/source-walkthrough.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
	else: report["pass"] = false
	print("SOURCE_WALK_RECORD_DONE ", JSON.stringify({"frames":144,"pass":report["pass"],"water_contact_frames":water_contact_frames,"water_seconds":water_seconds,"save_errors":save_errors}))
	return bool(report["pass"])

func _safe_quit(exit_code: int = 0) -> void:
	if not _booted: return
	if is_instance_valid(_exploration_notes): _exploration_notes.flush()
	_booted=false
	_retiring_world=true
	_gi_refresh_ticket+=1
	set_process(false)
	set_physics_process(false)
	if is_instance_valid(pool_audio):pool_audio.set_active(false)
	_dispose_distance_fog()
	if source_fog != null:source_fog.dispose();source_fog=null
	if is_instance_valid(water) and water.has_method("dispose"):water.dispose()
	# Complete render-thread release commands while the global RD still exists.
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	for node in [world,water,props,player,pool_audio,environment]:
		if is_instance_valid(node):
			if node.get_parent() == self: remove_child(node)
			node.queue_free()
	materials=null
	lighting=null
	var builder=load("res://scripts/world/room_builder.gd")
	builder.imported_scenes.clear()
	builder.imported_shapes.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	get_tree().quit(exit_code)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _booted:
		_safe_quit.call_deferred()

func _exit_tree()->void:
	if is_instance_valid(_facility_devices): _facility_devices.clear()
	_dispose_distance_fog()
	if source_fog!=null:source_fog.dispose();source_fog=null
