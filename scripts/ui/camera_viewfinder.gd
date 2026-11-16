extends Control
## Decorative camera OSD. Clock uses local system time; this does not record video.
var _date: Label
var _clock: Label
var _guide: Label

func _ready() -> void:
	name = "CameraViewfinder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "monospace"])
	var stamp := VBoxContainer.new()
	stamp.name = "Timestamp"
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	stamp.offset_left = -286
	stamp.offset_right = -40
	stamp.offset_top = -98
	stamp.offset_bottom = -36
	stamp.add_theme_constant_override("separation", 0)
	add_child(stamp)
	_date = _osd_label(17, font)
	_clock = _osd_label(27, font)
	stamp.add_child(_date)
	stamp.add_child(_clock)
	var rec := _osd_label(20, font)
	rec.name = "RecordingIndicator"
	rec.text = "● REC"
	rec.add_theme_color_override("font_color", Color("dd9b83"))
	rec.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rec.offset_left = -160
	rec.offset_right = -40
	rec.offset_top = 34
	rec.offset_bottom = 68
	add_child(rec)
	_guide = _osd_label(14, null)
	_guide.name = "HeldTabGuide"
	_guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide.text = "WASD 移动   Shift 奔跑   Space 跳跃   E 交互   Q 铭牌\n左键抓取   右键蓄力投掷   滚轮调距离\nL 手电筒   F 镜头   Esc 菜单   H 隐藏界面   G 诊断"
	_guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_guide.offset_left = 32
	_guide.offset_right = -320
	_guide.offset_top = -138
	_guide.offset_bottom = -64
	_guide.hide()
	add_child(_guide)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_update_clock)
	add_child(timer)
	timer.start()
	_update_clock()
	resized.connect(queue_redraw)

func _osd_label(size_px: int, font: Font) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if font != null: label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", Color("e5e5d2"))
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.015, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	return label

func _update_clock() -> void:
	var now := Time.get_datetime_dict_from_system()
	_date.text = "%04d.%02d.%02d" % [now.year, now.month, now.day]
	_clock.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]

func set_hints_visible(value: bool) -> void:
	if is_instance_valid(_guide): _guide.visible = value

func _draw() -> void:
	var border := Color(0.86, 0.88, 0.77, 0.32)
	for corner: Vector2 in [Vector2(24,24), Vector2(size.x-24,24), Vector2(24,size.y-24), size-Vector2(24,24)]:
		var inward := Vector2(1 if corner.x < size.x/2 else -1, 1 if corner.y < size.y/2 else -1)
		draw_line(corner, corner+Vector2(inward.x*16,0), border, 1)
		draw_line(corner, corner+Vector2(0,inward.y*16), border, 1)
