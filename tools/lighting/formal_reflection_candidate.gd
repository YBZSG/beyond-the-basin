extends RefCounted
## QA-only replacement of the EXISTING formal native ReflectionProbe. No
## production caller and no additional overlapping probe or diffuse ambient.
const ROOM_COORD := Vector2i(-1, -1)
const EXISTING_PATH := "NativeLighting/FormalReflectionFallback"
const BASELINE_META := "qa_reflection_baseline"
const CAPTURE_MASK := 1
const RECEIVER_MASK := 1
const LOCAL_CENTER := Vector3(0, 2.45, 0)
const BOX_SIZE := Vector3(22.6, 6.0, 20.6)
const PROPERTIES := ["position", "size", "origin_offset", "box_projection", "blend_distance", "ambient_mode", "ambient_color", "ambient_color_energy", "interior", "intensity", "enable_shadows", "cull_mask", "reflection_mask", "max_distance", "mesh_lod_threshold", "update_mode"]

static func create_probe() -> ReflectionProbe:
    # Pure, unattached configuration object. attach_to_mainhall never inserts it.
    var probe := ReflectionProbe.new()
    probe.position = LOCAL_CENTER
    probe.size = BOX_SIZE
    probe.origin_offset = Vector3.ZERO
    probe.box_projection = true
    probe.blend_distance = 0.6
    probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
    probe.ambient_color_energy = 0.0
    # interior=true removes the complete Environment in Godot Forward+.
    probe.interior = false
    # Match the existing fallback's energy: this comparison is not a boost.
    probe.intensity = 0.85
    probe.enable_shadows = true
    # Preserve baseline capture eligibility. Existing floating props also use
    # layer 1, so this is NOT a claim of dynamic-object exclusion.
    probe.cull_mask = CAPTURE_MASK
    probe.reflection_mask = RECEIVER_MASK
    probe.max_distance = 48.0
    probe.mesh_lod_threshold = 0.0
    probe.update_mode = ReflectionProbe.UPDATE_ONCE
    return probe

static func attach_to_mainhall(room: Node3D, coord: Vector2i) -> ReflectionProbe:
    if room == null or coord != ROOM_COORD: return null
    var existing := room.get_node_or_null(EXISTING_PATH) as ReflectionProbe
    if existing == null or room.find_children("*", "ReflectionProbe", true, false).size() != 1:
        push_warning("Specular QA requires exactly one existing formal fallback; no probe added")
        return null
    var valid_maps := 0
    for lightmap: LightmapGI in room.find_children("*", "LightmapGI", true, false):
        var data := lightmap.light_data
        if data != null and data.get_user_count() == 147 and data.is_using_spherical_harmonics(): valid_maps += 1
    if valid_maps != 1:
        push_warning("Specular QA requires one validated 147-receiver directional lightmap; fallback unchanged")
        return null
    return _configure_existing(existing)

static func _configure_existing(existing: ReflectionProbe) -> ReflectionProbe:
    if existing.has_meta(BASELINE_META): return existing
    var baseline: Dictionary = {}
    for property: String in PROPERTIES: baseline[property] = existing.get(property)
    existing.set_meta(BASELINE_META, baseline)
    var configuration := create_probe()
    for property: String in PROPERTIES: existing.set(property, configuration.get(property))
    configuration.free()
    return existing

static func restore(room: Node3D) -> bool:
    var existing := room.get_node_or_null(EXISTING_PATH) as ReflectionProbe
    if existing == null or not existing.has_meta(BASELINE_META): return false
    var baseline: Dictionary = existing.get_meta(BASELINE_META)
    for property: String in PROPERTIES: existing.set(property, baseline[property])
    existing.remove_meta(BASELINE_META)
    return true

static func refresh_once(probe: ReflectionProbe) -> void:
    # Verified 4.6.3 implementation: setting this same value emits the reflection
    # dependency change, requeues the instance and marks its capture dirty.
    # Never switch to UPDATE_ALWAYS, which can lower the shared atlas quality.
    if probe != null: probe.update_mode = ReflectionProbe.UPDATE_ONCE

static func describe(probe: ReflectionProbe) -> Dictionary:
    if probe == null: return {"enabled": false}
    return {"enabled": true, "candidate_active": probe.has_meta(BASELINE_META),
        "path": str(probe.get_path()) if probe.is_inside_tree() else str(probe.name),
        "instance_id": probe.get_instance_id(), "room_coord": [ROOM_COORD.x, ROOM_COORD.y],
        "local_center": [probe.position.x, probe.position.y, probe.position.z],
        "size": [probe.size.x, probe.size.y, probe.size.z], "origin_offset": probe.origin_offset,
        "box_projection": probe.box_projection, "ambient_mode": probe.ambient_mode,
        "interior": probe.interior, "intensity": probe.intensity,
        "capture_mask": probe.cull_mask, "receiver_mask": probe.reflection_mask,
        "update_mode": probe.update_mode, "shadows": probe.enable_shadows,
        "blend_distance": probe.blend_distance, "max_distance": probe.max_distance,
        "mesh_lod_threshold": probe.mesh_lod_threshold,
        "native_atlas_face_size": ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_size", 256),
        "capture_completion": "No public completion signal. Require settled native baseline/candidate images; configuration is not capture proof."}
