extends SceneTree
const Avatar=preload("res://scripts/art_pass/character/handmade_pool_avatar.gd")
const Player=preload("res://tests/handmade_motion/fixture_player.gd")
const Library=preload("res://assets/character_refinement/handmade_motion/handmade_actions.tres")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var p=Player.new();root.add_child(p)
	var cam=Camera3D.new();cam.name="ViewCamera";p.add_child(cam);cam.position.y=1.6
	var a=Avatar.new();a.model_path="res://assets/character_refinement/natural_hand_finish/explorer_natural_hand.glb";a.hand_contract_path="res://assets/character_refinement/natural_hand_finish/model_contract.json";a.setup(p);a.set_process(false)
	check(a.get_debug_state().loaded,"loaded natural model")
	check(a.get_debug_state().handmade_actions.installed,"new graph installed")
	check(a._skeleton.get_bone_count()==54,"54 bones")
	for name in ["Wade","Swim","SwimIdle","JumpRise","JumpAir","Land","ThrowCharge","ThrowRelease","ThrowRecover"]:check(a._clips.has(name),"preserved "+name)
	for name in Library.get_animation_list():
		var an=Library.get_animation(name);check(an.get_track_count()==42,"42 imported upper tracks "+name)
		for t in an.get_track_count():
			var path=an.track_get_path(t);var bone=str(path.get_subname(0))
			check(a._skeleton.find_bone(bone)>=0,"track target "+bone)
			check(an.track_get_type(t)==Animation.TYPE_ROTATION_3D,"rotations only")
			check(bone not in ["Root","Hips"] and not bone.contains("Leg") and not bone.contains("Foot") and not bone.contains("Toe"),"no lower body")
	p.tick(1.0/60.0);a._process(1.0/60.0)
	var prop=RigidBody3D.new();prop.set_script(load("res://tests/handmade_motion/fixture_prop.gd"));root.add_child(prop);prop.freeze=true;prop.position=Vector3(0,1.3,-.38)
	p.held=prop
	for i in 12:p.tick(1.0/60.0);a._process(1.0/60.0)
	var state=a.get_debug_state()
	check(state.handmade_actions.pickup_weight>.5,"pickup evaluated in graph")
	check(state.hand_ik.valid,"final contact IK retained")
	check(state.finger_pose.valid,"natural fingers retained")
	check(state.finger_pose.state=="Pickup","authored pickup fingers survive dry-idle policy")
	check(prop.position==Vector3(0,1.3,-.38),"avatar did not move object")
	p.held=null;p.snapshot.release_kind="drop";p.snapshot.throw_release_serial=1;p.snapshot.throw_release_age=0.0
	for i in 9:p.tick(1.0/60.0);a._process(1.0/60.0)
	check(a.get_debug_state().handmade_actions.setdown_weight>.9,"drop evaluated")
	p._in_water=true
	for i in 90:p.tick(1.0/60.0);a._process(1.0/60.0)
	check(float(a._tree.get("parameters/HandmadeWadeRestBlend/blend_amount"))>.99,"water rest graph")
	for i in a._skeleton.get_bone_count():check(a._skeleton.get_bone_pose_rotation(i).is_finite(),"finite pose "+str(i))
	var before=a._gait_phase
	for i in 60:p.tick(1.0/60.0,Vector3(0,0,-1.05/60.0));a._process(1.0/60.0)
	check(absf(fposmod(a._gait_phase-before+.5,1.0)-.5)<.001,"existing distance-driven wade one stride")
	p._swimming=true;p.snapshot.move_input=Vector2(0,-1);p.snapshot.move_speed=1.0
	for i in 60:p.snapshot.stroke_phase=float(i)/60.0;p.tick(1.0/60.0);a._process(1.0/60.0)
	check(a.get_debug_state().handmade_actions.pickup_weight==0,"no pickup over swim")
	check(a.get_debug_state().swim_blend>.99,"existing swim active")
	prop.queue_free();p.queue_free()
	await process_frame
	print("HANDMADE_RIG_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
