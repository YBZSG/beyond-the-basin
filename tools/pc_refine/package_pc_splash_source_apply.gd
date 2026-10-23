extends SceneTree
const MANIFEST_SHA256 := "d73a604e93159614c80a967c847fd0e84711d1337ac40c369834ebf5e28957cc"
const RECIPE_SHA256 := "1aa07adfabd38234f61396cbaf19e6139f986a1596806d237cb3352908a3b5a2"
func fail(message: String) -> void:
	push_error("SOURCE_PATCH_REFUSED: " + message)
	quit(80)
func _initialize() -> void:
	var engine := Engine.get_version_info()
	if int(engine.major) != 4 or int(engine.minor) != 6 or int(engine.patch) != 3 or str(engine.hash) != "7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3":fail("Use the exact official Godot 4.6.3 Standard engine.");return
	var source := ""
	var patch := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source-root="):source=arg.trim_prefix("--source-root=")
		elif arg.begins_with("--patch-root="):patch=arg.trim_prefix("--patch-root=")
	if source.is_empty() or patch.is_empty() or not source.is_absolute_path() or not patch.is_absolute_path():fail("Two absolute folders are required.");return
	if FileAccess.get_sha256(patch.path_join("SOURCE-PATCH-MANIFEST.json")) != MANIFEST_SHA256 or FileAccess.get_sha256(patch.path_join("CACHE-RECONSTRUCTION.json")) != RECIPE_SHA256:fail("Source manifest or cache recipe is damaged.");return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(patch.path_join("SOURCE-PATCH-MANIFEST.json")))
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(patch.path_join("CACHE-RECONSTRUCTION.json")))
	if FileAccess.get_sha256(source.path_join("project.godot")) != manifest.baseline_project_godot_sha256:fail("This is not the exact repair1 source project.");return
	var installed := true
	for row: Dictionary in manifest.files:
		if FileAccess.get_sha256(source.path_join(str(row.path))) != row.after_sha256:installed=false
	for row: Dictionary in recipe.files:
		if FileAccess.get_sha256(source.path_join(str(row.new_path))) != row.after_sha256:installed=false
	if installed:print("SOURCE_PATCH_ALREADY_APPLIED_OK");quit(0);return
	for row: Dictionary in manifest.baseline_dependency_files:
		if FileAccess.get_sha256(source.path_join(str(row.path))) != row.sha256:fail("Baseline dependency changed: " + str(row.path));return
	for row: Dictionary in manifest.files:
		var target := source.path_join(str(row.path))
		if row.before_sha256 == null:
			if FileAccess.file_exists(target):fail("New helper already exists with unexpected bytes.");return
		elif FileAccess.get_sha256(target) != row.before_sha256:fail("Source was edited or is a different baseline: " + str(row.path));return
		if FileAccess.get_sha256(patch.path_join(str(row.path))) != row.after_sha256:fail("Patch source file is damaged.");return
	var backup := source.path_join("PC-SPLASH-PATCH-BACKUP-20261022")
	if DirAccess.dir_exists_absolute(backup):fail("Backup folder already exists. Inspect the earlier attempt before applying again.");return
	var pending := source.path_join("PC-SPLASH-PATCH-PREPARED-20261022")
	var helper = load(patch.path_join("cache_reconstruct.gd"))
	var restored: Dictionary = helper.restore_files(recipe,source,pending)
	if not restored.ok:fail(str(restored.reason));return
	# Every source and every cache was checked before the first project overwrite.
	for row: Dictionary in manifest.files:
		if row.before_sha256 != null:
			var destination := backup.path_join(str(row.path))
			DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
			if DirAccess.copy_absolute(source.path_join(str(row.path)),destination) != OK:fail("Cannot back up source.");return
	for row: Dictionary in recipe.files:
		var destination := backup.path_join(str(row.old_path))
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if DirAccess.copy_absolute(source.path_join(str(row.old_path)),destination) != OK:fail("Cannot back up original cache.");return
	for row: Dictionary in manifest.files:
		var destination := source.path_join(str(row.path))
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if DirAccess.copy_absolute(patch.path_join(str(row.path)),destination) != OK:fail("Source copy failed; original is in the backup folder.");return
	for row: Dictionary in recipe.files:
		if DirAccess.copy_absolute(pending.path_join(str(row.new_path)),source.path_join(str(row.new_path))) != OK:fail("Cache copy failed; original is in the backup folder.");return
	for row: Dictionary in manifest.files:
		if FileAccess.get_sha256(source.path_join(str(row.path))) != row.after_sha256:fail("Written source hash mismatch.");return
	for row: Dictionary in recipe.files:
		if FileAccess.get_sha256(source.path_join(str(row.new_path))) != row.after_sha256:fail("Written cache hash mismatch.");return
	DirAccess.copy_absolute(patch.path_join("SOURCE-PATCH-MANIFEST.json"),source.path_join("SOURCE-PATCH-MANIFEST.json"))
	DirAccess.copy_absolute(patch.path_join("CACHE-RECONSTRUCTION.json"),source.path_join("PC-SPLASH-CACHE-RECONSTRUCTION.json"))
	for path: String in restored.paths: DirAccess.remove_absolute(path)
	print("SOURCE_PATCH_APPLIED_OK scripts=5 exact_caches=16 originals_preserved=" + backup)
	quit(0)
