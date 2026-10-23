extends RefCounted
## Lossless, hash-pinned header replacement. Release-time fresh regeneration
## proved every physical payload byte equal; historical timing stays unchanged.
static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

static func restore_files(recipe: Dictionary, input_root: String, output_root: String) -> Dictionary:
	var restored: Array = []
	if recipe.get("files", []).size() != 16: return {"ok":false,"reason":"Expected exactly 16 verified caches"}
	# Verify ALL source bytes and reconstructed bytes before writing anything.
	for row: Dictionary in recipe.files:
		var old_path: String = row.old_path
		var new_path: String = row.new_path
		if not old_path.begins_with("assets/cache/source_terrain/") or not new_path.begins_with("assets/cache/source_terrain/") or ".." in old_path or ".." in new_path:
			return {"ok":false,"reason":"Unsafe cache path"}
		var original := FileAccess.get_file_as_bytes(input_root.path_join(old_path))
		if digest(original) != row.before_sha256: return {"ok":false,"reason":"Original cache mismatch: " + old_path}
		var prefix := Marshalls.base64_to_raw(row.new_prefix_base64)
		var offset := int(row.old_prefix_bytes)
		if offset < 19 or offset > 65555 or offset > original.size() or prefix.size() > 65555:
			return {"ok":false,"reason":"Invalid cache header bounds"}
		var bytes := prefix + original.slice(offset)
		if digest(bytes) != row.after_sha256: return {"ok":false,"reason":"Reconstructed cache mismatch: " + new_path}
		restored.append({"path":new_path,"bytes":bytes})
	var paths: Array[String] = []
	for item: Dictionary in restored:
		var path := output_root.path_join(str(item.path))
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return {"ok":false,"reason":"Cannot create cache folder"}
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: return {"ok":false,"reason":"Cannot write reconstructed cache"}
		file.store_buffer(item.bytes); file.flush()
		if file.get_error() != OK: return {"ok":false,"reason":"Cache write failed"}
		file.close(); paths.append(path)
	return {"ok":true,"paths":paths}

static func mount_cache(recipe: Dictionary, expected_pack_sha256: String) -> Dictionary:
	var directory := "user://pc_splash_repair_20261022/" + expected_pack_sha256
	var pack_path := directory.path_join("exact-terrain.pck")
	if FileAccess.get_sha256(pack_path) != expected_pack_sha256:
		var restored := restore_files(recipe,"res://",directory.path_join("reconstruction"))
		if not restored.ok: return restored
		var packer := PCKPacker.new()
		var error := packer.pck_start(pack_path)
		if error != OK: return {"ok":false,"reason":"Cannot create exact cache pack"}
		for row: Dictionary in recipe.files:
			error = packer.add_file("res://"+str(row.new_path),directory.path_join("reconstruction").path_join(str(row.new_path)))
			if error != OK: return {"ok":false,"reason":"Cannot add exact cache resource"}
		error = packer.flush()
		if error != OK or FileAccess.get_sha256(pack_path) != expected_pack_sha256:
			return {"ok":false,"reason":"Reconstructed cache pack checksum mismatch"}
		# Remove only the known temporary files just created, never user content.
		for path: String in restored.paths: DirAccess.remove_absolute(path)
	if not ProjectSettings.load_resource_pack(pack_path,true):return {"ok":false,"reason":"Cannot mount exact cache pack"}
	for row: Dictionary in recipe.files:
		if FileAccess.get_sha256("res://"+str(row.new_path)) != row.after_sha256:
			return {"ok":false,"reason":"Mounted cache mismatch: " + str(row.new_path)}
	return {"ok":true,"pack":pack_path,"files":recipe.files.size(),"sha256":expected_pack_sha256}
