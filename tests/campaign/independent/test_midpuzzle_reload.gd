extends SceneTree
const State=preload("res://scripts/campaign/campaign_state.gd")
const SOLUTIONS=[[4,0],[0,0,1,2,2,2,3],[0,0,1,2],[0,2,1,3,4],[0,1,2],[1,3,3,0,2]]
var failures:Array[String]=[]
var checks:=0
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures.append(label);push_error(label)
func _initialize()->void:
 var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/campaign/independent/legacy_v1_migration_fixtures.json"))
 for chapter in range(6):
  for break_after in range(SOLUTIONS[chapter].size()):
   var state=State.new();state.restore(fixtures[chapter*3+1].save)
   for i in range(SOLUTIONS[chapter].size()):
    var index:int=SOLUTIONS[chapter][i]
    state.operate(state.current_chapter().items[index].id)
    if i==break_after:
     var new_state=State.new()
     check(new_state.restore(JSON.parse_string(JSON.stringify(state.serialize()))).ok,"reload accepted")
     state=new_state
   for i in range(48):state.advance_time(.25,true)
   if chapter==5:state.operate(state.current_chapter().items[4].id)
   check(state.can_depart(),"chapter %d reload after action %d still solvable"%[chapter,break_after])
 print("INDEPENDENT_MIDPUZZLE_RELOAD ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
