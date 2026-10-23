extends SceneTree
## CPU-only interaction/identity/persistence checks over actual production controls.
const Presentation = preload("res://scripts/ui/pool_interface_presentation.gd")
const Graphics = preload("res://scripts/rendering/desktop_quality_panel.gd")
const Settings = preload("res://scripts/water/source_port/source_water_settings.gd")
class Host extends "res://scripts/main.gd":
	var regenerate_requests: Array = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func regenerate(seed_value: int) -> void: regenerate_requests.append(seed_value)
class WaterSpy extends Node3D:
	var calls: Array = []
	var planar: Node
	var terrain_ready := true
	var settings := {}
	func set_quality(value: String) -> void: calls.append(["quality", value])
	func set_tuning(key: String, value: Variant) -> void: calls.append(["tuning", key, value])
	func set_caustics(value: bool) -> void: calls.append(["caustics", value])
	func set_paused(value: bool) -> void: calls.append(["paused", value])
	func set_enabled(value: bool) -> void: calls.append(["enabled", value])
	func is_terrain_ready() -> bool: return terrain_ready
class NotebookWorld extends Node3D:
	var seed_value := 250821
	var formal_mode := false
	var expanded_mode := false
	var current_room := Vector2i.ZERO
	var names := ["迎宾浅水池", "静谧长廊池", "高窗水光大厅", "深蓝回声泳池", "更衣淋浴过渡区", "圆顶休息水域", "玻璃天窗展廊", "暖光阶梯静室"]
	func get_room_coord(_position: Vector3) -> Vector2i: return current_room
	func is_room_ready(_coord: Vector2i) -> bool: return true
	func get_layout(coord: Vector2i) -> Dictionary:
		return {"coord":coord, "seed":str(seed_value), "variant":coord.x, "name":names[coord.x]}
class AudioSpy extends Node3D:
	func set_enabled(_value: bool) -> void: pass
	func set_ambience(_value: bool) -> void: pass
	func set_active(_value: bool) -> void: pass
var errors: Array[String] = []
var checks := 0
var details: Array = []
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, description: String) -> void:
	checks += 1
	if not value: errors.append(description)
func _settle() -> void:
	for frame: int in 8: await process_frame
func _select(option: OptionButton, index: int) -> void:
	option.select(index); option.item_selected.emit(index)
func _run() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("This contract is CPU-only."); quit(2); return
	var isolated := OS.get_environment("APPDATA") if OS.get_name() == "Windows" else OS.get_environment("XDG_DATA_HOME")
	if not isolated.contains("poolcore-ui-contract-") or not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated.replace("\\", "/")):
		push_error("Use isolated XDG_DATA_HOME containing poolcore-ui-contract-."); quit(2); return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var config := ConfigFile.new()
	config.set_value("future", "sentinel", {"preserve":true})
	config.set_value("water", "settings", {"windStrength":0.31, "futureWater":72})
	_check(config.save("user://settings.cfg") == OK, "Isolated fixture saves")
	var host := Host.new()
	root.add_child(host)
	host._setup_inputs()
	host._load_settings()
	host._exploration_notes = preload("res://scripts/gameplay/exploration_notes.gd").new()
	host.add_child(host._exploration_notes)
	host._exploration_notes.initialize_store(true, "user://ui-fixture-notebook.json")
	host._exploration_notes.begin_world(host.world_seed, host._spawn_mode)
	var notebook_world := NotebookWorld.new()
	host.add_child(notebook_world)
	for index: int in 8:
		notebook_world.current_room = Vector2i(index,0)
		_check(host._exploration_notes.observe_player_room(notebook_world, Vector3(index * 32, 1, 0)), "Populated notebook observation " + str(index))
	host._build_interface()
	host._destination.add_item("迎宾池 / ARRIVAL POOL")
	var spy := WaterSpy.new()
	host.add_child(spy); host.water = spy
	host.pool_audio = AudioSpy.new(); host.add_child(host.pool_audio)
	var graphics := Graphics.install(host, "user://graphics.cfg")
	var before: Dictionary = {}
	for control: Control in host._menu.get_parent().find_children("*", "Control", true, false):
		if control is BaseButton or control is HSlider or control is LineEdit:
			before[control.get_instance_id()] = control
	var presentation := Presentation.install(host)
	_check(Presentation.install(host) == presentation, "Install is idempotent")
	_check(host._menu.find_child("ExplorationNotesSummary", true, false) != null, "Production exploration notebook summary is retained")
	_check(host._exploration_notes.get_summary().recorded_coordinates == 8, "Notebook has actual populated records")
	_check(host._exploration_notes._menu_summary.text.contains("+2"), "Notebook exercises six-name wrapping and additional-room summary")
	await _settle()
	for id: int in before:
		_check(is_instance_valid(before[id]) and before[id].is_inside_tree(), "Original interactive control survives: " + str(id))
	_check(before.size() >= 75, "Contract captured all water/main/graphics controls")
	for field: Control in [host._spawn_select, host._destination, host._seed_edit]:
		var action := field.get_parent().get_child(1) as Button
		_check(action.size.x >= 54, "Field action is not an empty sliver: " + action.text)
		_check(action.size.x >= action.get_theme_font("font").get_string_size(action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, action.get_theme_font_size("font_size")).x + 18, "Field action text fits: " + action.text)
	_check((host._menu.get_child(0) as ScrollContainer).scroll_vertical == 0, "Opening menu retains visible brand header")
	for resolution: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080)]:
		root.content_scale_size = resolution
		await _settle()
		for panel: Control in [host._menu, host._advanced, graphics._panel]:
			host._menu.visible = panel == host._menu
			host._advanced.visible = panel == host._advanced
			graphics._panel.visible = panel == graphics._panel
			await _settle()
			presentation.refresh_layout()
			await _settle()
			_check(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(panel.get_global_rect()), "Panel fits " + str(resolution) + ": " + str(panel.name))
			var scroll := panel.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
			var content := scroll.get_child(0) as Control
			_check(content.size.x <= scroll.size.x + 0.5, "Scroll content width stays inside " + str(panel.name))
			_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "No hidden horizontal scrolling")
			var footer := panel.find_child("PinnedBackAndSave", true, false) as Control
			if footer: _check(panel.get_global_rect().encloses(footer.get_global_rect()), "Pinned Back/save footer stays visible")
			for child: Node in panel.find_children("*", "Control", true, false):
				# 4.8 adds hidden popup search fields outside the active page.
				if not child.is_visible_in_tree(): continue
				if child is HSlider or child is LineEdit or child is BaseButton:
					var rect: Rect2 = child.get_global_rect()
					_check(rect.position.x >= scroll.global_position.x - 1 and rect.end.x <= panel.get_global_rect().end.x - 12, "Control is not horizontally clipped: " + str(child.name))
			if panel == host._menu:
				scroll.scroll_vertical = 100000
				await _settle()
				var footer_row := content.get_child(content.get_child_count() - 1) as Control
				_check(scroll.get_global_rect().encloses(footer_row.get_global_rect()), "Main footer remains fully reachable with notebook summary")
				scroll.scroll_vertical = 0
			if panel == graphics._panel:
				scroll.scroll_vertical = 100000
				await _settle()
				_check(scroll.get_global_rect().encloses(graphics._options.caustic_interval.get_global_rect()), "Last graphics option remains reachable above footer")
				var last_graphics := content.get_child(content.get_child_count() - 1) as Control
				_check(last_graphics.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1, "Last graphics status is reachable above footer")
				scroll.scroll_vertical = 0
			if panel == host._advanced:
				scroll.scroll_vertical = 0
				await _settle()
				var top_cards := content.get_child(0) as Control
				_check(top_cards.get_global_rect().position.y >= scroll.get_global_rect().position.y - 0.5, "Water section headings are visible at scroll origin")
				for key: String in Settings.WIND_KEYS:
					_check(scroll.get_global_rect().encloses(host._wind_controls[key].get_global_rect()), "Wind visible without scrolling at " + str(resolution) + ": " + key)
				scroll.scroll_vertical = 100000
				await _settle()
				var last := content.get_child(content.get_child_count()-1) as Control
				_check(last.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1, "Last water section can scroll fully into view")
				scroll.scroll_vertical = 0
			details.append({"resolution":str(resolution), "panel":str(panel.name), "rect":str(panel.get_global_rect()), "content_width":content.size.x, "scroll_width":scroll.size.x})
	# Production canvas-items scaling: unchanged 1280x720 logical UI at 1.5x.
	root.content_scale_size = Vector2i(1920,1080)
	var ui: Control = host._menu.get_parent()
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1280,720)
	host._overlay.transform = Transform2D(0, Vector2.ZERO).scaled(Vector2(1.5,1.5))
	await _settle()
	presentation.refresh_layout(); await _settle()
	for panel: Control in [host._menu, host._advanced, graphics._panel]:
		var scaled_rect := Rect2(panel.get_global_rect().position * 1.5, panel.get_global_rect().size * 1.5)
		_check(Rect2(0,0,1920,1080).encloses(scaled_rect), "Production 150% canvas scaling stays inside 1080p: " + str(panel.name))
	host._overlay.transform = Transform2D.IDENTITY
	root.content_scale_size = Vector2i(1280,720)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle()
	# Real callbacks still invoke guarded runtime APIs, then save full actual config.
	host._menu.hide(); graphics._panel.hide(); host._advanced.show()
	await _settle()
	host._wind_controls.windStrength.value = 0.67
	host._wind_controls.windDirection.value = 248
	host._wind_controls.windDensity.value = 1.75
	_check(host._wind_controls.windDirection.get_parent().get_node("NumericValue").text == "248", "Existing numeric readout tracks slider")
	var saved := ConfigFile.new(); _check(saved.load("user://settings.cfg") == OK, "Actual saved settings reload")
	var water_saved: Dictionary = saved.get_value("water", "settings", {})
	_check(water_saved.futureWater == 72 and saved.get_value("future", "sentinel") == {"preserve":true}, "Unknown settings preserved")
	_check(water_saved.windDirection == 248, "Wind changes persisted")
	for key: String in ["dlss", "frame_generation", "raytracing"]:
		_check(graphics._options.has(key) or graphics._checks.has(key), "New rendering control retained: " + key)
	var graphics_before: Dictionary = graphics.settings.duplicate(true)
	host._reset_wind_settings()
	_check(host._water_settings.windDirection == Settings.DEFAULT.windDirection and host._water_settings.futureWater == 72, "Wind reset preserves unrelated settings")
	_check(graphics.settings == graphics_before, "Wind reset does not change graphics")
	host._retiring_world = true
	spy.calls.clear()
	host._wind_controls.windStrength.value = 0.41
	_check(spy.calls.is_empty(), "Retirement guard still blocks live callbacks")
	host._retiring_world = false
	graphics._scale.value = 115
	_select(graphics._options.msaa, 3)
	_select(graphics._options.shadow_size, 1)
	var saved_graphics := ConfigFile.new()
	_check(saved_graphics.load("user://graphics.cfg") == OK, "Graphics config reloads")
	_check(saved_graphics.get_value("graphics", "scale") == 1.15 and saved_graphics.get_value("graphics", "msaa") == 3 and saved_graphics.get_value("graphics", "shadow_size") == 2048, "Graphics callbacks and independent persistence retained")
	# Seed validation remains an actual host callback, including signed 64-bit range.
	host._booted = true
	host._seed_edit.text = "bad.seed"
	host._rebuild_seed_world()
	_check(host.regenerate_requests.is_empty() and host._seed_input_status.visible, "Invalid seed cannot rebuild")
	host._seed_edit.text = "9223372036854775808"
	host._rebuild_seed_world()
	_check(host.regenerate_requests.is_empty(), "Seed overflow cannot rebuild")
	host._seed_edit.text = "-4231"
	host._rebuild_seed_world()
	_check(host.regenerate_requests == [-4231], "Valid seed reaches original rebuild action")
	host._switching_spawn = true
	host._choose_spawn(2)
	_check(host.regenerate_requests.size() == 1, "Scene live-switch guard survives")
	host._switching_spawn = false
	_check(is_instance_valid(host._world_restart_button) and host._world_restart_button.pressed.is_connected(host._restart_into_selected_world), "Original restart-selected-world fallback callback remains")
	var existing_mode: String = host._spawn_mode
	var existing_seed: int = host.world_seed
	var rebuild_count: int = host.regenerate_requests.size()
	_select(host._spawn_select, 2)
	_check(host._spawn_mode == existing_mode and host.world_seed == existing_seed and host.regenerate_requests.size() == rebuild_count, "Pending world dropdown selection does not switch or regenerate")
	host._resume.pressed.emit(); await _settle()
	_check(not host.menu_open and not host._menu.visible and host._spawn_mode == existing_mode and host.world_seed == existing_seed and host.regenerate_requests.size() == rebuild_count, "Continue closes menu and keeps current world despite a different pending selection")
	host.set_menu(true)
	var spawn_action := host._spawn_select.get_parent().get_child(1) as Button
	spawn_action.pressed.emit(); await _settle()
	_check(host._spawn_mode == "expanded" and host.regenerate_requests.size() == rebuild_count + 1 and host.regenerate_requests.back() == -4231, "Only explicit 在此出生 applies selected world and validated seed")
	spy.terrain_ready = false
	host._resume.pressed.emit(); await _settle()
	_check(host.menu_open and host._menu.visible, "Continue cannot bypass water preparation guard")
	spy.terrain_ready = true
	# Water Esc/Back and reopen. Native event dispatch catches regression in routing.
	host._menu.hide(); host._advanced.show()
	await _settle()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE; event.physical_keycode = KEY_ESCAPE; event.pressed = true
	Input.parse_input_event(event)
	await _settle()
	_check(host._menu.visible and not host._advanced.visible and host.menu_open, "Esc from water returns to menu, not gameplay")
	var entry: Button = presentation.get("_water_entry")
	_check(root.gui_get_focus_owner() == entry, "Back restores focus to Water entry")
	entry.pressed.emit()
	await _settle()
	_check(host._advanced.visible and not host._menu.visible, "Water entry reopens same controls")
	var first := root.gui_get_focus_owner()
	_check(first != null and host._advanced.is_ancestor_of(first), "Reopened panel receives keyboard focus")
	var tab := InputEventKey.new(); tab.keycode = KEY_TAB; tab.physical_keycode = KEY_TAB; tab.pressed = true
	Input.parse_input_event(tab); await _settle()
	_check(root.gui_get_focus_owner() != first and host._advanced.is_ancestor_of(root.gui_get_focus_owner()), "Tab advances within visible panel")
	presentation.get("_water_back").pressed.emit(); await _settle()
	_check(host._menu.visible and not host._advanced.visible, "Pinned Back retains original navigation callback")
	graphics.open_panel(); await _settle(); graphics.close_panel(); await _settle()
	_check(host._menu.visible and not graphics._panel.visible, "Graphics open/close still works")
	host.set_menu(false); await _settle(); host.set_menu(true); await _settle()
	_check(host._menu.visible and not host._advanced.visible and not graphics._panel.visible, "Gameplay menu reopen resets nested panels")
	var result := {"passed":errors.is_empty(), "checks":checks, "errors":errors, "layouts":details, "original_controls":before.size(), "gpu_run":false, "scope":"Actual production controls, event routing and isolated persistence; mock world/water only"}
	print("POOL_UI_CONTRACT ", JSON.stringify(result))
	var output := "res://output/ui-refine/contract.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var report := FileAccess.open(output, FileAccess.WRITE)
	if report: report.store_string(JSON.stringify(result, "  "))
	host.free()
	quit(0 if errors.is_empty() else 1)
