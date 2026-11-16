@tool
extends EditorPlugin

class RawTextureExport extends EditorExportPlugin:
	func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		for name: String in ["green_metal_rust_arm_2k.png", "green_metal_rust_diff_2k.png", "green_metal_rust_nor_gl_2k_NATIVE_RGB8.png"]:
			var path := "res://assets/dreamcore/glasswell/coated_steel/" + name
			add_file(path, FileAccess.get_file_as_bytes(path), false)

var exporter := RawTextureExport.new()

func _enter_tree() -> void:
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_export_plugin(exporter)
