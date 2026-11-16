extends Node
## One bounded contact field for all streamed grass batches in this world.
## Blades remain GPU-instanced; no rigid body or collision shape per blade.
const Grass = preload("res://scripts/dreamcore/scenes/wind_grass.gd")
const Meadow = preload("res://scripts/dreamcore/scenes/wind_meadow.gd")
const MAX_STAMPS := 8
const RECOVERY_SECONDS := 7.0
const CONTACT_RADIUS := .62
var main: Node
var _clock := 0.0
var _publish_timer := 0.0
var _stamps: Array[Dictionary] = []
var _published_nonzero := false

func configure(host: Node) -> void:
	main = host

func _process(delta: float) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player): return
	if main.menu_open or main._switching_spawn or not main.player.enabled: return
	_clock += minf(maxf(delta, 0.0), .1)
	if main.player.is_on_floor():
		var p := Vector2(main.player.global_position.x, main.player.global_position.z)
		if _stamps.is_empty() or p.distance_to(_stamps.back().position) >= .32:
			_stamps.append({"position":p,"time":_clock})
			if _stamps.size() > MAX_STAMPS: _stamps.pop_front()
		else:
			# Standing still continues pressing the same patch, without filling the ring.
			_stamps.back().time = _clock
	while not _stamps.is_empty() and _clock - float(_stamps.front().time) >= RECOVERY_SECONDS:
		_stamps.pop_front()
	_publish_timer += delta
	if _publish_timer >= .1 and (not _stamps.is_empty() or _published_nonzero):
		_publish_timer = 0.0
		_publish()

func _publish() -> void:
	var field := PackedVector4Array()
	field.resize(MAX_STAMPS)
	for i in _stamps.size():
		var item := _stamps[i]
		var remaining := clampf(1.0 - (_clock - float(item.time)) / RECOVERY_SECONDS, 0.0, 1.0)
		var strength := remaining * remaining * (3.0 - 2.0 * remaining)
		field[i] = Vector4(item.position.x, item.position.y, CONTACT_RADIUS, strength)
	for library: Dictionary in [Grass.materials, Meadow.materials]:
		for material: ShaderMaterial in library.values():
			if is_instance_valid(material):
				material.set_shader_parameter("trample_stamps", field)
				material.set_shader_parameter("trample_count", _stamps.size())
	_published_nonzero = not _stamps.is_empty()

func _exit_tree() -> void:
	_stamps.clear()
	_publish()
