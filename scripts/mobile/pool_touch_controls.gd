extends Control
## Multi-touch overlay. Touch gameplay never rewrites the desktop input map.
## Left thumb: floating joystick; right drag: view; edge buttons: actions.

signal menu_requested
var player: CharacterBody3D
var gameplay_enabled := false
var look_sensitivity := 0.0031
var _move_finger := -1
var _look_finger := -1
var _origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _buttons: Dictionary = {}
var _button_fingers: Dictionary = {}
var _safe := Rect2()
var _radius := 70.0
var _throwing := false
var _throw_charge := 0.0
var _hint := ""
const ACTIONS := ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump", "throw_prop"]
const FG := Color(0.87, 0.96, 0.94, 0.94)
const BG := Color(0.02, 0.07, 0.08, 0.40)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()

func set_player(value: CharacterBody3D) -> void:
	if player == value: return
	release_all()
	player = value

func set_gameplay_enabled(value: bool) -> void:
	if gameplay_enabled == value: return
	gameplay_enabled = value
	if not value: release_all()
	visible = value
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()

func _exit_tree() -> void:
	release_all()

func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	_safe = Rect2(Vector2(24, 20), viewport_size - Vector2(48, 40))
	if OS.has_feature("android") or OS.has_feature("ios"):
		var screen_size := Vector2(DisplayServer.screen_get_size())
		var screen_safe := Rect2(DisplayServer.get_display_safe_area())
		if screen_size.x > 0.0 and screen_size.y > 0.0 and screen_safe.has_area():
			var scale_xy := viewport_size / screen_size
			_safe = Rect2(screen_safe.position * scale_xy + Vector2(20, 16), screen_safe.size * scale_xy - Vector2(40, 32))
	var right := _safe.end.x
	var bottom := _safe.end.y
	_radius = clampf(viewport_size.y * 0.115, 58.0, 88.0)
	_buttons = {
		"menu": Rect2(Vector2(right - 100, _safe.position.y), Vector2(100, 54)),
		"jump": Rect2(Vector2(right - 88, bottom - 200), Vector2(82, 82)),
		"grab": Rect2(Vector2(right - 190, bottom - 105), Vector2(88, 88)),
		"throw": Rect2(Vector2(right - 88, bottom - 105), Vector2(82, 88)),
		"interact": Rect2(Vector2(right - 195, bottom - 190), Vector2(88, 66)),
		"splash": Rect2(Vector2(right - 295, bottom - 100), Vector2(80, 78)),
		"near": Rect2(Vector2(right - 390, bottom - 183), Vector2(80, 66)),
		"far": Rect2(Vector2(right - 290, bottom - 183), Vector2(80, 66)),
	}
	if _move_finger < 0: _origin = Vector2(_safe.position.x + 110, bottom - 100)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not gameplay_enabled or not is_instance_valid(player) or not player.enabled: return
	if event is InputEventScreenTouch:
		if event.canceled:
			release_all()
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			for action: String in _buttons:
				if (_buttons[action] as Rect2).has_point(event.position):
					# One owner per button. A second thumb must not throw on first release.
					if action in _button_fingers.values():
						get_viewport().set_input_as_handled()
						return
					_button_fingers[event.index] = action
					_press_button(action)
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
			if event.position.x < get_viewport_rect().size.x * 0.43 and _move_finger < 0:
				_move_finger = event.index
				_origin = Vector2(clampf(event.position.x, _safe.position.x + _radius, _safe.end.x - _radius), clampf(event.position.y, _safe.position.y + _radius, _safe.end.y - _radius))
				_move_to(event.position)
			elif _look_finger < 0:
				_look_finger = event.index
		else:
			_release_finger(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _move_finger:
			_move_to(event.position)
		elif event.index == _look_finger:
			var camera: Camera3D = player.get_view_camera()
			player.rotate_y(-event.relative.x * look_sensitivity)
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * look_sensitivity, -1.3, 1.3)
		get_viewport().set_input_as_handled()
	queue_redraw()

func _move_to(point: Vector2) -> void:
	_stick = ((point - _origin) / _radius).limit_length()
	var value := Vector2.ZERO
	if _stick.length() > 0.17:
		value = _stick.normalized() * ((_stick.length() - 0.17) / 0.83)
	_set_axis("move_left", -value.x)
	_set_axis("move_right", value.x)
	_set_axis("move_forward", -value.y)
	_set_axis("move_back", value.y)
	_set_axis("sprint", 1.0 if _stick.length() > 0.88 else 0.0)

func _set_axis(action: String, value: float) -> void:
	if value > 0.035: Input.action_press(action, value)
	else: Input.action_release(action)

func _send_action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)

func _press_button(action: String) -> void:
	match action:
		"menu":
			release_all()
			menu_requested.emit()
		"jump": _send_action("jump", true)
		"throw":
			if is_instance_valid(player.held):
				_throwing = true
				_send_action("throw_prop", true)
		"grab":
			# A tap latches the grab so the right thumb is free to aim and throw.
			if is_instance_valid(player.held): player.release_prop()
			else:
				var picked: RigidBody3D = player.pick_prop()
				if picked: player.grab_prop(picked)
		"interact": player.toggle_ladder()
		"splash": player.strike_water()
		"near": _change_distance(false)
		"far": _change_distance(true)

func _change_distance(farther: bool) -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.held): return
	# Dispatch the actual desktop wheel path, retaining its 0.2m increment,
	# direction and 0.75m-3m clamp rather than a separate mobile approximation.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if farther else MOUSE_BUTTON_WHEEL_DOWN
	wheel.factor = 1.0
	wheel.pressed = true
	player._unhandled_input(wheel)

func _release_finger(index: int) -> void:
	if index == _move_finger:
		_move_finger = -1
		_stick = Vector2.ZERO
		for action in ["move_left", "move_right", "move_forward", "move_back", "sprint"]: Input.action_release(action)
	if index == _look_finger: _look_finger = -1
	if _button_fingers.has(index):
		var action: String = _button_fingers[index]
		_button_fingers.erase(index)
		if action == "jump": _send_action("jump", false)
		elif action == "throw" and _throwing:
			_throwing = false
			_send_action("throw_prop", false)

func release_all() -> void:
	# Never throw accidentally when a call, home gesture or pause interrupts play.
	if _throwing and is_instance_valid(player): player.release_prop()
	_throwing = false
	_throw_charge = 0.0
	_move_finger = -1
	_look_finger = -1
	_button_fingers.clear()
	_stick = Vector2.ZERO
	for action in ACTIONS:
		if InputMap.has_action(action): Input.action_release(action)
	queue_redraw()

func _process(_delta: float) -> void:
	if not gameplay_enabled or not is_instance_valid(player): return
	_throw_charge = player.get_charge()
	_hint = "持物 %.2fm · 按住蓄力，松开投出" % player.held_distance if is_instance_valid(player.held) else "左侧移动 · 推满奔跑 · 右侧滑动视角"
	queue_redraw()

func _draw() -> void:
	if not gameplay_enabled: return
	var font := get_theme_font("font")
	draw_circle(_origin, _radius, BG)
	draw_arc(_origin, _radius, 0, TAU, 48, Color(FG, 0.35), 1.5, true)
	draw_circle(_origin + _stick * _radius * 0.65, _radius * 0.34, Color(FG, 0.40))
	var labels := {"menu":"MENU", "jump":"跳跃", "grab":"放下" if is_instance_valid(player) and is_instance_valid(player.held) else "拿起", "throw":"投掷", "interact":"扶梯", "splash":"拍水", "near":"拉近", "far":"推远"}
	for action: String in _buttons:
		var box: Rect2 = _buttons[action]
		var active: bool = action in _button_fingers.values()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.17, 0.38, 0.38, 0.75) if active else BG
		style.border_color = Color(FG, 0.30)
		style.set_border_width_all(1)
		style.set_corner_radius_all(20)
		draw_style_box(style, box)
		var label: String = labels[action]
		var measured := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
		draw_string(font, box.get_center() + Vector2(-measured.x * 0.5, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, FG)
		if action == "throw" and _throw_charge > 0.0:
			draw_line(box.position + Vector2(8, box.size.y - 8), box.position + Vector2(8 + (box.size.x - 16) * _throw_charge, box.size.y - 8), Color(0.35, 0.95, 0.77), 4)
	draw_string(font, Vector2(_safe.position.x + 235, _safe.end.y - 9), _hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(FG, 0.75))
