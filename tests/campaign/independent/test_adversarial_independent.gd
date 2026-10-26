extends SceneTree
const State=preload("res://scripts/campaign/campaign_state.gd")
const Store=preload("res://scripts/campaign/campaign_store.gd")
const Obj=preload("res://scripts/campaign/campaign_objectives.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures.append(label);push_error(label)
func reject(state:RefCounted,bad:Dictionary,label:String)->void:
 var before:Dictionary=state.serialize().duplicate(true)
 check(not state.restore(bad).ok,label+" rejected")
 check(state.serialize()==before,label+" nonmutating")
func _initialize()->void:
 var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/campaign/independent/legacy_v1_migration_fixtures.json"))
 for chapter in range(6):
  var state=State.new();state.restore(fixtures[chapter*3+1].save)
  var original:Dictionary=state.serialize()
  for key:String in ["elapsed","legacy_credit","repairs"]:
   for value:Variant in [-1,INF,NAN,"0",null,{},[],true]:
    var bad:Dictionary=original.duplicate(true);bad[key]=value
    reject(state,bad,"chapter%d malformed %s"%[chapter,key])
  for key:String in ["relaxed","reduced_effects"]:
   for value:Variant in [0,"false",null,{},[]]:
    var bad:Dictionary=original.duplicate(true);bad[key]=value
    reject(state,bad,"chapter%d malformed %s"%[chapter,key])
  for key:String in ["values","sequence","stable","solved"]:
   var bad:Dictionary=original.duplicate(true);bad.objective.erase(key)
   reject(state,bad,"missing objective "+key)
  for value:Variant in [-1,13,INF,NAN,"0",true,null]:
   var bad:Dictionary=original.duplicate(true);bad.objective.stable=value
   reject(state,bad,"bad stable")
  for value:Variant in [-1,4,INF,NAN,"0",true,null,{}]:
   var bad:Dictionary=original.duplicate(true);bad.objective.values[0]=value
   reject(state,bad,"bad objective value")
  var bad:Dictionary=original.duplicate(true);bad.objective.sequence=[3]
  reject(state,bad,"invalid memory prefix")
  bad=original.duplicate(true);bad.objective.solved=true
  reject(state,bad,"solved without completion stamp")
  bad=original.duplicate(true);bad.pending_transition=true
  reject(state,bad,"unsolved pending transition")
  bad=original.duplicate(true);bad.inventory.append(bad.inventory[0])
  reject(state,bad,"duplicate inventory")
 # Actual Store behavior, fresh isolated user folder, no production saves.
 var state=State.new()
 var path:String="user://independent-qa/%d/存档 space.json"%Time.get_ticks_usec()
 check(Store.load_state(path).status=="new","missing save new")
 check(Store.save_state(state,path)==OK,"initial atomic save")
 var loaded:Dictionary=Store.load_state(path)
 state.advance_time(.125,true)
 check(Store.save_state(state,path,loaded.fingerprint)==OK,"timer update atomic save")
 check(Store.save_state(state,path,loaded.fingerprint)==ERR_BUSY,"stale writer rejected")
 check(is_equal_approx(Store.load_state(path).state.elapsed,.125),"saved timer read exact")
 check(Store.load_state(path+".bak").state.elapsed==0.0,"old backup retained")
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string("{bad");file.close()
 var recovered:Dictionary=Store.load_state(path)
 check(recovered.ok and not recovered.writable and recovered.status=="backup_read_only","corrupt primary backup read-only")
 check(Store.save_state(state,path)==ERR_FILE_CORRUPT,"corrupt primary not overwritten")
 check(FileAccess.get_file_as_string(path)=="{bad","corrupt evidence preserved")
 var orphan:String=path+"_orphan"
 file=FileAccess.open(orphan+".tmp",FileAccess.WRITE);file.store_string("evidence");file.close()
 check(Store.save_state(state,orphan)==ERR_FILE_CORRUPT,"orphan temp not overwritten")
 check(FileAccess.get_file_as_string(orphan+".tmp")=="evidence","orphan temp evidence preserved")
 check(Store.save_state(state,"user://../escape.json")==ERR_FILE_BAD_PATH,"traversal rejected")
 print("INDEPENDENT_ADVERSARIAL_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
