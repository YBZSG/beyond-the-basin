extends SceneTree
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
class TestRuntime extends Runtime:
	func _mounts_ready_for(_chapter:int)->bool:return true
class MockCamera extends Camera3D:
	pass
class MockPlayer extends CharacterBody3D:
	var camera:MockCamera
	var enabled:=false
	func _ready()->void:camera=MockCamera.new();add_child(camera);camera.current=true
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
	var handoff_alphas:Array=[]
	var break_save:=false
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
		handoff_alphas.append(runtime._shade.color.a)
		if break_save:runtime.writable=false
		runtime.world_replacing()
		await get_tree().process_frame
		if abort_before_replace and _allow_cancel:
			runtime._cancel_requested=true;_switching_spawn=false;return
		world.queue_free();world=MockWorld.new();add_child(world)
		player.queue_free();player=MockPlayer.new();add_child(player)
		_switching_spawn=false
	func travel_to(_coord:Vector2i,_restore:bool=false)->void:pass
	func _safe_quit()->void:_booted=false
var failures:Array[String]=[]
var checks:=0
var reports:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func setup(chapter:int)->MockMain:
	var main:=MockMain.new();root.add_child(main)
	var runtime:=TestRuntime.new();main.runtime=runtime;runtime.main=main;runtime.state=State.new();runtime.active=true;runtime.save_path="user://independent-timeline/%d_%d.json"%[Time.get_ticks_usec(),randi()];main.add_child(runtime);runtime._build_ui();runtime.set_process(false)
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/campaign/independent/legacy_v1_migration_fixtures.json"))
	runtime.state.restore(fixtures[chapter*3+2].save)
	return main
func run()->void:
	for scenario:String in ["chapter0","chapter1","chapter2","chapter3","chapter4","chapter5","cancel","timeout","save_error","skip"]:
		var chapter:int=int(scenario.trim_prefix("chapter")) if scenario.begins_with("chapter") else 0
		var main:=setup(chapter)
		if scenario=="timeout":main.water.terrain_ready=false;main.runtime.load_timeout_seconds=.05
		if scenario=="save_error":main.break_save=true
		var initial_time:float=main.runtime.state.elapsed
		var original_camera_id:int=main.player.camera.get_instance_id()
		main.runtime._depart()
		var frame:=0;var visible_play:=0;var stage_seen:=false;var activation_alpha:=-1.0;var acted:=false;var actual_mode:=-1
		while main.runtime.busy and frame<12000:
			await process_frame;frame+=1
			var stage:Node3D=main.runtime._cinematic
			if is_instance_valid(stage):
				if not stage_seen:activation_alpha=main.runtime._shade.color.a;stage_seen=true;actual_mode=stage.chapter_index
				if stage._playing and main.runtime._shade.color.a<.05 and root.get_camera_3d()==stage.camera:visible_play+=1
				if visible_play>5 and not acted:
					if scenario=="cancel":main.runtime._cancel_requested=true;stage.cancel();acted=true
					if scenario=="skip":stage.set_safe_to_skip(true);check(stage.request_skip(),"injected safe skip accepted");acted=true
		check(frame<12000,scenario+" bounded lifecycle")
		check(stage_seen,scenario+" actual stage created")
		check(actual_mode==chapter,scenario+" correct chapter cinematic selected")
		check(activation_alpha>.9,scenario+" camera activates under opaque fade")
		check(visible_play>5,scenario+" real stage camera visible while play progresses")
		for alpha:float in main.handoff_alphas:check(alpha>.99,scenario+" world handoff under black")
		check(root.get_camera_3d()==main.player.camera,scenario+" actual player camera restored")
		if main.regenerations>0:check(main.player.camera.get_instance_id()!=original_camera_id,scenario+" new-world camera rather than stale camera")
		check(not main.runtime._shade.visible and main.runtime._shade.color.a<.01,scenario+" final shade removed")
		check(not main.runtime._loading.visible and not main.runtime._cancel.visible,scenario+" loading controls hidden")
		check(main.player.enabled and not main.menu_open,scenario+" input/menu restored")
		check(main.runtime.state.elapsed==initial_time,scenario+" active timer unchanged")
		if scenario in ["cancel","timeout","save_error"]:
			check(main.runtime.state.chapter_index==0 and not main.runtime.state.pending_transition and main.runtime.state.can_depart(),scenario+" old solved checkpoint preserved")
		elif chapter==5:check(main.runtime.state.completed and main.regenerations==0,"ending commits only after stage, no seventh world")
		else:check(main.runtime.state.chapter_index==chapter+1,"normal/skip one chapter commit")
		reports.append({"scenario":scenario,"frames":frame,"visible_play_frames":visible_play,"activation_alpha":activation_alpha,"handoff_alphas":main.handoff_alphas,"mode":actual_mode})
		main.queue_free();await process_frame
	var file:=FileAccess.open("res://independent-timeline-results.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":reports,"scope":"actual coordinator/fade/transition geometry and Camera3D current selection; stubbed water/world/mount preparation, not GPU or full world handoff"},"\t"));file.close()
	print("INDEPENDENT_TIMELINE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
