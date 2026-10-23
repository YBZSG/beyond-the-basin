extends SceneTree
## External CPU-only smoke. All production resources resolve from --main-pack.
## This script has no production preloads and no active-project path fallback.
var errors: Array[String] = []
var report: Dictionary = {"pass": false, "visual_acceptance": false, "windows_executed": false, "scope": "Actual unchanged exported PCK: resource loads, authored skin/materials, Main menu/body controls and CPU native/fallback parser. No GPU/performance claim."}
var output: String = ""
var mode: String = "original"
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pack-smoke-report="): output = arg.trim_prefix("--pack-smoke-report=")
		if arg.begins_with("--pack-smoke-world="): mode = arg.trim_prefix("--pack-smoke-world=")
	check(DisplayServer.get_name() == "headless" and RenderingServer.get_rendering_device() == null, "CPU smoke must have no RenderingDevice")
	var guard_script: Script = load("res://validation/pc_expansion_pack_guard.gd")
	var guard: RefCounted = guard_script.new()
	report["pack_origin"] = guard.verify()
	check(report.pack_origin.pass, "Exact isolated PCK origin guard failed")
	if not errors.is_empty(): _finish(); return
	var manifest_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--validation-manifest="): manifest_path = arg.trim_prefix("--validation-manifest=")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var modules: Array[String] = []
	for name: String in m.smoke_scripts:
		var script: Script = load("res://" + name)
		check(script != null and script.can_instantiate(), "Runtime script load: " + name)
		modules.append(name)
	report["runtime_modules_loaded"] = modules
	var model_rows: Array[Dictionary] = []
	for name: String in m.expanded_models:
		var packed: PackedScene = load("res://" + name)
		check(packed != null, "Expanded GLB imported scene resolves: " + name)
		if packed == null: continue
		var instance: Node = packed.instantiate()
		check(instance is Node3D, "Expanded GLB instantiates as Node3D: " + name)
		model_rows.append({"path": name, "resource_path": packed.resource_path, "nodes": instance.find_children("*", "MeshInstance3D", true, false).size()})
		instance.free()
	report["expanded_models"] = model_rows
	check(model_rows.size() == 11, "All four rooms and seven props load from actual PCK")
	for name: String in m.avatar_texture_resources:
		check(load("res://" + name) is Texture2D, "Actual avatar material map loads: " + name)
	check(load("res://shaders/avatar_body.gdshader") is Shader, "Actual avatar shader loads")
	# Fresh per-world user state; audio alone is disabled, not shipped world/quality defaults.
	var config := ConfigFile.new()
	config.set_value("audio", "effects", false); config.set_value("audio", "ambience", false)
	check(config.save("user://settings.cfg") == OK, "Isolated user configuration writable")
	var main_script: Script = load("res://scripts/main.gd")
	var host: Node3D = main_script.new()
	root.add_child(host)
	host.set_process(false); host.set_physics_process(false)
	check(host._booted, "Actual exported Main completes startup")
	check(host._spawn_mode == mode, "Actual Main world selection matches process arguments")
	check(host._quality == "High", "Fresh-user production quality remains High")
	check(host.SPAWN_MODES == ["original", "formal", "expanded"], "Current three-mode contract")
	check(host._spawn_select.item_count == 3, "Current three-mode UI exists")
	var labels: Array[String] = []
	for i: int in host._spawn_select.item_count: labels.append(host._spawn_select.get_item_text(i))
	check(labels == ["原仓库场景 / ORIGINAL", "重做主池厅 / FORMAL HALL", "扩展随机地图 / EXPANDED"], "Exact current spawn menu labels")
	check(host.has_method("regenerate") and host.has_method("_choose_spawn"), "Current seed/spawn handlers exist")
	check(host._seed_edit != null and host._seed_edit.text == str(host.world_seed), "Current seed control binds actual world seed")
	check(host.world.formal_mode == (mode == "formal") and host.world.expanded_mode == (mode == "expanded"), "Actual world flags agree with selected menu mode")
	_architecture_material_smoke(host.materials)
	var avatar: Node = host.avatar
	check(is_instance_valid(avatar), "Actual Main attaches final avatar")
	if is_instance_valid(avatar):
		var debug: Dictionary = avatar.get_debug_state()
		report["avatar"] = debug
		check(debug.loaded and debug.bone_count == 42, "Actual final skinned avatar loads with 42 bones")
		for clip: String in ["Idle", "Walk", "Run", "Hold", "Wade", "Swim", "Climb"]: check(debug.clips.has(clip), "Actual authored clip: " + clip)
		var weighted_vertices: int = 0
		var mapped_surfaces: int = 0
		var albedo_surfaces: int = 0
		var surfaces: int = 0
		var meshes: Array = []
		meshes.append_array(avatar._body_meshes); meshes.append_array(avatar._head_meshes)
		for mesh: MeshInstance3D in meshes:
			check(mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) == avatar._skeleton, "Actual mesh binds shared skeleton")
			for surface: int in mesh.mesh.get_surface_count():
				surfaces += 1
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				check(not weights.is_empty() and weights.size() == bones.size(), "Actual vertex joints and skin weights present")
				weighted_vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var material: ShaderMaterial = mesh.get_active_material(surface) as ShaderMaterial
				check(material != null and material.shader.resource_path == "res://shaders/avatar_body.gdshader", "Actual body material uses current clip/PBR adapter")
				var imported: BaseMaterial3D = mesh.mesh.surface_get_material(surface) as BaseMaterial3D
				check(imported != null, "Actual imported PBR material remains available")
				if material != null and imported != null:
					for slot: String in ["albedo_texture", "roughness_texture", "metallic_texture", "normal_texture", "ao_texture", "emission_texture"]:
						check(material.get_shader_parameter(slot) == imported.get(slot), "Actual adapter preserves imported map slot, including valid null: " + slot)
					if imported.albedo_texture != null: albedo_surfaces += 1
					if imported.normal_enabled and imported.normal_texture != null: mapped_surfaces += 1
		check(mapped_surfaces == 0, "Current avatar has no authored normal-map surfaces")
		check(weighted_vertices > 1000 and albedo_surfaces >= 2, "Substantive skinned model and two authored albedo fabric surfaces, not placeholder geometry")
		report["avatar_mesh_materials"] = {"surfaces": surfaces, "weighted_vertices": weighted_vertices, "normal_mapped_surfaces": mapped_surfaces, "albedo_textured_surfaces": albedo_surfaces, "normal_maps_required": false, "map_slot_equality_checked": true, "authored_normal_maps": false, "limitation": "Current avatar has two authored albedo fabric maps and no authored normal maps; normal-mapped appearance is not claimed."}
		host._set_avatar_enabled(false)
		check(not avatar.visible and not host._avatar_enabled, "Current body toggle actually hides model")
		host._set_avatar_enabled(true)
		check(avatar.visible and host._avatar_enabled, "Current body toggle actually restores model")
	report["spawn_controls"] = {"mode": host._spawn_mode, "labels": labels, "seed": host.world_seed, "quality": host._quality, "seed_regeneration_executed": false, "body_toggle_executed": true}
	_parser_smoke()
	# Stop live scene processing and dispose without creating a GPU context.
	host._booted = false; host.world.set_process(false); host.pool_audio.set_active(false)
	host.water.dispose()
	for frame: int in 6: await process_frame; OS.delay_msec(25)
	for child: Node in host.pool_audio.get_children():
		if child.has_method("stop"): child.stop()
	host.free()
	var builder: Script = load("res://scripts/world/room_builder.gd")
	builder.imported_scenes.clear(); builder.imported_shapes.clear()
	for frame: int in 8: await process_frame; OS.delay_msec(25)
	_finish.call_deferred()
func _architecture_material_smoke(materials: RefCounted) -> void:
	var library: Script = load("res://scripts/rendering/pool_materials.gd")
	var paths: Dictionary = {"scan_albedo": library.ALBEDO_PATH, "scan_normal": library.NORMAL_PATH, "scan_roughness": library.ROUGHNESS_PATH}
	var textures: Dictionary = {}
	var rows: Array[Dictionary] = []
	var shader_path: String = library.CERAMIC_SHADER.resource_path
	var shader_source: String = FileAccess.get_file_as_string(shader_path)
	for slot: String in paths:
		var texture: Texture2D = load(paths[slot]) as Texture2D
		check(texture != null, "Actual architectural texture loads: " + slot)
		if texture == null: continue
		textures[slot] = texture
		check(texture.get_width() == library.CERAMIC_TEXTURE_SIZE and texture.get_height() == library.CERAMIC_TEXTURE_SIZE, "Actual architectural atlas dimensions: " + slot)
		var declaration: String = ""
		for line: String in shader_source.split("\n"):
			if line.strip_edges().begins_with("uniform sampler2D " + slot + " "): declaration = line.strip_edges()
		check(not declaration.is_empty(), "Actual ceramic shader declares " + slot)
		check(declaration.contains("source_color") == (slot == "scan_albedo"), "Only albedo is color; normal and roughness remain data: " + slot)
		if slot == "scan_normal": check(declaration.contains("hint_normal"), "Actual normal sampler has normal-data hint")
		rows.append({"slot": slot, "path": paths[slot], "resource_path": texture.resource_path, "width": texture.get_width(), "height": texture.get_height(), "actual_shader_declaration": declaration})
	var roles: Array[String] = ["formal_dry_deck", "formal_wainscot", "formal_basin", "formal_coping", "formal_arcade_tile", "formal_arcade_coping", "floor", "wall"]
	var bindings: Array[Dictionary] = []
	for role: String in roles:
		var material: ShaderMaterial = materials._materials.get(role) as ShaderMaterial
		check(material != null and material.shader == library.CERAMIC_SHADER, "Actual ceramic role uses current shader: " + role)
		if material == null: continue
		for slot: String in paths:
			check(textures.has(slot) and material.get_shader_parameter(slot) == textures.get(slot), "Actual architectural material map binding: " + role + "/" + slot)
		bindings.append({"role": role, "shader_path": material.shader.resource_path, "slots_checked": paths.keys()})
	report["architectural_material_maps"] = {"textures": rows, "material_bindings": bindings, "shader_path": shader_path, "shader_sha256": FileAccess.get_sha256(shader_path), "origin": "Actual PCK virtual resources and actual Main PoolMaterials instance", "native_shader_render_verified": false, "scope": "CPU loads, dimensions, bindings and shader color/data declarations only; no rendered appearance claim"}

func _parser_smoke() -> void:
	var script: Script = load("res://scripts/water/source_port/source_wave_solver.gd")
	var rows: Array[Dictionary] = []
	for native: bool in [true, false]:
		var solver: RefCounted = script.new()
		solver.physics_size = 2; solver.physics_eta.resize(4); solver.physics_u.resize(4); solver.physics_v.resize(4)
		solver.native_readback_enabled = native
		var fixture := Image.create(2, 2, false, Image.FORMAT_RGBAH)
		fixture.fill(Color(0.03125, -0.125, 0.0625, 1.0))
		solver._receive_readback(fixture.get_data(), solver._generation, 0.0, true)
		var expected: String = "native_exact" if native else "gdscript"
		check(solver._readback_parser_backend == expected, "Actual PCK solver parser branch: " + expected)
		for index: int in 4: check(solver.physics_eta[index] == 0.03125 and solver.physics_u[index] == -0.125 and solver.physics_v[index] == 0.0625, "Exact parser fixture values")
		rows.append({"requested_native": native, "backend": solver._readback_parser_backend, "solver_configure_called": false})
	report["cpu_parser_branches"] = rows
func _finish() -> void:
	report["pass"] = errors.is_empty(); report["errors"] = errors
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "  ") + "\n")
		else: report["pass"] = false; errors.append("Cannot write smoke report")
	print("PC_EXPANSION_PACK_SMOKE ", JSON.stringify(report))
	quit(0 if report["pass"] else 1)
