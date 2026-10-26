extends SceneTree
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Objectives=preload("res://scripts/campaign/campaign_objectives.gd")
class Player extends CharacterBody3D:
	var camera:Node3D
	func _ready()->void:camera=Node3D.new();add_child(camera)
class Main extends Node3D:
	var player:Player
	var _booted:=true
	var _switching_spawn:=false
	var menu_open:=false
	var _menu:Control
	var _spawn_select:OptionButton
	func _ready()->void:
		player=Player.new();add_child(player)
		_menu=Control.new();add_child(_menu)
		var column:=VBoxContainer.new();_menu.add_child(column)
		for i in 4:column.add_child(Label.new())
		var row:=HBoxContainer.new();column.add_child(row);_spawn_select=OptionButton.new();row.add_child(_spawn_select)
	func set_menu(value:bool)->void:menu_open=value;_menu.visible=value
var checks:=0
var failures:Array[String]=[]
func check(value:bool,note:String)->void:
	checks+=1
	if not value:failures.append(note);push_error(note)
func key(code:Key,echo:bool=false)->InputEventKey:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true;event.echo=echo;return event
func _initialize()->void:call_deferred("run")
func run()->void:
	for action:String in ["interact","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	InputMap.action_add_event("pause",key(KEY_ESCAPE));InputMap.action_add_event("interact",key(KEY_E))
	var main:=Main.new();root.add_child(main)
	var runtime:=Runtime.new();runtime.main=main;runtime.state=State.new();runtime.active=true;main.add_child(runtime);runtime._build_ui();runtime.set_process(false)
	var station:=Node3D.new();station.set_meta("label","主馈电复位杆");main.add_child(station)
	var spec:Dictionary=Objectives.specs(0,250821)[0];runtime._collectibles[spec.id]=station;runtime._specs[spec.id]=spec
	main.player.position=Vector3(0,0,1.5);main.player.camera.position=Vector3(0,1.24,0);main.player.camera.look_at(Vector3(0,1.24,0))
	await physics_frame
	var before:Dictionary=runtime.state.serialize()
	runtime._input(key(KEY_Q))
	check(runtime._inspecting and runtime._inspect_panel.visible,"Q explicitly opens readable Chinese plate")
	check(main.menu_open and not main._menu.visible,"reading pauses without competing menu")
	check(runtime._inspect_text.text.contains(Objectives.CLUES[0]),"full Chinese clue available intentionally")
	runtime.state.advance_time(5,not main.menu_open)
	check(runtime.state.elapsed==before.elapsed,"reading does not charge timer")
	runtime._input(key(KEY_E));check(runtime.state.serialize()==before,"E while reading cannot operate")
	runtime._input(key(KEY_Q,true));check(runtime._inspecting,"key echo never closes or toggles")
	runtime._input(key(KEY_Q));check(not runtime._inspecting and not main.menu_open,"Q closes and restores play")
	runtime._input(key(KEY_Q));runtime._input(key(KEY_ESCAPE))
	check(not runtime._inspecting and not main.menu_open,"Escape closes only inspection")
	main.player.position=Vector3(0,0,20);runtime._input(key(KEY_Q))
	check(not runtime._inspecting,"cannot inspect a remote station")
	main.player.position=Vector3(0,0,1.5);runtime._input(key(KEY_Q));main.player.position=Vector3(0,0,20);runtime._input(key(KEY_Q))
	check(not runtime._inspecting,"moving target away cannot trap modal")
	main.player.position=Vector3(0,0,1.5);runtime._input(key(KEY_Q));runtime._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not runtime._inspecting and main.menu_open and main._menu.visible,"focus loss dismisses inspection into safe pause")
	check(runtime.state.serialize()==before,"all inspection interruptions preserve objective")
	runtime._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	main.menu_open=false;runtime._input(key(KEY_Q));runtime.world_replacing()
	check(not runtime._inspecting and not runtime._inspect_panel.visible,"world replacement clears modal")
	main.queue_free();await process_frame
	print("CAMPAIGN_INSPECTION_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
