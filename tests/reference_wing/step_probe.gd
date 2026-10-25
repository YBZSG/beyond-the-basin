extends SceneTree
const World=preload("res://scripts/reference_wing/reference_world.gd")
const Catalog=preload("res://scripts/reference_wing/reference_catalog.gd")
const Walk=preload("res://tests/reference_wing/walkthrough.gd")
const Player=preload("res://scripts/player/pool_player.gd")
const Depth=preload("res://scripts/reference_wing/reference_depth_field.gd")
class ProbePlayer extends Player:
	var branches:Dictionary={}
	var samples:Array=[]
	func _try_step(delta:float,grounded:bool)->bool:
		var detail:={"p":str(global_position),"v":str(velocity),"grounded":grounded}
		var branch:="other"
		var travel:=Vector3(velocity.x,0,velocity.z)*delta
		if not grounded or velocity.y>.1:branch="not_grounded_or_rising"
		elif travel.length_squared()<.0000001:branch="no_travel"
		else:
			var wall:=KinematicCollision3D.new()
			if not test_move(global_transform,travel,wall):branch="no_wall"
			elif wall.get_normal().y>.5:branch="wall_normal_y";detail.normal=str(wall.get_normal())
			else:
				var probe:=global_position+travel.normalized()*(BODY_RADIUS+travel.length()+.03)
				var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe+Vector3.UP*(STEP_HEIGHT+.02),probe+Vector3.DOWN*.02,1,[get_rid()]))
				if hit.is_empty():branch="landing_empty"
				elif hit.normal.y<cos(floor_max_angle):branch="landing_normal"
				else:
					var elevation:float=hit.position.y-global_position.y+safe_margin;detail.elevation=elevation;detail.landing=str(hit.position)
					if elevation<.005 or elevation>STEP_HEIGHT+.005:branch="elevation"
					else:
						var raised:=global_transform;var collision:=KinematicCollision3D.new()
						if test_move(raised,Vector3.UP*elevation,collision):branch="up_blocked";detail.normal=str(collision.get_normal());detail.hit=str(collision.get_position())
						else:
							raised.origin.y+=elevation
							if test_move(raised,travel,collision):branch="raised_forward_blocked";detail.normal=str(collision.get_normal());detail.hit=str(collision.get_position())
							else:branch="accepted"
		branches[branch]=int(branches.get(branch,0))+1
		detail.branch=branch
		if samples.size()<20 or samples.size()%31==0:samples.append(detail)
		elif global_position.x>.65 and global_position.x<.8:
			if samples.size()<65:samples.append(detail)
		return super._try_step(delta,grounded)
func _initialize()->void:call_deferred("run")
func run()->void:
	if DirAccess.make_dir_recursive_absolute("res://output/reference_wing/integration") != OK:
		push_error("Cannot create reference test evidence directory")
		quit(2);return
	for id:String in Catalog.IDS:
		if not load(Catalog.ROOT+id+".glb") is PackedScene:
			push_error("Reference test aborted: missing or stale imported room "+id)
			quit(2);return
	for a in ["move_forward","move_back","move_left","move_right","sprint","jump","crouch","interact","throw","drop"]:
		if not InputMap.has_action(a):InputMap.add_action(a)
	var host:=Node3D.new();root.add_child(host)
	var world:=World.new();host.add_child(world);world.expanded_mode=true;world.initialize(250821,null);world.complete_pending_streaming()
	var water:=Walk.StaticWater.new();host.add_child(water);water.profiles=Depth.profiles(world._layouts)
	var player:CharacterBody3D=load("res://tests/reference_wing/diagnostic_player.gd").new();host.add_child(player);player.set_water(water);player.depth_wading_response_enabled=true
	player.warp_to(Vector3(.7061953,.1512297,-73.7639),Vector3(5.4,1.7,-73.8));player.set_enabled(true)
	Input.action_press("move_forward")
	for i in 900:await physics_frame
	Input.action_release("move_forward")
	var result:={"p":str(player.position),"branches":player.branches,"samples":player.samples}
	var f:=FileAccess.open("res://output/reference_wing/integration/step-probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	print("STEP_PROBE ",JSON.stringify({"p":result.p,"branches":result.branches}))
	host.queue_free();await process_frame;quit()
