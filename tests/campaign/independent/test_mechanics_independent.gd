extends SceneTree
const State=preload("res://scripts/campaign/campaign_state.gd")
const Obj=preload("res://scripts/campaign/campaign_objectives.gd")
const SOLUTIONS=[[4,0],[0,0,1,2,2,2,3],[0,0,1,2],[0,2,1,3,4],[0,1,2],[1,3,3,0,2]]
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures.append(label);push_error(label)
func step(state:RefCounted,seconds:float)->void:
 for i in range(int(ceil(seconds*4.0))):state.advance_time(.25,true)
func operate(state:RefCounted,index:int)->void:
 check(state.operate(state.current_chapter().items[index].id).accepted,"valid control accepted")
func solve(state:RefCounted)->void:
 for index:int in SOLUTIONS[state.chapter_index]:operate(state,index)
 step(state,12)
 if state.chapter_index==5:operate(state,4)
func _initialize()->void:
 var state=State.new()
 for chapter in range(6):
  check(state.chapter_index==chapter,"correct chapter")
  check(not state.can_depart(),"new puzzle not solved")
  check(not state.operate("unknown").accepted,"unknown control rejected")
  var initial:Dictionary=state.serialize().duplicate(true)
  for value:float in [-1.0,NAN,INF,0.0]:state.advance_time(value,true)
  check(state.serialize()==initial,"invalid delta unchanged")
  state.advance_time(50,false)
  check(state.serialize()==initial,"nonplayable delta unchanged")
  for item:Dictionary in state.current_chapter().items:state.collect(item.id)
  check(not state.can_depart(),"collect-all cannot bypass mechanics")
  state.retry_chapter()
  check(state.inventory.size()==[0,8,12,15,20,23][chapter],"retry preserves only prior chapters")
  # Deterministic wrong actions cannot cause invalid snapshots or lose retry route.
  for i in range(37):
   var snapshot:Dictionary=state.objective.duplicate(true)
   var index:int=(i*7+2)%state.current_chapter().items.size()
   var action:Dictionary=Obj.action(chapter,snapshot,index)
   check(snapshot==state.objective,"pure action input remains unchanged")
   check(Obj.valid(chapter,action.snapshot),"wrong-action snapshot valid")
   state.operate(state.current_chapter().items[index].id)
  check(state.retry_chapter(),"retry after arbitrary actions available")
  # Timer roundtrip at a nonzero in-progress point, then late repair without puzzle loss.
  state.advance_time(.125,true)
  check(is_equal_approx(state.elapsed,.125),"active timer increments")
  var restored=State.new()
  check(restored.restore(JSON.parse_string(JSON.stringify(state.serialize()))).ok,"partial timer roundtrip")
  check(is_equal_approx(restored.elapsed,state.elapsed),"reload does not reset timer")
  step(state,state.pressure_limit()+60.0)
  check(state.corruption()>.49 and state.corruption()<.51,"mid corruption gradual fraction")
  var objective:Dictionary=state.objective.duplicate(true)
  check(state.repair(),"late repair available")
  check(state.objective==objective,"repair retains puzzle")
  check(state.corruption()==0.0 and state.repairs==1,"repair reduces corruption")
  state.relaxed=true
  var time:float=state.elapsed
  step(state,10)
  check(state.elapsed==time and state.corruption()==0.0,"relaxed mode no pressure")
  state.relaxed=false
  check(state.retry_chapter(),"retry before solve")
  solve(state)
  check(state.can_depart(),"distinct mechanism solution completes")
  check(state.objective.solved,"objective solved")
  var done:Dictionary=state.objective.duplicate(true)
  check(not state.operate(state.current_chapter().items[0].id).accepted,"solved repeated action rejected")
  check(state.objective==done,"solved objective stable")
  check(state.begin_transition(),"solved transition starts")
  time=state.elapsed
  step(state,10)
  check(state.elapsed==time,"transition timer paused")
  check(not state.operate(state.current_chapter().items[0].id).accepted,"transition input blocked")
  var pending=State.new()
  var result:Dictionary=pending.restore(state.serialize())
  check(result.ok and result.recovered_pending,"pending recovers")
  check(pending.chapter_index==chapter and pending.can_depart(),"pending returns to solved old chapter")
  check(state.finish_transition(),"confirmed landing advances")
 check(state.completed,"all six mechanics finish campaign")
 check(not state.retry_chapter() and not state.repair(),"completed cannot regress")
 print("INDEPENDENT_MECHANICS_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
