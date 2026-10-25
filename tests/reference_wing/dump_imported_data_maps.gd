extends SceneTree
## CPU read-only import audit. Never runs the editor or changes import settings.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected source project, output directory, and bptc/astc codec")
		quit(1)
		return
	var project: String = args[0]
	var output: String = args[1]
	var codec: String = args[2]
	DirAccess.make_dir_recursive_absolute(output)
	var records: Array[Dictionary] = []
	for name: String in ["bevel_slope_rg_2k", "glaze_orm_2k"]:
		var source_path := project.path_join("assets/materials/reference_wing/" + name + ".png")
		var config := ConfigFile.new()
		if config.load(source_path + ".import") != OK:
			push_error("Cannot read import configuration")
			quit(1)
			return
		var relative: String = config.get_value("remap", "path." + codec, "")
		if relative.is_empty(): relative = config.get_value("remap", "path", "")
		var imported_path := project.path_join(relative.trim_prefix("res://"))
		var texture := CompressedTexture2D.new()
		var status := texture.load(imported_path)
		var record := {"name":name, "codec_requested":codec, "source_path":source_path,
			"imported_path":imported_path, "load_error":status,
			"compress_mode":config.get_value("params","compress/mode")}
		if status == OK:
			var decoded := texture.get_image()
			record["stored_format"] = decoded.get_format()
			record["was_compressed"] = decoded.is_compressed()
			record["mipmap_count"] = decoded.get_mipmap_count()
			var decode_error := decoded.decompress() if decoded.is_compressed() else OK
			record["decompress_error"] = decode_error
			if decode_error == OK:
				decoded.convert(Image.FORMAT_RGBA8)
				record["width"] = decoded.get_width()
				record["height"] = decoded.get_height()
				var filename := name + "_" + codec + "_decoded.rgba"
				var file := FileAccess.open(output.path_join(filename), FileAccess.WRITE)
				file.store_buffer(decoded.get_data().slice(0, decoded.get_width()*decoded.get_height()*4))
				file.close()
				record["decoded_base_rgba"] = filename
				var full_name := name + "_" + codec + "_decoded_mips.rgba"
				var full_file := FileAccess.open(output.path_join(full_name), FileAccess.WRITE)
				full_file.store_buffer(decoded.get_data());full_file.close()
				record["decoded_all_mips_rgba"] = full_name
				var original := Image.load_from_file(source_path)
				original.convert(Image.FORMAT_RGBA8)
				original.generate_mipmaps()
				var source_name := name + "_source_mips.rgba"
				var source_file := FileAccess.open(output.path_join(source_name), FileAccess.WRITE)
				source_file.store_buffer(original.get_data());source_file.close()
				record["source_rgba_with_cpu_mips"] = source_name
				var levels: Array[Dictionary] = []
				for level in decoded.get_mipmap_count()+1:
					levels.append({"level":level,"offset":decoded.get_mipmap_offset(level),
						"width":maxi(decoded.get_width()>>level,1),"height":maxi(decoded.get_height()>>level,1)})
				record["mip_layout"] = levels
			record["decoded_format"] = decoded.get_format()
		records.append(record)
	var report := {"engine":Engine.get_version_info(), "display":DisplayServer.get_name(),
		"scope":"Read/decompress existing imported files on CPU only; no import, editor, GPU or visual claim.",
		"records":records}
	var file := FileAccess.open(output.path_join("decode_" + codec + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("REFERENCE_DATA_MAP_DECODE " + JSON.stringify(report))
	quit()
