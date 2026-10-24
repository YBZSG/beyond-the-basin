extends Node
## Reproducible input driver. Never assigns player position or velocity.
## The unmodified PoolPlayer owns gravity, capsule, steps, collision and camera.
var player: CharacterBody3D
var room_origin := Vector3.ZERO
var completed := false
var running := false
var errors: Array[String] = []
var trace: Array = []
var phases: Array = []
var phase_index := 0
var phase_time := 0.0
var elapsed := 0.0
var physical_ticks := 0
var initial_epoch := -1
var wall_ticks := 0
var wet_ticks := 0
var grounded_ticks := 0
var min_feet_y := INF
var max_feet_y := -INF
var max_tick_displacement := 0.0
var previous_position := Vector3.ZERO
var phase_start := Vector3.ZERO
var phase_reports: Array = []
var pending_snapshots: Array[String] = []
var start_position := Vector3.ZERO

func _ready() -> void:
	process_physics_priority = -100
	set_physics_process(false)

func vec(p: Vector3) -> Array:
	return [snappedf(p.x,.00001),snappedf(p.y,.00001),snappedf(p.z,.00001)]

func start() -> void:
	phases=[
		{"label":"01-dry-landing","kind":"pause","duration":.25,"target":Vector3(-4,.52,-6.5)},
		{"label":"02-descend-real-north-stairs","kind":"walk","target":Vector3(-4,-.22,-6.5),"limit":6.0},
		{"label":"03-wade-towards-pier","kind":"walk","target":Vector3(-2.4,-.22,-6.5),"limit":4.0},
		{"label":"04-press-against-pier","kind":"contact","target":Vector3(-2.4,-.22,-7.5),"duration":1.5},
		{"label":"05-stop-at-pier","kind":"pause","target":Vector3(-2.4,-.22,-7.5),"duration":.35},
		{"label":"06-turn-and-retreat","kind":"walk","target":Vector3(-2.4,-.22,-6.5),"limit":4.0},
		{"label":"07-return-to-stairs","kind":"walk","target":Vector3(-4,-.22,-6.5),"limit":4.0},
		{"label":"08-climb-to-dry-landing","kind":"walk","target":Vector3(-4,.52,-9.6),"limit":6.0},
		{"label":"09-finish-dry-grounded","kind":"pause","target":Vector3(-4,.52,-12),"duration":.5}
	]
	initial_epoch=player.locomotion_epoch
	previous_position=player.global_position
	start_position=player.global_position
	phase_start=player.global_position
	running=true
	set_physics_process(true)

func current_label() -> String:
	return String(phases[mini(phase_index,phases.size()-1)].label) if not phases.is_empty() else "setup"

func _physics_process(delta: float) -> void:
	if not running or completed:return
	elapsed+=delta;physical_ticks+=1;phase_time+=delta
	var phase:Dictionary=phases[phase_index]
	var state:Dictionary=player.get_action_state()
	if state.in_water:wet_ticks+=1
	if player.is_on_wall():wall_ticks+=1
	if player.is_on_floor():grounded_ticks+=1
	min_feet_y=minf(min_feet_y,player.global_position.y)
	max_feet_y=maxf(max_feet_y,player.global_position.y)
	max_tick_displacement=maxf(max_tick_displacement,player.global_position.distance_to(previous_position))
	previous_position=player.global_position
	if physical_ticks%12==0:
		trace.append({"tick":physical_ticks,"simulation_seconds":snappedf(elapsed,.0001),"phase":phase.label,"feet":vec(player.global_position-room_origin),"eye":vec(player.camera.global_position-room_origin),"eye_height_above_feet":player.camera.global_position.y-player.global_position.y,"grounded":player.is_on_floor(),"wall":player.is_on_wall(),"mode":state.mode,"forward_input":Input.is_action_pressed("move_forward"),"locomotion_epoch":player.locomotion_epoch})
	if player.locomotion_epoch!=initial_epoch:
		fail("Unexpected warp/enable epoch change during continuous route")
		return
	if elapsed>32.0:
		fail("Continuous fixture route exceeded 32 simulated seconds")
		return
	var target:Vector3=room_origin+phase.target
	var difference:=target-player.global_position
	difference.y=0
	var desired_yaw:=atan2(-difference.x,-difference.z)
	var turn:=wrapf(desired_yaw-player.rotation.y,-PI,PI)
	# Look input only. No camera/root translation, velocity or collision override.
	player.rotate_y(clampf(turn,-PI*delta,PI*delta))
	player.camera.rotation.x=move_toward(player.camera.rotation.x,-.9 if phase.kind in ["contact","pause"] and phase_index in [3,4] else -.035,delta*.7)
	var walking:bool=phase.kind in ["walk","contact"] and absf(turn)<.16
	if walking:Input.action_press("move_forward")
	else:Input.action_release("move_forward")
	if phase.kind=="walk":
		if difference.length()<.075:
			advance_phase()
		elif phase_time>float(phase.limit):
			fail("Failed to reach "+String(phase.label))
	elif phase_time>=float(phase.duration):
		if phase.kind=="contact" and not player.is_on_wall():errors.append("Pier press did not end against a collision wall")
		advance_phase()

func advance_phase() -> void:
	Input.action_release("move_forward")
	var phase:Dictionary=phases[phase_index]
	phase_reports.append({"phase":phase.label,"duration":phase_time,"start":vec(phase_start-room_origin),"end":vec(player.global_position-room_origin),"grounded":player.is_on_floor(),"wall":player.is_on_wall(),"wet":player.get_action_state().in_water})
	pending_snapshots.append(phase.label)
	phase_index+=1;phase_time=0.0;phase_start=player.global_position
	if phase_index>=phases.size():
		if not player.is_on_floor() or absf(player.global_position.y-.52)>.04:errors.append("Return did not finish grounded on the dry deck")
		if wet_ticks==0:errors.append("Route did not enter water")
		if wall_ticks==0:errors.append("Route did not prove collision against the pier")
		if min_feet_y<-.26:errors.append("Feet fell below the basin floor")
		if max_tick_displacement>.20:errors.append("Unexpected discontinuous physical displacement")
		completed=true;running=false;set_physics_process(false)

func fail(message: String) -> void:
	errors.append(message);Input.action_release("move_forward")
	completed=true;running=false;set_physics_process(false)

func result() -> Dictionary:
	return {"pass":completed and errors.is_empty(),"errors":errors,"simulated_seconds":elapsed,"actual_physics_ticks":physical_ticks,"controller_delta_hz":physical_ticks/maxf(elapsed,.001),"phases":phase_reports,"trace":trace,"wet_ticks":wet_ticks,"wall_ticks":wall_ticks,"grounded_ticks":grounded_ticks,"minimum_feet_y":min_feet_y,"maximum_feet_y":max_feet_y,"maximum_tick_displacement":max_tick_displacement,"start":vec(start_position-room_origin),"end":vec(player.global_position-room_origin),"initial_locomotion_epoch":initial_epoch,"final_locomotion_epoch":player.locomotion_epoch,"position_writes_after_start":0,"input":"Normal Input actions and yaw/pitch look input only; automatic unmodified production PoolPlayer physics."}
