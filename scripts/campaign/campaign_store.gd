extends RefCounted
## Local-only campaign save. Never writes over a corrupt/unknown primary save.
const State = preload("res://scripts/campaign/campaign_state.gd")
const DEFAULT_PATH := "user://campaign_v1.json"
const MAX_BYTES := 65536

static func _safe(path: String) -> bool:
	if not path.begins_with("user://"): return false
	var relative := path.trim_prefix("user://")
	if "\\" in relative or ":" in relative: return false
	for part: String in relative.split("/"):
		if part in ["", ".", ".."]: return false
	return true

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"reason":"missing"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false,"reason":"unreadable"}
	if file.get_length()>MAX_BYTES: return {"ok":false,"reason":"oversized"}
	var text := file.get_as_text()
	var parser := JSON.new()
	if parser.parse(text)!=OK: return {"ok":false,"reason":"invalid_json"}
	var state := State.new()
	var restored := state.restore(parser.data)
	if not restored.ok: return {"ok":false,"reason":restored.reason}
	return {"ok":true,"state":state,"text":text,"recovered_pending":restored.recovered_pending}

static func load_state(path: String = DEFAULT_PATH) -> Dictionary:
	if not _safe(path): return {"ok":false,"state":State.new(),"status":"blocked","reason":"Unsafe save path."}
	var primary := _read(path)
	if primary.ok:
		return {"ok":true,"state":primary.state,"status":"recovered_transition" if primary.recovered_pending else "loaded","reason":"","fingerprint":primary.text.sha256_text(),"writable":true}
	var backup := _read(path+".bak")
	if backup.ok:
		return {"ok":true,"state":backup.state,"status":"backup_read_only","reason":"Primary missing or invalid; files preserved.","writable":false}
	if primary.reason=="missing" and backup.reason=="missing":
		return {"ok":true,"state":State.new(),"status":"new","reason":"","writable":true}
	return {"ok":false,"state":State.new(),"status":"corrupt_read_only","reason":"Save invalid; files preserved. Start a new separate save or restore a verified backup.","writable":false}

static func _write(path: String, text: String) -> Error:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

static func save_state(state: RefCounted, path: String = DEFAULT_PATH, expected_fingerprint: String = "") -> Error:
	if not _safe(path): return ERR_FILE_BAD_PATH
	var serialized: Dictionary = state.serialize()
	var validator := State.new()
	if not validator.restore(serialized).ok: return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error!=OK: return directory_error
	# An atomic directory claim serializes writers. Stale locks are preserved,
	# not guessed away; gameplay can continue with an explicit unsaved warning.
	var lock := absolute+".lock"
	if DirAccess.make_dir_absolute(lock)!=OK: return ERR_BUSY
	var error := _save_locked(state,path,expected_fingerprint)
	DirAccess.remove_absolute(lock)
	return error

static func _save_locked(state: RefCounted, path: String, expected_fingerprint: String) -> Error:
	var prior := _read(path)
	if not prior.ok and prior.reason!="missing": return ERR_FILE_CORRUPT
	if not prior.ok and prior.reason == "missing":
		# Do not overwrite interrupted-save evidence or silently reset a recovery copy.
		if FileAccess.file_exists(path+".bak") or FileAccess.file_exists(path+".tmp"): return ERR_FILE_CORRUPT
	if not expected_fingerprint.is_empty():
		if not prior.ok or prior.text.sha256_text()!=expected_fingerprint: return ERR_BUSY
	var text := JSON.stringify(state.serialize(),"\t")+"\n"
	if text.to_utf8_buffer().size()>MAX_BYTES: return ERR_OUT_OF_MEMORY
	var temp := path+".tmp"
	if FileAccess.file_exists(temp) or FileAccess.file_exists(path+".bak.tmp"): return ERR_BUSY
	var error := _write(temp,text)
	if error!=OK: return error
	# Validate serialized bytes before promotion. Keep a valid old primary until
	# the new file is fully written. Backup preparation never moves the primary.
	if not _read(temp).ok: return ERR_FILE_CORRUPT
	if prior.ok:
		error = _write(path+".bak.tmp",str(prior.text))
		if error!=OK: return error
		if not _read(path+".bak.tmp").ok: return ERR_FILE_CORRUPT
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".bak.tmp"),ProjectSettings.globalize_path(path+".bak"))
		if error!=OK: return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
