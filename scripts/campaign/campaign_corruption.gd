extends RefCounted
## Reversible presentation, not structural destruction. The coordinator owns time.
## No timers, physics, shared materials, environment, water or render toggles.
const MAX_LIGHTS := 48
const OUTAGE_INTERVAL := 64.0
const OUTAGE_DURATION := 7.0
var reduced_effects := false
var displayed_severity := 0.0
var ambience_amount := 0.0
var _world: WeakRef
var _lights: Array[Dictionary] = []
var _elapsed := 0.0
var _scan_remaining := 0.0
var _groups: Dictionary = {}
var _outage: WeakRef
var _outage_started := -1.0
var _next_outage_at := 18.0
var _outage_sequence := 0

func apply(world: Node, severity: float, delta: float) -> void:
	if not is_instance_valid(world):
		reset()
		return
	if _world == null or _world.get_ref() != world:
		reset()
		_world = weakref(world)
	var target := clampf(severity, 0.0, 1.0) if is_finite(severity) else 0.0
	if target <= 0.0:
		reset()
		return
	# Call only during active play. A pause/resume cannot consume a wall-clock gap.
	var step := clampf(delta, 0.0, 0.25) if is_finite(delta) else 0.0
	_elapsed += step
	displayed_severity = move_toward(displayed_severity, target, step * 0.055)
	ambience_amount = displayed_severity * (0.35 if reduced_effects else 1.0)
	_scan_remaining -= step
	if _scan_remaining <= 0.0:
		_discover(world)
		_scan_remaining = 1.0
	# A fixture can become protected or animated after discovery; relinquish it.
	for index in range(_lights.size()-1, -1, -1):
		var entry: Dictionary = _lights[index]
		var lamp := entry.ref.get_ref() as Light3D
		if is_instance_valid(lamp) and (_protected_light(lamp) or _unstable_fixture(lamp)):
			lamp.light_color = entry.color; lamp.light_energy = entry.energy
			_lights.remove_at(index)
	_update_outage(target)
	for index in range(_lights.size()):
		var entry: Dictionary = _lights[index]
		var lamp := entry.ref.get_ref() as Light3D
		if not is_instance_valid(lamp): continue
		var original_color: Color = entry.color
		var amount := displayed_severity * (0.19 if reduced_effects else 0.48)
		lamp.light_color = original_color.lerp(Color(0.48, 0.78, 0.39), amount)
		var energy_scale := 1.0 - displayed_severity * (0.08 if reduced_effects else 0.24)
		# Exactly one eligible fixture may be fully dark; other room lights stay on.
		if _outage != null and _outage.get_ref() == lamp:
			var age := _elapsed - _outage_started
			var down := 1.0 - smoothstep(0.0, 0.8, age)
			var up := smoothstep(4.8, OUTAGE_DURATION, age)
			energy_scale *= maxf(down, up)
		lamp.light_energy = float(entry.energy) * maxf(0.0, energy_scale)

func reset() -> void:
	for entry: Dictionary in _lights:
		var lamp := entry.ref.get_ref() as Light3D
		if is_instance_valid(lamp):
			lamp.light_color = entry.color
			lamp.light_energy = entry.energy
	_lights.clear()
	_world = null
	_elapsed = 0.0
	_scan_remaining = 0.0
	_groups.clear()
	_outage = null
	_outage_started = -1.0
	_next_outage_at = 18.0
	_outage_sequence = 0
	displayed_severity = 0.0
	ambience_amount = 0.0

func _update_outage(requested_severity: float) -> void:
	if reduced_effects or requested_severity < 0.78:
		_outage = null
		return
	if _outage != null:
		var current := _outage.get_ref() as Light3D
		# A safety light switched off or streamed away: immediately restore power.
		if not is_instance_valid(current) or _protected_light(current) or _unstable_fixture(current) or not _has_redundancy(current) or _elapsed - _outage_started >= OUTAGE_DURATION:
			_outage = null
	if _outage != null or displayed_severity < 0.78 or _elapsed < _next_outage_at: return
	var candidates: Array[Light3D] = []
	for entry: Dictionary in _lights:
		var lamp := entry.ref.get_ref() as Light3D
		if is_instance_valid(lamp) and float(entry.energy) >= 0.15 and lamp.is_visible_in_tree() and _has_redundancy(lamp):
			candidates.append(lamp)
	# Even a skipped attempt cannot repeatedly try rapid dark pulses.
	_next_outage_at = _elapsed + OUTAGE_INTERVAL
	if candidates.is_empty(): return
	_outage = weakref(candidates[_outage_sequence % candidates.size()])
	_outage_started = _elapsed
	_outage_sequence += 1

func _has_redundancy(candidate: Light3D) -> bool:
	if _world == null or not is_instance_valid(_world.get_ref()): return false
	var key := _room_key(candidate, _world.get_ref())
	if key == 0: return false
	for reference: WeakRef in _groups.get(key, []):
		var guard := reference.get_ref() as Light3D
		if is_instance_valid(guard) and guard != candidate and guard.is_visible_in_tree() and guard.light_energy >= 0.12 and not _unstable_fixture(guard) and not guard.get_meta("campaign_temporary_light", false) and _room_key(guard, _world.get_ref()) == key:
			return true
	return false

func _room_key(lamp: Light3D, root: Node) -> int:
	# Actual streamed resident ownership is required, never a name/global fallback.
	var has_residents := false
	for property: Dictionary in root.get_property_list():
		if property.name == "resident_rooms": has_residents = true; break
	if not has_residents: return 0
	var residents: Variant = root.get("resident_rooms")
	if not residents is Dictionary: return 0
	for room: Variant in residents.values():
		if not is_instance_valid(room) or not room is Node3D or room.is_queued_for_deletion(): continue
		# NativeLighting is the concrete rig created by PoolLighting.add_room_lights.
		# Temporary entry/puzzle lens nodes outside it never qualify as backups.
		var rig := room.get_node_or_null("NativeLighting") as Node3D
		if is_instance_valid(rig) and not rig.is_queued_for_deletion() and rig.is_ancestor_of(lamp): return room.get_instance_id()
	return 0

func _protected_light(lamp: Light3D) -> bool:
	return bool(lamp.get_meta("campaign_preserve_light", false)) or bool(lamp.get_meta("campaign_puzzle_light", false)) or bool(lamp.get_meta("campaign_temporary_light", false)) or lamp.name == "SourceExitLight"

func _unstable_fixture(lamp: Light3D) -> bool:
	var ancestor: Node = lamp
	while ancestor != null:
		if ancestor.is_queued_for_deletion(): return true
		if ancestor.has_method("enable_flicker") and ancestor.is_processing(): return true
		ancestor = ancestor.get_parent()
	return false

func _discover(root: Node) -> void:
	# Prune streamed-out rooms; guard references never retain source nodes.
	_lights = _lights.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry.ref.get_ref()))
	_groups.clear()
	var known := {}
	for entry: Dictionary in _lights:
		known[entry.ref.get_ref().get_instance_id()] = true
	var pending: Array[Node] = [root]
	var visited := 0
	while not pending.is_empty() and visited < 12000:
		visited += 1
		var node: Node = pending.pop_back()
		if node is Light3D and not node is DirectionalLight3D:
			var lamp := node as Light3D
			var authored_flicker := _unstable_fixture(lamp)
			# Dynamic flickering lamps cannot guarantee safe redundant illumination.
			if not authored_flicker and not lamp.get_meta("campaign_temporary_light", false):
				var key := _room_key(lamp, root)
				if key != 0:
					if not _groups.has(key): _groups[key] = []
					_groups[key].append(weakref(lamp))
			var protected := _protected_light(lamp)
			if not protected and not authored_flicker and not known.has(lamp.get_instance_id()) and _lights.size() < MAX_LIGHTS:
				_lights.append({"ref": weakref(lamp), "color": lamp.light_color, "energy": lamp.light_energy})
		for child: Node in node.get_children(): pending.append(child)
