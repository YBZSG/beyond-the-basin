extends SceneTree
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
class MockCamera extends Node3D:
	var current:=true
class MockPlayer extends CharacterBody3D:
	var camera:MockCamera
	var enabled:=false
	func _ready()->void:camera=MockCamera.new();add_child(camera)
	func release_prop()->void:pass
class MockWater extends Node:
	var terrain_ready:=true
	func is_terrain_ready()->bool:return terrain_ready
class MockWorld extends Node3D:
	func _ready()->void:
		var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(10,.2,10);collision.shape=box;collision.position.y=-.1;body.add_child(collision);add_child(body)
	var finite_coords:Array[Vector2i]=[Vector2i.ZERO]
	func current_room_ready()->bool:return true
class MockMain extends Node3D:
	var player:MockPlayer
	var water:MockWater
	var world:MockWorld
	var _booted:=true
	var _switching_spawn:=false
	var _spawn_mode:="original"
	var menu_open:=true
	var _menu:Control
	var _spawn_select:OptionButton
	var runtime:Node
	var regenerations:=0
	var abort_before_replace:=false
	func _ready()->void:
		player=MockPlayer.new();add_child(player)
		water=MockWater.new();add_child(water)
		world=MockWorld.new();add_child(world)
		_menu=Control.new();add_child(_menu)
		var column:=VBoxContainer.new();_menu.add_child(column)
		for index in range(4):column.add_child(Label.new())
		var row:=HBoxContainer.new();column.add_child(row)
		_spawn_select=OptionButton.new();row.add_child(_spawn_select)
	func set_menu(value:bool)->void:
		if not value and runtime.busy:return
		menu_open=value;player.enabled=not value;_menu.visible=value
	func regenerate(_seed:int,_allow_cancel:bool=false)->void:
		_switching_spawn=true;regenerations+=1
		runtime.world_replacing()
		await get_tree().process_frame
		if abort_before_replace and _allow_cancel:
			runtime._cancel_requested=true;_switching_spawn=false;return
		world.queue_free();world=MockWorld.new();add_child(world)
		_switching_spawn=false
	func travel_to(_coord:Vector2i,_restore:bool=false)->void:pass
	func _safe_quit()->void:_booted=false
var failures:Array[String]=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func setup()->MockMain:
	var main:=MockMain.new();root.add_child(main)
	var runtime:=Runtime.new();main.runtime=runtime;runtime.main=main;runtime.state=State.new();runtime.active=true;runtime.save_path="user://transition_test_%d_%d.json"%[Time.get_ticks_usec(),randi()];main.add_child(runtime);runtime._build_ui();runtime.set_process(false)
	for item:Dictionary in Catalog.chapter(0).items:runtime.state.collect(item.id)
	return main
func run()->void:
	# GPU-water is mocked, not treated as a graphical run. Exercise the real async coordinator.
	var main:=setup();main.water.terrain_ready=false
	main.runtime._depart()
	check(main.runtime.busy,"transition locks input")
	check(main.runtime.state.pending_transition,"pending marker before fall")
	check(main.runtime.state.chapter_index==0,"no early chapter advance")
	while main.regenerations==0:await process_frame
	await process_frame;await process_frame
	check(main.runtime.state.chapter_index==0,"water not ready prevents progression")
	check(not main.player.enabled,"waiting keeps player disabled")
	main.water.terrain_ready=true
	while main.runtime.busy:await process_frame
	check(main.runtime.state.chapter_index==1,"ready landing advances once")
	check(not main.runtime.state.pending_transition,"landing clears pending")
	check(main.player.enabled,"landed player enabled")
	main.queue_free();await process_frame
	main=setup();main.water.terrain_ready=false;main.runtime._depart()
	while main.regenerations==0:await process_frame
	main.runtime._cancel_requested=true
	while main.runtime.busy:await process_frame
	check(main.runtime.state.chapter_index==0,"cancel preserves previous chapter")
	check(main.runtime.state.inventory.size()==8,"cancel keeps collected items")
	check(main.regenerations==2,"cancel reloads previous world")
	main.queue_free();await process_frame
	main=setup();main.abort_before_replace=true;main.runtime._depart()
	while main.runtime.busy:await process_frame
	check(main.runtime.state.chapter_index==0,"drain cancellation preserves old stage")
	check(main.regenerations==1,"drain cancellation does not repeat stuck wait")
	main.queue_free();await process_frame
	print("CAMPAIGN_TRANSITION_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
