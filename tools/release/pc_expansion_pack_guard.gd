extends RefCounted
## External test-only origin guard. It never mounts or modifies a resource pack.
func verify() -> Dictionary:
	var errors: Array[String] = []
	var manifest_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--validation-manifest="): manifest_path = arg.trim_prefix("--validation-manifest=")
	var result: Dictionary = {"pass": false, "errors": errors, "scope": "Exact virtual-PCK entry hashes plus isolated physical host; not visual acceptance"}
	if manifest_path.is_empty(): errors.append("Explicit external validation manifest required"); return result
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null: errors.append("Cannot read external validation manifest"); return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: errors.append("Invalid validation manifest"); return result
	var m: Dictionary = parsed
	# Godot consumes --main-pack / --path before OS.get_cmdline_args(), and
	# globalize_path(res://) is empty with a standalone PCK. Read actual Linux argv.
	var args: Array[String] = []
	var command_file := FileAccess.open("/proc/self/cmdline", FileAccess.READ)
	var raw_args: PackedByteArray = command_file.get_buffer(65536) if command_file != null else PackedByteArray()
	if raw_args.is_empty() or raw_args.size() == 65536: errors.append("Cannot read complete Linux process argv")
	var item: PackedByteArray = []
	for byte: int in raw_args:
		if byte == 0:
			args.append(item.get_string_from_utf8()); item.clear()
		else: item.append(byte)
	if not item.is_empty(): args.append(item.get_string_from_utf8())
	var pack_arg: String = ""
	var project_arg: String = ""
	for i: int in args.size() - 1:
		if args[i] == "--main-pack": pack_arg = args[i + 1]
		if args[i] == "--path": project_arg = args[i + 1]
	if pack_arg != String(m.get("pack_path", "")): errors.append("--main-pack is not the inventoried isolated PCK")
	if FileAccess.get_sha256(pack_arg) != String(m.get("pck_sha256", "")): errors.append("PCK bytes differ from validation manifest")
	var cwd := DirAccess.open(".")
	var physical_root: String = cwd.get_current_dir().trim_suffix("/") if cwd != null else ""
	if physical_root != String(m.get("host_root", "")).trim_suffix("/") or project_arg != String(m.get("host_root", "")): errors.append("Process cwd/--path is not the isolated validation host")
	var verified: int = 0
	for row: Dictionary in m.get("pack_entries", []):
		var path: String = "res://" + String(row.path)
		if FileAccess.get_sha256(path) != String(row.sha256): errors.append("Virtual PCK entry differs or absent: " + path)
		else: verified += 1
	var mappings: Array[String] = []
	if OS.get_name() == "Linux":
		var maps := FileAccess.open("/proc/self/maps", FileAccess.READ)
		if maps == null: errors.append("Cannot verify Linux native-helper origin")
		else:
			while not maps.eof_reached():
				var line: String = maps.get_line()
				if line.contains("libsource_water") and line.contains(".so"):
					var at: int = line.find("/")
					if at >= 0 and not mappings.has(line.substr(at)): mappings.append(line.substr(at))
		if mappings != [String(m.get("expected_linux_helper", ""))]: errors.append("Native helper did not map exclusively from isolated host")
	if not ClassDB.class_exists("SourceWaterReadback"): errors.append("Expected isolated native helper did not register")
	result.merge({"pass": errors.is_empty(), "pck_sha256": m.get("pck_sha256", ""), "source_inventory_sha256": m.get("source_inventory_sha256", ""), "pack_path": pack_arg, "physical_host_root": physical_root, "virtual_entries_verified": verified, "virtual_entries_expected": m.get("pack_entries", []).size(), "native_helper_mappings": mappings, "manifest_sha256": FileAccess.get_sha256(manifest_path)}, true)
	return result
