extends Node
## Android-only quality controls. Presets and overrides survive app restarts.
## No desktop settings file or project-wide renderer values are changed here.
const Profile := preload("res://scripts/mobile/pool_mobile_profile.gd")
const SETTINGS_PATH := "user://mobile_settings.cfg"
const PRESETS := {
	"Low": {"scale":0.67, "aa":0, "shadow_size":512, "shadows":false, "reflections":false, "water":"Low", "caustics_refresh":6},
	"Medium": {"scale":0.85, "aa":1, "shadow_size":1024, "shadows":true, "reflections":true, "water":"Medium", "caustics_refresh":4},
	"High": {"scale":1.0, "aa":2, "shadow_size":2048, "shadows":true, "reflections":true, "water":"High", "caustics_refresh":2},
	"Ultra": {"scale":1.25, "aa":2, "shadow_size":4096, "shadows":true, "reflections":true, "water":"Ultra", "caustics_refresh":1},
}
var preset := "High"
var resolution_scale := 1.0
var shadows := true
var reflections := true
var screen_aa := Viewport.SCREEN_SPACE_AA_SMAA
var touch_sensitivity := 1.0
var caustics_refresh := 2
var frame_cap := 30
var _window_size := Vector2i.ZERO
var main: Node
var _water: Node
var _panel: PanelContainer
var _quality: OptionButton
var _scale: HSlider
var _scale_label: Label
var _shadow_check: CheckButton
var _reflection_check: CheckButton
var _aa: OptionButton
var _notes: Label
var _controls: Control
var _refresh: OptionButton
var _cap: OptionButton
# Apply only changed resource groups: look/cap sliders must not recreate water,
# resize GPU shadow atlases, or walk the entire streamed scene. New nodes and
# replacement water/environment instances are still initialized explicitly.
var _applied: Dictionary = {}
var apply_counts: Dictionary = {}
const FRAME_CAPS := [30, 45, 60, 90, 120, 0]

func configure(host: Node, controls: Control) -> void:
	main = host
	_controls = controls
	load_settings()
	get_tree().node_added.connect(_node_added)
	_build_panel()
	apply_settings()

func load_settings(path: String = SETTINGS_PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	preset = str(config.get_value("graphics", "preset", "High"))
	if not PRESETS.has(preset): preset = "High"
	resolution_scale = clampf(float(config.get_value("graphics", "scale", PRESETS[preset].scale)), 0.5, 1.25)
	shadows = bool(config.get_value("graphics", "shadows", PRESETS[preset].shadows))
	reflections = bool(config.get_value("graphics", "reflections", PRESETS[preset].reflections))
	# Migrate old approximation-build MSAA settings to supported post AA.
	# Mobile cannot resolve main depth for source compositors with MSAA.
	var legacy_msaa := int(config.get_value("graphics", "msaa", PRESETS[preset].aa))
	var migrated_aa := 0 if legacy_msaa == 0 else (1 if legacy_msaa == 1 else 2)
	screen_aa = clampi(int(config.get_value("graphics", "screen_aa", migrated_aa)), 0, 2)
	caustics_refresh = clampi(int(config.get_value("graphics", "caustics_refresh", PRESETS[preset].caustics_refresh)), 0, 6)
	var saved_cap := int(config.get_value("graphics", "frame_cap", 30))
	frame_cap = saved_cap if saved_cap in FRAME_CAPS else 30
	touch_sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.4, 2.0)

func save_settings(path: String = SETTINGS_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("graphics", "preset", preset)
	config.set_value("graphics", "scale", resolution_scale)
	config.set_value("graphics", "shadows", shadows)
	config.set_value("graphics", "reflections", reflections)
	config.set_value("graphics", "screen_aa", screen_aa)
	config.set_value("controls", "sensitivity", touch_sensitivity)
	config.set_value("graphics", "caustics_refresh", caustics_refresh)
	config.set_value("graphics", "frame_cap", frame_cap)
	return config.save(path)

func select_preset(value: String) -> void:
	if not PRESETS.has(value): return
	preset = value
	var settings: Dictionary = PRESETS[value]
	resolution_scale = settings.scale
	shadows = settings.shadows
	reflections = settings.reflections
	screen_aa = settings.aa
	caustics_refresh = int(settings.caustics_refresh)
	apply_settings()
	save_settings()

func _changed(group: String, signature: Array) -> bool:
	if _applied.get(group, []) == signature: return false
	_applied[group] = signature.duplicate()
	apply_counts[group] = int(apply_counts.get(group, 0)) + 1
	return true

func apply_settings() -> void:
	if not is_instance_valid(main): return
	var viewport := main.get_viewport()
	var shadow_size := int(PRESETS[preset].shadow_size)
	_window_size = main.get_window().size
	var actual_scale := Profile.render_scale(_window_size, preset, resolution_scale)
	if _changed("viewport", [viewport.get_instance_id(), actual_scale, screen_aa]):
		# Main and reflection captures must share linear HDR scene units.
		viewport.use_hdr_2d = true
		viewport.scaling_3d_scale = actual_scale
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		# Mobile cannot resolve compositor main depth with MSAA. Source liquid
		# internal 4x MSAA is separate and remains unchanged.
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = screen_aa
		viewport.use_taa = false
	if _changed("shadow_atlas", [viewport.get_instance_id(), shadow_size]):
		viewport.positional_shadow_atlas_size = shadow_size
		RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	if _changed("frame_cap", [frame_cap]): Engine.max_fps = frame_cap
	if is_instance_valid(_controls): _controls.look_sensitivity = 0.0031 * touch_sensitivity
	_water = main.get("water")
	if is_instance_valid(_water):
		var water_id := _water.get_instance_id()
		var water_quality := str(PRESETS[preset].water)
		var quality_changed := _changed("water_quality", [water_id, water_quality])
		if quality_changed: _water.set_quality(water_quality)
		# Quality reconfiguration may reset defaults; reapply user overrides only
		# then, or when that override itself changed. Unrelated sliders do neither.
		var reflection_changed := _changed("water_reflection", [water_id, reflections])
		if quality_changed or reflection_changed: _water.set_tuning("reflection", reflections)
		var cadence_changed := _changed("water_cadence", [water_id, caustics_refresh])
		if quality_changed or cadence_changed: _water.set_tuning("causticsRefresh", float(caustics_refresh))
	var environment_node := main.get("environment") as WorldEnvironment
	if is_instance_valid(environment_node) and environment_node.environment:
		var environment := environment_node.environment
		var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
		var gi := bool(main.get("_gi_on"))
		if _changed("environment", [environment.get_instance_id(), forward, gi, preset, reflections]):
			environment.sdfgi_enabled = forward and gi
			environment.ssao_enabled = forward and preset != "Low"
			environment.ssil_enabled = forward and preset in ["High", "Ultra"]
			environment.ssr_enabled = forward and reflections
			if not forward: environment.volumetric_fog_enabled = false
			# Original raymarched shafts remain a separate Mobile compositor.
	if _changed("light_overrides", [main.get_instance_id(), shadows]):
		for node in main.find_children("*", "Light3D", true, false): _apply_light(node)
	if _changed("probe_overrides", [main.get_instance_id(), reflections]):
		for node in main.find_children("*", "ReflectionProbe", true, false): _apply_probe(node)
	_refresh_interface()

func _node_added(node: Node) -> void:
	if node is Light3D: call_deferred("_apply_light", node)
	elif node is ReflectionProbe: call_deferred("_apply_probe", node)

func _apply_light(node: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(main) or not main.is_ancestor_of(node): return
	if node.has_meta("source_shadow_managed"):
		node.set_meta("source_shadows_allowed",shadows);return
	if not node.has_meta("mobile_authored_shadow"):
		node.set_meta("mobile_authored_shadow", node.shadow_enabled)
	node.shadow_enabled = shadows and bool(node.get_meta("mobile_authored_shadow"))

func _apply_probe(node: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(main) or not main.is_ancestor_of(node): return
	node.visible = reflections

func _process(_delta: float) -> void:
	if not is_instance_valid(main): return
	if not bool(main.get("_booted")):
		set_process(false)
		return
	# Regenerate builds new water and calls desktop initialization. Reapply once.
	if main.get("water") != _water or main.get_window().size != _window_size: apply_settings()
	if _panel.visible and not bool(main.get("menu_open")): _panel.hide()

func _build_panel() -> void:
	var menu := main.get("_menu") as PanelContainer
	var root := menu.get_parent() as Control
	_panel = PanelContainer.new()
	_panel.name = "AndroidQualityPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-300, -285)
	_panel.custom_minimum_size = Vector2(600, 570)
	_panel.size = Vector2(600, 570)
	_panel.add_theme_stylebox_override("panel", menu.get_theme_stylebox("panel"))
	root.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 510)
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	var heading := Label.new()
	heading.text = "手机版画质 / MOBILE GRAPHICS"
	heading.add_theme_font_size_override("font_size", 23)
	column.add_child(heading)
	_quality = OptionButton.new()
	for name in PRESETS: _quality.add_item(name)
	_quality.custom_minimum_size.y = 48
	_quality.item_selected.connect(func(index: int): select_preset(_quality.get_item_text(index)))
	column.add_child(_quality)
	_scale_label = Label.new()
	column.add_child(_scale_label)
	_scale = HSlider.new()
	_scale.min_value = 50
	_scale.max_value = 125
	_scale.step = 5
	_scale.custom_minimum_size.y = 40
	_scale.value_changed.connect(func(value: float): resolution_scale=value/100.0; apply_settings(); save_settings())
	column.add_child(_scale)
	_shadow_check = _check(column, "实时阴影 / REAL-TIME SHADOWS", func(value: bool): shadows=value; apply_settings(); save_settings())
	_reflection_check = _check(column, "反射探针 + 原版平面倒影 / REFLECTIONS", func(value: bool): reflections=value; apply_settings(); save_settings())
	_aa = OptionButton.new()
	for label in ["后期抗锯齿：关闭 / OFF", "后期抗锯齿：FXAA", "后期抗锯齿：SMAA"]: _aa.add_item(label)
	_aa.custom_minimum_size.y = 48
	_aa.item_selected.connect(func(index: int): screen_aa=index; apply_settings(); save_settings())
	column.add_child(_aa)
	var refresh_label := Label.new()
	refresh_label.text = "动态焦散更新间隔 / CAUSTIC INTERVAL"
	column.add_child(refresh_label)
	_refresh = OptionButton.new()
	for interval in range(7): _refresh.add_item("每次更新 / EVERY FRAME" if interval == 0 else "间隔 %d 帧 / %d FRAMES" % [interval, interval])
	_refresh.custom_minimum_size.y = 48
	_refresh.item_selected.connect(func(index: int): caustics_refresh=index; apply_settings(); save_settings())
	column.add_child(_refresh)
	_cap = OptionButton.new()
	for cap in FRAME_CAPS: _cap.add_item("帧率上限 / CAP: %d" % cap if cap > 0 else "不限制帧率 / UNCAPPED")
	_cap.custom_minimum_size.y = 48
	_cap.item_selected.connect(func(index: int): frame_cap=FRAME_CAPS[index]; apply_settings(); save_settings())
	column.add_child(_cap)
	var sensitivity := Label.new()
	sensitivity.text = "视角灵敏度 / LOOK SENSITIVITY"
	column.add_child(sensitivity)
	var look := HSlider.new()
	look.min_value = 0.4
	look.max_value = 2.0
	look.step = 0.1
	look.value = touch_sensitivity
	look.custom_minimum_size.y = 40
	look.value_changed.connect(func(value: float): touch_sensitivity=value; apply_settings(); save_settings())
	column.add_child(look)
	_notes = Label.new()
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.custom_minimum_size.x = 500
	_notes.add_theme_font_size_override("font_size", 13)
	column.add_child(_notes)
	var back := Button.new()
	back.text = "返回 / BACK"
	back.custom_minimum_size.y = 48
	back.pressed.connect(func(): _panel.hide(); menu.show())
	column.add_child(back)
	_panel.hide()
	var menu_column := (main.get("_resume") as Button).get_parent()
	var open := Button.new()
	open.name = "AndroidQualityButton"
	open.text = "手机版画质 / MOBILE GRAPHICS"
	open.custom_minimum_size.y = 44
	open.pressed.connect(func(): menu.hide(); _panel.show(); _refresh_interface())
	menu_column.add_child(open)
	menu_column.move_child(open, 3)
	# Hide desktop-only duplicate controls rather than expose unsupported toggles.
	for option in menu.find_children("*", "OptionButton", true, false):
		if option.item_count > 0 and option.get_item_text(0).begins_with("High"):
			option.get_parent().hide()
	var gi := main.get("_gi_check") as CheckButton
	if gi and RenderingServer.get_current_rendering_method() != "forward_plus": gi.hide()

func _check(parent: Node, title: String, callback: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = title
	check.custom_minimum_size.y = 44
	check.toggled.connect(callback)
	parent.add_child(check)
	return check

func _refresh_interface() -> void:
	if not is_instance_valid(_quality): return
	_quality.select(PRESETS.keys().find(preset))
	_scale.set_value_no_signal(resolution_scale * 100.0)
	_scale_label.text = "3D 渲染比例 / RESOLUTION: %d%%" % roundi(resolution_scale * 100.0)
	_shadow_check.set_pressed_no_signal(shadows)
	_reflection_check.set_pressed_no_signal(reflections)
	_aa.select(screen_aa)
	_refresh.select(caustics_refresh)
	_cap.select(FRAME_CAPS.find(frame_cap))
	var renderer := RenderingServer.get_current_rendering_method()
	_notes.text = "渲染器：%s。保留动态水面、涟漪、折射、焦散和平面倒影；手机版已移除立体水花和飞溅粒子。高画质控制在最长边 1600、短边 900 像素以内，再应用上方比例。" % renderer
	if preset == "Low":
		_notes.text += "\nLow 保留主浅水，关闭细波、微法线、泡沫、焦散及倒影等外观层。"
	if renderer != "forward_plus":
		_notes.text += "\nMobile 不支持 Godot SDFGI、SSAO、SSIL、引擎 SSR、原生体积雾或 TAA。原仓库光束雾为独立光线步进效果，不是这些功能的冒牌替代。"
	_notes.text += "\n主画面使用 FXAA/SMAA，平面倒影使用 2×MSAA。默认 30 帧上限以减少持续发热，可自行改为 60；实际帧率取决于设备。"
	_notes.text += "\n画质自动保存。Ultra 增加显存、耗电和发热；真机兼容性与性能尚待验证。"

func close_panel() -> void:
	if is_instance_valid(_panel): _panel.hide()
