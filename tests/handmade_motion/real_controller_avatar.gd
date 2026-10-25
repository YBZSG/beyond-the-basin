extends SceneTree
const Player=preload("res://scripts/player/pool_player.gd")
const Avatar=preload("res://scripts/art_pass/character/handmade_pool_avatar.gd")
const Prop=preload("res://scripts/player/pool_prop_body.gd")
var p:CharacterBody3D
var a:Node3D
var checks:Dictionary={}
class WaterStub extends Node3D:
	func is_water_at(_p:Vector3)->bool:return false
	func surface_height_at(_p:Vector3)->float:return -2.0
	func depth_at(_p:Vector3)->float:return 0.0
	func add_drop(_p:Vector3,_r:float,_s:float)->void:pass
func _initialize()->void:call_deferred("run")
func step(n:int)->void:
	for i in n:
		await physics_frame
		p._physics_process(1.0/60.0);a._process(1.0/60.0)
func run()->void:
	for key in ["move_left","move_right","move_forward","move_back","sprint","jump","throw_prop","grab_prop","interact","pause"]:
		if not InputMap.has_action(key):InputMap.add_action(key)
	var arena=Node3D.new();root.add_child(arena)
	var floor=StaticBody3D.new();var c=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(10,.2,10);c.shape=box;floor.add_child(c);floor.position.y=-.1;arena.add_child(floor)
	var w=WaterStub.new();arena.add_child(w)
	p=Player.new();arena.add_child(p);p.set_physics_process(false);p.set_process(false);p.set_water(w);p.warp_to(Vector3(0,.02,0),Vector3(0,1.6,-1))
	a=Avatar.new();a.model_path="res://assets/character_refinement/natural_hand_finish/explorer_natural_hand.glb";a.hand_contract_path="res://assets/character_refinement/natural_hand_finish/model_contract.json";a.setup(p);a.set_process(false)
	p.set_enabled(true)
	await step(20)
	var prop=Prop.new();prop.configure("duck",{"radius":.12,"mass":.30},w);arena.add_child(prop);prop.global_position=p.get_hold_anchor()
	p.grab_prop(prop);await step(12)
	checks.actual_pickup_gesture=a.get_debug_state().handmade_actions.pickup_weight>.5
	checks.actual_hand_ik=a.get_debug_state().hand_ik.valid
	p.release_prop(11.0)
	checks.same_tick_physics_release=p.held==null and not prop.held and prop.linear_velocity.length()>10
	await step(1)
	checks.throw_not_setdown=a.get_debug_state().handmade_actions.setdown_weight==0
	p.grab_prop(prop);await step(6);p.release_prop();await step(10)
	checks.actual_drop_gesture=a.get_debug_state().handmade_actions.setdown_weight>.8
	p.set_enabled(false);a._process(1.0/60.0)
	checks.real_pause_cancels_gesture=a.get_debug_state().handmade_actions.setdown_weight==0
	p.set_enabled(true);await step(1)
	checks.resume_does_not_replay=a.get_debug_state().handmade_actions.setdown_weight==0
	var passed=true
	for v in checks.values():passed=passed and bool(v)
	arena.queue_free();await process_frame
	print("HANDMADE_REAL_CONTROLLER ",JSON.stringify({"pass":passed,"checks":checks,"scope":"Actual controller+avatar+rigid prop, CPU physics; no GPU water/render validation."}));quit(0 if passed else 1)
