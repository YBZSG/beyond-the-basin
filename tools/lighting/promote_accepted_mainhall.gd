extends SceneTree
## Explicit, gated two-phase promotion. Never run without reviewed full-game
## images. prepare-assets copies only accepted original HDR bytes; a normal
## headless import follows. promote-native preserves hidden native SH storage.
const Installer = preload("res://tools/lighting/runtime_bake_installer_candidate.gd")
const Builder = preload("res://scripts/world/formal_room_builder.gd")
const Catalog = preload("res://scripts/world/formal_rooms.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const PREPARATION := "res://assets/lighting/final_mainhall/preparation_manifest.json"
const STAGING := "res://docs/verification/eight-hour/material-lighting/native-visual-staging.json"
const OPTICS := "res://docs/verification/eight-hour/material-lighting/final-baked-source-optics-contract-staged-full.json"
const PLAN := "res://assets/lighting/runtime_mainhall_candidate/production_promotion_plan.json"
const DEST := "res://assets/lighting_runtime/mainhall"
const DATA := DEST + "/indirect.lmbake"
const RECEIPT := DEST + "/acceptance.tres"
const HELPER := "res://scripts/rendering/formal_baked_lighting.gd"
const REPORT := "res://docs/verification/eight-hour/material-lighting/accepted-mainhall-promotion.json"
var phase := "verify-only"
var acceptance_path := ""
var comparison_path := ""
var report_path := REPORT
var errors: Array[String] = []
var acceptance: Dictionary
var comparison: Dictionary
var preparation: Dictionary
var staging: Dictionary

func _initialize() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
        elif arg.begins_with("--acceptance="): acceptance_path = arg.trim_prefix("--acceptance=")
        elif arg.begins_with("--comparison="): comparison_path = arg.trim_prefix("--comparison=")
        elif arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
    _run.call_deferred()

func require(condition: bool, label: String) -> bool:
    if not condition: errors.append(label)
    return condition

func read_json(path: String) -> Dictionary:
    if not require(not path.is_empty() and FileAccess.file_exists(path), "Required proof is absent: " + path): return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not require(value is Dictionary, "Invalid proof JSON: " + path): return {}
    return value

func validate_inputs() -> void:
    require(phase in ["verify-only", "prepare-assets", "promote-native"], "Explicit recognized phase required")
    acceptance = read_json(acceptance_path)
    comparison = read_json(comparison_path)
    preparation = read_json(PREPARATION)
    staging = read_json(STAGING)
    var optics := read_json(OPTICS)
    if not errors.is_empty(): return
    require(acceptance.get("decision", "") == "accept" and acceptance.get("scope", "") == "formal_mainhall_static_indirect_only", "Explicit mainhall-only art acceptance required")
    require(not str(acceptance.get("reviewer", "")).is_empty() and not str(acceptance.get("review_notes", "")).is_empty(), "Actual image review and attribution required")
    require(acceptance.get("comparison_sha256", "") == FileAccess.get_sha256(comparison_path), "Reviewed comparison report must be unchanged")
    require(comparison.get("pass", false) and comparison.get("renderer", "") == "forward_plus", "Actual full-game comparison must pass")
    require(comparison.get("installation", {}).get("pass", false) and comparison.get("binding_after", {}).get("pass", false), "Actual gameplay receiver/material bindings must pass")
    require(comparison.get("live_state", {}).get("same_system_identities", false) and comparison.get("live_state", {}).get("prop_transforms_advanced", false), "Actual water/props must resume on the same systems")
    var reviewed := {"a-sdfgi-frozen": "baseline_image_sha256", "b-lightmap-frozen": "candidate_image_sha256"}
    var seen: Dictionary = {}
    for frame: Dictionary in comparison.get("frames", []):
        if not reviewed.has(frame.get("label", "")): continue
        require(not seen.has(frame.label), "Each reviewed image has one unambiguous frame")
        seen[frame.label] = frame
        require(frame.get("image_size", []) == [1920, 1080], "Reviewed pair must be genuine Full HD")
        require(frame.get("simulation_frozen", false), "Reviewed pair must have frozen simulation")
        var hash_value := FileAccess.get_sha256(frame.get("image", ""))
        require(hash_value == frame.get("image_sha256", "") and hash_value == acceptance.get(reviewed[frame.label], "") and hash_value.length() == 64, "Reviewed actual image bytes must match")
    require(seen.size() == 2, "Both actual baseline and baked images must be reviewed")
    if seen.size() == 2:
        var before: Dictionary = seen["a-sdfgi-frozen"]
        var after: Dictionary = seen["b-lightmap-frozen"]
        for key: String in ["frozen_state_sha256", "camera_sha256", "rig_sha256"]:
            require(str(before.get(key, "")).length() == 64 and before.get(key) == after.get(key), "Actual comparison state is identical: " + key)
        var rig: Dictionary = after.get("rig", {})
        require(not rig.get("mood_tween_running", true) and rig.get("sky_class", "") == "PhysicalSkyMaterial", "Accepted rig uses settled physical daylight")
        for key: String in ["exposure", "ambient", "sky_energy", "sun_energy", "sun_indirect"]:
            var expected: Dictionary = {"exposure": 1.12, "ambient": 0.18, "sky_energy": 3.98049270761935, "sun_energy": 1.45, "sun_indirect": 0.8}
            require(is_equal_approx(float(rig.get(key, -1.0)), expected[key]), "Accepted rig value matches: " + key)
        require(rig.get("sun_bake_mode", -1) == Light3D.BAKE_DYNAMIC, "Realtime direct-light ownership is retained")
    var live: Dictionary = comparison.get("live_state", {})
    require(float(live.get("time_after", 0.0)) > float(live.get("time_before", 0.0)) and int(live.get("caustic_frames_after", 0)) > int(live.get("caustic_frames_before", 0)), "Actual water and photon time must advance after the frozen pair")
    require(preparation.get("pass", false) and staging.get("pass", false), "Successful preparation and native staging required")
    for path: String in preparation.get("input_sha256", {}): require(FileAccess.get_sha256(path) == preparation.input_sha256[path], "Prepared source changed: " + path)
    require(FileAccess.get_sha256(staging.get("visual", "")) == staging.get("visual_sha256", "") and comparison.get("staged_visual_sha256", "") == staging.get("visual_sha256", ""), "Compared staged visual must be current")
    require(FileAccess.get_sha256(staging.get("data", "")) == staging.get("data_sha256", ""), "Native staged data must be current")
    require(optics.get("pass", false) and optics.get("full_payload_compared", false) and optics.get("grid_size", 0) == 768 and optics.get("candidate_scene_sha256", "") == staging.get("visual_sha256", ""), "Exact full-resolution staged optical proof must be current")
    for row: Dictionary in staging.get("textures", []): require(FileAccess.get_sha256(row.target) == row.sha256, "Accepted original HDR bytes must be current")

func _run() -> void:
    validate_inputs()
    if not errors.is_empty(): finish({}); return
    if phase == "verify-only": finish({"validated_only": true}); return
    if phase == "prepare-assets": prepare_assets(); return
    if not require(DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null and RenderingServer.get_current_rendering_method() == "forward_plus", "Native production serialization requires a real Forward+ rendering device"): finish({}); return
    promote_native()

func prepare_assets() -> void:
    if not require(not FileAccess.file_exists(PLAN) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DEST)), "Inspect any previous/uncertain promotion instead of overwriting"): finish({}); return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
    var rows: Array[Dictionary] = []
    for index in staging.textures.size():
        var old: Dictionary = staging.textures[index]
        var target := DEST + "/indirect_%02d.exr" % index
        require(DirAccess.copy_absolute(ProjectSettings.globalize_path(old.target), ProjectSettings.globalize_path(target)) == OK, "Exact accepted EXR copy")
        require(FileAccess.get_sha256(target) == old.sha256, "Production EXR bytes are unchanged")
        var config := ConfigFile.new()
        require(config.load(old.target + ".import") == OK, "Accepted lossless import recipe exists")
        var imported := "res://.godot/imported/" + target.get_file() + "-" + target.md5_text() + ".ctexarray"
        config.set_value("remap", "uid", ResourceUID.id_to_text(ResourceUID.create_id()))
        config.set_value("remap", "path", imported)
        config.set_value("remap", "metadata", {"vram_texture": false})
        config.set_value("deps", "source_file", target)
        config.set_value("deps", "dest_files", PackedStringArray([imported]))
        config.set_value("params", "compress/mode", 3)
        config.set_value("params", "mipmaps/generate", false)
        require(config.save(target + ".import") == OK, "Production lossless array recipe saves")
        rows.append({"source": old.target, "target": target, "sha256": old.sha256})
    var plan := {"pass": errors.is_empty(), "acceptance_sha256": FileAccess.get_sha256(acceptance_path), "comparison_sha256": FileAccess.get_sha256(comparison_path), "staging_sha256": FileAccess.get_sha256(STAGING), "textures": rows, "status": "accepted_hdr_pending_native_serialization_not_export_ready"}
    if errors.is_empty(): write_json(PLAN, plan)
    finish(plan)

func promote_native() -> void:
    var plan := read_json(PLAN)
    require(plan.get("pass", false) and plan.get("acceptance_sha256", "") == FileAccess.get_sha256(acceptance_path) and plan.get("comparison_sha256", "") == FileAccess.get_sha256(comparison_path) and plan.get("staging_sha256", "") == FileAccess.get_sha256(STAGING), "Current accepted production plan required")
    require(not FileAccess.file_exists(DATA) and not FileAccess.file_exists(RECEIPT) and not FileAccess.file_exists(Installer.SCENE) and not FileAccess.file_exists(HELPER), "Inspect any prior native outcome before retrying")
    if not errors.is_empty(): finish({}); return
    var packed_source := load(staging.visual) as PackedScene
    if not require(packed_source != null, "Accepted native scene loads"): finish({}); return
    var candidate := packed_source.instantiate() as Node3D
    if not require(candidate != null, "Accepted native scene instantiates"): finish({}); return
    var lightmap := candidate.get_node_or_null("Bake_Mainhall_Indirect") as LightmapGI
    if not require(lightmap != null and lightmap.light_data != null, "Accepted native lightmap data resolves"): candidate.free(); finish({}); return
    var original_state := Installer.digest(Installer.stored_lightmap_state(lightmap.light_data))
    require(original_state == staging.native_state.storage_sha256, "Native probe/user storage matches the proven original")
    var textures: Array[TextureLayered] = []
    var texture_receipts: Array[Dictionary] = []
    var old_textures := lightmap.light_data.get_lightmap_textures()
    if not require(plan.get("textures", []).size() == old_textures.size() and not old_textures.is_empty(), "Every original texture has exactly one accepted relocation"): candidate.free(); finish({}); return
    for index in plan.textures.size():
        var row: Dictionary = plan.textures[index]
        require(FileAccess.get_sha256(row.target) == row.sha256, "Production original EXR hash matches")
        var texture := load(row.target) as TextureLayered
        var original: TextureLayered = old_textures[index]
        var import_config := ConfigFile.new()
        require(import_config.load(row.target + ".import") == OK and import_config.get_value("params", "compress/mode", -1) == 3, "Production HDR array import is uncompressed")
        if not require(texture != null and original != null, "Production imported HDR texture resolves"): continue
        if not require([texture.get_width(), texture.get_height(), texture.get_layers(), texture.get_format()] == [original.get_width(), original.get_height(), original.get_layers(), original.get_format()], "Native HDR array shape and format remain exact"): continue
        var hashes: Array[String] = []
        for layer in texture.get_layers():
            var actual := texture.get_layer_data(layer)
            var expected := original.get_layer_data(layer)
            require(actual != null and expected != null and not actual.is_compressed() and actual.get_data() == expected.get_data(), "Native production HDR bits match the finite original layer " + str(layer))
            hashes.append(Installer.digest(actual.get_data()) if actual != null else "missing")
        textures.append(texture)
        texture_receipts.append({"shape_format": [texture.get_width(), texture.get_height(), texture.get_layers(), texture.get_format()], "layer_sha256": hashes, "original_exr_sha256": row.sha256})
    var data := lightmap.light_data.duplicate(false) as LightmapGIData
    data.set_lightmap_textures(textures)
    require(Installer.digest(Installer.stored_lightmap_state(data)) == original_state, "Native duplication and atlas relocation preserve hidden SH and UV mapping")
    if not errors.is_empty(): candidate.free(); finish({}); return
    var library := Materials.new()
    var room := Node3D.new()
    root.add_child(room)
    var layout := Catalog.layout(Installer.COORD, 250821)
    var builder := Builder.new(room, layout, library)
    builder.build_shell(); builder.build_interior()
    var materials: Dictionary = {}
    var visual := candidate.get_node("FormalAuthoredArchitecture") as Node3D
    for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
        for role: String in mesh.get_meta("formal_live_material_roles", PackedStringArray()): materials[role] = Installer.material_signature(library.get_material(role))
    var receipt := {"schema": Installer.SCHEMA, "accepted": true, "scope": "formal_mainhall_static_indirect_only", "engine": "4.6.3", "renderer": "forward_plus",
        "original_visual_sha256": Installer.digest(Installer.visual_profile(room.get_node("FormalAuthoredArchitecture"))),
        "collision_sha256": Installer.digest(Installer.collision_profile(room.get_node("ArchitectureCollision"))),
        "baked_visual_sha256": Installer.digest(Installer.visual_profile(visual)), "materials": materials,
        "lightmap_storage_sha256": original_state, "textures": texture_receipts,
        "provenance": {"source_glb_sha256": preparation.source_sha256, "staged_scene_sha256": staging.visual_sha256,
            "acceptance_sha256": FileAccess.get_sha256(acceptance_path), "full_game_comparison_sha256": FileAccess.get_sha256(comparison_path),
            "full_optical_proof_sha256": FileAccess.get_sha256(OPTICS), "native_staging_proof_sha256": FileAccess.get_sha256(STAGING)},
        "rig": {"sun_bake_mode": Light3D.BAKE_DYNAMIC, "sun_energy": 1.45, "sun_indirect": 0.8, "sun_euler_degrees": Vector3(-62, -28, 0),
            "sun_colour": Color("fff9ee"), "physical_sky_energy": 3.98049270761935, "physical_sky_turbidity": 2.5, "exposure": 1.12, "ambient": 0.18}}
    require(Installer._validate_native_data(data, receipt).is_empty(), "Complete production finite/user/format receipt validates")
    if not errors.is_empty(): room.free(); candidate.free(); finish({}); return
    if not require(ResourceSaver.save(data, DATA) == OK, "Native production data saves"): room.free(); candidate.free(); finish({}); return
    var restored := ResourceLoader.load(DATA, "LightmapGIData", ResourceLoader.CACHE_MODE_IGNORE) as LightmapGIData
    if not require(Installer._validate_native_data(restored, receipt).is_empty(), "Native saved/reloaded data retains exact SH and HDR bits"): room.free(); candidate.free(); finish({}); return
    var resource := Resource.new()
    resource.resource_name = "Accepted mainhall indirect lighting / exact native receipt"
    resource.set_meta("receipt", receipt)
    if not require(ResourceSaver.save(resource, RECEIPT) == OK, "Dependency-linked acceptance resource saves"): room.free(); candidate.free(); finish({}); return
    resource = ResourceLoader.load(RECEIPT, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
    if not require(resource != null and Installer.digest(resource.get_meta("receipt", {})) == Installer.digest(receipt), "External acceptance resource reloads exactly"): room.free(); candidate.free(); finish({}); return
    lightmap.light_data = restored
    candidate.set_meta(Installer.RECEIPT_META, resource)
    candidate.set_meta("formal_bake_status", "accepted_mainhall_static_indirect")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Installer.SCENE.get_base_dir()))
    var packed := PackedScene.new()
    if not require(packed.pack(candidate) == OK and ResourceSaver.save(packed, Installer.SCENE) == OK, "Production visual scene saves"): room.free(); candidate.free(); finish({}); return
    require(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/lighting/runtime_bake_installer_candidate.gd"), ProjectSettings.globalize_path(HELPER)) == OK, "Self-contained runtime helper is promoted without tool dependencies")
    candidate.free()
    var installed := Installer.try_install(room, Installer.COORD, layout, library)
    require(installed.get("pass", false), "Actual exported-path installer succeeds on the native backend: " + str(installed))
    room.free()
    finish({"status": "native_promoted_pending_gameplay_hook_and_export_smoke", "scene": Installer.SCENE, "scene_sha256": FileAccess.get_sha256(Installer.SCENE),
        "data": DATA, "data_sha256": FileAccess.get_sha256(DATA), "receipt": RECEIPT, "receipt_sha256": FileAccess.get_sha256(RECEIPT), "helper": HELPER,
        "textures": plan.textures, "native_installation": installed, "native_state_sha256": original_state,
        "runtime_default_changed": false, "scope": "Accepted image and exact native production serialization. Main integration and exported-package runtime smoke remain required."})

func write_json(path: String, value: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if require(file != null, "Writable proof report: " + path): file.store_string(JSON.stringify(value, "  ") + "\n")

func finish(result: Dictionary) -> void:
    result["pass"] = errors.is_empty()
    result["phase"] = phase
    result["errors"] = errors
    write_json(report_path, result)
    print("ACCEPTED_MAINHALL_PROMOTION ", JSON.stringify(result))
    quit(0 if errors.is_empty() else 2)
