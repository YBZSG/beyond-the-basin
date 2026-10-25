extends RefCounted
## Small independent section; all controls round-trip through one validated setting dictionary.
const Settings=preload("res://scripts/reference_wing/reference_look_settings.gd")

static func build(parent: VBoxContainer, values: Dictionary, changed: Callable) -> void:
	var title:=Label.new();title.text="参考画面 / OPTIONAL REFERENCE LOOK";title.add_theme_font_size_override("font_size",18);parent.add_child(title)
	var note:=Label.new();note.text="菜单“青绿柔光”一键搭配滤镜和水波，也可在这里分别开关。保留脚步与涉水涟漪，滤镜不影响界面。";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(note)
	for entry: Array in [["referenceWaves","参考交错水波"],["referenceLook","参考镜头滤镜（不影响界面）"]]:
		var key: String=entry[0]
		var check:=CheckButton.new();check.name=key;check.text=entry[1];check.button_pressed=values[key]
		check.toggled.connect(func(value:bool):changed.call(key,value));parent.add_child(check)
		var rows: Array = [["referenceWaveStrength","水波起伏强度",0.0,1.0,.01],["referenceWaveDirection","波浪传播方向 °",0.0,359.0,1.0],["referenceWaveScale","波长尺度",.6,1.6,.01]] if key=="referenceWaves" else [["referenceFringePx","镜头彩边 / 像素",0.0,8.0,.05],["referenceGrain","颗粒强度",0.0,.02,.001],["referenceVignette","暗角强度",0.0,.45,.005]]
		for row: Array in rows:_slider(parent,row,values,changed)
	parent.add_child(HSeparator.new())

static func _slider(parent:VBoxContainer, entry:Array, values:Dictionary, changed:Callable)->void:
	var row:=HBoxContainer.new();parent.add_child(row)
	var label:=Label.new();label.text=entry[1];label.custom_minimum_size.x=180;row.add_child(label)
	var slider:=HSlider.new();slider.name=str(entry[0]);slider.min_value=entry[2];slider.max_value=entry[3];slider.step=entry[4];slider.value=values[entry[0]];slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(slider)
	var number:=Label.new();number.name="NumericValue";number.custom_minimum_size.x=55;number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;row.add_child(number)
	number.text=String.num(slider.value,3)
	var key:String=entry[0]
	slider.value_changed.connect(func(value:float):number.text=String.num(value,3);changed.call(key,value))
