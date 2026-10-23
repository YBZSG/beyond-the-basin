extends SceneTree
## Continuous, real CharacterBody3D/Jolt/RigidBody3D and native 54-bone model QA.
## Controlled constant water plane isolates motion. It is NOT source water QA.
const Player = preload("res://scripts/player/pool_player.gd")
const Avatar = preload("res://scripts/player/pool_avatar.gd")
const Finish = preload("res://scripts/player/avatar_finish_candidate.gd")
const Prop = preload("res://scripts/player/pool_prop_body.gd")
const Inspector = preload("res://tests/water_motion/rig_motion_contract.gd")
const MODEL := "res://assets/water_motion/explorer_water_motion.scn"
const DT := 1.0 / 60.0
const MAX_TICKS := 1836
const SEGMENTS: Array[Dictionary] = [
	{"name":"walk_start_turn", "start":0.9, "count":6, "view":"side"},
	{"name":"shallow_044_wade", "start":3.0, "count":4, "view":"front"},
	{"name":"ramp_foot_support", "start":5.8, "count":4, "view":"foot_closeup"},
	{"name":"deep_forward_swim", "start":7.0, "count":19, "view":"side"},
	{"name":"idle_tread", "start":9.4, "count":6, "view":"front"},
	{"name":"ramp_exit", "start":13.4, "count":6, "view":"side"},
	{"name":"ordinary_jump", "start":17.1, "count":4, "view":"side"},
	{"name":"egg_carry_jump", "start":18.6, "count":12, "view":"look_down"},
	{"name":"charge_release_recover", "start":20.6, "count":10, "view":"side"},
	{"name":"duck_ordinary_drop", "start":22.4, "count":2, "view":"look_down"},
	{"name":"swim_wall_limbs", "start":24.3, "count":4, "view":"front"},
	{"name":"deep_swim_first_person_down", "start":28.6, "count":10, "view":"look_down"},
]
var output := "res://output/water-motion/review01"
var cpu_only := false
var first_frame_only := false
var avatar_hz := 60
var avatar_updates := 0
var tick := 0
var active := false
var started_ms := 0
var world: Node3D
var player: CharacterBody3D
var avatar: Node3D
var water: Node3D
var rig: RefCounted
var external_camera: Camera3D
var overlay: Label
var output_trace: FileAccess
var frames: Array[Dictionary] = []
var events: Array[Dictionary] = []
var action_modes: Dictionary = {}
var errors: Array[String] = []
var observed: Dictionary = {}
var captures: Array[Dictionary] = []
var next_capture := 0
var prop_serial := 0
var finishing := false
var pose_row: Dictionary = {}
var pose_sample_tick := -1
var elapsed_start: int = 0
var initial_capsule: Dictionary = {}
var frame_ready: Dictionary = {}
var source_hashes_at_start: Dictionary = {}
var finish: RefCounted
var finish_status: Dictionary = {}
var expected_source_manifest := ""
var expected_source_hashes: Dictionary = {}
var packed_resource_verification: Dictionary = {"required":false,"pass":true,"checked":0,"mismatches":[]}

class ControlledWater extends Node3D:
	var splash_count := 0
	func is_water_at(p: Vector3) -> bool: return p.z < 4.55 and absf(p.x) < 2.65
	func surface_height_at(_p: Vector3) -> float: return 0.0
	func depth_at(p: Vector3) -> float: return maxf(0.0, -floor_y(p.z))
	static func floor_y(z: float) -> float:
		if z >= 5.0: return 0.10
		if z > 4.0: return lerpf(-0.44, 0.10, z - 4.0)
		if z >= 2.5: return -0.44
		if z > 1.5: return lerpf(-1.04, -0.44, z - 1.5)
		if z >= 0.0: return -1.04
		if z > -3.0: return lerpf(-2.20, -1.04, (z + 3.0) / 3.0)
		return -2.20
	func foot_splash(_p: Vector3, _s: float, _d: float, _v: Vector2) -> void: splash_count += 1
	func wave_impact(_p: Vector3, _n: float) -> void: pass
	func wake_dipole(_p: Vector3, _d: Vector2, _s: float, _r: float) -> void: pass
	func push(_p: Vector3, _v: Vector2, _n: float) -> void: pass
	func player_impact(_p: Vector3, _n: float) -> void: pass
	func current_velocity_at(_p: Vector3) -> Vector2: return Vector2.ZERO
	func slope_at(_p: Vector3, _r: float) -> Vector4: return Vector4.ZERO

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--cpu-check": cpu_only = true
		if arg == "--first-frame": first_frame_only = true
		if arg.begins_with("--expected-source-manifest="): expected_source_manifest=arg.trim_prefix("--expected-source-manifest=")
		if arg.begins_with("--avatar-hz="): avatar_hz=clampi(int(arg.trim_prefix("--avatar-hz=")),1,60)
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 12
	started_ms = Time.get_ticks_msec()
	_setup.call_deferred()

func _material(color: Color) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color; value.roughness = 0.78
	return value

func _solid(name: String, center: Vector3, size: Vector3, color: Color, tilt: float = 0.0) -> void:
	var body := StaticBody3D.new(); body.name = name; body.collision_layer = 1
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = size; collision.shape = box
	body.add_child(collision)
	var mesh := MeshInstance3D.new(); var box_mesh := BoxMesh.new(); box_mesh.size = size; mesh.mesh = box_mesh; mesh.material_override = _material(color)
	body.add_child(mesh); world.add_child(body); body.position = center; body.rotation.x = tilt

func _floor_section(name: String, z0: float, y0: float, z1: float, y1: float, color: Color) -> void:
	var length: float = Vector2(z1-z0, y1-y0).length()
	var tilt: float = -atan2(y1-y0, z1-z0)
	# Offset the center by its rotated top-face normal so analytic and collision heights coincide.
	var normal := Vector3(0, cos(tilt), sin(tilt))
	_solid(name, Vector3(0, (y0+y1)*0.5, (z0+z1)*0.5) - normal*0.10, Vector3(5.3,0.20,length), color, tilt)

func _pool() -> void:
	world = Node3D.new(); world.name = "ControlledMotionReviewPool"; root.add_child(world)
	water = ControlledWater.new(); world.add_child(water)
	_floor_section("DryDeck",5,.1,10,.1,Color(.71,.69,.61))
	_floor_section("EntryRamp",4,-.44,5,.1,Color(.57,.67,.69))
	_floor_section("Depth044",2.5,-.44,4,-.44,Color(.52,.64,.65))
	_floor_section("DepthChangeRamp",1.5,-1.04,2.5,-.44,Color(.57,.67,.69))
	_floor_section("Depth104",0,-1.04,1.5,-1.04,Color(.52,.64,.65))
	_floor_section("DeepRamp",-3,-2.2,0,-1.04,Color(.58,.68,.69))
	_floor_section("Depth220",-12,-2.2,-3,-2.2,Color(.49,.62,.65))
	for x: float in [-2.8, 2.8]: _solid("PoolSide",Vector3(x,-.95,-1),Vector3(.3,2.6,24),Color(.77,.77,.70))
	_solid("DeepEnd",Vector3(0,-.95,-12.15),Vector3(5.9,2.6,.3),Color(.77,.77,.70))
	# Crisp tile dividers provide static foot-slip and root-motion references.
	for z: int in range(-11,10):
		var marker := MeshInstance3D.new(); var box := BoxMesh.new(); box.size=Vector3(5.24,.006,.018); marker.mesh=box; marker.material_override=_material(Color(.34,.44,.45)); world.add_child(marker)
		marker.position=Vector3(0,ControlledWater.floor_y(float(z))+.006,float(z))
	var plane := MeshInstance3D.new(); plane.name="CONTROLLED_CONSTANT_WATER_PLANE_NOT_SOURCE_RENDERER"
	var plane_mesh := PlaneMesh.new(); plane_mesh.size=Vector2(5.28,16.55); plane.mesh=plane_mesh
	var water_material := _material(Color(.14,.51,.61,.19)); water_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; water_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; water_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	plane.material_override=water_material; world.add_child(plane); plane.position=Vector3(0,0,-3.725)
	var env_node := WorldEnvironment.new(); var env := Environment.new(); env_node.environment=env
	env.background_mode=Environment.BG_COLOR; env.background_color=Color(.12,.17,.19); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(.79,.88,.95); env.ambient_light_energy=.75
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC; world.add_child(env_node)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-30,0); sun.light_energy=1.5; sun.shadow_enabled=false; world.add_child(sun)
	external_camera=Camera3D.new(); external_camera.fov=48; external_camera.near=.035; external_camera.far=50; external_camera.cull_mask=1 | 2 | (1<<16) | (1<<17); world.add_child(external_camera)
	var canvas := CanvasLayer.new(); world.add_child(canvas)
	overlay=Label.new(); overlay.position=Vector2(12,8); overlay.add_theme_font_size_override("font_size",13); overlay.add_theme_color_override("font_shadow_color",Color.BLACK); overlay.add_theme_constant_override("shadow_offset_x",1); overlay.add_theme_constant_override("shadow_offset_y",1); canvas.add_child(overlay)

func _setup() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_verify_packed_resources()
	if not bool(packed_resource_verification.pass):
		errors.append("Exact packed resource hash verification failed: "+str(packed_resource_verification)); _finish(); return
	if not ResourceLoader.exists(MODEL):
		errors.append("Final packed motion model not ready: " + MODEL); _finish(); return
	source_hashes_at_start=_source_hashes()
	_pool()
	for action: String in ["move_forward","move_back","move_left","move_right","sprint","jump","throw_prop","grab_prop","interact","pause"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		Input.action_release(action)
	player=Player.new(); world.add_child(player); player.set_physics_process(false); player.enabled=true; player.water_motion_actions_enabled=true; player.set_water(water)
	avatar=Avatar.new(); avatar.model_path=MODEL; player.add_child(avatar); avatar.set_process(false)
	if not bool(avatar.get_debug_state().get("loaded",false)):
		errors.append("Production avatar load failed: " + str(avatar.get_debug_state())); _finish(); return
	finish=Finish.new(); finish_status=finish.apply_to(avatar,true)
	finish_status["uv2_tangents"]=_cloth_contract()
	if int(finish_status.get("applied_surfaces",0))!=2 or not bool(finish_status.uv2_tangents.finite): errors.append("Production fabric finish or finite UV2/tangent contract failed")
	rig=Inspector.new(); rig.setup(avatar._model,avatar._skeleton)
	initial_capsule={"height":player.get_node("PlayerCapsule").shape.height,"radius":player.get_node("PlayerCapsule").shape.radius,"eye_y":player.camera.position.y}
	player.action_event.connect(func(kind: String, state: Dictionary): events.append({"tick":tick,"t":tick*DT,"kind":kind,"state":_jsonable(state)}))
	player.held_changed.connect(func(body: RigidBody3D): events.append({"tick":tick,"t":tick*DT,"kind":"held_changed","held":is_instance_valid(body)}))
	for segment: Dictionary in SEGMENTS:
		for index: int in int(segment.count):
			captures.append({"tick":roundi((float(segment.start)+index*.1)*60),"segment":segment.name,"view":segment.view,"segment_frame":index})
	output_trace=FileAccess.open(output+"/trace.jsonl",FileAccess.WRITE)
	if output_trace==null: errors.append("Trace output could not be created"); _finish(); return
	_reset(Vector3(0,.12,7),0.0,"dry start")
	physics_frame.connect(_step)
	if not cpu_only: RenderingServer.frame_post_draw.connect(_draw_capture)
	elapsed_start=Time.get_ticks_msec(); active=true

func _input(action: String, pressed: bool) -> void:
	if pressed: Input.action_press(action)
	else: Input.action_release(action)
	if action in ["jump","throw_prop","interact"]:
		var event:=InputEventAction.new(); event.action=action; event.pressed=pressed; player._unhandled_input(event)
	events.append({"tick":tick,"t":tick*DT,"kind":"input","action":action,"pressed":pressed})

func _reset(position: Vector3, yaw: float, reason: String) -> void:
	for action: String in ["move_forward","move_back","move_left","move_right","jump","throw_prop"]: Input.action_release(action)
	player.warp_to(position,position+Vector3(0,1.6,-1)); player.rotation.y=yaw; player.camera.rotation.x=0
	events.append({"tick":tick,"t":tick*DT,"kind":"isolated_segment_reset","reason":reason,"position":Inspector.vector(position)})

func _part(body: RigidBody3D, center: Vector3, axes: Vector3, color: Color) -> void:
	var mesh:=MeshInstance3D.new(); var sphere:=SphereMesh.new(); sphere.radius=1; sphere.height=2; sphere.radial_segments=24; sphere.rings=12; mesh.mesh=sphere; mesh.material_override=_material(color); mesh.position=center; mesh.scale=axes; body.add_child(mesh)

func _grab(kind: String) -> void:
	var body:=Prop.new(); body.configure(kind,{"radius":.17 if kind=="egg" else .2,"mass":.30},water); world.add_child(body); body.global_position=player.get_hold_anchor()
	if kind=="egg": _part(body,Vector3.ZERO,Vector3(.145,.205,.145),Color(.94,.90,.76))
	else:
		_part(body,Vector3(0,-.085,0),Vector3(.16,.105,.235),Color(.96,.73,.08))
		_part(body,Vector3(0,.065,-.10),Vector3(.11,.12,.115),Color(.96,.73,.08))
		_part(body,Vector3(0,.045,-.222),Vector3(.075,.026,.06),Color(.94,.30,.05))
		for x: float in [-.087,.087]: _part(body,Vector3(x,.098,-.158),Vector3(.018,.020,.015),Color(.02,.02,.02))
		for x: float in [-.125,.125]: _part(body,Vector3(x,-.055,.025),Vector3(.052,.055,.13),Color(.96,.73,.08))
	player.grab_prop(body); prop_serial+=1
	events.append({"tick":tick,"t":tick*DT,"kind":"grab","prop_kind":kind,"prop_serial":prop_serial})

func _tape() -> void:
	match tick:
		24: _input("move_forward",true)
		96: _input("move_forward",false)
		132: _input("move_forward",true)
		156: _reset(Vector3(0,-.42,3.8),0,"supported 0.44m shallow")
		162: _input("move_forward",true)
		264: _reset(Vector3(0,-1.02,.8),0,"supported 1.04m then continuous ramp into deep water")
		270: _input("move_forward",true)
		540: _input("move_forward",false)
		612: _input("move_back",true)
		876: _input("move_back",false)
		990: _reset(Vector3(0,.12,6.8),0,"dry jump and carry station")
		1020: _input("jump",true)
		1021: _input("jump",false)
		1092: _grab("egg")
		1116: _input("jump",true)
		1117: _input("jump",false)
		1224: _input("throw_prop",true)
		1260: _input("throw_prop",false)
		1308: _grab("duck")
		1350: player.interact_action(); events.append({"tick":tick,"t":tick*DT,"kind":"ordinary_interact_drop"})
		1440: _reset(Vector3(2.15,-1.48,-6),-PI/2,"deep swim wall contact; upright capsule does not protect limbs")
		1452: _input("move_forward",true)
		1572: _input("move_forward",false)
		1620: _reset(Vector3(0,-1.48,-5),0,"free deep first-person downward swim")
		1680: _input("move_forward",true)
		1800: _input("move_forward",false)
	if tick>=75 and tick<=96: player.rotation.y+=(.60/22.0)

func _step() -> void:
	if not active or finishing: return
	_tape()
	player._physics_process(DT)
	var avatar_stride: int=60/avatar_hz
	if (tick+1)%avatar_stride==0:
		avatar._process(DT*avatar_stride); avatar_updates+=1
	var state: Dictionary=player.get_action_state()
	var avatar_debug: Dictionary=avatar.get_debug_state()
	state["review_gait_phase"]=avatar_debug.gait_phase
	state["review_swim_blend"]=avatar_debug.swim_blend
	state["review_swim_forward"]=avatar_debug.water_actions.get("swim_forward",0.0)
	action_modes[str(state.mode)]=true
	if str(state.get("jump_phase","none"))!="none": observed["jump_"+str(state.jump_phase)]=true
	if str(state.get("throw_phase","none"))!="none": observed["throw_"+str(state.throw_phase)]=true
	var detailed: bool=tick%6==0
	pose_row=rig.sample(state,func(p: Vector3) -> float:return ControlledWater.floor_y(p.z),detailed)
	if detailed:
		var row:=_trace_row(state,pose_row); output_trace.store_line(JSON.stringify(row)); pose_sample_tick=tick
	if tick==984: observed.ramp_exit_state=_jsonable(state); observed.ramp_exit_position=Inspector.vector(player.position)
	if tick==530: observed.deep_forward_state=_jsonable(state)
	if tick==605: observed.tread_state=_jsonable(state)
	_update_camera()
	tick+=1
	if tick>=MAX_TICKS or Time.get_ticks_msec()-started_ms>175000: _finish.call_deferred()

func _trace_row(state: Dictionary, pose: Dictionary) -> Dictionary:
	var debug: Dictionary=avatar.get_debug_state()
	return {"tick":tick,"simulated_seconds":tick*DT,"wall_seconds":(Time.get_ticks_msec()-elapsed_start)/1000.0,"player":Inspector.vector(player.position),"velocity":Inspector.vector(player.velocity),"yaw":player.rotation.y,"physical_state":_jsonable(state),"gait_phase":debug.gait_phase,"swim_blend":debug.swim_blend,"hold_blend":debug.hold_blend,"water_actions":_jsonable(debug.water_actions),"hand_ik":_jsonable(debug.hand_ik),"foot_clearance":_jsonable(debug.get("foot_clearance",{})),"pose":pose,"held_position":Inspector.vector(player.held.global_position) if is_instance_valid(player.held) else null}

func _update_camera() -> void:
	var view: String="side"; var segment: String="between recorded windows"
	for part: Dictionary in SEGMENTS:
		var begin: int=roundi(float(part.start)*60)-30
		var end: int=roundi((float(part.start)+float(part.count)*.1)*60)+6
		if tick>=begin and tick<=end: view=part.view; segment=part.name
	if view=="look_down":
		player.camera.current=true; player.camera.rotation.x=-1.05
	else:
		player.camera.rotation.x=0; external_camera.current=true
		var target: Vector3=player.position+Vector3(0,.9,0)
		if player.get_action_state().swimming: target.y=-.38
		var offset: Vector3=Vector3(2.9,1.15,1.35) if view=="side" else Vector3(.7,1.55,-4.0)
		if str(segment)=="swim_wall_limbs": offset=Vector3(-3.8,2.0,2.8)
		if view=="foot_closeup": target=player.position+Vector3(0,.28,0); offset=Vector3(1.8,.7,1.0)
		external_camera.position=target+offset; external_camera.look_at(target,Vector3.UP)
	var s: Dictionary=player.get_action_state()
	overlay.text="NATIVE SKIN + REAL PHYSICS | CONTROLLED WATER PLANE\n%s | %s | t=%.2fs | phase=%.2f\nFixed 60Hz physics / 10Hz recording, NOT real-time PC FPS"%[segment,str(s.mode),tick*DT,float(s.stroke_phase)]

func _draw_capture() -> void:
	if cpu_only or not active or finishing or next_capture>=captures.size(): return
	if tick<int(captures[next_capture].tick): return
	var item: Dictionary=captures[next_capture].duplicate()
	var filename: String="motion-%02d.jpg"%next_capture
	var image: Image=root.get_texture().get_image()
	if image.get_width()!=640 or image.get_height()!=360: image.resize(640,360,Image.INTERPOLATE_LANCZOS)
	var err: Error=image.save_jpg(output+"/"+filename,.82)
	if err!=OK: errors.append("Capture save error "+str(err))
	item.file=filename; item.actual_tick=tick; item.actual_simulated_seconds=tick*DT; item.state=_jsonable(player.get_action_state()); item.player=Inspector.vector(player.position); item.camera=Inspector.vector(get_root().get_camera_3d().global_position)
	item.pose=rig.sample(player.get_action_state(),func(p: Vector3) -> float:return ControlledWater.floor_y(p.z),true)
	frames.append(item); next_capture+=1
	if first_frame_only: _finish.call_deferred()

func _jsonable(value: Variant) -> Variant:
	if value is Vector3: return Inspector.vector(value)
	if value is Vector2: return [value.x,value.y]
	if value is Quaternion: return [value.x,value.y,value.z,value.w]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value: result[str(key)]=_jsonable(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(_jsonable(item))
		return result
	return value

func _cloth_contract() -> Dictionary:
	var result: Dictionary={"surfaces":0,"finite":true,"uv2_values":0,"tangent_values":0}
	for node: Node in avatar._model.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=node as MeshInstance3D
		if mesh.mesh==null: continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material=mesh.mesh.surface_get_material(surface)
			if material==null or material.resource_name not in [Finish.SHIRT_NAME,Finish.TROUSERS_NAME]: continue
			result.surfaces+=1
			var arrays: Array=mesh.mesh.surface_get_arrays(surface)
			for value: Vector2 in arrays[Mesh.ARRAY_TEX_UV2]:
				result.uv2_values+=1
				if not value.is_finite(): result.finite=false
			for value: float in arrays[Mesh.ARRAY_TANGENT]:
				result.tangent_values+=1
				if not is_finite(value): result.finite=false
	return result

func _verify_packed_resources() -> void:
	if expected_source_manifest.is_empty(): return
	packed_resource_verification.required=true
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(expected_source_manifest))
	if not parsed is Dictionary:
		packed_resource_verification.pass=false; packed_resource_verification.mismatches.append("Manifest is not a JSON object"); return
	expected_source_hashes=parsed.get("files",parsed)
	if expected_source_hashes.is_empty():
		packed_resource_verification.pass=false; packed_resource_verification.mismatches.append("Empty manifest"); return
	for path: String in expected_source_hashes:
		var expected: String=str(expected_source_hashes[path])
		var actual: String=FileAccess.get_sha256(path)
		packed_resource_verification.checked+=1
		if not path.begins_with("res://") or actual!=expected:
			packed_resource_verification.pass=false; packed_resource_verification.mismatches.append({"path":path,"expected":expected,"actual":actual})

func _source_hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in [MODEL,"res://scripts/player/pool_player.gd","res://scripts/player/water_motion_state.gd","res://scripts/player/pool_avatar.gd","res://scripts/player/avatar_water_actions.gd","res://scripts/player/avatar_hand_ik.gd","res://scripts/player/avatar_finger_poses.gd","res://scripts/player/avatar_finish_candidate.gd","res://shaders/avatar_finish_candidate.gdshader"]:
		result[path]=FileAccess.get_sha256(path)
	for path: String in expected_source_hashes:
		result[path]=FileAccess.get_sha256(path)
	if FileAccess.file_exists("res://scripts/player/avatar_foot_clearance.gd"):
		result["res://scripts/player/avatar_foot_clearance.gd"]=FileAccess.get_sha256("res://scripts/player/avatar_foot_clearance.gd")
	return result

func _finish() -> void:
	if finishing: return
	finishing=true; active=false
	if output_trace!=null: output_trace.close()
	var source_hashes_at_end: Dictionary=_source_hashes()
	var sources_stable: bool=source_hashes_at_start==source_hashes_at_end
	if not source_hashes_at_start.is_empty() and not sources_stable: errors.append("Production sources changed during this run; cannot claim stable-build acceptance")
	var rig_result: Dictionary=rig.result() if rig!=null else {}
	var structural: bool=not rig_result.is_empty() and rig_result.original_42_missing.is_empty() and rig_result.added_12_missing.is_empty() and int(rig_result.finite_transform_errors)==0 and float(rig_result.max_pose_scale_error)<.001 and float(rig_result.max_link_length_error_m)<.001 and rig_result.bind_errors.is_empty()
	var angular_pass: bool=float(rig_result.get("max_steady_forward_swim_rotation_step_degrees",0.0))<(10.0*60.0/float(avatar_hz))
	if not angular_pass: errors.append("Steady forward Swim pose exceeds10deg-per60Hz-normalized update diagnostic")
	var report: Dictionary={"scope":"Actual production player, avatar, AnimationTree, 54-bone skinned mesh and physical props in bounded native Jolt pool. Constant controlled-plane water, NOT source192/SWE water rendering. No lightmap/GI/probes/full-world overhead.","finish_status":finish_status,"angular_pass":angular_pass,"cpu_only":cpu_only,"structural_pass":structural,"visual_acceptance":false,"errors":errors,"simulated_seconds":tick*DT,"wall_seconds":(Time.get_ticks_msec()-started_ms)/1000.0,"packed_resource_verification":packed_resource_verification,"source_hashes_at_start":source_hashes_at_start,"source_hashes_at_end":source_hashes_at_end,"sources_stable":sources_stable,"physics_ticks":tick,"physics_hz":60,"avatar_update_hz":avatar_hz,"avatar_updates":avatar_updates,"controller_endpoint":Inspector.vector(player.position) if is_instance_valid(player) else [],"controller_velocity":Inspector.vector(player.velocity) if is_instance_valid(player) else [],"avatar_idle_clock":avatar._idle_clock if is_instance_valid(avatar) else 0.0,"recording_hz":10,"expected_images":1 if first_frame_only else captures.size(),"captured_images":frames.size(),"model":MODEL,"rig":rig_result,"modes_observed":action_modes.keys(),"observed":observed,"frames":frames,"events":events,"initial_capsule":initial_capsule,"final_avatar":_jsonable(avatar.get_debug_state()) if is_instance_valid(avatar) else {},"limitations":["Not target-PC FPS. Native deterministic fixed-time recording can run slower than real time.","Water is an explicitly controlled constant plane, not production wave/refraction/GI validation.","Hand/torso overlap is approximate; screenshots require visual inspection. Capsule does not enclose pitched limbs.","Named isolated resets separate test stations; captures inside each labelled segment are continuous."]}
	var file:=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("MOTION_REVIEW "+JSON.stringify({"structural_pass":structural,"cpu_only":cpu_only,"images":frames.size(),"errors":errors,"seconds":tick*DT,"rig":rig_result}))
	quit(0 if errors.is_empty() and structural and (cpu_only or frames.size()==(1 if first_frame_only else captures.size())) else 1)
