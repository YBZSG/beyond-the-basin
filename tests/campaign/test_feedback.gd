extends SceneTree
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
class Main extends Node3D:
	var menu_open:=false
	var _audio_on:=true
var checks:=0
var failures:Array[String]=[]
func check(value:bool,note:String)->void:
	checks+=1
	if not value:failures.append(note);push_error(note)
func _initialize()->void:call_deferred("run")
func run()->void:
	var main:=Main.new();root.add_child(main)
	var runtime:=Runtime.new();runtime.main=main;main.add_child(runtime);runtime.set_process(false)
	var bell:=Node3D.new();main.add_child(bell)
	runtime._ring_bell(bell)
	check(is_instance_valid(runtime._bell_voice),"actual service-bell voice created")
	var id:int=runtime._bell_voice.get_instance_id()
	for i in range(100):runtime._ring_bell(bell)
	check(runtime._bell_voice.get_instance_id()==id,"100 repeated strikes reuse one voice")
	check(runtime._bell_voice.max_polyphony==1,"bell does not stack voices")
	check(runtime._bell_sound.data.size()==38400,"bounded1.2s mono16bit PCM")
	check(runtime._bell_voice.volume_db<=-20.0,"quiet localized feedback")
	var nonzero:=false
	for i in range(0,runtime._bell_sound.data.size(),2):
		if runtime._bell_sound.data.decode_s16(i)!=0:nonzero=true;break
	check(nonzero,"synthesized bell is not silent placeholder")
	runtime._stop_bell();check(not runtime._bell_voice.playing,"pause stop is immediate")
	main._audio_on=false;runtime._ring_bell(bell);check(not runtime._bell_voice.playing,"mute refuses strike")
	main._audio_on=true;main.menu_open=true;runtime._ring_bell(bell);check(not runtime._bell_voice.playing,"paused interaction silent")
	main.queue_free();await process_frame
	print("CAMPAIGN_FEEDBACK_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
