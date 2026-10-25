extends SceneTree
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const World=preload("res://scripts/campaign/campaign_world.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Materials=preload("res://scripts/rendering/pool_materials.gd")
class TestPlayer extends CharacterBody3D:
	var camera:Node3D
	func _ready()->void:
		camera=Node3D.new();add_child(camera)
class TestMain extends Node3D:
	var world:Node3D
	var player:TestPlayer
	var _booted:=true
	var _switching_spawn:=false
	var menu_open:=false
	var hud_hidden:=false
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not InputMap.has_action("interact"):InputMap.add_action("interact")
	var mapping:=InputEventKey.new();mapping.physical_keycode=KEY_E;InputMap.action_add_event("interact",mapping)
	for index in range(Catalog.CHAPTER_COUNT):
		var data:Dictionary=Catalog.chapter(index)
		var main:=TestMain.new();root.add_child(main)
		main.player=TestPlayer.new();main.add_child(main.player)
		var runtime:=Runtime.new();runtime.main=main;runtime.active=true;runtime.state=State.new();runtime.writable=false
		for previous in range(index):
			for item:Dictionary in Catalog.chapter(previous).items:runtime.state.collect(item.id)
			runtime.state.begin_transition();runtime.state.finish_transition()
		main.add_child(runtime);runtime.set_process(false)
		main.world=World.new();main.world.chapter_index=index;main.world.formal_mode=data.mode=="formal";main.world.expanded_mode=data.mode in ["expanded","poolrooms","reference"];main.world.poolrooms_mode=data.mode=="poolrooms"
		main.add_child(main.world);main.world.room_loaded.connect(runtime.room_loaded)
		main.world.initialize(250821,Materials.new());main.world.complete_pending_streaming()
		await runtime._place_pending()
		await physics_frame;await physics_frame
		check(runtime._collectibles.size()==data.items.size(),"all actual mounts "+str(index))
		check(is_instance_valid(runtime._gate),"gate mounted "+str(index))
		for item:Dictionary in data.items:
			if not runtime._collectibles.has(item.id):continue
			var station:Node3D=runtime._collectibles[item.id]
			var point:Vector3=station.global_position+Vector3.UP*1.24
			check(point.y>.32,"key above water "+str(item.id))
			main.player.global_position=station.global_position+Vector3(.85,0,0)
			main.player.camera.position=Vector3(0,1.65,0);main.player.camera.look_at(point)
			var target:Dictionary=runtime._target()
			check(target.get("id")==item.id,"line of sight target "+str(item.id))
			var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=true
			runtime._input(event)
			check(runtime.state.inventory.has(item.id),"E collects real target "+str(item.id))
			check(not runtime._collectibles.has(item.id),"collected display removed")
		check(runtime.state.can_depart(),"chapter gate unlocked "+str(index))
		main.queue_free();await process_frame;await process_frame
	print("CAMPAIGN_RUNTIME_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
