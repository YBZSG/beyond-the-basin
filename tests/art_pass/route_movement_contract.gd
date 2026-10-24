extends SceneTree
## Actual unmodified production PoolPlayer + production collision builder + Jolt.
## Water here is a deterministic sampler of authored rectangles/steps, NOT SWE/MPM.
const Player=preload("res://scripts/player/pool_player.gd")
const Catalog=preload("res://scripts/world/expanded_room_catalog.gd")
const Builder=preload("res://scripts/world/room_builder.gd")
const DT=1.0/120.0
var room:Node3D
var builder:RefCounted
var player:CharacterBody3D
var sampler:Node3D
var reports:Array=[]
var errors:Array=[]
var current_trace:Array=[]
var frames:=0
var version:="candidate"

class AuthoredDepthSampler extends Node3D:
	var layout:Dictionary
	var origin:Vector3=Vector3.ZERO
	func is_water_at(p:Vector3)->bool:
		p-=origin
		for rectangle:Rect2 in layout.water_rects:
			if rectangle.has_point(Vector2(p.x,p.z)):
				for box:AABB in layout.water_exclusions:
					if p.x>=box.position.x and p.x<=box.end.x and p.z>=box.position.z and p.z<=box.end.z:return false
				return true
		return false
	func surface_height_at(_p:Vector3)->float:return .32+origin.y
	func depth_at(p:Vector3)->float:
		if not is_water_at(p):return 0.0
		p-=origin
		var floor_y:float=-.72
		for box:AABB in layout.water_steps:
			if p.x>=box.position.x and p.x<=box.end.x and p.z>=box.position.z and p.z<=box.end.z:floor_y=maxf(floor_y,box.end.y)
		return maxf(0.0,.32-floor_y)
	func wave_impact(_p:Vector3,_power:float)->void:pass
	func wake_dipole(_p:Vector3,_direction:Vector2,_speed:float,_sigma:float)->void:pass
	func push(_p:Vector3,_direction:Vector2,_sigma:float)->void:pass
	func player_impact(_p:Vector3,_power:float)->void:pass
	func current_velocity_at(_p:Vector3)->Vector2:return Vector2.ZERO
	func slope_at(_p:Vector3,_radius:float)->Vector4:return Vector4.ZERO

func _initialize()->void:
	Engine.physics_ticks_per_second=120
	_run.call_deferred()
func vec(v:Vector3)->Array:return [snappedf(v.x,.00001),snappedf(v.y,.00001),snappedf(v.z,.00001)]
func tick(count:int=1)->void:
	for i in count:
		await physics_frame
		player._physics_process(DT);frames+=1
		if frames%30==0:
			var s:Dictionary=player.get_action_state()
			current_trace.append({"frame":frames,"position":vec(player.position),"grounded":player.is_on_floor(),"mode":s.mode,"jump_phase":s.jump_phase})
func warp(p:Vector3)->void:
	Input.action_release("move_forward");Input.action_release("sprint")
	player.warp_to(p,p+Vector3(0,1.6,-1));player.enabled=true
	await tick(15)
func travel(target:Vector3,max_seconds:float=25.0)->Dictionary:
	var start:Vector3=player.position;var start_frame:int=frames
	var minimum_y:float=player.position.y;var maximum_y:float=player.position.y
	var swimming_ticks:=0;var air_ticks:=0;var wall_ticks:=0
	var previous:Vector3=player.position;var stalls:=0
	Input.action_press("move_forward")
	var reached:=false
	for i:int in ceili(max_seconds*120):
		var difference:Vector3=target-player.position;difference.y=0.0
		if difference.length()<.085:reached=true;break
		player.rotation.y=atan2(-difference.x,-difference.z)
		await tick()
		minimum_y=minf(minimum_y,player.position.y);maximum_y=maxf(maximum_y,player.position.y)
		if player.get_action_state().swimming:swimming_ticks+=1
		if not player.is_on_floor():air_ticks+=1
		if player.is_on_wall():wall_ticks+=1
		if i>60 and player.position.distance_to(previous)<.00001:stalls+=1
		previous=player.position
		if stalls>240:break
	Input.action_release("move_forward")
	return {"reached":reached,"start":vec(start),"target":vec(target),"end":vec(player.position),"duration_seconds":float(frames-start_frame)*DT,"min_y":minimum_y,"max_y":maximum_y,"swimming_ticks":swimming_ticks,"air_ticks":air_ticks,"wall_ticks":wall_ticks,"stalled_ticks":stalls,"height_error":absf(player.position.y-target.y)}
func add(label:String,passed:bool,data:Dictionary)->void:
	data["name"]=label;data["pass"]=passed;reports.append(data)
	if not passed:errors.append(label)
	print("ROUTE_MOVEMENT_CASE ",label," ",passed)
func _run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--baseline":version="baseline"
	for action:String in ["move_left","move_right","move_forward","move_back","sprint","jump","throw_prop","grab_prop","interact","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		Input.action_release(action)
	room=Node3D.new();root.add_child(room)
	var layout:Dictionary=Catalog.room_layout(Vector2i(1,0),250821,1)
	if version=="candidate":layout.geometry_path="res://assets/models/art_pass/low_arched_bath_crossing_runtime.glb"
	builder=Builder.new(room,layout,null);builder.build_shell()
	sampler=AuthoredDepthSampler.new();sampler.layout=layout;root.add_child(sampler)
	player=Player.new();root.add_child(player);player.set_physics_process(false);player.set_water(sampler);player.enabled=true;player.water_motion_actions_enabled=true
	var sides:Array[Vector2i]=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	# Every ordered pair of distinct inner portals: four straight and eight 90-degree turns.
	for entry:int in 4:
		for exit:int in 4:
			if entry==exit:continue
			current_trace=[]
			await warp(Vector3(sides[entry].x*12.0,.54,sides[entry].y*12.0))
			var centre:Dictionary=await travel(Vector3(0,.52,0))
			var end:Dictionary=await travel(Vector3(sides[exit].x*12.0,.52,sides[exit].y*12.0))
			var ok:bool=centre.reached and end.reached and centre.height_error<.04 and end.height_error<.04 and centre.min_y>.49 and end.min_y>.49 and centre.swimming_ticks==0 and end.swimming_ticks==0
			add("inner_portal_%d_to_%d"%[entry,exit],ok,{"segments":[centre,end],"trace":current_trace})
	# Full outside threshold to deck and back at each of the original seven-riser entries.
	for side:int in 4:
		current_trace=[];var direction:=Vector3(sides[side].x,0,sides[side].y)
		await warp(direction*15.75+Vector3(0,-.70,0))
		var up:Dictionary=await travel(direction*10.6+Vector3(0,.52,0))
		var down:Dictionary=await travel(direction*15.75+Vector3(0,-.72,0))
		await tick(45)
		down["settled_end"]=vec(player.position);down["settled_height_error"]=absf(player.position.y+.72)
		add("outer_entry_stairs_%d"%side,up.reached and down.reached and up.height_error<.04 and down.settled_height_error<.04 and up.swimming_ticks==0 and down.swimming_ticks==0,{"segments":[up,down],"trace":current_trace})
	# Descend/ascend the real original five-tread access into every 7x7m basin.
	for sx:int in [-1,1]:
		for sz:int in [-1,1]:
			current_trace=[];await warp(Vector3(sx*2.0,.54,sz*6.4))
			var down:Dictionary=await travel(Vector3(sx*6.0,-.72,sz*6.4))
			var up:Dictionary=await travel(Vector3(sx*2.0,.52,sz*6.4))
			add("basin_stairs_%d_%d"%[sx,sz],down.reached and up.reached and down.height_error<.04 and up.height_error<.04 and down.swimming_ticks==0 and up.swimming_ticks==0,{"segments":[down,up],"trace":current_trace})
	# Jump directly below each new arch and near its lower spring. No artificial roof shape.
	for axis:int in 2:
		for side:int in [-1,1]:
			for offset:float in [0.0,2.1]:
				current_trace=[]
				var start:=Vector3(offset,.54,side*2.72) if axis==0 else Vector3(side*2.72,.54,offset)
				await warp(start)
				var y0:float=player.position.y;var apex:float=y0;var ceiling_ticks:=0;var took_off:=false
				var event:=InputEventAction.new();event.action="jump";event.pressed=true;player._unhandled_input(event)
				for i in 180:
					await tick();apex=maxf(apex,player.position.y)
					if player.is_on_ceiling():ceiling_ticks+=1
					if not player.is_on_floor():took_off=true
				var theoretical:float=Player.JUMP_SPEED*Player.JUMP_SPEED/(2.0*Player.GRAVITY)
				add("full_jump_arch_%d_%d_%.1f"%[axis,side,offset],took_off and ceiling_ticks==0 and absf(apex-y0-theoretical)<.035 and player.is_on_floor() and absf(player.position.y-y0)<.015,{"start":vec(start),"apex_feet_y":apex,"apex_capsule_top_y":apex+Player.BODY_HEIGHT,"theoretical_jump_rise":theoretical,"ceiling_ticks":ceiling_ticks,"trace":current_trace})
	# New piers must block diagonal walking rather than allow clipping through architecture.
	if version=="candidate":
		for sx:int in [-1,1]:
			for sz:int in [-1,1]:
				current_trace=[];await warp(Vector3(sx*1.6,.54,sz*1.6))
				var contact:Dictionary=await travel(Vector3(sx*2.72,.52,sz*2.72),4.0)
				var distance:float=Vector2(absf(player.position.x)-2.51,absf(player.position.z)-2.51).length()
				add("pier_blocks_diagonal_%d_%d"%[sx,sz],not contact.reached and contact.wall_ticks>0 and absf(player.position.x)<2.51 and absf(player.position.z)<2.51 and distance>.30,{"segment":contact,"distance_to_pier_corner":distance,"trace":current_trace})
	var report:Dictionary={"pass":errors.is_empty(),"errors":errors,"version":version,"engine":Engine.get_version_info(),"physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine"),"controller":"Unmodified production PoolPlayer", "physics_hz":120,"simulated_seconds":frames*DT,"checks":reports,"water_scope":"Controlled static authored-depth sampler only, not source SWE/MPM, optical water, waves, currents, or performance acceptance.","scope":"Current-engine headless physics and collision checks; water is an authored-depth fixture and GPU visuals are separate."}
	FileAccess.open("res://output/art-pass/route-contracts/movement-"+version+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ROUTE_MOVEMENT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"version":version,"cases":reports.size(),"simulated_seconds":frames*DT}))
	player.free();sampler.free();room.free();builder=null
	await process_frame;quit(0 if errors.is_empty() else 1)
