extends RefCounted
## Character preference is deliberately separate from campaign checkpoints and
## graphics settings. Unknown IDs and damaged/missing files fall back safely.
const SETTINGS_PATH := "user://character.cfg"
const IDS := ["original", "ithappy"]
const LABELS := ["角色：原版探索者 / ORIGINAL", "角色：ithappy 创意角色 / CREATIVE"]

static func sanitize(value: String) -> String:
	return value if value in IDS else "original"

static func load_character(path: String = SETTINGS_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK: return "original"
	return sanitize(str(config.get_value("character", "selected", "original")))

static func save_character(value: String, path: String = SETTINGS_PATH) -> Error:
	if value not in IDS: return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("character", "selected", value)
	var pending := path + ".pending"
	var result := config.save(pending)
	if result != OK: return result
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(pending), ProjectSettings.globalize_path(path))
