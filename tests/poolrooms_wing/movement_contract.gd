extends SceneTree
## Production PoolWorld -> RoomBuilder -> exported BOX collisions and PoolPlayer.
## Only water sampling is a controlled authored-depth fixture, not SWE/MPM.
const Player = preload("res://scripts/player/pool_player.gd")
const World = preload("res://scripts/world/pool_world.gd")
const Wing = preload("res://scripts/poolrooms_wing/poolrooms_catalog.gd")
const DT := 1.0/120.0
const SIDES: Array[Vector2i] = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
var world: Node3D
var player: CharacterBody3D
var sampler: Node3D
var reports: Array=[]
var errors: Array=[]
var frames:=0
var trace: Array=[]
var geometry: Dictionary
var tall_capsule: CapsuleShape3D

class AuthoredDepthSampler extends Node3D:
	var world: Node3D
	func _layout(p: Vector3) -> Dictionary:
		var coord: Vector2i=world.get_room_coord(p)
		return world.get_layout(coord) if world.resident_rooms.has(coord) else {}
	func _local(p: Vector3) -> Vector3:
		var coord: Vector2i=world.get_room_coord(p)
		return p-Vector3(coord.x*32,0,coord.y*32)
	func is_water_at(p: Vector3) -> bool:
		var layout:=_layout(p)
		p=_local(p)
		for rectangle: Rect2 in layout.get("water_rects",[]):
			if rectangle.has_point(Vector2(p.x,p.z)):
				for box: AABB in layout.get("water_exclusions",[]):
					if p.x>=box.position.x and p.x<=box.end.x and p.z>=box.position.z and p.z<=box.end.z:return false
				return true
		return false
	func surface_height_at(_p: Vector3) -> float:return .32
	func depth_at(p: Vector3) -> float:
		if not is_water_at(p):return 0.0
		var layout:=_layout(p)
		p=_local(p)
		var floor_y:float=layout.get("water_floor_y",-.72)
		for box: AABB in layout.get("water_steps",[]):
			if p.x>=box.position.x and p.x<=box.end.x and p.z>=box.position.z and p.z<=box.end.z:floor_y=maxf(floor_y,box.end.y)
		return maxf(0.0,.32-floor_y)
	func wave_impact(_p:Vector3,_power:float)->void:pass
	func wake_dipole(_p:Vector3,_direction:Vector2,_speed:float,_sigma:float)->void:pass
	func push(_p:Vector3,_direction:Vector2,_sigma:float)->void:pass
	func player_impact(_p:Vector3,_power:float)->void:pass
	func current_velocity_at(_p:Vector3)->Vector2:return Vector2.ZERO
	func slope_at(_p:Vector3,_radius:float)->Vector4:return Vector4.ZERO

func _initialize() -> void:
	Engine.physics_ticks_per_second=120
	_run.call_deferred()

func v(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func vec(p: Vector3) -> Array:return [snappedf(p.x,.00001),snappedf(p.y,.00001),snappedf(p.z,.00001)]
func origin(coord: Vector2i) -> Vector3:return Vector3(coord.x*32,0,coord.y*32)
func point(coord: Vector2i,x:float,y:float,z:float) -> Vector3:return origin(coord)+Vector3(x,y,z)

func add(label:String,passed:bool,data:Dictionary={}) -> void:
	data.merge({"name":label,"pass":passed})
	reports.append(data)
	if not passed: errors.append(label)
	print("POOLROOMS_MOVEMENT_CASE ",label," ",passed)

func tick(count:int=1) -> void:
	for i:int in count:
		await physics_frame
		player._physics_process(DT)
		frames+=1
		if frames%60==0:
			var state:Dictionary=player.get_action_state()
			trace.append({"frame":frames,"position":vec(player.position),"grounded":player.is_on_floor(),"mode":state.mode,"jump_phase":state.jump_phase})

func warp(p:Vector3) -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")
	player.warp_to(p,p+Vector3(0,1.6,-1))
	player.enabled=true
	await tick(30)

func tall_clear(p:Vector3) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=tall_capsule
	query.transform=Transform3D(Basis.IDENTITY,p+Vector3(0,1.015,0))
	query.collision_mask=1
	return world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func travel(target:Vector3,seconds:float=25.0,check_tall:bool=false) -> Dictionary:
	var start:=player.position
	var start_frame:=frames
	var minimum_y:=player.position.y
	var maximum_y:=player.position.y
	var swimming_ticks:=0
	var wet_ticks:=0
	var wall_ticks:=0
	var ceiling_ticks:=0
	var blocked_tall_samples:=0
	var previous:=player.position
	var stalls:=0
	var reached:=false
	Input.action_press("move_forward")
	for i:int in ceili(seconds*120):
		var difference:Vector3=target-player.position
		difference.y=0
		if difference.length()<.085:reached=true;break
		player.rotation.y=atan2(-difference.x,-difference.z)
		await tick()
		minimum_y=minf(minimum_y,player.position.y)
		maximum_y=maxf(maximum_y,player.position.y)
		var state:Dictionary=player.get_action_state()
		if state.swimming:swimming_ticks+=1
		if state.in_water:wet_ticks+=1
		if player.is_on_wall():wall_ticks+=1
		if player.is_on_ceiling():ceiling_ticks+=1
		if check_tall and i%15==0 and not tall_clear(player.position):blocked_tall_samples+=1
		if i>60 and player.position.distance_to(previous)<.00001:stalls+=1
		previous=player.position
		if stalls>240:break
	Input.action_release("move_forward")
	return {"reached":reached,"start":vec(start),"target":vec(target),"end":vec(player.position),"seconds":float(frames-start_frame)*DT,"min_y":minimum_y,"max_y":maximum_y,"height_error":absf(player.position.y-target.y),"swimming_ticks":swimming_ticks,"wet_ticks":wet_ticks,"wall_ticks":wall_ticks,"ceiling_ticks":ceiling_ticks,"blocked_2m_capsule_samples":blocked_tall_samples,"stalled_ticks":stalls}

func dry_ok(result:Dictionary) -> bool:
	return result.reached and result.height_error<.04 and result.min_y>.49 and result.swimming_ticks==0 and result.wet_ticks==0 and result.ceiling_ticks==0 and result.blocked_2m_capsule_samples==0

func stairs_ok(result:Dictionary) -> bool:
	return result.reached and result.height_error<.04 and result.min_y>-.76 and result.swimming_ticks==0 and result.ceiling_ticks==0

func stop(label:String,expected_y:float,wet:bool) -> void:
	Input.action_release("move_forward")
	await tick(60)
	var start:=player.position
	await tick(120)
	var state:Dictionary=player.get_action_state()
	add(label,player.is_on_floor() and player.position.distance_to(start)<.01 and absf(player.position.y-expected_y)<.04 and not state.swimming and bool(state.in_water)==wet,{"position":vec(player.position),"drift":player.position.distance_to(start),"state":state.mode,"water_fixture_depth":sampler.depth_at(player.position)})

func room_routes(coord:Vector2i) -> void:
	var index:int=Wing.ANCHORS[coord]
	var label:String=Wing.FILES[index]
	var contract:Dictionary=geometry.rooms[label]
	trace=[]
	var spawn:Vector3=world.get_spawn_position(coord)
	await warp(spawn)
	add(label+"_spawn_collision_ready",world.is_room_ready(coord) and spawn.is_equal_approx(origin(coord)+v(contract.spawn_local)) and absf(player.position.y-.52)<.04 and player.is_on_floor() and tall_clear(player.position),{"spawn":vec(spawn),"settled":vec(player.position)})
	await stop(label+"_dry_stop",.52,false)
	var segments:Array=[]
	var ring:Array=contract.dry_route_ring
	await warp(origin(coord)+v(ring[0])+Vector3(0,.02,0))
	var ring_ok:=true
	for i:int in range(1,ring.size()+1):
		var segment:Dictionary=await travel(origin(coord)+v(ring[i%ring.size()]),30.0,true)
		segments.append(segment)
		ring_ok=ring_ok and dry_ok(segment)
		if not segment.reached:break # Preserve the first obstruction; avoid cascading diagonals.
	add(label+"_complete_dry_perimeter",ring_ok,{"segments":segments,"trace":trace})
	for side:int in 4:
		trace=[]
		var direction:=Vector3(SIDES[side].x,0,SIDES[side].y)
		# At 15.75 m the .32 m-radius capsule can still be supported by the
		# final tread ending at 15.5 m. 15.9 m is on the actual bottom landing,
		# even allowing the fixed .085 m arrival tolerance; no tolerance changes.
		await warp(origin(coord)+direction*15.9+Vector3(0,-.70,0))
		var up:Dictionary=await travel(origin(coord)+direction*10.6+Vector3(0,.52,0))
		var down:Dictionary=await travel(origin(coord)+direction*15.9+Vector3(0,-.72,0))
		await tick(45)
		down["settled_height_error"]=absf(player.position.y+.72)
		add(label+"_outer_portal_stairs_"+str(side),stairs_ok(up) and stairs_ok(down) and down.settled_height_error<.04,{"segments":[up,down],"trace":trace})
		# Link each inner portal to the proved perimeter, rather than treating
		# four isolated portal tests and an unrelated ring as connectivity proof.
		var ring_distance:float=9.0 if side==1 else 10.0
		if side==0:ring_distance=10.0 if index==1 else 9.5
		if side==2:ring_distance=8.0 if index==0 else (10.0 if index==1 else 9.5)
		if side==3:ring_distance=9.0 if index==1 else 10.0
		await warp(origin(coord)+direction*10.6+Vector3(0,.54,0))
		var link:Dictionary=await travel(origin(coord)+direction*ring_distance+Vector3(0,.52,0),10.0,true)
		add(label+"_portal_to_dry_perimeter_"+str(side),dry_ok(link),{"segment":link})
	# Each authored basin access has four .148 m risers and .5 m treads.
	var accesses:Array=[]
	match index:
		0:accesses=[[Vector3(2.4,.52,4.0),Vector3(2.4,-.22,0.0)]]
		1:accesses=[[Vector3(-4,.52,-10),Vector3(-4,-.22,-6.0)],[Vector3(4,.52,-10),Vector3(4,-.22,-6.0)]]
		2:accesses=[[Vector3(-1.5,.52,7.0),Vector3(-1.5,-.22,3.0)]]
	for access_index:int in accesses.size():
		trace=[]
		var access:Array=accesses[access_index]
		await warp(origin(coord)+access[0]+Vector3(0,.02,0))
		var down:Dictionary=await travel(origin(coord)+access[1])
		await stop(label+"_basin_wet_stop_"+str(access_index),-.22,true)
		var up:Dictionary=await travel(origin(coord)+access[0])
		add(label+"_basin_stairs_"+str(access_index),stairs_ok(down) and stairs_ok(up) and down.min_y>-.26 and up.min_y>-.26 and down.wet_ticks>0 and up.wet_ticks>0,{"segments":[down,up],"trace":trace})
		await stop(label+"_basin_exit_dry_stop_"+str(access_index),.52,false)

func gateway_routes() -> void:
	var coord:=Vector2i.RIGHT
	for offset:float in [0.0,-.9,.9]:
		trace=[]
		await warp(point(coord,.8,.54,offset))
		var east:Dictionary=await travel(point(coord,3.7,.52,offset),10,true)
		var west:Dictionary=await travel(point(coord,.8,.52,offset),10,true)
		add("circular_gateway_clearance_offset_"+str(offset),dry_ok(east) and dry_ok(west),{"segments":[east,west],"capsule_width":.64,"additional_headroom_capsule_height":2.0,"trace":trace})
	# Outside the circular opening a real proxy must stop the production capsule.
	await warp(point(coord,.8,.54,2.8))
	var blocked:Dictionary=await travel(point(coord,3.7,.52,2.8),4.0)
	add("circular_gateway_solid_band_blocks_walk",not blocked.reached and blocked.wall_ticks>0 and player.position.x<32+1.9-.30,{"segment":blocked})

func threshold_routes() -> void:
	for side:Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.LEFT]:
		trace=[]
		var direction:=Vector3(side.x,0,side.y)
		var start:=direction*10.6+Vector3(0,.52,0)
		var end:=direction*21.4+Vector3(0,.52,0)
		await warp(start+Vector3(0,.02,0))
		var outward:Dictionary=await travel(end)
		var arrived:Vector2i=world.get_room_coord(player.position)
		var inward:Dictionary=await travel(start)
		add("between_rooms_threshold_"+str(side),stairs_ok(outward) and stairs_ok(inward) and arrived==side and world.get_room_coord(player.position)==Vector2i.ZERO and outward.wet_ticks>0 and inward.wet_ticks>0,{"segments":[outward,inward],"arrival_coord":str(arrived),"destination_mode":"poolrooms" if Wing.ANCHORS.has(side) else "expanded fallback","trace":trace})

func _run() -> void:
	geometry=JSON.parse_string(FileAccess.get_file_as_string("res://source_provenance/poolrooms_wing/geometry.json"))
	for action:String in ["move_left","move_right","move_forward","move_back","sprint","jump","throw_prop","grab_prop","interact","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		Input.action_release(action)
	world=World.new()
	world.poolrooms_mode=true
	world.expanded_mode=true
	world.stream_radius=0
	root.add_child(world)
	world.initialize(250821,null)
	world.set_process(false)
	for coord:Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.LEFT]:world.ensure_room_ready(coord)
	for coord:Vector2i in Wing.ANCHORS:
		var name:String=Wing.FILES[Wing.ANCHORS[coord]]
		var room:Node3D=world.resident_rooms[coord]
		var stats:Dictionary=room.get_meta("expanded_geometry_stats",{})
		add(name+"_production_proxy_count",stats.get("proxies",-1)==geometry.rooms[name].proxy_count,{"actual":stats.get("proxies",-1),"expected":geometry.rooms[name].proxy_count})
	sampler=AuthoredDepthSampler.new()
	sampler.world=world
	root.add_child(sampler)
	player=Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_water(sampler)
	player.enabled=true
	player.water_motion_actions_enabled=true
	player.depth_wading_response_enabled=true
	tall_capsule=CapsuleShape3D.new()
	tall_capsule.radius=.32
	tall_capsule.height=2.0
	var shape:CapsuleShape3D=player.get_node("PlayerCapsule").shape
	add("unmodified_production_capsule_dimensions",is_equal_approx(shape.radius,.32) and is_equal_approx(shape.height,1.64),{"width":shape.radius*2,"height":shape.height,"extra_clearance_probe_height":2.0})
	for coord:Vector2i in Wing.ANCHORS:await room_routes(coord)
	await gateway_routes()
	await threshold_routes()
	var source_hashes:Dictionary={}
	for name:String in Wing.FILES:source_hashes[name+".glb"]=FileAccess.get_sha256("res://assets/models/poolrooms_wing/"+name+".glb")
	for path:String in ["scripts/player/pool_player.gd","scripts/world/room_builder.gd","scripts/world/pool_world.gd","scripts/poolrooms_wing/poolrooms_catalog.gd","scripts/poolrooms_wing/geometry_contract.gd","source_provenance/poolrooms_wing/geometry.json"]:source_hashes[path]=FileAccess.get_sha256("res://"+path)
	var report:Dictionary={"pass":errors.is_empty(),"errors":errors,"engine":Engine.get_version_info(),"physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine"),"physics_hz":120,"simulated_seconds":frames*DT,"source_sha256":source_hashes,"checks":reports,"controller":"Unmodified production PoolPlayer with production depth wading option enabled","collision":"Production PoolWorld and RoomBuilder loading final authored GLB BOX proxies","thresholds":{"horizontal_arrival_metres":.085,"height_error_metres":.04,"dry_minimum_feet_y":.49,"basin_minimum_feet_y":-.26,"threshold_minimum_feet_y":-.76,"settled_drift_metres":.01,"swimming_ticks_allowed":0},"water_scope":"Controlled authored rectangles, exclusions and stair AABBs only. NOT source SWE/MPM, optical water, waves, currents, GPU, Android or performance acceptance."}
	FileAccess.open("res://output/poolrooms_wing/contracts/movement-contract.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("POOLROOMS_MOVEMENT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"cases":reports.size(),"simulated_seconds":frames*DT}))
	player.free()
	sampler.free()
	world.free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
