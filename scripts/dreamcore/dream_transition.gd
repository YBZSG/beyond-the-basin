extends CanvasLayer
## Stationary, bounded threshold presentation. Never moves the camera/player,
## commits progression, or bypasses world/water/landing readiness.
signal cancel_requested
signal quit_requested
const DreamFont = preload("res://assets/fonts/dreamcore/PoolCoreDreamSC.otf")
const Loading = preload("res://scripts/ui/map_loading_screen.gd")
const STYLES := {"lime_gallery":"glass","sportsground":"service","sluice_courtyard":"mist","aquarium_atrium":"aqua","night_busstop":"depot","oculus_hall":"oculus","cloud_ballpit":"aqua","hanging_hand":"glass","stair_labyrinth":"service","soffit_reservoir":"service","parallax_bath":"glass","crossing_channels":"depot","inverted_pool":"aqua","hollow_visage":"service","glasswell_bath":"glass"}
const CAPTIONS := {"glass":"Glazed threshold / service door","service":"Concrete service passage / open air","mist":"Mist arch / aqua glass corridor","aqua":"Quiet glass corridor / night platform","depot":"Depot double door / daylight beyond","oculus":"A quiet threshold / return to light"}
const COLORS := {"glass":Color(.16,.23,.20),"service":Color(.12,.11,.10),"mist":Color(.38,.43,.41),"aqua":Color(.08,.22,.23),"depot":Color(.035,.055,.075),"oculus":Color(.30,.34,.27)}
# Presentation only: origin context + the coordinator-supplied actual destination.
const ROOM_PROFILES := {"soffit_reservoir":"压顶水库 · 侧门","parallax_bath":"错尺长池 · 门廊","crossing_channels":"交错旱渠 · 侧门","inverted_pool":"倒悬浴场 · 侧门","hollow_visage":"空面水殿 · 侧门","glasswell_bath":"浅水深井 · 回廊"}
class Threshold extends Control:
	var coverage := 0.0
	var style := "glass"
	var reduced := true
	var room_profile := ""
	func _draw() -> void:
		var p := clampf(coverage,0.0,1.0)
		if p<=0.0: return
		if not room_profile.is_empty():
			_draw_room_profile(); return
		var color: Color = COLORS.get(style,Color(.1,.15,.15))
		var ink := color.lightened(.18)
		if p>=.9999: draw_rect(Rect2(Vector2.ZERO,size),color); return
		match style:
			"glass":
				# Two planar frosted leaves slide toward the centre; source view
				# stays untouched in the uncovered slot until it fully closes.
				var width := size.x*.5*p
				draw_rect(Rect2(0,0,width,size.y),color); draw_rect(Rect2(size.x-width,0,width,size.y),color)
				draw_line(Vector2(width,0),Vector2(width,size.y),ink,5); draw_line(Vector2(size.x-width,0),Vector2(size.x-width,size.y),ink,5)
			"service":
				# A ribbed service shutter descends, unlike sliding glass.
				var height := size.y*p; draw_rect(Rect2(0,0,size.x,height),color)
				if not reduced:
					for index in 16:
						var y := height-float(index)*size.y/16.0
						if y>0: draw_line(Vector2(0,y),Vector2(size.x,y),ink,2)
			"mist":
				# Rounded-arch aperture contracts within a soft ground veil.
				draw_rect(Rect2(Vector2.ZERO,size),Color(color,p*.18))
				var rows := 64
				for index in rows:
					var y := size.y*float(index)/rows; var row_height := size.y/rows+1
					var normal_y := (y-size.y*.48)/(size.y*.55)
					var arch := sqrt(maxf(0,1-normal_y*normal_y)) if y<size.y*.48 else 1.0
					var half := size.x*.56*(1-p)*arch
					draw_rect(Rect2(0,y,maxf(0,size.x*.5-half),row_height),color)
					draw_rect(Rect2(size.x*.5+half,y,maxf(0,size.x*.5-half),row_height),color)
			"aqua":
				# A single aquarium-glass wipe crosses the view, with a broad
				# refractive-edge motif, not a second pair of closing doors.
				var width := size.x*p; draw_rect(Rect2(0,0,width,size.y),color)
				draw_line(Vector2(width,0),Vector2(width,size.y),ink,12 if not reduced else 3)
				if not reduced: draw_line(Vector2(maxf(0,width-30),0),Vector2(maxf(0,width-80),size.y),color.lightened(.08),6)
			"depot":
				# Hinged depot leaves have trapezoidal silhouettes and diagonal
				# perspective edges. Camera and player remain stationary.
				var width := size.x*.5*p; var skew := size.y*.18*(1-p)
				draw_colored_polygon(PackedVector2Array([Vector2.ZERO,Vector2(width,-skew),Vector2(width,size.y+skew),Vector2(0,size.y)]),color)
				draw_colored_polygon(PackedVector2Array([Vector2(size.x,0),Vector2(size.x-width,skew),Vector2(size.x-width,size.y-skew),Vector2(size.x,size.y)]),color)
				draw_line(Vector2(width,-skew),Vector2(width,size.y+skew),ink,4)
				draw_line(Vector2(size.x-width,skew),Vector2(size.x-width,size.y-skew),ink,4)
			"oculus":
				# Concentric aperture: a true circular opening, not a tint fade.
				var center := size*.5; var outer := size.length()*.55; var inner := outer*(1-p)
				for index in 64:
					var a := TAU*float(index)/64; var b := TAU*float(index+1)/64
					var va := Vector2(cos(a),sin(a)); var vb := Vector2(cos(b),sin(b))
					draw_colored_polygon(PackedVector2Array([center+va*inner,center+va*outer,center+vb*outer,center+vb*inner]),color)
				if not reduced:
					for ratio in [.18,.4,.64]: draw_arc(center,inner+(outer-inner)*ratio,0,TAU,64,ink,2)

	# This single primitive stream is both drawn and exported by the tests.
	# No viewport capture, camera transform, world access or mutable progress.
	func frame_primitives() -> Array:
		var result: Array = []
		var p := clampf(coverage,0.0,1.0)
		if not ROOM_PROFILES.has(room_profile) or p<=0.0: return result
		var c: Color = COLORS.get(style,Color(.1,.15,.15))
		var ink := c.lightened(.12)
		var w := size.x; var h := size.y
		if p>=.9999:
			result.append({"kind":"rect","rect":Rect2(Vector2.ZERO,size),"color":c}); return result
		if reduced:
			# Quiet whole-view cover. Static frame, opacity only; no moving bars.
			result.append({"kind":"rect","rect":Rect2(Vector2.ZERO,size),"color":Color(c,p)})
			result.append({"kind":"line","points":PackedVector2Array([Vector2(w*.12,h*.82),Vector2(w*.88,h*.82)]),"color":Color(ink,p),"width":2.0})
			return result
		match room_profile:
			"soffit_reservoir":
				var y := h*.82*p; var lower := h*.18*p
				result.append({"kind":"rect","rect":Rect2(0,0,w,y),"color":c})
				result.append({"kind":"rect","rect":Rect2(0,h-lower,w,lower),"color":c})
				result.append({"kind":"line","points":PackedVector2Array([Vector2(0,y),Vector2(w,y)]),"color":ink,"width":3.0})
			"parallax_bath":
				# Actual planar tapered opening; the underlying player view never zooms.
				var left := w*.5*p; var right := w-left
				var top := h*.34*p; var bottom := h-h*.22*p
				var taper := w*.12*(1.0-p)*p
				result.append({"kind":"polygon","points":PackedVector2Array([Vector2.ZERO,Vector2(w,0),Vector2(right-taper,top),Vector2(left+taper,top)]),"color":c})
				result.append({"kind":"polygon","points":PackedVector2Array([Vector2(0,h),Vector2(left,bottom),Vector2(right,bottom),Vector2(w,h)]),"color":c})
				result.append({"kind":"polygon","points":PackedVector2Array([Vector2.ZERO,Vector2(left+taper,top),Vector2(left,bottom),Vector2(0,h)]),"color":c})
				result.append({"kind":"polygon","points":PackedVector2Array([Vector2(w,0),Vector2(w,h),Vector2(right,bottom),Vector2(right-taper,top)]),"color":c})
			"crossing_channels":
				var a := w*.64*p; var b := w*.36*p; var skew := w*.08*p*(1.0-p)
				result.append({"kind":"polygon","points":PackedVector2Array([Vector2.ZERO,Vector2(a+skew,0),Vector2(a-skew,h),Vector2(0,h)]),"color":c})
				result.append({"kind":"polygon","points":PackedVector2Array([Vector2(w-b+skew,0),Vector2(w,0),Vector2(w,h),Vector2(w-b-skew,h)]),"color":c})
				result.append({"kind":"line","points":PackedVector2Array([Vector2(a*.35,h*.32),Vector2(a-skew,h*.32)]),"color":ink,"width":3.0})
			"inverted_pool":
				var y := h*p
				result.append({"kind":"rect","rect":Rect2(0,0,w,y),"color":c})
				result.append({"kind":"line","points":PackedVector2Array([Vector2(w*.5,0),Vector2(w*.5,y*.78)]),"color":ink,"width":2.0})
				result.append({"kind":"polygon","points":PackedVector2Array([Vector2(w*.5-5,y*.78),Vector2(w*.5+5,y*.78),Vector2(w*.5,y*.78+minf(12,y*.12))]),"color":ink})
			"hollow_visage":
				var x := w*p
				result.append({"kind":"rect","rect":Rect2(0,0,x,h),"color":c})
				result.append({"kind":"line","points":PackedVector2Array([Vector2(x,0),Vector2(x,h)]),"color":ink,"width":3.0})
				# Side-service leaf, deliberately no facial silhouette or eye motion.
				for y in [h*.25,h*.75]:
					result.append({"kind":"rect","rect":Rect2(maxf(0,x-18),y,minf(8,x),6),"color":ink})
			"glasswell_bath":
				var x := w*.5*p; var y := h*.5*p
				for rect in [Rect2(0,0,w,y),Rect2(0,h-y,w,y),Rect2(0,y,x,h-2*y),Rect2(w-x,y,x,h-2*y)]:
					result.append({"kind":"rect","rect":rect,"color":c})
				result.append({"kind":"line","points":PackedVector2Array([Vector2(x,y),Vector2(w-x,y),Vector2(w-x,h-y),Vector2(x,h-y),Vector2(x,y)]),"color":ink,"width":2.0})
		return result
	func _draw_room_profile() -> void:
		for item: Dictionary in frame_primitives():
			match item.kind:
				"rect": draw_rect(item.rect,item.color)
				"polygon": draw_colored_polygon(item.points,item.color)
				"line": draw_polyline(item.points,item.color,item.width)

var _root: Control
var _canvas: Threshold
var _caption: Label
var _loading_backdrop: Control
var _destination := ""
var _cancel_button: Button
var _skip_button: Button
var _skip := false
var _cancelled := false
var _epoch := 0
func _ready() -> void:
	layer=110
	_root=Control.new(); _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _root.mouse_filter=Control.MOUSE_FILTER_STOP; add_child(_root)
	_canvas=Threshold.new(); _canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE; _root.add_child(_canvas)
	_loading_backdrop=Loading.Backdrop.new(); _loading_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _loading_backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE; _root.add_child(_loading_backdrop); _loading_backdrop.hide()
	_caption=Label.new(); _caption.position=Vector2(40,42); _caption.size=Vector2(800,100); _caption.add_theme_font_override("font",DreamFont); _caption.add_theme_font_size_override("font_size",20); _root.add_child(_caption)
	var buttons:=HBoxContainer.new(); buttons.position=Vector2(40,158); buttons.add_theme_constant_override("separation",12); _root.add_child(buttons)
	_skip_button=Button.new(); _skip_button.text="Skip visual beat"; _skip_button.pressed.connect(skip); buttons.add_child(_skip_button)
	_cancel_button=Button.new(); _cancel_button.text="Cancel / safe menu"; _cancel_button.pressed.connect(cancel); buttons.add_child(_cancel_button)
	var quit_button:=Button.new(); quit_button.text="Safe quit"; quit_button.pressed.connect(_request_quit); buttons.add_child(quit_button)
	_root.resized.connect(_layout_room_caption)
	var window := get_window()
	if is_instance_valid(window): window.close_requested.connect(_window_closing)
	_root.hide()
func begin(from_id: String, to_title: String, reduced: bool) -> void:
	_epoch+=1; _skip=false; _cancelled=false
	_destination=to_title; _loading_backdrop.hide(); _skip_button.show()
	_canvas.style=str(STYLES.get(from_id,"glass")); _canvas.reduced=reduced; _canvas.coverage=0
	_canvas.room_profile=from_id if ROOM_PROFILES.has(from_id) else ""
	_caption.text=tr(str(ROOM_PROFILES.get(from_id,CAPTIONS[_canvas.style])))+"\n→ "+tr(to_title)
	_layout_room_caption()
	_cancel_button.disabled=false; _skip_button.disabled=false; _root.show(); _skip_button.grab_focus()
	await _animate(1.0,.12 if reduced else .55)
func preparing() -> void:
	_canvas.coverage=1.0; _canvas.queue_redraw()
	_loading_backdrop.show(); _skip_button.hide()
	_caption.text = "BEYOND THE BASIN\n\n" + tr(_destination) + tr("\n\n正在准备这个空间…")
	_layout_room_caption()
	_skip_button.disabled=true # Skip NEVER bypasses the transaction.
func _layout_room_caption() -> void:
	if not is_instance_valid(_caption) or not is_instance_valid(_skip_button): return
	var viewport_size := get_viewport().get_visible_rect().size
	var buttons: HBoxContainer = _skip_button.get_parent()
	if _loading_backdrop.visible:
		_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_caption.size=Vector2(minf(520.0,viewport_size.x-48.0),180)
		_caption.position=Vector2((viewport_size.x-_caption.size.x)*.5,viewport_size.y*.33)
		buttons.position=Vector2((viewport_size.x-buttons.get_combined_minimum_size().x)*.5,viewport_size.y*.68)
	else:
		_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
		_caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_caption.position=Vector2(40,42); _caption.size=Vector2(minf(800.0,viewport_size.x-80.0),100)
		buttons.position=Vector2(40,158)
	var captions := ["跳过画面","取消","退出"]
	for index in 3:
		var button: Button = buttons.get_child(index)
		button.text=captions[index];button.add_theme_font_override("font",DreamFont)
		button.custom_minimum_size=Vector2(100,36)
		button.add_theme_color_override("font_color",Color("c1d0c6"))
		button.add_theme_color_override("font_hover_color",Color("f0f5ef"))
		var normal := StyleBoxFlat.new();normal.bg_color=Color("1c302b");normal.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal",normal)
		var hover := normal.duplicate();hover.bg_color=Color("2b463d");button.add_theme_stylebox_override("hover",hover)
		var focus := StyleBoxFlat.new();focus.draw_center=false;focus.border_color=Color("a1c5af");focus.set_border_width_all(1);button.add_theme_stylebox_override("focus",focus)
func finish(reduced: bool) -> void:
	_loading_backdrop.hide(); _layout_room_caption()
	_cancel_button.disabled=true; _skip_button.disabled=false; _skip=false
	await _animate(0.0,.12 if reduced else .35)
	hide_safely()
func _window_closing() -> void:
	# Main still owns shutdown. This listener only releases all-style visual
	# epochs; it never emits quit again or touches world/save/readiness.
	hide_safely()
func _request_quit() -> void:
	# All-style cleanup releases the pending animation await before the
	# existing Main shutdown's two deletion boundaries. No save/world authority.
	hide_safely()
	quit_requested.emit()
func skip() -> void: _skip=true
func cancel() -> void:
	_cancelled=true; _skip=true; cancel_requested.emit()
func hide_safely() -> void:
	_epoch+=1
	if is_instance_valid(_root): _root.hide()
func _animate(target: float, duration: float) -> void:
	var epoch:=_epoch
	var initial:=_canvas.coverage; var elapsed:=0.0
	while elapsed<duration and not _skip and epoch==_epoch and is_inside_tree():
		await get_tree().process_frame
		if epoch!=_epoch or not is_inside_tree(): return
		elapsed+=minf(get_process_delta_time(),.1)
		_canvas.coverage=lerpf(initial,target,smoothstep(0.0,1.0,minf(1.0,elapsed/duration))); _canvas.queue_redraw()
	if epoch==_epoch: _canvas.coverage=target; _canvas.queue_redraw()
func diagnostics() -> Dictionary:
	var result := {"visible":is_instance_valid(_root) and _root.visible,"style":_canvas.style if is_instance_valid(_canvas) else "","cancelled":_cancelled,"skipped":_skip,"camera_motion":false,"owns_progress":false,"motion_signature":_canvas.style if is_instance_valid(_canvas) else ""}
	if is_instance_valid(_canvas) and not _canvas.room_profile.is_empty():
		result.room_profile=_canvas.room_profile
		result.motion_signature=_canvas.room_profile
	return result
