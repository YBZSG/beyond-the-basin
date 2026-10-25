extends SceneTree
const Preferences = preload("res://scripts/player/character_preferences.gd")
var failures: Array[String] = []

func expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	var path := "user://character_preferences_contract.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	expect(Preferences.load_character(path) == "original", "Missing preference defaults to original")
	expect(Preferences.save_character("ithappy", path) == OK, "New preference saved")
	expect(Preferences.load_character(path) == "ithappy", "Preference survives reload")
	for id: String in ["original", "ithappy", "original", "ithappy"]:
		expect(Preferences.save_character(id, path) == OK, "Repeated replacement saved: " + id)
		expect(Preferences.load_character(path) == id, "Repeated replacement read: " + id)
	expect(Preferences.save_character("unknown", path) == ERR_INVALID_PARAMETER, "Unknown ID rejected")
	expect(Preferences.load_character(path) == "ithappy", "Rejected ID leaves prior preference intact")
	var config := ConfigFile.new()
	config.set_value("character", "selected", "unknown")
	config.save(path)
	expect(Preferences.load_character(path) == "original", "Unknown stored value defaults to original")
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("[broken")
	broken.close()
	expect(Preferences.load_character(path) == "original", "Damaged file defaults to original")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("CHARACTER_PREFERENCES_CONTRACT ", JSON.stringify({"passed":failures.is_empty(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
