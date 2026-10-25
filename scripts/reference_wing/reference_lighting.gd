extends "res://scripts/rendering/pool_lighting.gd"
## Native binding for the five new references only. The legacy environment,
## source fixtures, formal lighting and source photon transport stay unchanged.
## No rectangular-light API: the pinned target PT supports POINT/SPOT only.

const MAX_VISIBLE_LIGHTS := 27
const MAX_SHADOWED_LIGHTS := 4
const SOURCE_ENERGY_SCALE := 0.07
var _reference_lights: Array[WeakRef] = []
var _reference_active := false

static func _vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

static func binding(source: Dictionary) -> Dictionary:
	var authored: Dictionary = source.get("reference_light", source)
	var at := _vector(authored.get("position"), _vector(source.get("position"), Vector3.ZERO))
	var direction := _vector(authored.get("direction", authored.get("emission_direction")), Vector3.ZERO)
	if direction.is_zero_approx() and authored.has("target"):
		direction = _vector(authored.target, at) - at
	var kind := String(authored.get("native_type", "")).to_lower()
	if kind.is_empty():
		kind = "spot" if not direction.is_zero_approx() else String(authored.get("type", "omni")).to_lower()
	assert(kind in ["spot", "omni", "point"], "Reference light needs an explicit supported native type: " + kind)
	if kind == "spot": assert(not direction.is_zero_approx(), "Reference spot needs an authored direction")
	var rgb: Variant = authored.get("color", source.get("color", Color.WHITE))
	var color: Color = rgb if rgb is Color else Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	var color_space := String(authored.get("color_space", "srgb")).to_lower()
	assert(color_space in ["srgb", "linear"], "Reference light color space must be explicit linear/srgb")
	# Blender Light.color is scene-linear. Light3D stores sRGB and both native
	# rendering and the original liquid collector decode it to linear once.
	if color_space == "linear": color = color.linear_to_srgb()
	return {
		"name": String(authored.get("name", "ReferenceFixture")),
		"fixture_object": String(authored.get("fixture_object", source.get("fixture_object", authored.get("name", "")))),
		"type": "spot" if kind == "spot" else "omni", "position": at,
		"direction": direction.normalized(), "color": color, "authored_color_space": color_space,
		"energy": maxf(0.0, float(authored.get("native_energy", authored.get("energy", float(source.get("power", 1.0 / SOURCE_ENERGY_SCALE)) * SOURCE_ENERGY_SCALE)))),
		"range": clampf(float(authored.get("range", source.get("range", 6.0))), 1.0, 20.0),
		"radius": clampf(float(authored.get("emitter_radius", 0.005)), 0.0, 1.0),
		"attenuation": clampf(float(authored.get("attenuation", 2.0)), 0.0, 10.0),
		"spot_angle": clampf(float(authored.get("spot_angle_deg", 80.0)), 1.0, 89.0),
		"spot_attenuation": maxf(0.001, float(authored.get("spot_angle_attenuation", 0.25))),
		"shadow": bool(authored.get("shadow", source.get("shadow", true))),
		"specular": clampf(float(authored.get("native_specular", 0.0)), 0.0, 1.0),
	}

func add_room_lights(room: Node3D, variant: int) -> void:
	var layout: Dictionary = room.get_meta("layout", {})
	if not layout.get("reference_wing", false):
		super.add_room_lights(room, variant)
		return
	if room.has_node("NativeLighting"): return
	_prune_reference_lights()
	var rig := Node3D.new()
	rig.name = "NativeLighting"
	rig.set_meta("reference_wing", true)
	rig.set_meta("variant", variant)
	room.add_child(rig)
	var fixtures: Array = layout.get("fixtures", [])
	for slot in fixtures.size():
		var source: Dictionary = fixtures[slot]
		if not source.get("alive", true): continue
		var spec := binding(source)
		var lamp: Light3D
		if spec.type == "spot":
			var spot := SpotLight3D.new()
			spot.spot_range = spec.range
			spot.spot_attenuation = spec.attenuation
			spot.spot_angle = spec.spot_angle
			spot.spot_angle_attenuation = spec.spot_attenuation
			# Godot emits along local -Z. A nonparallel up axis also handles
			# exactly vertical up/down coves and ceiling fixtures without NaNs.
			var up := Vector3.FORWARD if absf(spec.direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
			spot.basis = Basis.looking_at(spec.direction, up)
			lamp = spot
		else:
			var point := OmniLight3D.new()
			point.omni_range = spec.range
			point.omni_attenuation = spec.attenuation
			lamp = point
		lamp.name = "ReferenceLight_%02d_%s" % [slot, spec.name]
		lamp.position = spec.position
		_configure_local_light(lamp, spec.color, spec.energy, spec.radius)
		# Extended strip/window glints come from the authored emissive geometry,
		# not an invented spherical glint. This remains a direct-light proxy.
		lamp.light_specular = spec.specular
		lamp.visible = false
		lamp.shadow_enabled = false
		lamp.set_meta("reference_binding", spec)
		lamp.set_meta("reference_authored_shadow", spec.shadow)
		lamp.set_meta("source_power_per_energy", 1.0 / SOURCE_ENERGY_SCALE)
		lamp.set_meta("source_shadow_priority", true)
		lamp.set_meta("source_shadow_managed", true)
		lamp.set_meta("source_room_coord", room.get_meta("coord", layout.get("coord", Vector2i.ZERO)))
		rig.add_child(lamp)
		_reference_lights.append(weakref(lamp))
	_add_reflection_probe(rig, float(layout.get("interior_ceiling", layout.get("ceiling", 5.5))), false)
	_room_roots.append(weakref(rig))

func update_active_room(coord: Vector2i, layout: Dictionary) -> void:
	var was_reference := _reference_active
	_reference_active = bool(layout.get("reference_wing", false))
	# A mode switch may reuse (0,0). Preserve the inherited environment's
	# normal transition even when this new room shares the prior coordinate.
	if was_reference != _reference_active: super.invalidate_active_room()
	if not _reference_active: _hide_reference_lights()
	else: _hide_legacy_source_lights()
	super.update_active_room(coord, layout)

func _prune_reference_lights() -> void:
	var alive: Array[WeakRef] = []
	for reference: WeakRef in _reference_lights:
		if is_instance_valid(reference.get_ref()): alive.append(reference)
	_reference_lights = alive
	# A rebuild can reuse the coordinate and skip the base active-room pass.
	# Do not retain dead rig weakrefs until the player crosses another portal.
	var rigs: Array[WeakRef] = []
	for reference: WeakRef in _room_roots:
		if is_instance_valid(reference.get_ref()): rigs.append(reference)
	_room_roots = rigs

func _hide_reference_lights() -> void:
	_prune_reference_lights()
	for reference: WeakRef in _reference_lights:
		var lamp := reference.get_ref() as Light3D
		lamp.visible = false
		lamp.shadow_enabled = false

func _hide_legacy_source_lights() -> void:
	var alive: Array[WeakRef] = []
	for reference: WeakRef in _source_lights:
		var lamp := reference.get_ref() as Light3D
		if not is_instance_valid(lamp): continue
		alive.append(reference)
		lamp.visible = false
		lamp.shadow_enabled = false
	_source_lights = alive

func update_source_view(camera: Camera3D) -> void:
	if not _reference_active:
		_hide_reference_lights()
		super.update_source_view(camera)
		return
	_hide_legacy_source_lights()
	_prune_reference_lights()
	if not is_instance_valid(camera):
		_hide_reference_lights()
		return
	var selected: Array[Dictionary] = []
	var focus := camera.global_position
	var forward := -camera.global_basis.z
	for index in _reference_lights.size():
		var lamp := _reference_lights[index].get_ref() as Light3D
		var coord: Vector2i = lamp.get_meta("source_room_coord", Vector2i.ZERO)
		var delta := coord - _last_coord
		lamp.visible = false
		lamp.shadow_enabled = false
		if maxi(absi(delta.x), absi(delta.y)) > 1: continue
		# Rooms hidden while retired must not reserve the live world's budget.
		if not lamp.get_parent().is_visible_in_tree(): continue
		var relative := lamp.global_position - focus
		var along := relative.dot(forward)
		selected.append({"light": lamp, "active": coord == _last_coord,
			"score": relative.length_squared() - along * along + (2500.0 if along < 0.0 else 0.0), "order": index})
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.active != b.active: return a.active
		# Match the source's stable active-fixture ordering: turning the camera
		# must not swap the current room's four raster shadow maps every frame.
		if a.active: return a.order < b.order
		if not is_equal_approx(a.score, b.score): return a.score < b.score
		return a.order < b.order)
	var shadow_count := 0
	for index in mini(selected.size(), MAX_VISIBLE_LIGHTS):
		var lamp: Light3D = selected[index].light
		lamp.visible = true
		lamp.shadow_enabled = shadow_count < MAX_SHADOWED_LIGHTS and bool(lamp.get_meta("reference_authored_shadow", true)) and bool(lamp.get_meta("source_shadows_allowed", true))
		if lamp.shadow_enabled: shadow_count += 1

func reference_lighting_stats() -> Dictionary:
	_prune_reference_lights()
	var visible_count := 0
	var shadow_count := 0
	for reference: WeakRef in _reference_lights:
		var lamp := reference.get_ref() as Light3D
		if lamp.is_visible_in_tree():
			visible_count += 1
			if lamp.shadow_enabled: shadow_count += 1
	return {"active": _reference_active, "tracked": _reference_lights.size(), "visible": visible_count, "shadowed": shadow_count,
		"visible_limit": MAX_VISIBLE_LIGHTS, "raster_shadow_limit": MAX_SHADOWED_LIGHTS}
