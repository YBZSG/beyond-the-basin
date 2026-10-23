extends Node
## One opt-in integration point. The desktop build never instantiates this node.
const TouchControls = preload("res://scripts/mobile/pool_touch_controls.gd")
const Capabilities = preload("res://scripts/mobile/pool_mobile_capabilities.gd")
const MobileQuality = preload("res://scripts/mobile/pool_mobile_quality.gd")
var main: Node
var controls: Control
var quality: Node
var capabilities: RefCounted
var source_blocker := ""
var _check_elapsed := 0.0
var _warning: Label

static func is_mobile_session() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args()

static func install(host: Node) -> Node:
	if not is_mobile_session(): return null
	var runtime := load("res://scripts/mobile/pool_mobile_runtime.gd").new() as Node
	runtime.name = "MobileRuntime"
	host.add_child(runtime)
	runtime.configure(host)
	return runtime

func configure(host: Node) -> void:
	main = host
	get_tree().quit_on_go_back = false
	var layer := CanvasLayer.new()
	layer.name = "TouchInterface"
	layer.layer = 5
	add_child(layer)
	controls = TouchControls.new()
	layer.add_child(controls)
	controls.theme = (main.get("_menu") as Control).get_parent().theme
	controls.set_player(main.get("player"))
	controls.menu_requested.connect(open_menu)
	quality = MobileQuality.new()
	add_child(quality)
	quality.configure(main, controls)
	_warning = main.get("_renderer_warning") as Label
	if _warning:
		_warning.hide()
		_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_warning.size.x = 340
		_warning.custom_minimum_size.x = 340
	capabilities = Capabilities.new()
	capabilities.completed.connect(_capabilities_checked)
	capabilities.start()
	var menu := main.get("_menu") as Control
	for label in menu.find_children("*", "Label", true, false):
		if label.text.begins_with("POOLCORE ·"):
			label.text = "POOLCORE · ORIGINAL WATER · ANDROID\n原仓库场景 / 重做主池厅 / 原版水体 / 触屏"
		elif label.text.begins_with("WASD"):
			label.text = "左摇杆移动，推满奔跑 · 右侧滑动视角\n拿起后可单手瞄准，按住投掷蓄力\n跳跃 / 扶梯 / 拍水 / 拉近 / 推远 · MENU 暂停"
	# Existing main menu supports touch through Godot's mouse emulation.
	Input.emulate_mouse_from_touch = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.has_feature("android"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	print("POOLCORE_MOBILE_READY ", JSON.stringify({"quality":quality.preset,"renderer":RenderingServer.get_current_rendering_method(),"touch":true}))

func _process(delta: float) -> void:
	if not is_instance_valid(main): return
	if not bool(main.get("_booted")):
		controls.set_gameplay_enabled(false)
		set_process(false)
		return
	_check_elapsed += delta
	if _check_elapsed >= 0.5:
		_check_elapsed = 0.0
		var water: Node = main.get("water")
		var errors: Array[String] = []
		if is_instance_valid(water) and water.has_method("debug_stats"):
			errors = Capabilities.source_errors(water.debug_stats())
		for effect_name in ["source_fog", "distance_fog"]:
			var effect: Variant = main.get(effect_name)
			if effect != null and effect.has_method("debug_stats"):
				var info: Dictionary = effect.debug_stats()
				var error := str(info.get("error", ""))
				if not error.is_empty() and error not in errors: errors.append(error)
		if not errors.is_empty(): _block_source("\n".join(errors))
	if not source_blocker.is_empty():
		if not bool(main.get("menu_open")): main.set_menu(true)
		var resume := main.get("_resume") as Button
		if resume: resume.disabled = true
	var current_player: Variant = main.get("player")
	controls.set_player(current_player if is_instance_valid(current_player) and current_player is CharacterBody3D else null)
	controls.set_gameplay_enabled(not bool(main.get("menu_open")))
	Input.emulate_mouse_from_touch = bool(main.get("menu_open"))
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hint := main.get("_hint") as Label
	if hint: hint.visible = false

func _notification(what: int) -> void:
	if not is_instance_valid(main) or not bool(main.get("_booted")): return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		controls.release_all()
		open_menu()

func open_menu() -> void:
	if is_instance_valid(quality): quality.close_panel()
	main.set_menu(true)

func _capabilities_checked(report: Dictionary) -> void:
	print("POOLCORE_MOBILE_CAPABILITIES ", JSON.stringify(report))
	if not report.supported: _block_source("\n".join(report.errors))

func _block_source(reason: String) -> void:
	if source_blocker == reason: return
	source_blocker = reason
	controls.release_all()
	open_menu()
	if _warning:
		_warning.text = "原版水体无法运行 / ORIGINAL WATER UNAVAILABLE\n" + reason + "\n需要支持完整 Vulkan 计算/存储缓冲和纹理的设备；不会静默替换水体。"
		_warning.show()
	push_error("POOLCORE_MOBILE_SOURCE_BLOCKED: " + reason)
