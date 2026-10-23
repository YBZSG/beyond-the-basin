extends SceneTree
## Actual controller input in the original pool. Fixed-step images are visual
## evidence only, not real-time performance measurements.
var destination := ""
var report: Dictionary = {"errors":[],"steps":[],"samples":[],"phases":{}}
var recorded_frame := 0
var phase_name := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wading-out="): destination=arg.trim_prefix("--wading-out=")
	var isolated := OS.get_environment("APPDATA").replace("\\","/")
	if destination.is_empty() or not isolated.contains("/output/wading/") or not OS.get_user_data_dir().replace("\\","/").begins_with(isolated):
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(destination.path_join("frames"))
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	game.qa_capture_hook=_inspect
	root.add_child(game)

func _inspect(game: Node3D) -> int:
	report.device=RenderingServer.get_video_adapter_name()
	report.method="Actual WASD/sprint input, fixed 30 simulation frames/second, recorded at 15 FPS. Props frozen to isolate player waves. No synthetic water splash. Not a realtime benchmark."
	# main.gd deliberately clears water tuning in QA. Restore the isolated
	# copy explicitly so this comparison represents the player's real settings.
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return 3
	report.water_overrides=config.get_value("water", "settings", {})
	for key: String in report.water_overrides:
		game.water.set_tuning(key, report.water_overrides[key])
	game.set_menu(false)
	game.props.set_enabled(false)
	for body in game.props.bodies:
		body.freeze=true
		body.collision_layer=0
		body.collision_mask=0
	game.player.warp_to(Vector3(0,-0.70,12),Vector3(0,-0.70,0))
	game.player.camera.rotation.x=-0.95
	game.player.set_enabled(true)
	game.player.interaction.connect(_on_interaction)
	for i in 45: await process_frame
	report.start=game.player.get_status()
	await _phase(game,"walk",90,true,false)
	await _phase(game,"walk_stop",60,false,false)
	await _phase(game,"sprint",90,true,true)
	await _phase(game,"sprint_stop",120,false,false)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	report.water=game.water.debug_stats()
	report.avatar=game.avatar.get_debug_state()
	report.surface_uniforms={}
	for key in ["simulationOn","waveHeight","rippleGain","normalBoost","ripplesOn"]:
		report.surface_uniforms[key]=game.water._materials.values()[0].get_shader_parameter(key)
	if float(report.surface_uniforms.simulationOn)<0.5 or float(report.surface_uniforms.waveHeight)<=0.0: report.errors.append("Surface waves hidden by material settings")
	report.frames=recorded_frame/2
	if report.steps.size()<10: report.errors.append("Too few actual wading footsteps")
	if not report.avatar.loaded: report.errors.append("Avatar unavailable")
	if not game.water.last_error.is_empty(): report.errors.append(game.water.last_error)
	if not str(report.water.caustic_error).is_empty(): report.errors.append(report.water.caustic_error)
	report.pass=report.errors.is_empty()
	FileAccess.open(destination.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("WADING_QA_RESULT ",JSON.stringify({"pass":report.pass,"errors":report.errors,"phases":report.phases}))
	return 0 if report.pass else 1

func _on_interaction(kind: String, point: Vector3, power: float) -> void:
	if kind=="step_water": report.steps.append({"frame":recorded_frame,"phase":phase_name,"position":point,"speed_weight":power})

func _phase(game: Node3D, label: String, frames: int, moving: bool, sprinting: bool) -> void:
	phase_name=label
	if moving: Input.action_press("move_forward")
	else: Input.action_release("move_forward")
	if sprinting: Input.action_press("sprint")
	else: Input.action_release("sprint")
	var first: Vector3=game.player.global_position
	var water_start: float=game.water._time
	var step_count: int=report.steps.size()
	var peak := 0.0
	var late_peak := 0.0
	var liquid_max := 0
	for i in frames:
		await process_frame
		var height := 0.0
		var center: Vector2=Vector2(game.player.global_position.x,game.player.global_position.z)-game.water.domain_origin
		# Existing asynchronous physics snapshot; no synchronous GPU readback.
		for x in range(-8,9):
			for z in range(-8,9): height=maxf(height,absf(game.water.solver.height_at(center+Vector2(x,z)*.25)))
		peak=maxf(peak,height)
		if i>=frames-15: late_peak=maxf(late_peak,height)
		var water_state: Dictionary=game.water.debug_stats()
		liquid_max=maxi(liquid_max,int(water_state.liquid.domains))
		# Allow the initial deceleration, then reject any new stationary step.
		if not moving and i==30: step_count=report.steps.size()
		if not moving and i>30 and report.steps.size()>step_count: report.errors.append("Idle footstep in "+label)
		report.samples.append({"frame":recorded_frame,"phase":label,"position":game.player.global_position,"speed":game.player.locomotion_speed,"local_height_peak_m":height,"liquid_domains":water_state.liquid.domains})
		if recorded_frame%2==0:
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			if picture.get_format() in [Image.FORMAT_RGBH,Image.FORMAT_RGBAH,Image.FORMAT_RGBF,Image.FORMAT_RGBAF]:
				var display := Image.create(picture.get_width(),picture.get_height(),false,Image.FORMAT_RGBA8)
				for y in picture.get_height():
					for x in picture.get_width(): display.set_pixel(x,y,picture.get_pixel(x,y).linear_to_srgb())
				picture=display
			var error := picture.save_png(destination.path_join("frames/%04d.png"%int(recorded_frame/2)))
			if error!=OK: report.errors.append("Capture failed: "+str(error))
		recorded_frame+=1
	report.phases[label]={"distance_m":game.player.global_position.distance_to(first),"water_seconds":game.water._time-water_start,"height_peak_m":peak,"last_half_second_peak_m":late_peak,"liquid_max_domains":liquid_max}
	if moving and float(report.phases[label].distance_m)<1.0: report.errors.append("Movement blocked during "+label)
	print("WADING_QA_PHASE ",label," ",JSON.stringify(report.phases[label]))
