extends SceneTree
const Main=preload("res://scripts/main.gd")
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
class UiMain extends Main:
 func _ready()->void:pass
 func _process(_delta:float)->void:pass
 func _input(_event:InputEvent)->void:pass
 func _build_water_panel(_ui:Control)->void:pass
var failures:Array[String]=[]
var rows:Array=[]
func check(value:bool,note:String)->void:
 if not value:failures.append(note);push_error(note)
func _initialize()->void:call_deferred("run")
func run()->void:
 for dimensions:Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=dimensions
  var main:=UiMain.new();root.add_child(main);main.set_process(false);main.set_process_input(false)
  main._build_interface()
  var runtime:=Runtime.new();runtime.main=main;runtime.state=State.new();main.add_child(runtime);runtime.set_process(false);runtime.set_process_input(false);runtime._build_ui()
  runtime._menu_summary.text="第四章 · 五间记忆 · 回声 3 / 4 拍 · 错序可从阶厅重演\n旧版已收集记录保留；当前机关获得 150 秒额外宽限。\n只读恢复：本次进度无法写入，请保留原存档。"
  main._menu.show()
  for i in range(8):await process_frame
  var panel:Rect2=main._menu.get_global_rect()
  var scroll:=main._menu.get_child(0) as ScrollContainer
  var column:=scroll.get_child(0) as VBoxContainer
  var row:Dictionary={"resolution":[dimensions.x,dimensions.y],"panel":[panel.position.x,panel.position.y,panel.size.x,panel.size.y],"scroll_height":scroll.size.y,"content_height":column.size.y,"buttons":[]}
  check(panel.position.x>=0 and panel.position.y>=0 and panel.end.x<=dimensions.x and panel.end.y<=dimensions.y,"panel fits "+str(dimensions))
  check(scroll.get_v_scroll_bar().max_value>scroll.size.y,"overflow scroll available")
  for control:Control in [runtime._continue,runtime._relaxed_check,runtime._reduced_check,runtime._repair_button,runtime._retry_button,main._character_select]:
   scroll.ensure_control_visible(control)
   for i in range(3):await process_frame
   var rect:Rect2=control.get_global_rect();var bounds:Rect2=scroll.get_global_rect()
   check(rect.position.y>=bounds.position.y-.1 and rect.end.y<=bounds.end.y+.1,"scroll reveals "+control.name)
   check(rect.position.x>=bounds.position.x and rect.end.x<=bounds.end.x+.1,"horizontal control fit "+control.name)
   row.buttons.append({"text":control.text if control is Button else control.name,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
  rows.append(row)
  main.queue_free();await process_frame
 var file:=FileAccess.open("res://independent-menu-results.json",FileAccess.WRITE);file.store_string(JSON.stringify({"scope":"actual main menu and campaign Control layout, no GPU or phone acceptance","rows":rows,"failures":failures},"\t"));file.close()
 print("INDEPENDENT_MENU ",JSON.stringify({"failures":failures,"resolutions":rows.size()}))
 quit(0 if failures.is_empty() else 1)
