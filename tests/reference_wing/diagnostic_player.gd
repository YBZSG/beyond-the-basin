extends "res://scripts/player/pool_player.gd"
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
	if global_position.z < -64 and global_position.x>.65 and global_position.x<.8:
		samples.append(detail)
		if samples.size()>40:samples.pop_front()
	return super._try_step(delta,grounded)
