extends SceneTree
## Real physics LOS regression: nearby unrelated walls must not count as station hits.
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
class TestPlayer extends CharacterBody3D:
	var camera:Node3D
	func _ready()->void:
		camera=Node3D.new();add_child(camera)
class TestMain extends Node3D:
	var player:TestPlayer
var failures:Array[String]=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func box(parent:Node3D,position:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=1;body.position=position
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape
	body.add_child(collision);parent.add_child(body);return body
func _initialize()->void:call_deferred("run")
func run()->void:
	var main:=TestMain.new();root.add_child(main)
	main.player=TestPlayer.new();main.add_child(main.player)
	main.player.position=Vector3(0,0,2);main.player.camera.position=Vector3(0,1.24,0)
	var runtime:=Runtime.new();runtime.main=main;main.add_child(runtime);runtime.set_process(false);runtime.set_process_input(false)
	var station:=Node3D.new();station.set_meta("label","test station");main.add_child(station)
	runtime._collectibles["test_key"]=station
	await physics_frame;await physics_frame
	check(runtime._target().get("id")=="test_key","clear sight accepted")
	var own_body:=box(station,Vector3(0,1.24,.06),Vector3(.2,.2,.08))
	await physics_frame;await physics_frame
	check(runtime._target().get("id")=="test_key","station descendant collider accepted")
	var wall:=box(main,Vector3(0,1.24,.2),Vector3(1,1,.02))
	await physics_frame;await physics_frame
	check(runtime._target().is_empty(),"2cm unrelated wall within old .45m exemption blocks target")
	wall.queue_free();await physics_frame;await physics_frame
	check(runtime._target().get("id")=="test_key","removing occluder restores target")
	main.queue_free();await process_frame;await process_frame
	print("CAMPAIGN_TARGET_OCCLUSION_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
