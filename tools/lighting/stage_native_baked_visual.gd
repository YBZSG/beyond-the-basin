extends SceneTree
## Two-phase, fail-closed migration into the existing export quarantine.
## prepare-assets is CPU-safe and never saves LightmapGIData. stage-native
## REQUIRES a real rendering device because headless resaving drops probe SH.
## Neither phase changes builders, runtime defaults, source geometry or water.
const Audit = preload("res://tools/lighting/lightmap_data_audit.gd")
const PREPARATION = "res://assets/lighting/final_mainhall/preparation_manifest.json"
const ASSETS = "res://assets/lighting/runtime_mainhall_candidate"
const PLAN = ASSETS + "/asset_stage_manifest.json"
const DATA = ASSETS + "/native_indirect.lmbake"
const VISUAL = "res://scenes/lighting_lab/runtime_mainhall_candidate.tscn"
const DEFAULT_REPORT = "res://docs/verification/eight-hour/material-lighting/native-visual-staging.json"
const GEOMETRY_PROOF = "res://docs/verification/eight-hour/material-lighting/final-mainhall-bake-contract-baked.json"
const OPTICS_PROOF = "res://docs/verification/eight-hour/material-lighting/final-baked-source-optics-contract-full.json"
var report_path := DEFAULT_REPORT
var phase := ""
var proof_path := ""
var errors: Array[String] = []
var manifest: Dictionary
var proof: Dictionary
var scene: Node3D
var lightmap: LightmapGI

func _initialize() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
        elif arg.begins_with("--native-proof="): proof_path = arg.trim_prefix("--native-proof=")
        elif arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
    _run.call_deferred()

func require(condition: bool, message: String) -> bool:
    if not condition:
        errors.append(message)
        push_error(message)
    return condition

func read_json(path: String) -> Dictionary:
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not require(value is Dictionary, "Invalid JSON: " + path): return {}
    return value

func digest(value: Variant) -> String:
    var hasher := HashingContext.new()
    hasher.start(HashingContext.HASH_SHA256)
    hasher.update(var_to_bytes(value))
    return hasher.finish().hex_encode()

func storage_state(data: LightmapGIData) -> Dictionary:
    # Includes native probe_data and complete user_data (paths, Rect2 UV scales,
    # slices and sub-instances), not merely the public receiver path list.
    var stored: Dictionary = {}
    for property: Dictionary in data.get_property_list():
        var key := str(property.name)
        if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
        if key.begins_with("resource_") or key in ["script", "lightmap_textures", "light_texture", "shadowmask_textures"]: continue
        var value: Variant = data.get(key)
        require(not value is Resource, "Unrecognized nested lightmap resource: " + key)
        stored[key] = value
    var probes: Dictionary = data.get("probe_data")
    var sh: PackedColorArray = probes.get("sh", PackedColorArray())
    require(not sh.is_empty(), "Native probe SH must not be empty")
    for value: Color in sh:
        require(is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a), "Native SH coefficient must be finite")
    return {"storage_sha256": digest(stored), "probe_sha256": digest(probes), "probe_coefficients": sh.size(), "user_count": data.get_user_count(), "directional": data.is_using_spherical_harmonics(), "property_names": stored.keys()}

func validate_inputs() -> bool:
    if not require(not proof_path.is_empty(), "Supply the actual successful native camera report with --native-proof"): return false
    manifest = read_json(PREPARATION)
    proof = read_json(proof_path)
    if not require(manifest.get("pass", false) and proof.get("pass", false), "Successful preparation and native camera proof are mandatory"): return false
    for path: String in manifest.input_sha256:
        require(FileAccess.get_sha256(path) == manifest.input_sha256[path], "Prepared input changed: " + path)
    require(proof.get("scene", "") == manifest.scene, "Native proof refers to this prepared scene")
    require(proof.get("scene_sha256", "") == FileAccess.get_sha256(manifest.scene), "Native camera scene hash is current")
    require(proof.get("baked_data_path", "") == manifest.data, "Native proof refers to this baked data")
    require(proof.get("baked_data_sha256", "") == FileAccess.get_sha256(manifest.data), "Native baked-data hash is current")
    require(proof.get("renderer", "") == "forward_plus", "Actual Forward+ proof is required")
    require(proof.get("nonfinite_probe_coefficients", -1) == 0 and proof.get("probe_coefficient_count", 0) > 0, "Native probe finite-data proof is required")
    require(proof.get("users", 0) == 147 and proof.get("directional", false), "All 147 directional receivers were observed natively")
    require(proof.get("radiance", {}).get("pass", false), "Original HDR must have passed the native finite-data gate")
    require(FileAccess.file_exists(proof.get("output", "")) and proof.get("image_save_error", -1) == OK, "An actual camera image must exist")
    var geometry := read_json(GEOMETRY_PROOF)
    var optics := read_json(OPTICS_PROOF)
    require(geometry.get("pass", false) and geometry.get("require_baked", false), "Post-bake CPU geometry gate passed")
    require(geometry.get("scene_sha256", "") == FileAccess.get_sha256(manifest.scene) and geometry.get("manifest_sha256", "") == FileAccess.get_sha256(PREPARATION), "Post-bake geometry proof is current")
    require(optics.get("pass", false) and optics.get("full_payload_compared", false) and optics.get("grid_size", 0) == 768, "Full-resolution source-water payload equivalence passed")
    require(optics.get("candidate_scene_sha256", "") == FileAccess.get_sha256(manifest.scene) and optics.get("source_model_sha256", "") == manifest.source_sha256, "Full source-optics proof is current")
    if not errors.is_empty(): return false
    scene = (load(manifest.scene) as PackedScene).instantiate() as Node3D
    lightmap = scene.get_node_or_null("Bake_Mainhall_Indirect") as LightmapGI
    if not require(lightmap != null and lightmap.light_data != null, "Prepared lightmap and data must resolve"): return false
    var data := lightmap.light_data
    require(data.get_user_count() == 147 and data.is_using_spherical_harmonics(), "Current saved data contains all directional users")
    require(data.get_shadowmask_textures().is_empty(), "This indirect-only migration does not support unreviewed shadow masks")
    require(scene.find_children("*", "CollisionObject3D", true, false).is_empty(), "Visual scene must not replace original colliders")
    var expected: Dictionary = {}
    for row: Dictionary in manifest.receivers:
        var mesh := scene.get_node_or_null(row.path) as MeshInstance3D
        if not require(mesh != null, "Receiver exists: " + row.path): continue
        # The hash-pinned CPU geometry proof covers complete triangle/attribute
        # identity without attaching unvalidated native data to a scenario.
        require(mesh.transform == Transform3D.IDENTITY, "Authored mesh local transform remains identity")
        require(Array(mesh.get_meta("formal_live_material_roles", PackedStringArray())) == row.live_material_roles, "Live material roles remain exact: " + row.path)
        if row.classification == "static_architecture": expected[str(lightmap.get_path_to(mesh))] = true
    require(expected.size() == 147, "Exact expected receiver set")
    var seen: Dictionary = {}
    for index in data.get_user_count():
        var path := str(data.get_user_path(index))
        require(expected.has(path) and not seen.has(path) and lightmap.has_node(path), "Unique resolved baked user: " + path)
        seen[path] = true
    for texture: TextureLayered in data.get_lightmap_textures():
        require(proof.get("original_hdr_sha256", {}).get(texture.resource_path, "") == FileAccess.get_sha256(texture.resource_path), "Original HDR hash is current: " + texture.resource_path)
    require(Audit.inspect_data(data).get("pass", false), "Current original HDR is finite; never sanitize invalid radiance")
    return errors.is_empty()

func _run() -> void:
    if not require(phase in ["prepare-assets", "stage-native"], "Choose --phase=prepare-assets or --phase=stage-native"): finish({}); return
    if phase == "stage-native" and not require(DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null, "Native staging is forbidden on the headless/dummy backend; it loses probe SH"): finish({}); return
    if not validate_inputs(): finish({}); return
    if phase == "prepare-assets": prepare_assets()
    else: stage_native()

func prepare_assets() -> void:
    # Never duplicate/resave LightmapGIData here. Only exact EXR byte copies and
    # lossless 2D-array importer recipes are prepared for the CPU editor import.
    if not require(not FileAccess.file_exists(PLAN), "Stage plan already exists; inspect/reconcile the previous outcome instead of overwriting"): finish({}); return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSETS))
    var textures: Array[Dictionary] = []
    var index := 0
    for texture: TextureLayered in lightmap.light_data.get_lightmap_textures():
        var source := texture.resource_path
        var target := ASSETS + "/indirect_%02d.exr" % index
        if not require(not FileAccess.file_exists(target), "Destination already exists: " + target): finish({}); return
        var config := ConfigFile.new()
        if not require(config.load(source + ".import") == OK, "Source array import metadata exists"): finish({}); return
        require(config.get_value("params", "slices/horizontal", 0) == 1, "Expected vertical array slices")
        require(config.get_value("params", "slices/vertical", 0) == texture.get_layers(), "Source slice count matches texture")
        if not errors.is_empty(): finish({}); return
        if not require(DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)) == OK, "Exact EXR copy succeeds"): finish({}); return
        require(FileAccess.get_sha256(target) == FileAccess.get_sha256(source), "Copied HDR bytes match exactly")
        var imported := "res://.godot/imported/" + target.get_file() + "-" + target.md5_text() + ".ctexarray"
        config.set_value("remap", "uid", ResourceUID.id_to_text(ResourceUID.create_id()))
        config.set_value("remap", "path", imported)
        config.set_value("remap", "metadata", {"vram_texture": false})
        config.set_value("deps", "source_file", target)
        config.set_value("deps", "dest_files", PackedStringArray([imported]))
        config.set_value("params", "compress/mode", 3)
        config.set_value("params", "mipmaps/generate", false)
        require(config.save(target + ".import") == OK, "Lossless array import recipe saves")
        textures.append({"source": source, "target": target, "sha256": FileAccess.get_sha256(source), "layers": texture.get_layers(), "width": texture.get_width(), "height": texture.get_height()})
        index += 1
    var plan := {"pass": errors.is_empty(), "source_scene": manifest.scene, "source_scene_sha256": FileAccess.get_sha256(manifest.scene), "source_data": manifest.data, "source_data_sha256": FileAccess.get_sha256(manifest.data), "preparation_sha256": FileAccess.get_sha256(PREPARATION), "native_proof": proof_path, "native_proof_sha256": FileAccess.get_sha256(proof_path), "textures": textures, "status": "quarantined_atlases_pending_import_and_native_staging", "runtime_default_changed": false}
    if errors.is_empty(): write_json(PLAN, plan)
    finish(plan)

func verify_texture(texture: TextureLayered, row: Dictionary) -> bool:
    require(texture != null, "Imported staged texture resolves")
    if texture == null: return false
    require(FileAccess.get_sha256(row.target) == row.sha256, "Staged HDR is byte-identical")
    var config := ConfigFile.new()
    require(config.load(row.target + ".import") == OK and config.get_value("params", "compress/mode", -1) == 3, "Staged importer is uncompressed")
    require(texture.get_layers() == row.layers and texture.get_width() == row.width and texture.get_height() == row.height, "Staged array dimensions are exact")
    var source := Image.load_from_file(row.source)
    if not require(source != null and source.get_format() == texture.get_format(), "HDR and GPU array retain the same exact sample format"): return false
    for layer in texture.get_layers():
        var uploaded := texture.get_layer_data(layer)
        if not require(uploaded != null, "Actual native texture layer is readable"): continue
        var expected := source.get_region(Rect2i(0, layer * texture.get_height(), texture.get_width(), texture.get_height()))
        require(not uploaded.is_compressed() and uploaded.get_format() == expected.get_format() and uploaded.get_data() == expected.get_data(), "Every native HDR sample is lossless in layer " + str(layer))
    return errors.is_empty()

func stage_native() -> void:
    var plan := read_json(PLAN)
    require(plan.get("pass", false), "Successful CPU stage plan is required")
    require(plan.get("preparation_sha256", "") == FileAccess.get_sha256(PREPARATION), "Stage plan preparation hash is current")
    require(plan.get("native_proof_sha256", "") == FileAccess.get_sha256(proof_path), "Stage plan native proof is current")
    require(plan.get("source_scene_sha256", "") == FileAccess.get_sha256(manifest.scene) and plan.get("source_data_sha256", "") == FileAccess.get_sha256(manifest.data), "Stage source files are unchanged")
    require(not FileAccess.file_exists(DATA) and not FileAccess.file_exists(VISUAL), "Native stage outputs must not exist; inspect an uncertain previous outcome before retry")
    if not errors.is_empty(): finish({}); return
    var original := storage_state(lightmap.light_data)
    var staged := lightmap.light_data.duplicate(false) as LightmapGIData
    require(staged != null and storage_state(staged) == original, "Native resource duplication preserves all storage and SH")
    var textures: Array[TextureLayered] = []
    for row: Dictionary in plan.textures:
        var texture := load(row.target) as TextureLayered
        verify_texture(texture, row)
        textures.append(texture)
    if not errors.is_empty(): finish({"native_state": original}); return
    staged.set_lightmap_textures(textures)
    require(storage_state(staged) == original, "Atlas rebinding preserves probe SH and every UV/slice/user entry")
    if not errors.is_empty(): finish({"native_state": original}); return
    require(ResourceSaver.save(staged, DATA) == OK, "Native LightmapGIData saves successfully")
    var restored := ResourceLoader.load(DATA, "LightmapGIData", ResourceLoader.CACHE_MODE_IGNORE) as LightmapGIData
    require(restored != null and storage_state(restored) == original, "Saved/reloaded native SH and complete user mapping are byte-identical")
    if not errors.is_empty(): finish({"native_state": original}); return
    lightmap.light_data = restored
    # Keep receiver and LightmapGI names/relative paths unchanged. Remove study
    # environment, sun, camera and explicit probe markers, never bake in water.
    for child: Node in scene.get_children():
        if child.name not in ["FormalAuthoredArchitecture", "Bake_Mainhall_Indirect"]:
            scene.remove_child(child)
            child.free()
    scene.name = "FormalMainhallBakedVisuals"
    scene.set_meta("formal_bake_requires_live_material_binding", true)
    scene.set_meta("formal_bake_source_glb_sha256", manifest.source_sha256)
    scene.set_meta("formal_bake_preparation_sha256", FileAccess.get_sha256(PREPARATION))
    scene.set_meta("formal_bake_status", "quarantined_runtime_candidate_not_accepted")
    # Keep the scene off the rendering tree: this is serialization validation,
    # not a substitute for the subsequent actual full-game water comparison.
    own_children(scene, scene)
    var packed := PackedScene.new()
    require(packed.pack(scene) == OK and ResourceSaver.save(packed, VISUAL) == OK, "Quarantined visual PackedScene saves")
    if not errors.is_empty(): finish({"native_state": original}); return
    var reloaded := (ResourceLoader.load(VISUAL, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
    var saved_lightmap := reloaded.get_node("Bake_Mainhall_Indirect") as LightmapGI
    require(storage_state(saved_lightmap.light_data) == original, "PackedScene retains the exact native probe/user state")
    require(reloaded.find_children("*", "CollisionObject3D", true, false).is_empty() and reloaded.find_children("*", "Camera3D", true, false).is_empty() and reloaded.find_children("*", "Light3D", true, false).is_empty() and reloaded.find_children("*", "WorldEnvironment", true, false).is_empty(), "Staged scene contains visuals/lightmap only")
    for row: Dictionary in manifest.receivers:
        var before := scene.get_node(row.path) as MeshInstance3D
        var after := reloaded.get_node(row.path) as MeshInstance3D
        require(mesh_buffers(before.mesh) == mesh_buffers(after.mesh) and before.mesh.lightmap_size_hint == after.mesh.lightmap_size_hint, "Packed mesh vertex/normal/UV0/UV2 buffers are identical: " + row.path)
        require(before.transform == after.transform and before.layers == after.layers and before.visible == after.visible and before.cast_shadow == after.cast_shadow and before.gi_mode == after.gi_mode, "Visual transforms and rendering flags remain exact")
        require(before.get_meta("formal_live_material_roles") == after.get_meta("formal_live_material_roles"), "Runtime material bindings remain explicit")
    for index in saved_lightmap.light_data.get_user_count(): require(saved_lightmap.has_node(saved_lightmap.light_data.get_user_path(index)), "Saved receiver path resolves")
    reloaded.free()
    finish({"native_state": original, "source_scene_sha256": FileAccess.get_sha256(manifest.scene), "source_data_sha256": FileAccess.get_sha256(manifest.data), "visual": VISUAL, "visual_sha256": FileAccess.get_sha256(VISUAL), "data": DATA, "data_sha256": FileAccess.get_sha256(DATA), "textures": plan.textures, "status": "quarantined_runtime_candidate_not_accepted", "runtime_default_changed": false, "live_material_binding_required": true})

func mesh_buffers(mesh: ArrayMesh) -> Array:
    var surfaces: Array = mesh.get("_surfaces").duplicate(true)
    # Surface material objects may be reloaded as distinct Resource instances.
    # Their semantic role is checked separately and rebound before gameplay.
    for surface: Dictionary in surfaces: surface.erase("material")
    return surfaces

func own_children(node: Node, owner_node: Node) -> void:
    for child: Node in node.get_children():
        child.owner = owner_node
        own_children(child, owner_node)

func write_json(path: String, value: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if require(file != null, "Report path is writable: " + path): file.store_string(JSON.stringify(value, "  ") + "\n")

func finish(result: Dictionary) -> void:
    result["pass"] = errors.is_empty()
    result["phase"] = phase
    result["errors"] = errors
    result["scope"] = "Guarded quarantine only. Full-game optical/geometry comparison and art acceptance are still mandatory; no runtime default or export promotion."
    write_json(report_path, result)
    print("NATIVE_VISUAL_STAGING ", JSON.stringify(result))
    if is_instance_valid(scene): scene.free()
    quit(0 if errors.is_empty() else 1)
