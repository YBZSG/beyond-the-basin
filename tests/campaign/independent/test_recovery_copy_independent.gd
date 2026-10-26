extends SceneTree
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const Store=preload("res://scripts/campaign/campaign_store.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
var failures:Array[String]=[]
var checks:=0
func check(value:bool,note:String)->void:
 checks+=1
 if not value:failures.append(note);push_error(note)
func _initialize()->void:
 var path:String="user://independent-recovery/%d/primary.json"%Time.get_ticks_usec()
 var state=State.new();state.advance_time(.125,true)
 check(Store.save_state(state,path)==OK,"initial synthetic save")
 var original:Dictionary=Store.load_state(path)
 state.advance_time(.125,true)
 check(Store.save_state(state,path,original.fingerprint)==OK,"backup prepared")
 var backup:String=FileAccess.get_file_as_string(path+".bak")
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string("{synthetic-corrupt}");file.close()
 var recovered:Dictionary=Store.load_state(path)
 check(recovered.ok and not recovered.writable,"loads valid backup read-only")
 var runtime:=Runtime.new();runtime.state=recovered.state;runtime.writable=false;runtime.save_path=path;runtime.set_process(false);runtime.set_process_input(false)
 # The recovery action is explicitly invoked, never silently auto-overwrites.
 runtime._create_recovery_save()
 check(runtime.writable and runtime.save_path!=path,"explicit copy becomes writable separate save")
 check(FileAccess.get_file_as_string(path)=="{synthetic-corrupt}","corrupt primary preserved byte-for-byte")
 check(FileAccess.get_file_as_string(path+".bak")==backup,"original backup preserved byte-for-byte")
 var copy:Dictionary=Store.load_state(runtime.save_path)
 check(copy.ok and copy.writable and is_equal_approx(copy.state.elapsed,.125),"recovery uses proven backup progress")
 var config:=ConfigFile.new()
 check(config.load("user://campaign_profile.cfg")==OK and config.get_value("campaign","save_path","")==runtime.save_path,"restart selects recovery copy")
 runtime.free()
 print("INDEPENDENT_RECOVERY_COPY ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
