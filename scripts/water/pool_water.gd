class_name PoolWater
extends Node3D
## Source-based Godot migration of InteractiveWater/ShallowWater/SplashParticles.
## Native shader/heightfield, not a Three shader pasted into an unlit plane.
## Externally owned rooms are free to stream out; stale references are pruned.

const Field = preload("res://scripts/water/water_field.gd")
const WATER_SHADER = preload("res://shaders/water_surface.gdshader")
const WATER_LEVEL: float = 0.32
const ROOM_SIZE: float = 32.0
const MAX_IMPACTS: int = 32
const MAX_DROPS: int = 512
const MAX_BUBBLES: int = 384
const QUALITY := {
	"Low": {"surface": 40, "steps": 6, "ssr": false, "micro": 0.45},
	"Medium": {"surface": 64, "steps": 10, "ssr": true, "micro": 0.6},
	"High": {"surface": 96, "steps": 14, "ssr": true, "micro": 0.65},
	"Ultra": {"surface": 160, "steps": 22, "ssr": true, "micro": 0.8},
}

var quality: String = "High"
var caustics_enabled: bool = true
var enabled: bool = true
var interaction_count: int = 0
var ripple_returns: int = 0
var field: PoolWaterField = Field.new()
var _materials: Dictionary = {}
var _rooms: Dictionary = {}
var _surfaces: Dictionary = {}
var _layouts: Dictionary = {}
var _plane: PlaneMesh
var _time: float = 0.0
var _impacts: Array[Vector4] = []
var _drops: Array[Dictionary] = []
var _bubbles: Array[Dictionary] = []
var _drop_mesh: MultiMeshInstance3D
var _bubble_mesh: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _material_library: RefCounted
var _prune_timer: float = 0.0
var _wake_ring_timer: float = 0.0
var _configured: bool = false
var _tuning: Dictionary = {}

func configure(material_library: RefCounted) -> void:
	_material_library = material_library
	if _configured:
		return
	_configured = true
	_rng.seed = 516224
	_build_plane()
	_create_particles()
	set_process(true)

func _ready() -> void:
	if not _configured:
		configure(null)

func _build_plane() -> void:
	_plane = PlaneMesh.new()
	_plane.size = Vector2(ROOM_SIZE, ROOM_SIZE)
	_plane.subdivide_width = int(QUALITY[quality].surface)
	_plane.subdivide_depth = int(QUALITY[quality].surface)

func add_room(room: Node3D, coord: Vector2i, layout: Dictionary) -> void:
	if not _configured:
		configure(_material_library)
	if not is_instance_valid(room):
		return
	if _surfaces.has(coord):
		# A streamed-out Node may already be freed while water processing is
		# paused. Validate the Variant before any typed assignment or cast.
		if is_instance_valid(_surfaces[coord]):
			var existing := _surfaces[coord] as MeshInstance3D
			if existing.get_parent() == room:
				return
		remove_room(coord)
	var state: ImageTexture = field.add_room(coord, layout)
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.resource_name = "Connected pool water %s" % coord
	material.render_priority = 0
	material.set_shader_parameter("water_state", state)
	material.set_shader_parameter("room_center", Vector2(coord) * ROOM_SIZE)
	material.set_shader_parameter("simulation_resolution", float(field.resolution))
	material.set_shader_parameter("pool_floor", float(layout.get("water_floor_y", -0.78)))
	_apply_material_quality(material)
	var surface := MeshInstance3D.new()
	surface.name = "ConnectedWater"
	surface.mesh = _plane
	surface.material_override = material
	surface.position.y = WATER_LEVEL
	# Layer 2 receives the room reflection probes while staying out of their
	# opaque layer-1 capture. No recursive water / screen-texture feedback.
	surface.layers = 2
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.extra_cull_margin = 0.4
	surface.visible = enabled and bool(layout.get("water_enabled", true))
	room.add_child(surface)
	_rooms[coord] = weakref(room)
	_surfaces[coord] = surface
	_materials[coord] = material
	_layouts[coord] = layout
	# Lifecycle signals still run while _process is disabled (for example in
	# the travel menu). The identity guard prevents an old room's deferred exit
	# from deleting the freshly registered replacement at the same coordinate.
	var exit_handler: Callable = _on_room_tree_exiting.bind(coord, room.get_instance_id())
	if not room.tree_exiting.is_connected(exit_handler):
		room.tree_exiting.connect(exit_handler, CONNECT_ONE_SHOT)

func _on_room_tree_exiting(coord: Vector2i, room_id: int) -> void:
	var registered: WeakRef = _rooms.get(coord)
	if registered == null:
		return
	var registered_room: Variant = registered.get_ref()
	if is_instance_valid(registered_room) and registered_room.get_instance_id() == room_id:
		remove_room(coord)

func remove_room(coord: Vector2i) -> void:
	if _surfaces.has(coord) and is_instance_valid(_surfaces[coord]):
		(_surfaces[coord] as MeshInstance3D).queue_free()
	_surfaces.erase(coord)
	_materials.erase(coord)
	_rooms.erase(coord)
	_layouts.erase(coord)
	field.remove_room(coord)

func set_enabled(value: bool) -> void:
	enabled = value
	for key in _surfaces:
		if is_instance_valid(_surfaces[key]):
			(_surfaces[key] as MeshInstance3D).visible = value and bool(_layouts[key].get("water_enabled", true))
	if is_instance_valid(_drop_mesh):
		_drop_mesh.visible = value
		_bubble_mesh.visible = value

func set_quality(value: String) -> void:
	var normalized := value.capitalize()
	if not QUALITY.has(normalized):
		push_warning("Unknown water quality '%s'; preserving %s." % [value, quality])
		return
	quality = normalized
	_build_plane()
	for key in _materials:
		_apply_material_quality(_materials[key])
		if is_instance_valid(_surfaces[key]):
			(_surfaces[key] as MeshInstance3D).mesh = _plane

func _apply_material_quality(material: ShaderMaterial) -> void:
	var preset: Dictionary = QUALITY[quality]
	material.set_shader_parameter("trace_steps", preset.steps)
	material.set_shader_parameter("ssr_enabled", preset.ssr)
	material.set_shader_parameter("micro_strength", preset.micro)
	material.set_shader_parameter("caustics_enabled", caustics_enabled)
	material.set_shader_parameter("water_time", _time)
	material.set_shader_parameter("impacts", _packed_impacts())
	material.set_shader_parameter("impact_count", _impacts.size())
	for key in _tuning:
		material.set_shader_parameter(key, _tuning[key])

func set_caustics(value: bool) -> void:
	caustics_enabled = value
	for material in _materials.values():
		(material as ShaderMaterial).set_shader_parameter("caustics_enabled", value)

func set_debug_view(value: int) -> void:
	set_tuning("debug_view", clampi(value, 0, 8))

func set_tuning(parameter: String, value: Variant) -> void:
	# Only native material controls are accepted, never an arbitrary resource.
	var allowed := ["wave_height", "ripple_gain", "micro_strength", "normal_boost", "refraction_strength", "absorption_strength", "reflection_strength", "caustics_intensity", "foam_strength", "surface_roughness", "debug_view", "ssr_enabled", "refraction_enabled"]
	if parameter not in allowed:
		return
	var ranges := {
		"wave_height": Vector2(0.0, 2.0), "ripple_gain": Vector2(0.0, 3.0),
		"micro_strength": Vector2(0.0, 2.0), "normal_boost": Vector2(0.5, 2.0),
		"refraction_strength": Vector2(0.0, 2.0), "absorption_strength": Vector2(0.0, 3.0),
		"reflection_strength": Vector2(0.0, 1.5), "caustics_intensity": Vector2(0.0, 3.0),
		"foam_strength": Vector2(0.0, 2.0), "surface_roughness": Vector2(0.01, 0.4),
	}
	if ranges.has(parameter):
		if not (value is float or value is int) or not is_finite(float(value)):
			return
		var limits: Vector2 = ranges[parameter]
		value = clampf(float(value), limits.x, limits.y)
	elif parameter == "debug_view":
		value = clampi(int(value), 0, 8)
	else:
		value = bool(value)
	_tuning[parameter] = value
	for material in _materials.values():
		(material as ShaderMaterial).set_shader_parameter(parameter, value)

func _process(delta: float) -> void:
	if not enabled:
		return
	var dt: float = clampf(delta, 0.0, 0.10)
	_time += dt
	_wake_ring_timer = maxf(0.0, _wake_ring_timer - dt)
	while not _impacts.is_empty() and _time - _impacts[0].z > 5.5:
		_impacts.pop_front()
	field.advance(dt)
	var packed := _packed_impacts()
	for material in _materials.values():
		(material as ShaderMaterial).set_shader_parameter("water_time", _time)
		(material as ShaderMaterial).set_shader_parameter("impacts", packed)
		(material as ShaderMaterial).set_shader_parameter("impact_count", _impacts.size())
	_update_particles(dt)
	_prune_timer += dt
	if _prune_timer > 1.0:
		_prune_timer = 0.0
		for key in _rooms.keys():
			if (_rooms[key] as WeakRef).get_ref() == null:
				remove_room(key)

func _packed_impacts() -> PackedVector4Array:
	var packed := PackedVector4Array()
	packed.resize(MAX_IMPACTS)
	for i in range(_impacts.size()):
		packed[i] = _impacts[i]
	return packed

func _add_ripple(pos: Vector3, power: float) -> void:
	if _impacts.size() >= MAX_IMPACTS:
		_impacts.pop_front()
	_impacts.append(Vector4(pos.x, pos.z, _time, clampf(power, 0.0, 3.0)))

func impact(pos: Vector3, power: float) -> void:
	if not enabled or not pos.is_finite() or not is_finite(power) or power <= 0.0 or not is_water_at(pos):
		return
	power = clampf(power, 0.0, 3.0)
	interaction_count += 1
	field.impact(Vector2(pos.x, pos.z), power)
	_add_ripple(pos, power)
	if power >= 0.08:
		_emit_splash(pos, power)

func wake(pos: Vector3, relative: Vector2, power: float) -> void:
	if not enabled or not pos.is_finite() or not relative.is_finite() or not is_finite(power) or power <= 0.0 or not is_water_at(pos):
		return
	field.wake(Vector2(pos.x, pos.z), relative.limit_length(8.0), clampf(power, 0.0, 1.0))
	# Fine wakes are a separate band from the momentum injection. A small
	# sampling interval prevents 60 Hz prop wakes from evicting all impact rings.
	if _wake_ring_timer <= 0.0 and relative.length_squared() > 0.04:
		_add_ripple(pos, clampf(power * 3.0, 0.04, 0.2))
		_wake_ring_timer = 0.10

func is_water_at(pos: Vector3) -> bool:
	return enabled and field.depth_at(Vector2(pos.x, pos.z)) > 0.005

func surface_height_at(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	var height: float = field.sample(p).x + _ambient_height(p)
	for ripple in _impacts:
		var age: float = _time - ripple.z
		var distance: float = p.distance_to(Vector2(ripple.x, ripple.y))
		var front: float = distance - age * 2.35
		if absf(front) <= 1.2 and age >= 0.0 and age <= 5.5:
			height += sin(front * 14.0) * exp(-front * front * 5.8 - age * 0.72) / sqrt(1.0 + distance) * ripple.w * 0.012 * float(_tuning.get("ripple_gain", 1.0))
	return WATER_LEVEL + height * float(_tuning.get("wave_height", 1.0))

func current_velocity_at(pos: Vector3) -> Vector2:
	var sample: Vector4 = field.sample(Vector2(pos.x, pos.z))
	return Vector2(sample.y, sample.z)

func _ambient_height(p: Vector2) -> float:
	return sin(p.dot(Vector2(0.71, 0.43)) + _time * 0.57) * 0.007 + sin(p.dot(Vector2(-0.35, 1.17)) - _time * 0.43) * 0.0035 + sin(p.dot(Vector2(1.8, -0.67)) + _time * 0.71) * 0.0015

func _create_particles() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.66, 0.86, 0.91, 0.56)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.roughness = 0.065
	drop_material.metallic_specular = 0.255
	drop_material.vertex_color_use_as_albedo = true
	drop_material.render_priority = 2
	_drop_mesh = _make_multimesh("DetachedWaterDrops", sphere, drop_material, MAX_DROPS, true)
	var bubble_material := StandardMaterial3D.new()
	# Opaque miniature air interfaces are present in the opaque color/depth
	# capture and are therefore transmitted exactly once by the water pass.
	bubble_material.albedo_color = Color(0.46, 0.68, 0.69)
	bubble_material.roughness = 0.09
	bubble_material.metallic_specular = 0.65
	bubble_material.vertex_color_use_as_albedo = true
	_bubble_mesh = _make_multimesh("EntrainedAirBubbles", sphere, bubble_material, MAX_BUBBLES, false)

func _make_multimesh(node_name: String, mesh: Mesh, material: Material, capacity: int, above: bool) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_colors = true
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = capacity
	node.multimesh.visible_instance_count = 0
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 2 if above else 1
	node.custom_aabb = AABB(Vector3(-512.0, -8.0, -512.0), Vector3(1024.0, 32.0, 1024.0))
	add_child(node)
	return node

func _emit_splash(pos: Vector3, power: float) -> void:
	var water_y: float = surface_height_at(pos)
	var count: int = clampi(int(5.0 + power * 19.0), 4, 48)
	var flow: Vector2 = current_velocity_at(pos)
	for i in range(count):
		var angle: float = _rng.randf() * TAU
		var direction := Vector2(cos(angle), sin(angle))
		var radius: float = _rng.randf_range(0.015, 0.16)
		var outward: float = _rng.randf_range(0.18, 0.8) * sqrt(power)
		var position := Vector3(pos.x + direction.x * radius, water_y + 0.018, pos.z + direction.y * radius)
		var velocity := Vector3(direction.x * outward + flow.x, _rng.randf_range(0.6, 2.2) * sqrt(power), direction.y * outward + flow.y)
		_drops.append({"position": position, "velocity": velocity, "life": 0.0, "size": _rng.randf_range(0.004, 0.014) * minf(1.3, sqrt(power + 0.3))})
		if _drops.size() > MAX_DROPS:
			_drops.pop_front()
	for i in range(clampi(count / 2, 2, 24)):
		_bubbles.append({"position": Vector3(pos.x + _rng.randf_range(-0.14, 0.14), water_y - _rng.randf_range(0.04, 0.30), pos.z + _rng.randf_range(-0.14, 0.14)), "velocity": Vector3(flow.x, -0.12, flow.y), "life": 0.0, "size": _rng.randf_range(0.004, 0.011)})
		if _bubbles.size() > MAX_BUBBLES:
			_bubbles.pop_front()

func _update_particles(dt: float) -> void:
	if not is_instance_valid(_drop_mesh):
		return
	var live_drops: Array[Dictionary] = []
	for particle in _drops:
		var p: Vector3 = particle.position
		var v: Vector3 = particle.velocity
		var life: float = float(particle.life) + dt
		v.y -= 9.81 * dt
		v.x *= exp(-dt * 0.45)
		v.z *= exp(-dt * 0.45)
		var next: Vector3 = p + v * dt
		var surface: float = surface_height_at(next)
		if life > 2.0 or not is_water_at(next):
			continue
		if next.y <= surface and v.y < 0.0:
			# Swept surface intersection. Small returning drops seed fine ripples,
			# not recursively generated splashes or arbitrary high-energy sources.
			var previous_surface: float = surface_height_at(p)
			var fraction: float = clampf((p.y - previous_surface) / maxf(0.00001, (p.y - previous_surface) - (next.y - surface)), 0.0, 1.0)
			var contact: Vector3 = p.lerp(next, fraction)
			_add_ripple(contact, minf(0.065, float(particle.size) * absf(v.y) * 1.2))
			ripple_returns += 1
			continue
		particle.position = next
		particle.velocity = v
		particle.life = life
		live_drops.append(particle)
	_drops = live_drops
	_drop_mesh.multimesh.visible_instance_count = _drops.size()
	for i in range(_drops.size()):
		var p: Dictionary = _drops[i]
		var size: float = p.size
		var stretch: float = 1.0 + minf(1.0, absf((p.velocity as Vector3).y) * 0.12)
		var transform := Transform3D(Basis.from_scale(Vector3(size, size * stretch, size)), to_local(p.position))
		_drop_mesh.multimesh.set_instance_transform(i, transform)
		_drop_mesh.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, clampf(2.0 - float(p.life), 0.0, 1.0)))
	var live_bubbles: Array[Dictionary] = []
	for particle in _bubbles:
		var p: Vector3 = particle.position
		var v: Vector3 = particle.velocity
		var life: float = float(particle.life) + dt
		var flow := current_velocity_at(p)
		v = v.lerp(Vector3(flow.x, 0.23, flow.y), 1.0 - exp(-dt * 4.0))
		p += v * dt
		if life > 3.0 or not is_water_at(p):
			continue
		if p.y >= surface_height_at(p) - 0.008:
			_add_ripple(p, 0.024)
			continue
		particle.position = p
		particle.velocity = v
		particle.life = life
		live_bubbles.append(particle)
	_bubbles = live_bubbles
	_bubble_mesh.multimesh.visible_instance_count = _bubbles.size()
	for i in range(_bubbles.size()):
		var p: Dictionary = _bubbles[i]
		var size: float = float(p.size) * clampf(3.0 - float(p.life), 0.0, 1.0)
		_bubble_mesh.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), to_local(p.position)))
		_bubble_mesh.multimesh.set_instance_color(i, Color(0.8, 0.95, 1.0))

func debug_stats() -> Dictionary:
	return {"rooms": _materials.size(), "quality": quality, "field_resolution": field.resolution, "simulation_steps": field.step_count, "impacts": interaction_count, "active_ripples": _impacts.size(), "droplets": _drops.size(), "bubbles": _bubbles.size(), "droplet_returns": ripple_returns, "caustics": caustics_enabled, "enabled": enabled}
