class_name PoolProps
extends Node3D
## Seeded native floating props. Source visuals: engine.ts prop()/PROP_SPEC.

signal interaction(kind: String, position: Vector3, power: float)
signal water_impact(position: Vector3, power: float)
signal prop_spawned(body: RigidBody3D)

const SourceActivity = preload("res://scripts/player/source_prop_activity.gd")
const PropBodyScript = preload("res://scripts/player/pool_prop_body.gd")
const PROP_SPEC: Dictionary = {
	"egg": {"radius": 0.17, "float_bias": 0.0, "name": "鸡蛋", "sink": 0.0, "buoy_k": 16.0, "buoy_zeta": 0.5, "buoy_max": 4.0, "flow_rate": 3.0, "splash_boost": 1.6, "mass": 1.0},
	"duck": {"radius": 0.2, "float_bias": 0.125, "name": "小黄鸭", "sink": 0.125, "buoy_k": 90.0, "buoy_zeta": 0.32, "buoy_max": 30.0, "flow_rate": 2.0, "splash_boost": 1.0, "mass": 1.0},
	"ball": {"radius": 0.21, "float_bias": 0.05, "name": "海滩球", "sink": 0.0, "buoy_k": 110.0, "buoy_zeta": 0.35, "buoy_max": 34.0, "flow_rate": 1.6, "splash_boost": 1.0, "mass": 1.0}
}
var bodies: Array[RigidBody3D] = []
var _material_library: RefCounted
var _water: Node
var _player: CharacterBody3D
var _materials: Dictionary = {}
var _unit_sphere: SphereMesh
var _ball_sphere: SphereMesh
var _enabled: bool = true
var _source_activity: Node

func initialize(material_library: RefCounted, water_node: Node) -> void:
	_material_library = material_library
	_water = water_node
	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 1.0
	_unit_sphere.height = 2.0
	_unit_sphere.radial_segments = 16
	_unit_sphere.rings = 11 # Godot rings+1 equals Three heightSegments=12.
	_ball_sphere = SphereMesh.new()
	_ball_sphere.radius = 0.21
	_ball_sphere.height = 0.42
	_ball_sphere.radial_segments = 64
	_ball_sphere.rings = 47 # Godot rings+1 equals Three heightSegments=48.
	_materials["yellow"] = _get_material("yellow", Color("f2c32c"), 0.3)
	_materials["orange"] = _get_material("orange", Color("d36a24"), 0.35)
	_materials["black"] = _get_material("black", Color("151713"), 0.27)
	_materials["ivory"] = _get_material("ivory", Color("b9b398"), 0.23)
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_texture = _beach_ball_texture()
	ball_material.roughness = 0.27
	ball_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials["ball"] = ball_material

func _get_material(role: String, color: Color, roughness: float) -> Material:
	if _material_library != null and _material_library.has_method("get_material"):
		var material: Variant = _material_library.call("get_material", role)
		if material is BaseMaterial3D:
			# Architecture shares role names, but source prop colour/roughness are exact.
			var prop_material: BaseMaterial3D = material.duplicate()
			prop_material.albedo_color = color
			prop_material.roughness = roughness
			return prop_material
		if material is ShaderMaterial:
			# Native shader roles are shared with architecture. Duplicate first so
			# the original prop pigment/roughness do not silently inherit later art.
			var prop_material: ShaderMaterial = material.duplicate()
			prop_material.set_shader_parameter("pigment", color)
			prop_material.set_shader_parameter("roughness_value", roughness)
			return prop_material
		if material is Material:
			return material
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = color
	fallback.roughness = roughness
	return fallback

func set_enabled(value: bool) -> void:
	_enabled = value
	if is_instance_valid(_source_activity) and _source_activity.owns_callbacks:
		_source_activity.set_enabled(value)
		return
	for body in bodies:
		if is_instance_valid(body):
			body.freeze = not value

func attach_player(player: CharacterBody3D) -> void:
	_player = player
	if _player.has_method("set_props"):
		_player.call("set_props", self)
	if "--no-source-prop-active-set" in OS.get_cmdline_user_args() or not _player.has_method("get_view_camera"):
		return
	if is_instance_valid(_source_activity):
		_source_activity._release_all()
		_source_activity.queue_free()
	_source_activity = SourceActivity.new()
	add_child(_source_activity)
	if not _source_activity.configure(bodies, _player.call("get_view_camera"), _enabled):
		_source_activity.queue_free()
		_source_activity = null

func spawn_for_room(room: Node3D, coord: Vector2i, layout: Dictionary, world_seed: int) -> void:
	if _unit_sphere == null:
		initialize(_material_library, _water)
	if room.has_meta("native_props_spawned"):
		return
	room.set_meta("native_props_spawned", true)
	if str(layout.get("reference_id", "")) == "ball_lounge":
		var lounge := preload("res://scripts/reference_wing/lounge_interactions.gd").new()
		lounge.configure(room, layout, _player, _water)
	if layout.has("prop_spawns"):
		for entry: Dictionary in layout["prop_spawns"]:
			spawn_prop(room, str(entry.get("kind", "duck")), entry.get("position", Vector3.ZERO), float(entry.get("yaw", 0.0)))
		return
	# Fallback only: normal world generation supplies exact source-seeded prop_spawns.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663)
	var variant: int = int(layout.get("variant", 0))
	var count: int = int(layout.get("ducks", 4)) * 2
	if variant >= 8:
		count = 4
	for index in range(count):
		var kind: String = "duck" if index % 3 == 0 else "egg"
		spawn_prop(room, kind, Vector3(rng.randf_range(-14.0, 14.0), 0.32 + float(PROP_SPEC[kind]["sink"]), rng.randf_range(-13.5, 13.5)), rng.randf() * TAU)
	var ball_count: int = int(rng.randf() * 2.4) if variant < 8 else (1 if rng.randf() > 0.8 else 0)
	for index in range(ball_count):
		spawn_prop(room, "ball", Vector3(rng.randf_range(-14.0, 14.0), 0.32, rng.randf_range(-13.5, 13.5)), rng.randf() * TAU)

func spawn_prop(parent: Node3D, kind: String, local_position: Vector3, yaw: float = 0.0) -> RigidBody3D:
	if not PROP_SPEC.has(kind):
		kind = "duck"
	var body: RigidBody3D = PropBodyScript.new()
	body.name = "Float_%s_%d" % [kind, bodies.size()]
	body.call("configure", kind, PROP_SPEC[kind], _water)
	body.position = local_position
	body.rotation.y = yaw
	_make_visual(body, kind)
	body.connect("water_impact", _on_water_impact)
	body.connect("hard_impact", _on_hard_impact)
	body.connect("picked_up", _on_picked_up)
	parent.add_child(body)
	body.freeze = not _enabled
	bodies.append(body)
	if is_instance_valid(_source_activity) and _source_activity.owns_callbacks:
		_source_activity.track(body)
	prop_spawned.emit(body)
	return body

func _make_visual(body: RigidBody3D, kind: String) -> void:
	if kind == "ball":
		var mesh := MeshInstance3D.new()
		# Moving source floaters receive GI; they are not static bake geometry.
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		mesh.name = "ContinuousSixPanelBeachBall"
		mesh.mesh = _ball_sphere
		# Source SphereGeometry starts its longitude seam at -X; native
		# SphereMesh starts at +Z. Preserve panel direction under seeded yaw.
		mesh.rotation.y = -PI * 0.5
		mesh.material_override = _materials["ball"]
		body.add_child(mesh)
	elif kind == "egg":
		_part(body, "ivory", Vector3.ZERO, Vector3(0.145, 0.205, 0.145))
	else:
		const SINK: float = 0.125
		_part(body, "yellow", Vector3(0, 0.04 - SINK, 0), Vector3(0.16, 0.105, 0.235))
		_part(body, "yellow", Vector3(0, 0.19 - SINK, -0.1), Vector3(0.11, 0.12, 0.115))
		_part(body, "orange", Vector3(0, 0.17 - SINK, -0.222), Vector3(0.075, 0.026, 0.06))
		for side in [-1.0, 1.0]:
			_part(body, "black", Vector3(side * 0.087, 0.223 - SINK, -0.158), Vector3(0.018, 0.02, 0.015))
		_part(body, "yellow", Vector3(-0.125, 0.07 - SINK, 0.025), Vector3(0.052, 0.055, 0.13))
		_part(body, "yellow", Vector3(0.125, 0.07 - SINK, 0.025), Vector3(0.052, 0.055, 0.13))

func _part(body: RigidBody3D, material_role: String, part_position: Vector3, part_scale: Vector3) -> void:
	var part := MeshInstance3D.new()
	# Native LightmapGI probes require DYNAMIC for these rigid-body visuals.
	part.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	part.name = "%sPart" % material_role.capitalize()
	part.mesh = _unit_sphere
	part.material_override = _materials[material_role]
	part.position = part_position
	part.scale = part_scale
	body.add_child(part)

func _beach_ball_texture() -> ImageTexture:
	# Exact six colours, white polar caps and welded seam function from beach-ball.ts.
	var width: int = 1024
	var height: int = 512
	var pixels := PackedByteArray()
	pixels.resize(width * height * 4)
	var panels: Array[Color] = [Color8(220, 62, 46), Color8(245, 242, 222), Color8(32, 134, 192), Color8(245, 242, 222), Color8(245, 199, 43), Color8(245, 242, 222)]
	for y in range(height):
		var v: float = float(y) / float(height - 1)
		var cap: bool = v < 0.045 or v > 0.955
		for x in range(width):
			var u: float = float(x) / float(width) * 6.0
			var fraction: float = fposmod(u, 1.0)
			var edge: float = minf(fraction, 1.0 - fraction)
			var color: Color = panels[1] if cap else panels[int(u)]
			var shade: float = 1.0 if cap else 1.0 - 0.16 * exp(-edge * edge / 0.00008) + 0.025 * exp(-pow(edge - 0.018, 2.0) / 0.0001)
			var offset: int = (x + y * width) * 4
			pixels[offset] = mini(255, int(round(color.r * 255.0 * shade)))
			pixels[offset + 1] = mini(255, int(round(color.g * 255.0 * shade)))
			pixels[offset + 2] = mini(255, int(round(color.b * 255.0 * shade)))
			pixels[offset + 3] = 255
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _on_picked_up(body: RigidBody3D) -> void:
	# Promoted props follow the player across streamed rooms, just as in Three.
	if body.get_parent() != self:
		body.reparent.call_deferred(self, true)

func _on_water_impact(point: Vector3, power: float) -> void:
	if is_instance_valid(_water) and not _water.has_method("splash") and _water.has_method("impact"):
		_water.call("impact", point, power)
	water_impact.emit(point, power)

func _on_hard_impact(kind: String, point: Vector3, strength: float) -> void:
	interaction.emit("hit_" + kind, point, strength)

func _physics_process(_delta: float) -> void:
	for index in range(bodies.size() - 1, -1, -1):
		var body: RigidBody3D = bodies[index]
		if not is_instance_valid(body):
			bodies.remove_at(index)
			continue
		if is_instance_valid(_player) and bool(body.get("promoted")) and not bool(body.get("held")) and body.global_position.distance_to(_player.global_position) > 80.0:
			body.queue_free()
			bodies.remove_at(index)

func get_status() -> Dictionary:
	var counts: Dictionary = {"egg": 0, "duck": 0, "ball": 0, "total": 0}
	for body in bodies:
		if is_instance_valid(body):
			counts[str(body.get("prop_kind"))] += 1
			counts["total"] += 1
	return counts
