extends Node

signal locale_changed

const SETTINGS_PATH := "user://language.cfg"
const LOCALES := ["zh_CN", "en"]

func _ready() -> void:
	var config := ConfigFile.new()
	var locale := "zh_CN" if OS.get_locale_language() == "zh" else "en"
	if config.load(SETTINGS_PATH) == OK:
		var saved := str(config.get_value("language", "locale", locale))
		if saved in LOCALES: locale = saved
	TranslationServer.set_locale(locale)

func select_locale(locale: String) -> Error:
	var config := ConfigFile.new()
	config.set_value("language", "locale", locale)
	var result := config.save(SETTINGS_PATH + ".pending")
	if result == OK:
		result = DirAccess.rename_absolute(ProjectSettings.globalize_path(SETTINGS_PATH + ".pending"), ProjectSettings.globalize_path(SETTINGS_PATH))
	if result != OK: return result
	TranslationServer.set_locale(locale)
	locale_changed.emit()
	return OK
