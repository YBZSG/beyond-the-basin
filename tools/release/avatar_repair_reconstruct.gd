extends SceneTree
# CPU-only cross-platform proof of the same bounded range-copy format used by CMD.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		fail("Expected one package folder", 10); return
	var folder := args[0]
	var m = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("AVATAR-REPAIR-MANIFEST.json")))
	if not m is Dictionary or m.get("format") != "poolcore-byte-range-delta-v1":
		fail("Invalid manifest", 11); return
	var base_path := folder.path_join("PoolCore-PC-Expansion-20261022.pck")
	var payload_path := folder.path_join("Avatar-Repair.payload")
	var output_path := folder.path_join("PoolCore-PC-Avatar-Repair-20261022.pck")
	if FileAccess.get_sha256(base_path) != m.base_sha256:
		fail("Wrong baseline; original preserved", 12); return
	if FileAccess.get_sha256(payload_path) != m.payload_sha256:
		fail("Wrong payload; original preserved", 13); return
	if FileAccess.file_exists(output_path):
		if FileAccess.get_sha256(output_path) != m.output_sha256:
			fail("Existing output differs; refusing overwrite", 14); return
		print("AVATAR_REPAIR_RECONSTRUCT_ALREADY_OK"); quit(); return
	var temporary := output_path + ".tmp-" + str(Time.get_ticks_usec())
	if FileAccess.file_exists(temporary):
		fail("Temporary output exists", 15); return
	var base := FileAccess.open(base_path, FileAccess.READ)
	var payload := FileAccess.open(payload_path, FileAccess.READ)
	var target := FileAccess.open(temporary, FileAccess.WRITE)
	if base == null or payload == null or target == null:
		fail("Cannot open streams", 16); return
	var written := 0
	for op in m.operations:
		if not op is Array or op.size() != 3 or not op[0] in ["base", "payload"]:
			fail("Invalid range operation", 17); return
		var input := base if op[0] == "base" else payload
		var offset := int(op[1]); var remaining := int(op[2])
		if offset < 0 or remaining < 0 or offset + remaining > input.get_length() or written + remaining > int(m.output_bytes):
			fail("Range exceeds input or output bounds", 18); return
		input.seek(offset)
		while remaining > 0:
			var count := mini(1048576, remaining)
			var block := input.get_buffer(count)
			if block.size() != count:
				fail("Short read", 19); return
			target.store_buffer(block)
			remaining -= count; written += count
	target.close(); base.close(); payload.close()
	if written != int(m.output_bytes) or FileAccess.get_sha256(temporary) != m.output_sha256:
		DirAccess.remove_absolute(temporary)
		fail("Output hash mismatch", 20); return
	if FileAccess.file_exists(output_path) or DirAccess.rename_absolute(temporary, output_path) != OK:
		fail("Cannot commit verified output without overwriting", 21); return
	print("AVATAR_REPAIR_RECONSTRUCT_OK " + m.output_sha256)
	quit()
func fail(message: String, code: int) -> void:
	printerr("AVATAR_REPAIR_REFUSED: " + message)
	quit(code)
