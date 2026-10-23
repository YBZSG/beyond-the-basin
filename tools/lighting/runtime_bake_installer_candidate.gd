extends RefCounted
## Staged production implementation, currently uncalled. Promote this script
## only after the actual full-game pair receives explicit visual acceptance.
## Runtime validation uses loaded resources, not raw GLB/TSCN files which may
## be remapped away in an exported PCK. It never reads excluded lab reports.
const SCENE := "res://scenes/formal_baked/mainhall.tscn"
const COORD := Vector2i(-1, -1)
const META := "accepted_formal_mainhall_bake"
const RECEIPT_META := "formal_bake_acceptance"
const SCHEMA := 1
const AUTHORED_UNIFORMS := [
    "pigment", "grout_pigment", "repeat_metres", "face_roughness",
    "normal_strength", "coat_strength", "water_exposure", "waterline_metres",
    "tile_face_only", "planar_clip_enabled", "upper_plaster", "dado_height",
    "plaster_pigment", "scan_albedo", "scan_normal", "scan_roughness",
    "roughness_value", "metallic_value", "specular_value", "light_emission", "light_energy"]
static var _verified_resources: Dictionary = {}

static func digest(value: Variant) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(value if value is PackedByteArray else var_to_bytes(value))
    return context.finish().hex_encode()

static func failure(reason: String) -> Dictionary:
    return {"installed": false, "pass": false, "fallback": "original_visuals_and_existing_lighting", "reason": reason}

static func engine_compatible() -> bool:
    var info := Engine.get_version_info()
    return info.major == 4 and info.minor == 6 and info.patch == 3

static func mesh_buffers(mesh: ArrayMesh) -> Array:
    var surfaces: Array = mesh.get("_surfaces").duplicate(true)
    for surface: Dictionary in surfaces: surface.erase("material")
    return surfaces

static func visual_profile(visual: Node3D) -> Array:
    var result: Array = []
    for node: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
        if String(node.name).begins_with("COLLISION_") and not node.visible: continue
        if not node.mesh is ArrayMesh: return []
        result.append([str(visual.get_path_to(node)), node.transform, mesh_buffers(node.mesh),
            node.mesh.lightmap_size_hint, node.layers, node.visible, node.cast_shadow,
            node.gi_mode, node.get_meta("source_transmissive", false), node.get_meta("source_exclude_optics", false)])
    return result

static func collision_profile(body: StaticBody3D) -> Array:
    var result: Array = []
    for child: Node in body.get_children():
        if not child is CollisionShape3D or not child.shape is ConvexPolygonShape3D: return []
        result.append([child.transform, child.disabled, child.shape.points])
    return [body.transform, body.collision_layer, body.collision_mask, result]

static func shader_signature(shader: Shader) -> String:
    if shader == null: return "missing"
    var includes: Array = []
    var expression := RegEx.new()
    expression.compile('#include\\s+"([^"]+)"')
    # The authored shaders have one flat shared include. Record its loaded
    # resource code as well; source strings alone do not expand #include.
    for match_value: RegExMatch in expression.search_all(shader.code):
        var path := match_value.get_string(1)
        if not ResourceLoader.exists(path): return "missing_include:" + path
        var include: Resource = load(path)
        if include == null or not include.get("code") is String: return "invalid_include:" + path
        includes.append([path, include.get("code")])
    return digest([shader.code, includes])

static func material_signature(material: Material) -> String:
    if material is ShaderMaterial:
        var values: Array = []
        for key: String in AUTHORED_UNIFORMS:
            var value: Variant = material.get_shader_parameter(key)
            if value is Texture: value = [value.get_class(), value.resource_path]
            values.append([key, value])
        # Photon textures, gain, current room origin and wall extents are
        # intentionally NOT baked-state inputs. Their live values must survive.
        return digest([shader_signature(material.shader), values])
    if material is StandardMaterial3D:
        return digest([material.transparency, material.albedo_color, material.roughness,
            material.metallic, material.metallic_specular, material.cull_mode,
            material.emission_enabled, material.emission, material.emission_energy_multiplier])
    return "unsupported_material"

static func stored_lightmap_state(data: LightmapGIData) -> Dictionary:
    var result: Dictionary = {}
    for property: Dictionary in data.get_property_list():
        var key := str(property.name)
        if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
        if key.begins_with("resource_") or key in ["script", "lightmap_textures", "light_texture", "shadowmask_textures"]: continue
        result[key] = data.get(key)
    return result

static func _validate_native_data(data: LightmapGIData, receipt: Dictionary) -> String:
    if data == null or data.get_user_count() != 147 or not data.is_using_spherical_harmonics(): return "Wrong directional receiver data"
    if not data.get_shadowmask_textures().is_empty(): return "Unexpected baked direct shadow mask"
    if digest(stored_lightmap_state(data)) != receipt.get("lightmap_storage_sha256", ""): return "Native user, UV or SH state changed"
    var probes: Dictionary = data.get("probe_data")
    var coefficients: PackedColorArray = probes.get("sh", PackedColorArray())
    if coefficients.size() != 1692: return "Expected all native probe coefficients"
    for value: Color in coefficients:
        if not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b) or not is_finite(value.a): return "Non-finite native probe coefficient"
    var textures := data.get_lightmap_textures()
    if not receipt.get("textures", null) is Array: return "Malformed texture receipt"
    var expected: Array = receipt["textures"]
    if textures.size() != expected.size() or textures.is_empty(): return "Lightmap texture count changed"
    for index in textures.size():
        var texture: TextureLayered = textures[index]
        if texture == null or not expected[index] is Dictionary: return "Missing texture or malformed layer receipt"
        var row: Dictionary = expected[index]
        if not row.get("layer_sha256", null) is Array: return "Malformed layer hash receipt"
        if [texture.get_width(), texture.get_height(), texture.get_layers(), texture.get_format()] != row.get("shape_format", []): return "Lightmap HDR format or dimensions changed"
        var hashes: Array = row.get("layer_sha256", [])
        if hashes.size() != texture.get_layers(): return "Incomplete per-layer finite-data receipt"
        for layer in texture.get_layers():
            var image := texture.get_layer_data(layer)
            if image == null or image.is_compressed() or digest(image.get_data()) != hashes[layer]: return "Imported HDR samples differ from accepted finite radiance"
    return ""

static func clear_scene_owners(node: Node) -> void:
    # Runtime-only reparenting, never a PackedScene serialization operation.
    node.owner = null
    for child: Node in node.get_children(): clear_scene_owners(child)

static func try_install(room: Node3D, coord: Vector2i, layout: Dictionary, library: RefCounted) -> Dictionary:
    if room == null or coord != COORD or not layout.get("formal", false) or layout.get("coord", Vector2i.ZERO) != COORD:
        return failure("Only the selectable authored mainhall is eligible")
    if room.get_meta(META, false): return {"pass": true, "installed": true, "already_installed": true}
    if not engine_compatible() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_rendering_device() == null:
        return failure("This native bake is not validated on the active backend")
    if library == null or not library.has_method("get_material") or not ResourceLoader.exists(SCENE): return failure("Accepted resources or live material library are unavailable")
    var old := room.get_node_or_null("FormalAuthoredArchitecture") as Node3D
    var collision := room.get_node_or_null("ArchitectureCollision") as StaticBody3D
    if old == null or collision == null or collision.get_child_count() != 254: return failure("Expected original mainhall and untouched colliders")
    if not room.find_children("*", "LightmapGI", true, false).is_empty(): return failure("Ambiguous existing LightmapGI ownership")
    var packed := load(SCENE) as PackedScene
    if packed == null: return failure("Accepted scene could not load")
    var candidate := packed.instantiate() as Node3D
    if candidate == null: return failure("Accepted scene could not instantiate")
    var receipt_resource := candidate.get_meta(RECEIPT_META, null) as Resource
    var receipt_value: Variant = receipt_resource.get_meta("receipt", {}) if receipt_resource != null else {}
    if not receipt_value is Dictionary:
        candidate.free()
        return failure("Malformed accepted-production receipt")
    var receipt: Dictionary = receipt_value
    var error := ""
    if receipt.get("schema", 0) != SCHEMA or receipt.get("accepted", false) != true: error = "No explicit accepted-production receipt"
    elif receipt.get("scope", "") != "formal_mainhall_static_indirect_only": error = "Receipt scope does not match"
    elif not receipt.get("materials", null) is Dictionary: error = "Malformed authored material receipt"
    elif receipt.get("renderer", "") != "forward_plus" or receipt.get("engine", "") != "4.6.3": error = "Receipt backend does not match"
    var visual := candidate.get_node_or_null("FormalAuthoredArchitecture") as Node3D
    var lightmap := candidate.get_node_or_null("Bake_Mainhall_Indirect") as LightmapGI
    if visual == null or lightmap == null: error = "Accepted scene lacks visual or lightmap nodes"
    if not candidate.find_children("*", "CollisionObject3D", true, false).is_empty() or not candidate.find_children("*", "Light3D", true, false).is_empty() or not candidate.find_children("*", "WorldEnvironment", true, false).is_empty() or not candidate.find_children("*", "Camera3D", true, false).is_empty(): error = "Artifact may not replace physics or add a second lighting rig/camera"
    if error.is_empty() and (digest(visual_profile(old)) != receipt.get("original_visual_sha256", "") or digest(collision_profile(collision)) != receipt.get("collision_sha256", "")):
        error = "Current original geometry or collision differs from the accepted source"
    if error.is_empty() and digest(visual_profile(visual)) != receipt.get("baked_visual_sha256", ""): error = "Native UV2 visual buffers changed"
    if error.is_empty():
        var material_hashes: Dictionary = receipt.get("materials", {})
        for role: String in material_hashes:
            if material_signature(library.get_material(role)) != material_hashes[role]: error = "Authored live material changed: " + role
        var bound := 0
        for node: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
            var roles: PackedStringArray = node.get_meta("formal_live_material_roles", PackedStringArray())
            var original := old.get_node_or_null(visual.get_path_to(node)) as MeshInstance3D
            if original == null or roles.size() != node.mesh.get_surface_count(): error = "Incomplete source/live material role mapping"; break
            for index in roles.size():
                if not material_hashes.has(roles[index]): error = "Unaccepted material role"; break
                var material: Material = library.get_material(roles[index])
                if original.get_active_material(index) != material: error = "Original material ownership changed"; break
                node.set_surface_override_material(index, material)
                bound += 1
        if bound != 223: error = "Expected all 223 live material surfaces"
    if error.is_empty():
        var key := str(packed.get_instance_id()) + ":" + digest(receipt)
        if not _verified_resources.has(key):
            error = _validate_native_data(lightmap.light_data, receipt)
            # Retain the immutable PackedScene so room return/spawn reuses the
            # validated resource rather than repeating 48 GPU layer readbacks.
            if error.is_empty(): _verified_resources[key] = packed
        if error.is_empty():
            for index in lightmap.light_data.get_user_count():
                if not lightmap.has_node(lightmap.light_data.get_user_path(index)): error = "Native receiver path is unresolved"
    if not error.is_empty(): candidate.free(); return failure(error)
    var sibling_index := old.get_index()
    var original_shapes := collision.get_children()
    var collision_id := collision.get_instance_id()
    clear_scene_owners(visual); clear_scene_owners(lightmap)
    candidate.remove_child(visual); candidate.remove_child(lightmap)
    room.remove_child(old)
    room.add_child(visual); room.move_child(visual, sibling_index)
    room.add_child(lightmap)
    for index in lightmap.light_data.get_user_count():
        if not lightmap.has_node(lightmap.light_data.get_user_path(index)): error = "Moved receiver path is unresolved"
    if collision.get_instance_id() != collision_id or collision.get_children() != original_shapes: error = "Physics identity changed"
    if not error.is_empty():
        room.remove_child(visual); room.remove_child(lightmap)
        room.add_child(old); room.move_child(old, sibling_index)
        visual.free(); lightmap.free(); candidate.free()
        return failure(error + "; original visuals restored")
    old.free(); candidate.free()
    room.set_meta(META, true)
    room.set_meta("formal_bake_receipt_sha256", digest(receipt))
    room.set_meta("formal_bake_original_collision_id", collision_id)
    return {"pass": true, "installed": true, "static_receivers": 147, "live_material_surfaces": 223,
        "original_collider_shapes": 254, "static_lightmap_independent_of_dynamic_sdfgi_setting": true,
        "receipt_sha256": digest(receipt), "needs_mainhall_rig_selection": true}
