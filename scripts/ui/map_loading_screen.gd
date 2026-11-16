extends CanvasLayer
## Covers world changes until scene, collision and water are ready.
const FONT = preload("res://assets/fonts/dreamcore/PoolCoreDreamSC.otf")

class Backdrop extends Control:
 var elapsed := 0.0
 func _process(delta: float) -> void:
  if not is_visible_in_tree(): return
  elapsed += minf(delta, .1)
  queue_redraw()
 func _draw() -> void:
  var s := size
  draw_rect(Rect2(Vector2.ZERO, s), Color("101a19"))
  # Quiet architectural bands echo the submerged rooms, without a fake progress bar.
  var horizon := s.y * .67
  draw_rect(Rect2(0, horizon, s.x, s.y-horizon), Color("142523"))
  draw_line(Vector2(0,horizon), Vector2(s.x,horizon), Color(.37,.53,.48,.22), 1.0)
  var center := Vector2(s.x*.5,horizon)
  for i in range(-5,6):
   draw_line(center + Vector2(i*s.x*.05,0), Vector2(s.x*.5+i*s.x*.22,s.y), Color(.37,.55,.49,.055), 1.0)
  for i in 7:
   var depth := float(i+1)/8.0
   var y := horizon + (s.y-horizon)*depth*depth
   draw_line(Vector2(0,y), Vector2(s.x,y), Color(.46,.64,.56,.08), 1.0)
  var w := minf(s.x*.23, 250.0)
  var y := s.y*.59
  draw_line(Vector2(s.x*.5-w,y), Vector2(s.x*.5+w,y), Color(.64,.76,.68,.14), 1.0)
  var phase := fmod(elapsed*.14,1.0)
  for i in 3:
   var p := fmod(phase+float(i)/3.0,1.0)
   draw_arc(Vector2(s.x*.5,y),w*(.18+.8*p),PI*1.06,PI*1.94,32,Color(.62,.81,.72,.16*(1.0-p)),1.0,true)
  var margin := clampf(s.x*.045,24.0,72.0)
  var col := Color(.74,.84,.77,.30)
  for x in [margin,s.x-margin]:
   var dir := 1.0 if x < s.x*.5 else -1.0
   for yy in [margin,s.y-margin]:
    var dy := 1.0 if yy < s.y*.5 else -1.0
    draw_line(Vector2(x,yy),Vector2(x+dir*18,yy),col,1.0)
    draw_line(Vector2(x,yy),Vector2(x,yy+dy*18),col,1.0)

var _root: Control
var _status: Label
var _detail: Label

func _ready() -> void:
 layer = 120
 _root = Control.new()
 _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _root.mouse_filter = Control.MOUSE_FILTER_STOP
 add_child(_root)
 var bg := Backdrop.new()
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _root.add_child(bg)
 var box := VBoxContainer.new()
 box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 box.offset_left = -260; box.offset_right = 260
 box.offset_top = -90; box.offset_bottom = 65
 box.add_theme_constant_override("separation", 12)
 _root.add_child(box)
 var eyebrow := Label.new()
 eyebrow.text = "B E Y O N D   T H E   B A S I N"
 eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 eyebrow.add_theme_font_size_override("font_size", 12)
 eyebrow.add_theme_color_override("font_color", Color("86a59a"))
 box.add_child(eyebrow)
 _status = Label.new()
 _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _status.add_theme_font_override("font", FONT)
 _status.add_theme_font_size_override("font_size", 27)
 _status.add_theme_color_override("font_color", Color("e4ebe2"))
 box.add_child(_status)
 _detail = Label.new()
 _detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _detail.add_theme_font_override("font", FONT)
 _detail.add_theme_font_size_override("font_size", 14)
 _detail.add_theme_color_override("font_color", Color("a3b8ab"))
 box.add_child(_detail)
 _root.hide()

func begin(title: String) -> void:
 _status.text = title
 _detail.text = "正在准备这个空间…"
 _root.show()

func set_detail(value: String) -> void:
 _detail.text = value if value.contains("失败") else "正在准备这个空间…"

func finish() -> void:
 _root.hide()
