extends Node3D
## Six contained architectural vignettes. No player motion or loading authority.
## Coordinator must fade out before freeing this node and keep its collision/water
## readiness handshake. Camera stays here after play until release/cancel/free.
const MODES := ["service_threshold", "pump_lift", "water_turn", "memory_reveal", "ventilation_hatch", "daylight_steps"]
const DURATIONS := [3.8, 4.6, 4.8, 4.4, 4.5, 4.8]
const STAGE_LAYER := 1 << 19
var reduced_effects := false
var chapter_index := 0
var mode_id := "service_threshold"
var camera: Camera3D
var _stage: Node3D
var _door: Node3D
var _platform: Node3D
var _reveal_light: OmniLight3D
var _previous_camera: WeakRef
var _playing := false
var _cancelled := false
var _skip_requested := false
var _safe_to_skip := false
var _generation := 0
var _wall: StandardMaterial3D
var _metal: StandardMaterial3D
var _floor: StandardMaterial3D
var _accent: StandardMaterial3D
var _dado: StandardMaterial3D
var _plaster: StandardMaterial3D
var _base_door_position := Vector3.ZERO
var _ceiling_height := 3.4

func configure(index: int) -> void:
	cancel()
	chapter_index = clampi(index, 0, MODES.size() - 1)
	mode_id = MODES[chapter_index]
	_safe_to_skip = false
	if is_inside_tree(): _build()

func _ready() -> void:
	_build()

func set_safe_to_skip(value: bool) -> void:
	_safe_to_skip = value

func request_skip() -> bool:
	if not _safe_to_skip or not _playing: return false
	_skip_requested = true
	return true

func activate_camera() -> void:
	if not is_inside_tree(): return
	_capture_camera()
	camera.make_current()

func play() -> void:
	if _playing or not is_inside_tree(): return
	if not is_instance_valid(camera): _build()
	_capture_camera()
	_cancelled = false
	_skip_requested = false
	_playing = true
	_generation += 1
	var token := _generation
	var elapsed := 0.0
	var duration: float = 1.5 if reduced_effects else float(DURATIONS[chapter_index])
	_sample(0.0)
	camera.make_current()
	while elapsed < duration and not _cancelled and not _skip_requested and token == _generation:
		await get_tree().process_frame
		if not is_inside_tree() or token != _generation: return
		if get_tree().paused: continue
		elapsed += minf(get_process_delta_time(), 0.1)
		_sample(clampf(elapsed / duration, 0.0, 1.0))
	if token != _generation: return
	if not _cancelled: _sample(1.0)
	_playing = false

func cancel() -> void:
	_cancelled = true
	_playing = false
	_generation += 1
	release_camera()

func release_camera() -> void:
	if is_instance_valid(camera) and camera.is_current():
		var previous := _previous_camera.get_ref() as Camera3D if _previous_camera != null else null
		if is_instance_valid(previous) and previous.is_inside_tree():
			previous.make_current()
		else:
			# If the source world was freed, allow an extant viewport camera to win.
			camera.clear_current(true)
	_previous_camera = null

func _capture_camera() -> void:
	var current := get_viewport().get_camera_3d()
	if current != camera:
		_previous_camera = weakref(current) if is_instance_valid(current) else null

func _exit_tree() -> void:
	cancel()

func _mat(color: String, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	material.metallic = metallic
	return material

func _finish(role: String, tint: Color) -> StandardMaterial3D:
	var specs := {
		"tile_pearl": ["tile_pearl_albedo_2k.png", "tile_normal_gl_2k.png", "tile_pearl_orm_2k.png", 0.8],
		"tile_blue": ["tile_blue_albedo_2k.png", "tile_normal_gl_2k.png", "tile_blue_orm_2k.png", 0.8],
		"steel": ["steel_brushed_albedo_512.png", "steel_normal_gl_512.png", "steel_orm_512.png", 0.25],
		"storage": ["storage_green_albedo_512.png", "storage_normal_gl_512.png", "storage_orm_512.png", 0.5],
		"plaster": ["plaster_oyster_albedo_2k.png", "plaster_normal_gl_2k.png", "plaster_orm_2k.png", 2.0],
		"coping": ["coping_ivory_albedo_1k.png", "coping_normal_gl_1k.png", "coping_orm_1k.png", 1.0]
	}
	var spec: Array = specs[role]
	var directory := "res://assets/materials/art_pass/textures/"
	var material := StandardMaterial3D.new()
	material.resource_name = "Campaign / " + role
	material.albedo_color = tint
	material.albedo_texture = load(directory + str(spec[0]))
	material.normal_enabled = true
	material.normal_texture = load(directory + str(spec[1]))
	material.normal_scale = 0.65 if role.begins_with("tile") else 0.45
	material.roughness_texture = load(directory + str(spec[2]))
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.roughness = 1.0
	material.metallic_texture = material.roughness_texture
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.metallic = 1.0
	material.ao_enabled = true; material.ao_texture = material.roughness_texture
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_triplanar = true; material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / float(spec[3])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.set_meta("campaign_repeat_metres", float(spec[3]))
	return material

func _build() -> void:
	if is_instance_valid(_stage): _stage.free()
	_stage = Node3D.new(); _stage.name = "Contained_" + mode_id; add_child(_stage)
	camera = null; _door = null; _platform = null; _reveal_light = null
	# Reuse existing authored PBR maps, but own every material instance.
	_wall = _finish("tile_pearl", Color("d2d5c6") if chapter_index < 2 else Color.WHITE)
	# 200 mm wall ceramic contrasts the existing 100 mm floor/dado mosaic.
	_wall.uv1_scale = Vector3.ONE / 1.6
	_wall.set_meta("campaign_repeat_metres", 1.6)
	_floor = _finish("tile_blue", Color("afc4be")) if chapter_index < 3 else _finish("tile_pearl", Color("9baba2") if chapter_index == 3 else Color("e5e5d7"))
	_accent = _finish("storage", Color("b5b79e") if chapter_index == 3 else Color.WHITE)
	_metal = _finish("steel", Color("89968f") if chapter_index < 2 else Color("bac5bf"))
	_dado = _finish("tile_blue", Color("adbbb0") if chapter_index == 3 else Color.WHITE)
	_plaster = _finish("plaster", Color("d8ceba") if chapter_index == 3 else Color("efeee5"))
	if chapter_index == 3: _wall = _plaster
	if chapter_index == 5: _accent = _finish("coping", Color.WHITE)

	match chapter_index:
		0: _build_service()
		1: _build_pump()
		2: _build_turn()
		3: _build_memory()
		4: _build_vent()
		5: _build_daylight()
	camera = Camera3D.new(); camera.name = "PresentationCamera"
	camera.cull_mask = STAGE_LAYER; camera.near = 0.08; camera.far = 38.0; camera.fov = 68.0
	# Camera-local exposure/ambient prevents the source chapter's fog or mood
	# from washing out this off-world set; no global Environment is mutated.
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("171d1b")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("c2cabb")
	atmosphere.ambient_light_energy = 0.18
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	camera.environment = atmosphere
	_stage.add_child(camera)
	_base_door_position = _door.position if is_instance_valid(_door) else Vector3.ZERO
	_sample(0.0)

func _box(label: String, point: Vector3, size: Vector3, material: Material = null, parent: Node3D = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new(); mesh.name = label
	var shape := BoxMesh.new(); shape.size = size
	mesh.mesh = shape; mesh.position = point; mesh.material_override = material if material != null else _wall
	mesh.layers = STAGE_LAYER
	(parent if parent != null else _stage).add_child(mesh)
	return mesh

func _light(point: Vector3, color: Color, energy: float, reach: float = 7.0) -> OmniLight3D:
	var lamp := OmniLight3D.new(); lamp.position = point; lamp.light_color = color
	lamp.light_energy = energy * 0.75; lamp.omni_range = reach; lamp.shadow_enabled = true
	lamp.light_cull_mask = STAGE_LAYER; _stage.add_child(lamp)
	# Practical fixture and suspension make the light source architectural.
	_box("LuminaireHousing",point+Vector3.UP*0.16,Vector3(0.72,0.12,0.24),_metal)
	var lens := _box("LuminaireOpal",point+Vector3.UP*0.09,Vector3(0.62,0.025,0.17),_opal("e1e3ca"))
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cable_length := maxf(0.05,_ceiling_height-point.y-0.22)
	_box("LuminaireSuspension",point+Vector3.UP*(0.22+cable_length/2),Vector3(0.018,cable_length,0.018),_metal)
	return lamp

func _shell(width: float, height: float, length: float) -> void:
	_ceiling_height = height
	# Overlapping closed walls: a staged passage, never a view into a void.
	_box("Floor", Vector3(0, -0.16, -length/2), Vector3(width+0.6, 0.32, length+0.6), _floor)
	_box("Ceiling", Vector3(0, height+0.16, -length/2), Vector3(width+0.6, 0.32, length+0.6), _plaster)
	_box("Left", Vector3(-width/2-0.15, height/2, -length/2), Vector3(0.3, height, length+0.6))
	_box("Right", Vector3(width/2+0.15, height/2, -length/2), Vector3(0.3, height, length+0.6))
	_box("Rear", Vector3(0, height/2, 0.2), Vector3(width+0.6, height, 0.4))
	_box("End", Vector3(0, height/2, -length-0.2), Vector3(width+0.6, height, 0.4))
	# Ceramic dado and narrow coping separate human scale from the tall shell.
	for side in [-1.0, 1.0]:
		_box("TiledDado", Vector3(side*(width/2-0.025),0.62,-length/2),Vector3(0.045,1.24,length),_dado)
		_box("DadoCapping",Vector3(side*(width/2-0.045),1.26,-length/2),Vector3(0.09,0.055,length),_accent)
		_box("FloorSkirting",Vector3(side*(width/2-0.045),0.07,-length/2),Vector3(0.09,0.14,length),_metal)


func _frame(z: float, width: float = 2.0, height: float = 2.8) -> void:
	for side in [-1.0, 1.0]:
		_box("DoorJamb", Vector3(side*(width/2+0.1), height/2, z), Vector3(0.2, height, 0.3), _metal)
	_box("Lintel", Vector3(0, height+0.1, z), Vector3(width+0.4, 0.2, 0.3), _metal)

func _opal(color: String) -> StandardMaterial3D:
	var material := _mat(color, 0.4)
	material.emission_enabled = true; material.emission = Color(color); material.emission_energy_multiplier = 0.65
	return material

func _build_service() -> void:
	_shell(3.4, 3.4, 10.0)
	_frame(-3.8, 3.2)
	_door = Node3D.new(); _door.name = "RollingServiceShutter"; _door.position.z = -3.8; _stage.add_child(_door)
	for index in range(14):
		_box("ShutterSlat", Vector3(0, 0.1+index*0.2, 0), Vector3(3.2, 0.19, 0.12), _metal, _door)
	# A solid offset baffle implies the service dogleg beyond the threshold.
	_box("DoglegBaffle", Vector3(-0.65, 1.7, -7.8), Vector3(2.1, 3.4, 0.3))
	_box("ServiceExitDoor",Vector3(1.05,1.25,-9.96),Vector3(1.12,2.5,0.06),_accent)
	for x in [0.43,1.67]: _box("ServiceExitJamb",Vector3(x,1.3,-9.88),Vector3(0.09,2.6,0.16),_metal)
	_box("ServiceExitLintel",Vector3(1.05,2.6,-9.88),Vector3(1.33,0.1,0.16),_metal)
	_box("ServiceExitHandle",Vector3(1.43,1.2,-9.78),Vector3(0.06,0.25,0.07),_metal)
	_box("ExitTransom",Vector3(1.05,2.92,-9.97),Vector3(1.12,0.35,0.04),_opal("c6d6b7"))

	for index in range(4):
		_box("ChangingLocker", Vector3(1.45, 1.0, -5.0-index*0.65), Vector3(0.35, 2, 0.55), _accent)
		_box("LockerHandle", Vector3(1.245, 1.05, -4.85-index*0.65), Vector3(0.045, 0.23, 0.035), _metal)
		for slat in range(3): _box("LockerVent", Vector3(1.265,1.65+slat*0.075,-5.0-index*0.65),Vector3(0.02,0.025,0.3),_metal)
	_light(Vector3(0, 2.8, -1.5), Color("cfdbc4"), 1.1)
	_light(Vector3(0.6, 2.7, -6), Color("d6e7de"), 1.7)

func _build_pump() -> void:
	_shell(4.8, 4.8, 9.0)
	_platform = Node3D.new(); _platform.name = "DryPumpPlatform"; _stage.add_child(_platform)
	_box("PlatformDeck", Vector3(0, 0.95, -2.8), Vector3(3.1, 0.2, 4.8), _metal, _platform)
	for side in [-1.0, 1.0]:
		_box("PlatformRail", Vector3(side*1.48, 1.95, -2.8), Vector3(0.07, 0.07, 4.8), _accent, _platform)
		for z in [-0.6, -2.8, -5.0]: _box("RailPost", Vector3(side*1.48, 1.45, z), Vector3(0.07, 1.0, 0.07), _metal, _platform)
		_box("GuideRail", Vector3(side*1.9, 2.2, -4.8), Vector3(0.14, 4.4, 0.14), _metal)
		_box("PumpHeader", Vector3(side*2.1, 1.0, -7), Vector3(0.45, 1.8, 1.4), _accent)
		_box("PressurePipe", Vector3(side*2.1,2.25,-7.3),Vector3(0.16,0.9,0.16),_metal)
		_box("PumpGauge",Vector3(side*1.85,1.4,-6.8),Vector3(0.07,0.25,0.25),_floor)
		for slat in range(5): _box("PumpCoolingFin",Vector3(side*1.86,0.6+slat*0.11,-7.25),Vector3(0.025,0.035,0.5),_metal)
	_frame(-5.5, 3.2)
	_door = _box("PumpSafetyGate", Vector3(0, 1.5, -5.5), Vector3(3.2, 3, 0.15), _metal)
	_light(Vector3(0, 4, -2), Color("d7cc98"), 1.8)
	_light(Vector3(0, 2.8, -7), Color("a3d4cc"), 1.8)

func _build_turn() -> void:
	_shell(10.0, 4.6, 10.0)
	# A solid inner core forces the passage to turn ninety degrees to the right.
	_box("TurnInnerWall", Vector3(2.15, 2.3, -2.9), Vector3(5.7, 4.6, 5.8))
	var rill := _mat("6c9e99", 0.08, 0.25)
	_box("ApproachRill", Vector3(-4.2, 0.03, -4.6), Vector3(0.6, 0.04, 8.6), rill)
	_box("TurnedRill", Vector3(0, 0.03, -9.0), Vector3(8.8, 0.04, 0.6), rill)
	for index in range(6):
		_box("LandingStep", Vector3(-2.4, (5-index)*0.12, -3.7-index*0.65), Vector3(2.6, 0.24, 0.7), _floor)
	for index in range(20):
		var arch := _box("CircularDoorSegment", Vector3(-2.4+cos(float(index)*PI/19)*1.5, 1.8+sin(float(index)*PI/19)*1.5, -2.8), Vector3(0.27, 0.18, 0.35), _accent)
		arch.rotation.z = float(index)*PI/19+PI/2
	for x in [-3.9,-0.9]: _box("CircularDoorSupport",Vector3(x,0.9,-2.8),Vector3(0.18,1.8,0.35),_accent)
	_box("TurnExitPanel", Vector3(4.78, 1.6, -7.65), Vector3(0.12, 3.2, 2.5), _accent)
	for z in [-9.0,-6.3]:
		_box("TurnExitJamb", Vector3(4.65, 1.7, z), Vector3(0.25,3.4,0.18),_metal)
	_box("TurnExitLintel",Vector3(4.65,3.4,-7.65),Vector3(0.25,0.18,2.9),_metal)
	_light(Vector3(-2.5, 3.5, -1.8), Color("d6d1b4"), 1.6)
	_light(Vector3(2.4, 3.5, -7.5), Color("b3cfcb"), 2.0)

func _build_memory() -> void:
	_shell(5.2, 3.8, 10)
	_door = Node3D.new(); _door.name = "FoldingPrivacyScreen"; _door.position = Vector3(-2.5, 0, -3.6); _stage.add_child(_door)
	for index in range(6):
		var panel := _box("PrivacyPanel", Vector3(0.43+index*0.83, 1.5, 0.10 if index%2 else -0.10), Vector3(0.86, 3.0, 0.1), _accent, _door)
		panel.rotation.y = 0.13 if index%2 else -0.13
	_box("LoungeBench", Vector3(-1.9, 0.35, -1.8), Vector3(0.8, 0.7, 2.2), _floor)
	for side in [-1.0, 1.0]:
		_box("ArchiveCabinet", Vector3(side*2.1, 1.1, -7), Vector3(0.6, 2.2, 3.2), _metal)
		for row in range(4):
			_box("ArchiveDrawerSeam",Vector3(side*1.79,0.25+row*0.5,-7),Vector3(0.025,0.025,3.1),_accent)
			for column in range(4): _box("ArchivePull",Vector3(side*1.76,0.5+row*0.5,-5.85-column*0.75),Vector3(0.06,0.055,0.18),_accent)
	_light(Vector3(0, 2.8, -1.5), Color("dbc7a1"), 1.2)
	_reveal_light = _light(Vector3(0, 3.1, -7), Color("c9d2bd"), 0.6)
	var opal := _mat("e1e2c7")
	opal.emission_enabled = true; opal.emission = Color("cdd8b8"); opal.emission_energy_multiplier = 0.7
	_box("OculusLight", Vector3(0, 3.77, -7), Vector3(1.7, 0.04, 1.7), opal)

func _build_vent() -> void:
	_shell(3.6, 4.8, 9)
	_platform = Node3D.new(); _platform.name = "VentServicePlatform"; _stage.add_child(_platform)
	_box("LiftDeck", Vector3(0, 0.08, -2.4), Vector3(3.3, 0.16, 4.4), _metal, _platform)
	_door = Node3D.new(); _door.name = "VerticalLouverCover"; _door.position.z = -4.7; _stage.add_child(_door)
	for index in range(17):
		var blade := _box("VentBlade", Vector3(0, 0.13+index*0.25, 0), Vector3(3.4, 0.28, 0.15), _metal, _door)
		blade.rotation.x = -0.3
	_box("RaisedLanding", Vector3(0, 0.43, -6.85), Vector3(3.6, 0.86, 4.2), _floor)
	for side in [-1.0, 1.0]: _box("ServiceRunner", Vector3(side*1.65, 2.0, -2.5), Vector3(0.12, 4.0, 0.12), _accent)
	_light(Vector3(0, 3.4, -1), Color("a9c1ac"), 1.2)
	_light(Vector3(0, 3.8, -7), Color("e8e9cf"), 2.5)
	for pane in range(3): _box("ClerestoryDaylight",Vector3(-1.0+pane,3.15,-8.98),Vector3(0.85,1.8,0.025),_opal("dce8d2"))
	_box("WindowSill",Vector3(0,2.2,-8.85),Vector3(3.35,0.12,0.3),_accent)

func _build_daylight() -> void:
	_shell(6, 5.5, 13)
	for index in range(9):
		_box("DaylightStep", Vector3(0, index*0.12, -3.0-index*0.8), Vector3(4, 0.24, 0.85), _floor)
	_frame(-4.1, 4.1, 4.3)
	_door = _box("DaylightDoor", Vector3(0, 2.15, -4.1), Vector3(4.1, 4.3, 0.16), _accent)
	for side in [-1.0, 1.0]:
		for z in [-5.0, -7.5, -10.0]: _box("SunlitPier", Vector3(side*2.55, 2.75, z), Vector3(0.35, 5.5, 0.45))
	_light(Vector3(0, 3.5, -1), Color("c5ccb7"), 1.4)
	_light(Vector3(0, 4.3, -8), Color("fff0c9"), 3.5, 10)
	_box("FinalDaylightPane",Vector3(0,3.2,-12.98),Vector3(4.7,4.4,0.025),_opal("fff3d7"))
	for x in [-2.4,0.0,2.4]: _box("DaylightMullion",Vector3(x,3.2,-12.9),Vector3(0.11,4.5,0.12),_accent)

func _sample(progress: float) -> void:
	if not is_instance_valid(camera): return
	var t := smoothstep(0.0, 1.0, progress)
	var open := smoothstep(0.05, 0.5, progress)
	var point := Vector3.ZERO
	var target := Vector3(0, 1.6, -8)
	match chapter_index:
		0:
			_door.position = _base_door_position + Vector3(0, open*3.1, 0)
			point = Vector3(lerpf(0.25,0.75,t), 1.65, lerpf(-1.1, -5.8, t)); target = Vector3(1.05, 1.6, -9.9)
		1:
			var drop := smoothstep(0.1, 0.65, progress)*0.85
			_platform.position.y = -drop
			_door.position = _base_door_position + Vector3(0, smoothstep(0.6, 0.95, progress)*3.3, 0)
			point = Vector3(0, 2.65-drop, lerpf(-1.6, -3.8, smoothstep(0.65, 1.0, progress))); target = Vector3(0, 2.0-drop, -7.4)
		2:
			var turn := smoothstep(0.58, 1.0, progress)
			point = Vector3(lerpf(-2.4, 1.9, turn), lerpf(2.15, 1.85, t), lerpf(-0.8, -7.65, smoothstep(0.0, 0.78, progress)))
			var heading := lerpf(0.0, PI/2, smoothstep(0.32, 0.74, progress))
			target = point + Vector3(sin(heading), -0.04, -cos(heading))*3.0
		3:
			_door.scale.x = lerpf(1.0, 0.12, open)
			_reveal_light.light_energy = lerpf(0.45, 1.35, smoothstep(0.18, 0.9, progress))
			point = Vector3(0, 1.65, lerpf(-1.0, -5.6, t)); target = Vector3(0, lerpf(1.7, 2.4, t), -8)
		4:
			var rise := smoothstep(0.05, 0.55, progress)*0.85
			_platform.position.y = rise
			_door.position = _base_door_position + Vector3(0, smoothstep(0.35, 0.8, progress)*4.4, 0)
			point = Vector3(0, 1.75+rise, lerpf(-1.6, -5.9, smoothstep(0.55, 1.0, progress))); target = Vector3(0, 2.6, -8)
		5:
			_door.position = _base_door_position + Vector3(open*4.4, 0, 0)
			point = Vector3(0, lerpf(1.65, 2.5, t), lerpf(-1.1, -8.4, t)); target = Vector3(0, 2.9, -12)
	if reduced_effects:
		# Fixed viewpoint: architecture animates, no forced glide or vertical motion.
		point = [Vector3(0.25,1.65,-1.1),Vector3(0,2.65,-1.6),Vector3(-2.4,2.15,-1.0),Vector3(0,1.65,-1),Vector3(0,2.5,-1.6),Vector3(0,1.65,-1.1)][chapter_index]
		if chapter_index == 2: target = Vector3(-2.4,1.9,-7.8)
	camera.position = point
	camera.look_at(to_global(target))
