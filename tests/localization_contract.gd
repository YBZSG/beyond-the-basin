extends SceneTree

class InterfaceHost extends "res://scripts/main.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var checks := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var localization := root.get_node("Localization")
	var saved_locale := TranslationServer.get_locale()
	check(localization.select_locale("en") == OK, "English preference saves")
	var config := ConfigFile.new()
	check(config.load(localization.SETTINGS_PATH) == OK and config.get_value("language", "locale") == "en", "English preference persists")
	var catalogue: Translation = load("res://assets/translations/en.po")
	for message: String in catalogue.get_message_list():
		check(not catalogue.get_message(message).is_empty(), "Translation exists for " + message)
	check(TranslationServer.translate("进入主线") == "Enter campaign", "Campaign button translates")
	check(TranslationServer.translate("浅水深井") == "Glasswell Bath", "Map title translates")
	var objectives = load("res://scripts/campaign/campaign_objectives.gd")
	check(objectives.feedback(1, objectives.initial(1)).contains("Pressures"), "Interpolated mechanics translate")
	var preparation = load("res://scripts/diagnostics/preparation_status.gd")
	check(preparation.describe({"stage":"collecting_geometry", "rooms_collected":1, "rooms_total":3, "elapsed_ms":4000}).contains("rooms"), "Composed loading status translates")
	check(localization.select_locale("zh_CN") == OK, "Chinese preference saves")
	check(TranslationServer.translate("进入主线") == "进入主线", "Switches back to Chinese")
	for id: String in ["hanging_hand", "aquarium_atrium", "inverted_pool", "sluice_courtyard", "crossing_channels"]:
		var scene = load("res://scripts/dreamcore/scenes/" + id + ".gd")
		check(is_equal_approx(float(scene.layout(Vector2i.ZERO).water_floor_y), -.13), id + " has the new pool floor")
		check(scene.pool_steps().size() == (2 if id == "crossing_channels" else 4), id + " has the delivered real steps")
	var host := InterfaceHost.new()
	root.add_child(host)
	host._setup_inputs()
	host.menu_open = false
	var event := InputEventAction.new()
	event.action = "show_hints"
	event.pressed = true
	host._input(event)
	check(host._hints_held, "Tab hints work without unified interactions")
	host.free()
	print("LOCALIZATION_CONTRACT ", JSON.stringify({"checks":checks,"failures":failures,"previous_locale":saved_locale}))
	quit(0 if failures.is_empty() else 1)
