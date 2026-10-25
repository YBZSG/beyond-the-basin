extends SceneTree
const World=preload("res://scripts/reference_wing/reference_world.gd")
const Catalog=preload("res://scripts/reference_wing/reference_catalog.gd")
const Player=preload("res://scripts/reference_wing/reference_player.gd")
const Depth=preload("res://scripts/reference_wing/reference_depth_field.gd")
class StaticWater extends Node:
	var profiles:Array=[]
	var events:=0
	func depth_at(p:Vector3)->float:
		for profile:Dictionary in profiles:
			var point:=Vector2(p.x,p.z)-Vector2(profile.offset)
			if profile.bounds.grow(.001).has_point(point):return Depth.point_depth(point,profile)
		return 0.0
	func is_water_at(p:Vector3)->bool:return depth_at(p)>0
	func surface_height_at(_p:Vector3)->float:return .32
	func player_impact(_p:Vector3,_power:float)->void:events+=1
	func splash(_p:Vector3,_power:float,_direction:Dictionary={})->void:events+=1
	func wave_impact(_p:Vector3,_power:float)->void:events+=1
	func push(_p:Vector3,_impulse:Vector2,_radius:float)->void:events+=1
	func wake_dipole(_p:Vector3,_direction:Vector2,_speed:float,_radius:float)->void:events+=1
	func crest(_p:Vector3,_power:float)->void:events+=1
var host:Node3D
var world:Node3D
var player:CharacterBody3D
var water:StaticWater
var legs:Array=[]
var trace:Array=[]
var travelled:=0.0
var lowest:=100.0
var max_floor_gap:=0.0
func _initialize()->void:call_deferred("run")
func run()->void:
	if DirAccess.make_dir_recursive_absolute("res://output/reference_wing/integration") != OK:
		push_error("Cannot create reference test evidence directory")
		quit(2);return
	for id:String in Catalog.IDS:
		if not load(Catalog.ROOT+id+".glb") is PackedScene:
			push_error("Reference test aborted: missing or stale imported room "+id)
			quit(2);return
	for action in ["move_forward","move_back","move_left","move_right","sprint","jump","crouch","interact","throw","drop"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	host=Node3D.new();root.add_child(host)
	world=World.new();host.add_child(world);world.expanded_mode=true
	world.initialize(250821,null);world.complete_pending_streaming()
	water=StaticWater.new();host.add_child(water)
	water.profiles=Depth.profiles(world._layouts)
	player=load("res://tests/reference_wing/diagnostic_player.gd").new() if "--probe-step" in OS.get_cmdline_user_args() else Player.new();host.add_child(player);player.set_water(water);player.depth_wading_response_enabled=true
	player.warp_to(world.get_spawn_position(),Vector3(1.4,1,-4));player.set_enabled(true)
	await physics_frame;await physics_frame
	# One continuous five-room circuit and return to the upper entrance. No mid-route warp.
	var path:Array=[Vector2(1.4,0.2),Vector2(1.4,-4.5),Vector2(0,-16),Vector2(0,-30.8),Vector2(0,-46),Vector2(0,-50),Vector2(0,-73.8),Vector2(4.5,-73.8),Vector2(4.5,-72.8),Vector2(5.4,-72.8),Vector2(5.4,-64),Vector2(21.5,-64),Vector2(21.5,-72),Vector2(22.3,-72),Vector2(22.3,-73),Vector2(30.55,-73),Vector2(30.55,-70),Vector2(30.55,-69),Vector2(32,-68.8),Vector2(32,-64),Vector2(32,-68.8),Vector2(33.45,-69),Vector2(33.45,-70),Vector2(33.45,-73),Vector2(41.8,-73),Vector2(41.8,-72.2),Vector2(42.5,-72.2),Vector2(42.5,-52.8),Vector2(41.8,-52.8),Vector2(41.8,-52),Vector2(32,-52),Vector2(32,-48),Vector2(32,-42.5),Vector2(26.5,-42.5),Vector2(26.5,-41.5),Vector2(25.5,-41.5),Vector2(25.5,-25.7),Vector2(30.35,-25.7),Vector2(25.5,-25.7),Vector2(25.5,-32),Vector2(16,-32),Vector2(4,-32),Vector2(3.5,-30.7),Vector2(0,-30.7),Vector2(0,-16),Vector2(1.4,-4.5),Vector2(1.4,0.2),Vector2(1.4,10.8)]
	var failure:=false
	for target:Vector2 in path:
		var start:Vector3=player.global_position
		var max_ticks:=ceili(Vector2(start.x,start.z).distance_to(target)/.6*Engine.physics_ticks_per_second)+180
		var ticks:=0
		Input.action_press("move_forward")
		while Vector2(player.position.x,player.position.z).distance_to(target)>.16 and ticks<max_ticks:
			var direction:=target-Vector2(player.position.x,player.position.z)
			player.rotation.y=atan2(-direction.x,-direction.y)
			var before:Vector3=player.position
			await physics_frame
			travelled+=player.position.distance_to(before);lowest=minf(lowest,player.position.y)
			world.update_player_position(player.position)
			if ticks%30==0:trace.append({"leg":legs.size(),"tick":ticks,"p":[player.position.x,player.position.y,player.position.z],"water":water.depth_at(player.position),"floor":player.is_on_floor()})
			ticks+=1
		Input.action_release("move_forward")
		var reached:=Vector2(player.position.x,player.position.z).distance_to(target)<=.16
		var result:={"target":[target.x,target.y],"reached":reached,"ticks":ticks,"position":[player.position.x,player.position.y,player.position.z]}
		legs.append(result);print("REFERENCE_WALK_LEG ",JSON.stringify(result))
		if not reached:
			failure=true
			if "--probe-step" in OS.get_cmdline_user_args():
				var probe_file:=FileAccess.open("res://output/reference_wing/integration/walk-step-probe.json",FileAccess.WRITE)
				probe_file.store_string(JSON.stringify({"branches":player.branches,"samples":player.samples},"\t"));probe_file.close()
			break
	for tick in 30:await physics_frame
	var report:={"scope":"Actual existing PoolPlayer, Godot4.6.3 headless fixed60 process /120Hz physics, exact static water-depth stub only; no fluid/RT visual/FPS proof", "passed":not failure,"physics_hz":Engine.physics_ticks_per_second,"legs":legs,"distance_m":travelled,"lowest_feet_y":lowest,"water_events":water.events,"visited":world.get_discovered_count(),"trace":trace}
	var file:=FileAccess.open("res://output/reference_wing/integration/walkthrough.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("REFERENCE_WALK_DONE ",not failure," distance_m=",travelled," visited=",world.get_discovered_count()," events=",water.events)
	host.queue_free();await process_frame;quit(1 if failure else 0)
