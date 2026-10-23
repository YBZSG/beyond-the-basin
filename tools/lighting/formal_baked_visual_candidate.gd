extends RefCounted
## Explicit QA-only installation of a proven quarantined artifact. No caller
## in the production builder/default path. All checks precede the atomic swap.
const VISUAL := "res://scenes/lighting_lab/runtime_mainhall_candidate.tscn"
const STAGING := "res://docs/verification/eight-hour/material-lighting/native-visual-staging.json"
const OPTICS := "res://docs/verification/eight-hour/material-lighting/final-baked-source-optics-contract-staged-full.json"
const PREPARATION := "res://assets/lighting/final_mainhall/preparation_manifest.json"
const SOURCE := "res://assets/models/formal/formal_mainhall.glb"
const PHYSICAL_SKY_ENERGY := 3.98049270761935

static func _read(path: String) -> Dictionary:
    if not FileAccess.file_exists(path): return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return value if value is Dictionary else {}

static func _hash(value: Variant) -> String:
    var hasher := HashingContext.new()
    hasher.start(HashingContext.HASH_SHA256)
    hasher.update(var_to_bytes(value))
    return hasher.finish().hex_encode()

static func _failure(reason: String) -> Dictionary:
    return {"pass": false, "installed": false, "reason": reason, "runtime_default_changed": false}

static func clear_scene_owners(node: Node) -> void:
    # Runtime-only reparenting, never a PackedScene serialization operation.
    node.owner = null
    for child: Node in node.get_children(): clear_scene_owners(child)

static func install(room: Node3D, coord: Vector2i, library: RefCounted, environment: Environment, sun: DirectionalLight3D) -> Dictionary:
    if room == null or coord != Vector2i(-1, -1): return _failure("Only the formal mainhall is eligible")
    if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
        return _failure("Native SH validation requires a real rendering device")
    if room.get_meta("qa_native_mainhall_installed", false): return audit(room, library, environment, sun)
    if library == null or not library.has_method("get_material"): return _failure("The existing live material library is required")
    var environment_errors := _environment_errors(environment, sun)
    if not environment_errors.is_empty(): return _failure(str(environment_errors))
    var staged := _read(STAGING)
    var optics := _read(OPTICS)
    var preparation := _read(PREPARATION)
    if not staged.get("pass", false) or staged.get("phase", "") != "stage-native": return _failure("Successful native staging proof is required")
    if not optics.get("pass", false) or not optics.get("full_payload_compared", false) or optics.get("grid_size", 0) != 768: return _failure("Full-resolution staged optical equivalence is required")
    if not preparation.get("pass", false): return _failure("Successful pinned preparation is required")
    for path: String in preparation.input_sha256:
        if FileAccess.get_sha256(path) != preparation.input_sha256[path]: return _failure("Prepared input changed: " + path)
    if FileAccess.get_sha256(SOURCE) != preparation.source_sha256: return _failure("Source geometry changed")
    if not FileAccess.file_exists(VISUAL) or FileAccess.get_sha256(VISUAL) != staged.get("visual_sha256", ""): return _failure("Staged visual hash changed")
    if optics.get("candidate_scene_sha256", "") != FileAccess.get_sha256(VISUAL) or optics.get("source_model_sha256", "") != preparation.source_sha256: return _failure("Staged optical proof is stale")
    if FileAccess.get_sha256(staged.get("data", "")) != staged.get("data_sha256", ""): return _failure("Staged lightmap data changed")
    for texture: Dictionary in staged.get("textures", []):
        if FileAccess.get_sha256(texture.target) != texture.sha256: return _failure("Staged HDR bytes changed")
    var old := room.get_node_or_null("FormalAuthoredArchitecture") as Node3D
    var collision := room.get_node_or_null("ArchitectureCollision") as StaticBody3D
    if old == null or collision == null or collision.get_child_count() != 254: return _failure("Expected original visuals and 254 untouched collider shapes")
    if not room.find_children("*", "LightmapGI", true, false).is_empty(): return _failure("An existing lightmap makes ownership ambiguous")
    var packed := load(VISUAL) as PackedScene
    if packed == null: return _failure("Staged PackedScene did not load")
    var candidate := packed.instantiate() as Node3D
    var visual := candidate.get_node_or_null("FormalAuthoredArchitecture") as Node3D
    var lightmap := candidate.get_node_or_null("Bake_Mainhall_Indirect") as LightmapGI
    var error := ""
    if visual == null or lightmap == null or lightmap.light_data == null: error = "Missing staged architecture or data"
    elif candidate.get_meta("formal_bake_source_glb_sha256", "") != preparation.source_sha256: error = "Packed visual provenance differs"
    elif not candidate.find_children("*", "CollisionObject3D", true, false).is_empty(): error = "Visual artifact must not contain physics"
    else:
        var data := lightmap.light_data
        var probe_data: Dictionary = data.get("probe_data")
        if data.get_user_count() != 147 or not data.is_using_spherical_harmonics() or _hash(probe_data) != staged.native_state.probe_sha256:
            error = "Native directional users or probe coefficients differ from the accepted staging proof"
        for index in data.get_user_count():
            if not lightmap.has_node(data.get_user_path(index)): error = "A native receiver path is unresolved"
    if not error.is_empty(): candidate.free(); return _failure(error)
    var mesh_count := 0
    var surfaces := 0
    for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
        mesh_count += 1
        var roles: PackedStringArray = mesh.get_meta("formal_live_material_roles", PackedStringArray())
        if roles.size() != mesh.mesh.get_surface_count(): error = "A surface lacks an explicit live role"
        for index in roles.size():
            var material: Material = library.get_material(roles[index])
            if material == null: error = "A live material role cannot resolve"
            else: mesh.set_surface_override_material(index, material)
            surfaces += 1
    if mesh_count != 223 or surfaces != 223: error = "Expected all 223 live-bound surfaces"
    if not error.is_empty(): candidate.free(); return _failure(error)
    var index := old.get_index()
    var collision_id := collision.get_instance_id()
    var collision_shapes := collision.get_children()
    # No awaits: no partially swapped scene can be observed by another frame.
    # Preserve the architectural sibling/DFS position and original colliders.
    clear_scene_owners(visual); clear_scene_owners(lightmap)
    candidate.remove_child(visual)
    candidate.remove_child(lightmap)
    room.remove_child(old)
    room.add_child(visual)
    room.move_child(visual, index)
    room.add_child(lightmap)
    for user in lightmap.light_data.get_user_count():
        if not lightmap.has_node(lightmap.light_data.get_user_path(user)): error = "Moved native receiver path failed"
    if collision.get_instance_id() != collision_id or collision.get_children() != collision_shapes: error = "Original physics identity changed"
    if not error.is_empty():
        room.remove_child(visual); room.remove_child(lightmap)
        room.add_child(old); room.move_child(old, index)
        visual.free(); lightmap.free(); candidate.free()
        return _failure(error + "; original visual restored")
    old.free(); candidate.free()
    room.set_meta("qa_native_mainhall_installed", true)
    room.set_meta("qa_native_mainhall_artifact", staged.visual_sha256)
    room.set_meta("qa_native_mainhall_collider_id", collision_id)
    return audit(room, library, environment, sun)

static func _environment_errors(environment: Environment, sun: DirectionalLight3D) -> Array[String]:
    var errors: Array[String] = []
    if environment == null or environment.sky == null or not environment.sky.sky_material is PhysicalSkyMaterial:
        errors.append("Accepted PhysicalSky is required")
    elif absf(environment.sky.sky_material.energy_multiplier - PHYSICAL_SKY_ENERGY) > 0.00001:
        errors.append("PhysicalSky energy differs from the baked rig")
    if environment != null and (absf(environment.tonemap_exposure - 1.12) > 0.00001 or absf(environment.ambient_light_energy - 0.18) > 0.00001):
        errors.append("Formal exposure/ambient tween has not settled")
    if sun == null or sun.light_bake_mode != Light3D.BAKE_DYNAMIC or not sun.shadow_enabled:
        errors.append("Realtime-direct, shadowed Sun is required")
    elif absf(sun.light_energy - 1.45) > 0.00001 or absf(sun.light_indirect_energy - 0.8) > 0.00001:
        errors.append("Live Sun has not settled to the baked formal rig")
    if sun != null:
        var expected_ray := Basis.from_euler(Vector3(deg_to_rad(-62.0), deg_to_rad(-28.0), 0)).z.normalized()
        if sun.global_basis.z.normalized().distance_to(expected_ray) > 0.000002 or not sun.light_color.is_equal_approx(Color("fff9ee")):
            errors.append("Live Sun direction or colour differs from the baked rig")
    return errors

static func audit(room: Node3D, library: RefCounted, environment: Environment, sun: DirectionalLight3D) -> Dictionary:
    var errors := _environment_errors(environment, sun)
    var lightmap := room.get_node_or_null("Bake_Mainhall_Indirect") as LightmapGI
    var visual := room.get_node_or_null("FormalAuthoredArchitecture") as Node3D
    var collision := room.get_node_or_null("ArchitectureCollision") as StaticBody3D
    var count := 0
    var static_count := 0
    var dynamic_count := 0
    var glazing := 0
    var bound := 0
    if lightmap == null or visual == null or collision == null: return _failure("Live baked nodes are incomplete")
    for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
        count += 1
        if mesh.gi_mode == GeometryInstance3D.GI_MODE_STATIC: static_count += 1
        elif mesh.gi_mode == GeometryInstance3D.GI_MODE_DYNAMIC: dynamic_count += 1
        elif mesh.get_meta("source_transmissive", false): glazing += 1
        var roles: PackedStringArray = mesh.get_meta("formal_live_material_roles", PackedStringArray())
        for index in roles.size():
            if mesh.get_active_material(index) == library.get_material(roles[index]): bound += 1
            else: errors.append("Live material identity differs: " + str(mesh.name))
    var data := lightmap.light_data
    var probes: Dictionary = data.get("probe_data")
    for index in data.get_user_count():
        if not lightmap.has_node(data.get_user_path(index)): errors.append("Unresolved live lightmap user")
    if [count, static_count, dynamic_count, glazing, bound] != [223, 147, 65, 11, 223]: errors.append("Unexpected live mesh/GI/material ownership counts")
    if collision.get_instance_id() != room.get_meta("qa_native_mainhall_collider_id", -1) or collision.get_child_count() != 254: errors.append("Original collider identity changed")
    return {"pass": errors.is_empty(), "installed": true, "errors": errors, "coord": [-1, -1], "visuals": count, "static_lightmap_receivers": static_count, "dynamic_probe_receivers": dynamic_count, "transmissive_glazing": glazing, "shared_live_material_surfaces": bound, "native_users": data.get_user_count(), "native_probe_coefficients": probes.get("sh", PackedColorArray()).size(), "probe_sha256": _hash(probes), "collider_shapes": collision.get_child_count(), "original_collider_instance_id": collision.get_instance_id(), "sun_bake_mode": sun.light_bake_mode, "sdfgi_still_enabled": environment.sdfgi_enabled, "runtime_default_changed": false, "scope": "Actual native binding/configuration evidence; no claim of visual acceptance or observed moving shadows."}
