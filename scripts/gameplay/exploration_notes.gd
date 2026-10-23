extends Node
## Optional, passive, menu-only notebook. No process/input hooks or distance counter.
## Instantiated by the PC menu integration; stores only local world discoveries.
const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://exploration_notes_v1.json"
const MODES := ["original", "formal", "expanded"]
const MAX_WORLDS := 24
const MAX_COORDS := 4096
const MAX_ARCHETYPES := 32
const MAX_COORD_COMPONENT := 1000000
const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_NAME_LENGTH := 96
const EXPANDED_MODULES := ["shower_changing", "low_arched_bath", "skylight_gallery", "service_transition"]
const FORMAL_COORDS := ["-1,-1", "0,-1", "-1,0", "0,-2", "-1,-2"]

var enabled := false
var storage_path := DEFAULT_PATH
var _configured := false
var _worlds: Dictionary = {}
var _active_key := ""
var _active_seed := ""
var _active_mode := ""
var _dirty := false
var _write_blocked := false
var _expected_fingerprint := ""
var _storage_note := ""
var _scope_note := ""
var _last_observation := ""
var _menu_summary: Label

static func world_key(seed_value: int, spawn_mode: String) -> String:
	return spawn_mode + ":" + str(seed_value) if spawn_mode in MODES else ""

func initialize_store(opt_in: bool = false, path: String = DEFAULT_PATH) -> Error:
	# Disabled means no disk access, no menu controls and no captured discoveries.
	if _configured: return ERR_ALREADY_IN_USE
	_configured = true
	enabled = opt_in
	storage_path = path
	if not enabled: return OK
	if path.is_empty() or not path.begins_with("user://"):
		return _block("Notebook path must be inside user://.", ERR_FILE_BAD_PATH)
	var relative_path := path.trim_prefix("user://")
	if "\\" in relative_path or ":" in relative_path:
		return _block("Notebook path is not a safe relative user path.", ERR_FILE_BAD_PATH)
	for component: String in relative_path.split("/"):
		if component in ["", ".", ".."]:
			return _block("Notebook path cannot leave its user directory.", ERR_FILE_BAD_PATH)
	if FileAccess.file_exists(path):
		var loaded := _read_document(path)
		if loaded.ok:
			_worlds = _index_document(loaded.document)
			_expected_fingerprint = str(loaded.text).sha256_text()
		else:
			_try_read_backup()
			return _block("Existing notebook was not changed: " + str(loaded.reason), ERR_FILE_CORRUPT)
	elif FileAccess.file_exists(path + ".bak"):
		_try_read_backup()
		return _block("Primary notebook is missing. Recovery copy is read-only; files were not changed.", ERR_FILE_CORRUPT)
	if FileAccess.file_exists(path + ".pending") or FileAccess.file_exists(path + ".backup_pending"):
		return _block("An interrupted save is preserved. Notebook is read-only until the saved copies are reviewed.", ERR_BUSY)
	if DirAccess.dir_exists_absolute(_absolute(path + ".lock")):
		_storage_note = "A save lock exists. Saving will be retried when the menu opens; a stale lock needs review."
	return OK

func begin_world(seed_value: int, spawn_mode: String) -> Error:
	if not enabled: return ERR_UNAVAILABLE
	_active_key = world_key(seed_value, spawn_mode)
	_active_seed = str(seed_value)
	_active_mode = spawn_mode
	_last_observation = ""
	_scope_note = ""
	if _active_key.is_empty():
		_scope_note = "Unknown world mode; no discoveries recorded."
		return ERR_INVALID_PARAMETER
	if not _worlds.has(_active_key):
		if _worlds.size() >= MAX_WORLDS:
			_scope_note = "Notebook has reached its 24-world limit. Existing records are retained; this world is not recorded."
			return ERR_OUT_OF_MEMORY
		# Merely selecting a world does not consume a notebook slot.
	return OK

func observe_player_room(world: Node, player_position: Vector3) -> bool:
	# Called by the host AFTER world.update_player_position, not by room_loaded or
	# room_changed: those signals can fire for streamed or not-yet-warped rooms.
	if not enabled or _active_key.is_empty() or not is_instance_valid(world): return false
	if not _worlds.has(_active_key) and _worlds.size() >= MAX_WORLDS: return false
	if not player_position.is_finite(): return false
	if absf(player_position.x) > MAX_COORD_COMPONENT * 32.0 or absf(player_position.z) > MAX_COORD_COMPONENT * 32.0: return false
	if not world.has_method("get_room_coord") or not world.has_method("get_layout") or not world.has_method("is_room_ready"): return false
	var actual_mode := "formal" if bool(world.get("formal_mode")) else ("expanded" if bool(world.get("expanded_mode")) else "original")
	if actual_mode != _active_mode or str(world.get("seed_value")) != _active_seed: return false
	var coord: Vector2i = world.call("get_room_coord", player_position)
	if coord != world.get("current_room") or not bool(world.call("is_room_ready", coord)): return false
	var coordinate := _coord_key(coord)
	if coordinate == _last_observation: return false
	var layout: Dictionary = world.call("get_layout", coord)
	if layout.get("coord") != coord or str(layout.get("seed")) != _active_seed: return false
	var archetype := _archetype(layout, _active_mode)
	if archetype.is_empty():
		_scope_note = "Unrecognized room layout; no invented discovery was recorded."
		return false
	if not _worlds.has(_active_key):
		_worlds[_active_key] = {"seed":_active_seed, "mode":_active_mode, "coords":[], "archetypes":[], "last":"", "coordinate_limit_reached":false}
	_last_observation = coordinate
	var record: Dictionary = _worlds[_active_key]
	var changed := false
	if not coordinate in record.coords:
		if record.coords.size() < MAX_COORDS:
			record.coords.append(coordinate)
			changed = true
		elif not record.coordinate_limit_reached:
			record.coordinate_limit_reached = true
			changed = true
	var found := false
	for entry: Dictionary in record.archetypes:
		if entry.id == archetype.id:
			found = true
			break
	if not found and record.archetypes.size() < MAX_ARCHETYPES:
		record.archetypes.append(archetype)
		changed = true
	if record.last != coordinate:
		record.last = coordinate
		changed = true
	_dirty = _dirty or changed
	return changed

static func _archetype(layout: Dictionary, mode: String) -> Dictionary:
	if not layout.get("variant") is int: return {}
	var variant: int = layout.variant
	var identity := ""
	if mode == "formal":
		if not bool(layout.get("formal", false)) or bool(layout.get("expanded", false)) or variant < 8 or variant > 12: return {}
		identity = "formal:" + str(variant)
	elif mode == "expanded" and bool(layout.get("expanded", false)):
		var module := str(layout.get("expanded_module", ""))
		if variant < 11 or variant > 14 or module != EXPANDED_MODULES[variant - 11]: return {}
		if bool(layout.get("formal", false)): return {}
		identity = "expanded:" + module
	else:
		if bool(layout.get("formal", false)) or bool(layout.get("expanded", false)) or variant < 0 or variant > 7: return {}
		if mode == "expanded" and not bool(layout.get("expanded_mode", false)): return {}
		if mode == "original" and bool(layout.get("expanded_mode", false)): return {}
		identity = "original:" + str(variant)
	var room_name: Variant = layout.get("name")
	if not _valid_name(room_name): return {}
	return {"id":identity, "name":room_name}

func get_summary() -> Dictionary:
	var record: Dictionary = _worlds.get(_active_key, {})
	return {"enabled":enabled, "seed":_active_seed, "mode":_active_mode,
		"recorded_coordinates":record.get("coords", []).size(),
		"archetypes":record.get("archetypes", []).duplicate(true), "last":record.get("last", ""),
		"coordinate_limit_reached":record.get("coordinate_limit_reached", false),
		"world_limit":MAX_WORLDS, "coordinate_limit":MAX_COORDS,
		"dirty":_dirty, "read_only":_write_blocked, "storage_note":_storage_note, "scope_note":_scope_note}

func get_snapshot() -> Dictionary:
	# Isolated copy for tests/export tooling; callers cannot mutate live records.
	return _document().duplicate(true)

func add_menu_summary(parent: Container) -> Label:
	# Inherits the host's existing fonts/theme. No overlay, input listener or HUD.
	if not enabled: return null
	if is_instance_valid(_menu_summary): return _menu_summary
	_menu_summary = Label.new()
	_menu_summary.name = "ExplorationNotesSummary"
	_menu_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_menu_summary)
	refresh_menu_summary()
	return _menu_summary

func refresh_menu_summary() -> void:
	if not is_instance_valid(_menu_summary): return
	var summary := get_summary()
	var names := PackedStringArray()
	for entry: Dictionary in summary.archetypes:
		if names.size() >= 6: break
		names.append(entry.name)
	var observed := "、".join(names) if not names.is_empty() else "尚未记录 / Nothing recorded yet"
	if summary.archetypes.size() > 6: observed += " · +%d" % (summary.archetypes.size() - 6)
	var text := "探索手记 / EXPLORATION NOTES\n%s · SEED %s\n已记录 %d 处 / Recorded places · %d 类房间 / Room types\n%s" % [_active_mode.to_upper(), _active_seed, summary.recorded_coordinates, summary.archetypes.size(), observed]
	if summary.coordinate_limit_reached: text += "\n已保留前 4096 处坐标 / First 4096 coordinates retained; further types can still be noted."
	if not _scope_note.is_empty(): text += "\n" + _scope_note
	if _write_blocked: text += "\n只读 / READ ONLY: new discoveries are session-only."
	elif _dirty: text += "\n尚未保存 / Not yet saved"
	elif _worlds.is_empty(): text += "\n尚无记录 / No saved discoveries yet"
	else: text += "\n已保存 / Saved"
	if not _storage_note.is_empty(): text += "\n" + _storage_note
	_menu_summary.text = text

func flush() -> Error:
	# Explicit menu/shutdown boundary only. No write on entry or per-frame timer.
	if not enabled or not _dirty: return OK
	if _write_blocked: return ERR_FILE_CANT_WRITE
	var directory := _absolute(storage_path.get_base_dir())
	var made := DirAccess.make_dir_recursive_absolute(directory)
	if made != OK: return _save_error("Notebook directory could not be created.", made)
	var lock_path := _absolute(storage_path + ".lock")
	var locked := DirAccess.make_dir_absolute(lock_path)
	if locked != OK: return _save_error("Notebook save lock is busy or unavailable; unsaved discoveries remain in this session.", locked)
	var result := _flush_locked()
	var released := DirAccess.remove_absolute(lock_path)
	if released != OK:
		_storage_note = "Save lock could not be removed; later saves require review."
	return result

func _flush_locked() -> Error:
	if FileAccess.file_exists(storage_path + ".pending") or FileAccess.file_exists(storage_path + ".backup_pending"):
		return _block("An interrupted save was preserved. Review saved copies before writing again.", ERR_BUSY)
	var previous := ""
	if FileAccess.file_exists(storage_path):
		var current := _read_document(storage_path)
		if not current.ok or str(current.text).sha256_text() != _expected_fingerprint:
			return _block("Notebook changed outside this session. Existing files were not overwritten.", ERR_BUSY)
		previous = current.text
	elif not _expected_fingerprint.is_empty():
		return _block("Notebook disappeared outside this session. No replacement was written.", ERR_BUSY)
	var text := JSON.stringify(_document()) + "\n"
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _save_error("Notebook exceeded the 4 MiB save bound; existing records were retained.", ERR_OUT_OF_MEMORY)
	var written := _write_verified_pending(storage_path + ".pending", text)
	if written != OK: return _block("Notebook save could not be verified; any partial copy was preserved.", written)
	if not previous.is_empty():
		written = _write_verified_pending(storage_path + ".backup_pending", previous)
		if written != OK: return _block("Recovery-copy write failed; primary notebook was not changed.", written)
		written = DirAccess.rename_absolute(_absolute(storage_path + ".backup_pending"), _absolute(storage_path + ".bak"))
		if written != OK: return _block("Recovery-copy rename failed; primary notebook was not changed.", written)
	written = DirAccess.rename_absolute(_absolute(storage_path + ".pending"), _absolute(storage_path))
	if written != OK: return _block("Atomic replacement failed; original and pending notebook were retained.", written)
	_expected_fingerprint = text.sha256_text()
	_dirty = false
	_storage_note = ""
	return OK

func _write_verified_pending(path: String, text: String) -> Error:
	if FileAccess.file_exists(path): return ERR_ALREADY_EXISTS
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var written := file.get_error()
	file.close()
	if written != OK: return written
	var check := _read_document(path)
	if not check.ok or check.text != text: return ERR_FILE_CORRUPT
	return OK

func _document() -> Dictionary:
	var records: Array = []
	var keys := _worlds.keys()
	keys.sort()
	for key: String in keys: records.append(_worlds[key])
	return {"schema_version":SCHEMA_VERSION, "worlds":records}

func _try_read_backup() -> void:
	if not FileAccess.file_exists(storage_path + ".bak"): return
	var recovered := _read_document(storage_path + ".bak")
	if recovered.ok:
		_worlds = _index_document(recovered.document)
		_storage_note = "Using valid recovery copy in read-only mode. "

func _block(message: String, code: Error) -> Error:
	_write_blocked = true
	_storage_note += message
	return code

func _save_error(message: String, code: Error) -> Error:
	_storage_note = message
	return code

static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)

static func _coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]

static func _valid_decimal(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(value.to_int()) == value

static func _valid_coordinate(value: Variant) -> bool:
	if not value is String: return false
	var components: PackedStringArray = value.split(",")
	if components.size() != 2: return false
	for component: String in components:
		if not _valid_decimal(component): return false
		var number := component.to_int()
		if number < -MAX_COORD_COMPONENT or number > MAX_COORD_COMPONENT: return false
	return true

static func _valid_name(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= MAX_NAME_LENGTH and not "\n" in value and not "\r" in value and not "\t" in value

static func _valid_archetype_id(identity: Variant, mode: String) -> bool:
	if not identity is String: return false
	if mode == "formal": return identity in ["formal:8", "formal:9", "formal:10", "formal:11", "formal:12"]
	if identity in ["original:0", "original:1", "original:2", "original:3", "original:4", "original:5", "original:6", "original:7"]: return true
	return mode == "expanded" and identity.begins_with("expanded:") and identity.trim_prefix("expanded:") in EXPANDED_MODULES

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key: String in expected:
		if not value.has(key): return false
	return true

static func validate_document(document: Variant) -> String:
	# Whole-document validation. Never silently drop a malformed record and save
	# the remainder over it. Future schemas remain untouched and read-only.
	if not document is Dictionary: return "root is not an object"
	if not _exact_keys(document, ["schema_version", "worlds"]): return "unexpected root fields"
	if not document.schema_version is float and not document.schema_version is int: return "invalid schema version"
	if document.schema_version != SCHEMA_VERSION: return "unsupported schema version"
	if not document.worlds is Array or document.worlds.size() > MAX_WORLDS: return "world count exceeds bound"
	var seen_worlds: Dictionary = {}
	for record: Variant in document.worlds:
		if not record is Dictionary or not _exact_keys(record, ["seed", "mode", "coords", "archetypes", "last", "coordinate_limit_reached"]): return "invalid world record"
		if not _valid_decimal(record.seed) or not record.mode in MODES: return "invalid world identity"
		var key: String = record.mode + ":" + record.seed
		if seen_worlds.has(key): return "duplicate world identity"
		seen_worlds[key] = true
		if not record.coords is Array or record.coords.size() > MAX_COORDS: return "coordinate count exceeds bound"
		var seen_coords: Dictionary = {}
		for coordinate: Variant in record.coords:
			if not _valid_coordinate(coordinate) or seen_coords.has(coordinate): return "invalid or duplicate coordinate"
			if record.mode == "formal" and not coordinate in FORMAL_COORDS: return "unknown formal coordinate"
			seen_coords[coordinate] = true
		if not record.coordinate_limit_reached is bool: return "invalid coordinate limit flag"
		if record.coordinate_limit_reached and record.coords.size() != MAX_COORDS: return "inconsistent coordinate limit flag"
		if not record.last is String or (not record.last.is_empty() and not _valid_coordinate(record.last)): return "invalid last coordinate"
		if record.mode == "formal" and not record.last.is_empty() and not record.last in FORMAL_COORDS: return "unknown formal last coordinate"
		if not record.coordinate_limit_reached and not record.last.is_empty() and not seen_coords.has(record.last): return "last coordinate was not visited"
		if not record.archetypes is Array or record.archetypes.size() > MAX_ARCHETYPES: return "archetype count exceeds bound"
		var seen_types: Dictionary = {}
		for entry: Variant in record.archetypes:
			if not entry is Dictionary or not _exact_keys(entry, ["id", "name"]): return "invalid archetype record"
			if not _valid_archetype_id(entry.id, record.mode) or not _valid_name(entry.name) or seen_types.has(entry.id): return "invalid or duplicate archetype"
			seen_types[entry.id] = true
		if record.coords.is_empty() != record.archetypes.is_empty(): return "inconsistent discoveries"
	return ""

static func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok":false, "reason":"file could not be read"}
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return {"ok":false, "reason":"file exceeds 4 MiB bound"}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK: return {"ok":false, "reason":"malformed JSON"}
	var reason := validate_document(parser.data)
	if not reason.is_empty(): return {"ok":false, "reason":reason}
	return {"ok":true, "text":text, "document":parser.data}

static func _index_document(document: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in document.worlds:
		result[record.mode + ":" + record.seed] = record.duplicate(true)
	return result
