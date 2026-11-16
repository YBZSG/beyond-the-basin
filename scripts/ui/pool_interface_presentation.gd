extends Node
## PC-only presentation over the existing live controls. No settings owner,
## callback replacement, runtime allocation, renderer effects or mobile changes.
const INK := Color("e6e6d9")
const MUTED := Color("a1aaa0")
const ACCENT := Color("c6d7ae")
const EDGE := Color("414b40")
var main: Node
var ui: Control
var _menu: PanelContainer
var _water: PanelContainer
var _graphics: PanelContainer
var _water_entry: Button
var _water_back: Button
var _main_body: BoxContainer
var _world_note: Label
var _backdrop: ColorRect
var _panels: Array[PanelContainer] = []
var _layout_pending := false
var _suppress_focus_scroll := false
var _home: VBoxContainer
var _settings_scroll: ScrollContainer
var _settings_back: Button

static func install(host: Node) -> Node:
	if OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args(): return null
	var existing := host.get_node_or_null("PoolInterfacePresentation")
	if existing: return existing
	var presentation := load("res://scripts/ui/pool_interface_presentation.gd").new() as Node
	presentation.name = "PoolInterfacePresentation"
	host.add_child(presentation)
	presentation.configure(host)
	return presentation

func configure(host: Node) -> void:
	main = host
	_menu = main.get("_menu") as PanelContainer
	_water = main.get("_advanced") as PanelContainer
	if not is_instance_valid(_menu) or not is_instance_valid(_water): return
	ui = _menu.get_parent() as Control
	var original_font := ui.theme.default_font
	ui.theme = _theme(original_font)
	_backdrop = ColorRect.new()
	_backdrop.name = "MenuAtmosphere"
	_backdrop.color = Color(0.008, 0.018, 0.012, 0.62)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_backdrop)
	ui.move_child(_backdrop, _menu.get_index())
	_style_existing(ui)
	_build_main_presentation()
	_build_water_presentation()
	var desktop := main.get_node_or_null("DesktopQuality")
	if desktop != null:
		_graphics = desktop.get("_panel") as PanelContainer
		_build_graphics_presentation()
	_build_home()
	for panel: PanelContainer in [_menu, _water, _graphics]:
		if not is_instance_valid(panel): continue
		_panels.append(panel)
		panel.add_theme_stylebox_override("panel", _box(Color("141b18"), EDGE, 3, 24))
		panel.visibility_changed.connect(_panel_visibility_changed.bind(panel))
		panel.minimum_size_changed.connect(_queue_layout)
	ui.resized.connect(refresh_layout)
	for key: String in ["_room_title", "_status", "_hint"]:
		var label := main.get(key) as Label
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", Color("cdd5bd"))
			label.add_theme_font_size_override("font_size", 13)
	refresh_layout()
	_panel_visibility_changed(_menu)

func _box(color: Color, edge: Color = EDGE, radius: int = 3, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style

func _theme(font: Font) -> Theme:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "LineEdit", "PopupMenu"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, INK)
		theme.set_color("font_disabled_color", type, Color("637d89"))
	var normal := _box(Color("243129"), Color("4a5849"), 7, 10)
	var hover := _box(Color("354839"), Color("9cae86"), 7, 10)
	var pressed := _box(Color("303f2b"), ACCENT, 7, 10)
	var disabled := _box(Color("1d2720"), Color("354235"), 7, 10)
	var focus := _box(Color(0,0,0,0), ACCENT, 8, 0)
	focus.set_border_width_all(2)
	for type: String in ["Button", "OptionButton"]:
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, {"normal":normal, "hover":hover, "pressed":pressed, "disabled":disabled, "focus":focus}[state])
		theme.set_constant("h_separation", type, 10)
	theme.set_stylebox("normal", "LineEdit", _box(Color("101a14"), EDGE, 7, 10))
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color("3d6775"))
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	var quiet := _box(Color(0,0,0,0), Color(0,0,0,0), 5, 4)
	for state: String in ["normal", "pressed", "disabled"]: theme.set_stylebox(state, "CheckButton", quiet)
	theme.set_stylebox("hover", "CheckButton", _box(Color("283a2c"), Color(0,0,0,0), 5, 4))
	theme.set_stylebox("hover_pressed", "CheckButton", _box(Color("283a2c"), Color(0,0,0,0), 5, 4))
	theme.set_stylebox("focus", "CheckButton", focus)
	theme.set_color("icon_normal_color", "CheckButton", ACCENT)
	theme.set_color("icon_hover_color", "CheckButton", Color("b8f2ee"))
	theme.set_color("icon_pressed_color", "CheckButton", ACCENT)
	var track := _box(Color("111c15"), Color("465642"), 3, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(Color("aabd91"), Color("aabd91"), 3, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	theme.set_color("grabber_color", "HSlider", ACCENT)
	theme.set_color("grabber_highlight_color", "HSlider", Color.WHITE)
	theme.set_color("grabber_disabled_color", "HSlider", Color("56727d"))
	var rail := _box(Color("1d2b20"), Color(0,0,0,0), 3, 0)
	rail.content_margin_left = 4
	rail.content_margin_right = 4
	var thumb := _box(Color("607657"), Color(0,0,0,0), 3, 0)
	thumb.content_margin_left = 4
	thumb.content_margin_right = 4
	for type: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, rail)
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]: theme.set_stylebox(state, type, thumb)
	theme.set_stylebox("panel", "PopupMenu", _box(Color("1f2c22"), EDGE, 8, 8))
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_constant("v_separation", "PopupMenu", 12)
	theme.set_stylebox("panel", "TooltipPanel", _box(Color("263329"), EDGE, 7, 10))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_font_size("font_size", "TooltipLabel", 14)
	theme.set_stylebox("separator", "HSeparator", _box(Color("42553e"), Color(0,0,0,0), 0, 0))
	return theme

func _style_existing(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child.name == "CameraViewfinder": continue
		if child is CheckButton:
			child.custom_minimum_size.y = 32
			child.add_theme_font_size_override("font_size", 14)
		elif child is Button:
			child.custom_minimum_size.y = 40
			child.add_theme_font_size_override("font_size", 15)
			child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if not child is OptionButton:
				child.custom_minimum_size.x = minf(220, child.get_theme_font("font").get_string_size(child.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 24)
			if child.tooltip_text.is_empty(): child.tooltip_text = child.text
		elif child is LineEdit: child.custom_minimum_size.y = 40
		elif child is HSlider:
			child.custom_minimum_size.y = 32
			child.focus_mode = Control.FOCUS_ALL
		elif child is Label:
			child.add_theme_color_override("font_color", INK)
			if child.has_theme_font_size_override("font_size") and child.get_theme_font_size("font_size") <= 13:
				child.add_theme_font_size_override("font_size", 13)
				child.add_theme_color_override("font_color", MUTED)
		if child is BoxContainer: child.add_theme_constant_override("separation", 10)
		_style_existing(child)

func _move(node: Node, parent: Node) -> void:
	if node.get_parent(): node.get_parent().remove_child(node)
	parent.add_child(node)

func _label(text: String, size: int = 14, color: Color = MUTED) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(Color("1b2720"), Color("3b4a3b"), 3, 18))
	parent.add_child(panel)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	panel.add_child(list)
	if not title.is_empty(): list.add_child(_label(title, 14, ACCENT))
	return list

func _build_main_presentation() -> void:
	var scroll := _menu.get_child(0) as ScrollContainer
	var column := scroll.get_child(0) as VBoxContainer
	var old := column.get_children()
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	column.add_theme_constant_override("separation", 16)
	var brand := old[0] as Label
	brand.add_theme_font_size_override("font_size", 30)
	var sub := old[1] as Label
	sub.text = "泳池之外   /   FIELD CAMERA     ·     待机 STANDBY"
	sub.add_theme_color_override("font_color", MUTED)
	for index: int in range(2, old.size()): column.remove_child(old[index])
	_main_body = BoxContainer.new()
	_main_body.name = "MenuSections"
	_main_body.add_theme_constant_override("separation", 18)
	column.add_child(_main_body)
	var world_card := _card(_main_body, "01   选择世界 / STARTING WORLD")
	var preference_card := _card(_main_body, "02   相机与探索 / CAMERA SETUP")
	preference_card.add_child(_label("镜头 / LENS", 13, ACCENT))
	_move(main.get("_looks"), preference_card)
	# Reuse the live, validated controls, not a second settings owner.
	for key: String in ["referenceHalation", "referenceFringePx", "referenceGrain", "referenceVignette"]:
		var slider := _water.find_child(key, true, false) as HSlider
		if slider != null:
			_move(slider.get_parent(), preference_card)
			slider.get_parent().get_child(0).custom_minimum_size.x = 130
	var waves := CheckButton.new()
	waves.name = "referenceWaves"
	waves.text = "大波纹 / 交错水面"
	waves.button_pressed = bool(main.get("_reference_settings").referenceWaves)
	waves.toggled.connect(func(value: bool): main._change_reference_setting("referenceWaves", value))
	preference_card.add_child(waves)
	preference_card.add_child(_label("关闭大波纹仍保留脚步与涉水涟漪。\nF 切换镜头 · 按住 Tab 查看提示，松开隐藏。", 13))
	var dream := main.get("_dream") as Node
	if is_instance_valid(dream):
		world_card.add_child(_label("新增地图 / DREAMCORE", 13, ACCENT))
		for field: String in ["_summary", "_selector", "_enter", "_relaxed", "_reduced", "_repair", "_recovery"]:
			var control := dream.get(field) as Control
			if is_instance_valid(control): _move(control, world_card)
	var campaign := main.get("_campaign") as Node
	if is_instance_valid(campaign):
		_move(campaign.get("_menu_summary"), world_card)
		_move(campaign.get("_continue"), world_card)
		for field in ["_relaxed_check", "_reduced_check", "_repair_button", "_retry_button", "_rebuild_button", "_recovery_button"]:
			_move(campaign.get(field), world_card)
	var spawn := main.get("_spawn_select") as OptionButton
	var spawn_row := spawn.get_parent()
	_move(spawn_row, world_card)
	spawn.custom_minimum_size.x = 0
	spawn.get_parent().get_child(1).text = "在此出生"
	_world_note = _label("")
	world_card.add_child(_world_note)
	spawn.item_selected.connect(_world_selection_changed)
	_world_selection_changed(spawn.selected)
	var resume := main.get("_resume") as Button
	_move(resume, world_card)
	resume.custom_minimum_size.y = 48
	resume.add_theme_stylebox_override("normal", _box(Color("46573b"), Color("a9bd90"), 8, 12))
	resume.add_theme_stylebox_override("hover", _box(Color("586e49"), ACCENT, 8, 12))
	_move(main.get("_loading_status"), world_card)
	world_card.add_child(_label("快速前往 / DESTINATION", 13))
	_move((main.get("_destination") as Control).get_parent(), world_card)
	world_card.add_child(_label("世界种子 / SEED", 13))
	_move((main.get("_seed_edit") as Control).get_parent(), world_card)
	_move(main.get("_seed_input_status"), world_card)
	var restart := main.get("_world_restart_button") as Button
	if is_instance_valid(restart):
		restart.text = "兼容方式：重启到所选世界"
		restart.add_theme_font_size_override("font_size", 13)
		_move(restart, world_card)
		_move(main.get("_world_restart_status"), world_card)
		_collapse_empty_status(main.get("_world_restart_status"))
	var preview := main.get("_pc_preview_check") as CheckButton
	if is_instance_valid(preview):
		preview.text = "实验主池厅烘焙 / PC PREVIEW"
		_move(preview, world_card)
		_move(main.get("_pc_preview_status"), world_card)
	var character := main.get("_character_select") as OptionButton
	if is_instance_valid(character):
		preference_card.add_child(_label("角色选择 / CHARACTER", 13, ACCENT))
		_move(character, preference_card)
		character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_move(main.get("_character_status"), preference_card)
		preference_card.add_child(_label("即时切换并自动保存；低头查看身体，抓取物品查看手部。", 13))
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	preference_card.add_child(navigation)
	var options := GridContainer.new()
	options.name = "ExplorationOptions"
	options.columns = 2
	options.add_theme_constant_override("h_separation", 14)
	options.add_theme_constant_override("v_separation", 4)
	preference_card.add_child(options)
	var labels := {"原生间接光 / SDFGI":"间接光 / SDFGI", "水下焦散 / CAUSTICS":"水下焦散", "显示角色身体 / PLAYER BODY":"角色身体", "衣物织纹 / CLOTH FINISH":"衣物织纹", "主厅设施互动 / QUIET VALVES":"设施互动", "深水步行减速 / DEPTH RESPONSE":"深水减速", "声音 / ORIGINAL SOUND EFFECTS":"声音效果", "空间底噪 / AMBIENCE":"空间底噪"}
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	for node: Node in old:
		if node.get_parent() != null or node.is_queued_for_deletion(): continue
		if node is CheckButton:
			if labels.has(node.text):
				if node.tooltip_text.is_empty(): node.tooltip_text = node.text
				node.text = labels[node.text]
				node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				options.add_child(node)
			else: preference_card.add_child(node)
		elif node is Button and node.name == "DesktopQualityButton":
			node.text = "画质 / GRAPHICS"
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			navigation.add_child(node)
		elif node is Button and node.text.contains("WATER"):
			_water_entry = node
			node.text = "水体 / WATER"
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			navigation.add_child(node)
		elif node is OptionButton:
			preference_card.add_child(node)
		elif node is Label and node.text.begins_with("WASD"):
			node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			node.text = "WASD 移动 · Shift 奔跑\nSpace 跳跃 / 水中上浮 · E 交互 · Q 阅读机关铭牌\n左键抓取 · 右键蓄力投掷 · 滚轮调距离\n按住 Tab 查看提示 · L 手电筒 · F 镜头\nH 隐藏取景界面 · G 诊断（Tab 查看） · F11 全屏 · Esc 暂停 / 返回"
			preference_card.add_child(node)
		elif node is Button and (node.text.contains("DIAGNOSTICS") or node.text.contains("QUIT")):
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			footer.add_child(node)
		elif node is Label and node.text.contains("STARTING WORLD"):
			# The same label remains present as an accessible section heading.
			node.text = "当前选择在点击「在此出生」后应用。"
			node.add_theme_font_size_override("font_size", 12)
			node.add_theme_color_override("font_color", MUTED)
			world_card.add_child(node)
		else: preference_card.add_child(node)
	preference_card.add_child(_label("镜头与水面设置独立保存。\n实验主池厅烘焙仅在本次运行生效。", 13, MUTED))
	column.add_child(footer)

func _build_home() -> void:
	# Reuse the real controls and callbacks; the homepage owns no game state.
	_settings_scroll = _menu.get_child(0) as ScrollContainer
	_menu.remove_child(_settings_scroll)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	_menu.add_child(shell)
	_home = VBoxContainer.new()
	_home.name = "HomePage"
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home.add_theme_constant_override("separation", 18)
	shell.add_child(_home)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	_home.add_child(header)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 3)
	header.add_child(identity)
	identity.add_child(_label("BEYOND THE BASIN", 28, INK))
	identity.add_child(_label("泳池之外  ·  选择旅程", 14, MUTED))
	var mark := _label("POOLCORE\nEXPLORATION", 12, ACCENT)
	mark.autowrap_mode = TextServer.AUTOWRAP_OFF
	mark.custom_minimum_size.x = 120
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(mark)
	var language_box := VBoxContainer.new()
	header.add_child(language_box)
	language_box.add_child(_label("语言 / Language", 12, MUTED))
	var language := OptionButton.new()
	language.name = "LanguageSelector"
	language.add_item("简体中文 / Simplified Chinese")
	language.add_item("English")
	language.select(0 if TranslationServer.get_locale().begins_with("zh") else 1)
	language.custom_minimum_size = Vector2(220, 40)
	language_box.add_child(language)
	var language_status := _label("", 12)
	language_status.hide()
	language_box.add_child(language_status)
	var localization := get_node("/root/Localization")
	language.item_selected.connect(func(index: int):
		var result: Error = localization.select_locale(localization.LOCALES[index])
		language_status.visible = result != OK
		if result != OK:
			language_status.text = tr("语言保存失败（%s）") % error_string(result)
			language.select(0 if TranslationServer.get_locale().begins_with("zh") else 1))
	localization.locale_changed.connect(_queue_layout)
	localization.locale_changed.connect(func(): language.select(0 if TranslationServer.get_locale().begins_with("zh") else 1))
	_home.add_child(HSeparator.new())
	var cards := HBoxContainer.new()
	cards.name = "HomeChoices"
	cards.add_theme_constant_override("separation", 16)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home.add_child(cards)
	var journey := _card(cards, "01   继续旅程")
	var campaign := main.get("_campaign") as Node
	if is_instance_valid(campaign):
		_move(campaign.get("_menu_summary"), journey)
		_move(campaign.get("_continue"), journey)
		(campaign.get("_continue") as Button).text = "进入主线"
	journey.add_child(HSeparator.new())
	journey.add_child(_label("当前场景", 13, ACCENT))
	_move(main.get("_resume"), journey)
	_move(main.get("_loading_status"), journey)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journey.add_child(spacer)
	journey.add_child(_label("进度自动保存 · Esc 返回菜单", 13))
	var maps := _card(cards, "02   选择地图")
	var dream := main.get("_dream") as Node
	if is_instance_valid(dream):
		_move(dream.get("_summary"), maps)
		var dream_row := HBoxContainer.new()
		dream_row.add_theme_constant_override("separation", 8)
		maps.add_child(dream_row)
		_move(dream.get("_selector"), dream_row)
		(dream.get("_selector") as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_move(dream.get("_enter"), dream_row)
		(dream.get("_enter") as Button).text = "进入"
		(dream.get("_enter") as Button).custom_minimum_size.x = 80
	maps.add_child(HSeparator.new())
	maps.add_child(_label("原有场景", 14, INK))
	var spawn := main.get("_spawn_select") as OptionButton
	var spawn_row := spawn.get_parent() as HBoxContainer
	_move(spawn_row, maps)
	(spawn_row.get_child(1) as Button).text = "进入"
	var caption := _label("选择场景后加载；设置中可更改种子。", 13)
	maps.add_child(caption)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	_home.add_child(foot)
	var settings := Button.new()
	settings.name = "OpenSettings"
	settings.text = "设置  /  SETTINGS"
	settings.custom_minimum_size = Vector2(180, 42)
	settings.pressed.connect(func(): _set_home_visible(false))
	foot.add_child(settings)
	var note := _label("镜头 · 水体 · 画质 · 声音", 13)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(note)
	_settings_back = Button.new()
	_settings_back.name = "SettingsBackToHome"
	_settings_back.text = "←  返回主页"
	_settings_back.custom_minimum_size.y = 40
	_settings_back.pressed.connect(func(): _set_home_visible(true))
	shell.add_child(_settings_back)
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(_settings_scroll)
	_set_home_visible(true)

func _set_home_visible(value: bool) -> void:
	if not is_instance_valid(_home): return
	_home.visible = value
	_settings_scroll.visible = not value
	_settings_back.visible = not value
	_queue_layout()
	if _menu.is_visible_in_tree(): _focus_panel.call_deferred(_menu)

func _collapse_empty_status(label: Label) -> void:
	label.visible = not label.text.is_empty()
	label.minimum_size_changed.connect(func(): label.visible = not label.text.is_empty())

func _world_selection_changed(index: int) -> void:
	if not is_instance_valid(_world_note): return
	var descriptions := ["原仓库场景\n保留原始房间与熟悉的水面交互。", "重做主池厅\n从宽阔的主池空间开始安静探索。", "扩展随机地图\n由世界种子生成更多相连的泳池空间。", "曲廊池区\n三处新池厅相连，外侧延续种子地图。", "五境参考场景\n阶厅、暗柱水厅、青窗水廊、八角池与球池休息室。"]
	_world_note.text = descriptions[clampi(index, 0, descriptions.size() - 1)]

func _panel_shell(panel: PanelContainer, scroll: ScrollContainer, title: Label, subtitle: String, back: Button) -> void:
	var shell := VBoxContainer.new()
	shell.name = "PanelShell"
	shell.add_theme_constant_override("separation", 14)
	panel.remove_child(scroll)
	panel.add_child(shell)
	_move(title, shell)
	title.add_theme_font_size_override("font_size", 26)
	shell.add_child(_label(subtitle, 13))
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	shell.add_child(scroll)
	var footer := HBoxContainer.new()
	footer.name = "PinnedBackAndSave"
	footer.add_theme_constant_override("separation", 18)
	shell.add_child(footer)
	_move(back, footer)
	back.custom_minimum_size.x = 146
	var note := _label("更改会自动保存 · Esc 返回\n无需额外点击应用", 13)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(note)

func _build_water_presentation() -> void:
	var scroll := _water.get_child(0) as ScrollContainer
	var list := scroll.get_child(0) as VBoxContainer
	var old := list.get_children()
	var title := old[0] as Label
	for node: Node in old:
		if node is Button and node.text == "返回 / BACK": _water_back = node
	_panel_shell(_water, scroll, title, "WATER & LAYERS   /   光学、交互与表面细节分别调节", _water_back)
	for node: Node in old:
		if node.get_parent() == list: list.remove_child(node)
	list.add_theme_constant_override("separation", 14)
	var reference := _card(list, "大波纹 / CROSS WAVES")
	reference.add_child(_label("与镜头滤镜独立；关闭后仍可踩出小涟漪。", 13))
	for node: Node in old:
		if node.name in ["ReferenceHeading", "ReferenceNote", "referenceLook"]:
			node.queue_free()
		elif node.name == "referenceWaves" or (node is HBoxContainer and node.find_child("referenceWave*", false, false) != null):
			_move(node, reference)
	var wind := _card(list, "室内风纹 / WIND")
	for key: String in ["windWaves", "windStrength", "windDirection", "windDensity"]:
		if not main.get("_wind_controls").has(key): continue
		var control: Control = main.get("_wind_controls")[key]
		_move(control if control is CheckButton else control.get_parent(), wind)
	for node: Node in old:
		if node.name == "WindOpticsNote" or node.name == "ResetWind": _move(node, wind)
	var groups := {
		"波浪与交互 / WAVES & INTERACTION":["waveHeight","waveSpeed","damping","viscosity","wallLoss","impact","ringWaves","wavePush","solverSteps","rippleSteps"],
		"表面与光学 / SURFACE & OPTICS":["rippleGain","rippleFrequency","microStrength","environmentalStrength","normalBoost","distortion","refractionStrength","fresnelStrength","absorptionStrength"],
		"焦散与浮沫 / CAUSTICS & FOAM":["causticsIntensity","causticsScale","causticsSpeed","causticsRefresh","foamStrength","foamLife","spray"]}
	for heading: String in groups:
		var section := _card(list, heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 4)
		section.add_child(grid)
		for key: String in groups[heading]:
			for node: Node in old:
				if node is HBoxContainer and node.find_child("Water_" + key, false, false) != null:
					_move(node, grid)
					node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var layers := _card(list, "图层与诊断 / LAYERS & DEBUG")
	var checks := GridContainer.new()
	checks.columns = 2
	checks.add_theme_constant_override("h_separation", 24)
	checks.add_theme_constant_override("v_separation", 4)
	layers.add_child(checks)
	for node: Node in old:
		if node.get_parent() != null or node.is_queued_for_deletion(): continue
		if node is CheckButton:
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			checks.add_child(node)
		elif node is HSeparator: layers.add_child(node)
		else: layers.add_child(node)
	for slider: HSlider in _water.find_children("*", "HSlider", true, false):
		var row := slider.get_parent() as HBoxContainer
		row.add_theme_constant_override("separation", 10)
		var label := row.get_child(0) as Label
		label.custom_minimum_size.x = 128
		label.add_theme_font_size_override("font_size", 14)
		var numeric := row.get_node_or_null("NumericValue") as Label
		if numeric != null:
			numeric.custom_minimum_size.x = 60
			numeric.add_theme_font_size_override("font_size", 14)
			numeric.add_theme_color_override("font_color", ACCENT)
		slider.custom_minimum_size.x = 90
	_water_back.pressed.connect(_restore_water_entry_focus)

func _build_graphics_presentation() -> void:
	var scroll := _graphics.get_child(0) as ScrollContainer
	var list := scroll.get_child(0) as VBoxContainer
	var title := list.get_child(0) as Label
	var back: Button
	for node: Node in list.get_children():
		if node is Button and node.text == "返回 / BACK": back = node
	_panel_shell(_graphics, scroll, title, "PC GRAPHICS   /   预设是起点，每项设置均可独立调整", back)
	list.add_theme_constant_override("separation", 12)
	for label: Label in list.find_children("*", "Label", true, false):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
	var summary := main.get_node("DesktopQuality").get("_summary") as Label
	summary.add_theme_color_override("font_color", ACCENT)

func _queue_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	_refresh_deferred.call_deferred()

func _refresh_deferred() -> void:
	_layout_pending = false
	refresh_layout()

func refresh_layout() -> void:
	if not is_instance_valid(ui): return
	var available := ui.size
	if available.x < 1 or available.y < 1: available = get_viewport().get_visible_rect().size
	var width := minf(1040.0, maxf(580.0, available.x - 48.0))
	var height := minf(760.0, maxf(360.0, available.y - 48.0))
	for panel: PanelContainer in _panels:
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.custom_minimum_size = Vector2.ZERO
		panel.size = Vector2(width if panel != _graphics else minf(width, 860), height)
		panel.position = (available - panel.size) * 0.5
	if is_instance_valid(_main_body): _main_body.vertical = width < 800
	_backdrop.visible = _menu.visible or _water.visible or (is_instance_valid(_graphics) and _graphics.visible)

func _panel_visibility_changed(panel: PanelContainer) -> void:
	refresh_layout()
	if panel.visible:
		if panel == _menu and is_instance_valid(_home): _set_home_visible(true)
		_focus_panel.call_deferred(panel)

func _focus_panel(panel: PanelContainer) -> void:
	if not is_instance_valid(panel) or not panel.is_visible_in_tree(): return
	var controls: Array[Control] = []
	for node: Node in panel.find_children("*", "Control", true, false):
		if not node.is_visible_in_tree() or node.focus_mode != Control.FOCUS_ALL: continue
		if node is BaseButton and node.disabled: continue
		if node is ScrollBar: continue
		controls.append(node)
		if not node.has_meta("pool_focus_scroll"):
			node.set_meta("pool_focus_scroll", true)
			node.focus_entered.connect(_keep_focus_visible.bind(node))
	for index: int in controls.size():
		controls[index].focus_next = controls[index].get_path_to(controls[(index + 1) % controls.size()])
		controls[index].focus_previous = controls[index].get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
	# A newly opened page starts at its heading. Skip focus scrolling until the
	# first container layout has settled; subsequent keyboard traversal reveals
	# only controls that actually fall outside the current scroll viewport.
	_suppress_focus_scroll = true
	if not controls.is_empty(): controls[0].grab_focus()
	_suppress_focus_scroll = false
	for scroll: ScrollContainer in panel.find_children("*", "ScrollContainer", true, false):
		scroll.scroll_vertical = 0

func _keep_focus_visible(control: Control) -> void:
	if _suppress_focus_scroll: return
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			var bounds: Rect2 = parent.get_global_rect()
			var item := control.get_global_rect()
			if item.position.y < bounds.position.y + 6:
				parent.scroll_vertical -= ceili(bounds.position.y + 6 - item.position.y)
			elif item.end.y > bounds.end.y - 6:
				parent.scroll_vertical += ceili(item.end.y - bounds.end.y + 6)
			return
		parent = parent.get_parent()

func _restore_water_entry_focus() -> void:
	if is_instance_valid(_water_entry): _water_entry.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and is_instance_valid(_menu) and _menu.visible and is_instance_valid(_home) and not _home.visible:
		_set_home_visible(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and is_instance_valid(_water) and _water.visible:
		_water_back.pressed.emit()
		get_viewport().set_input_as_handled()
