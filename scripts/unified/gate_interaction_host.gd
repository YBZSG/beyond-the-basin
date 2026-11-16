extends "res://scripts/unified/interaction_host.gd"
## Resident firstslice architecture only. Original inspection lamp session is inherited.
const GateArt = preload("res://scripts/unified/gates/maintenance_gate.gd")
const GateController = preload("res://scripts/unified/gates/resident_gate_controller.gd")
var gate_controller: Node3D
var resident_gates: Dictionary = {}
var _gate_player: CharacterBody3D
var _gate_world: Node3D

func install_gates(actual_player: CharacterBody3D) -> void:
	assert(resident_gates.is_empty() and not _disposed)
	for id: String in ["hanging_hand","aquarium_atrium"]:
		var gate := GateArt.new()
		gate.name = "ResidentMaintenanceGate_"+id
		gate.configure(34.0 if id == "hanging_hand" else 59.0,-1.0 if id == "hanging_hand" else 1.0)
		# Authored initial pose, before entering physics world; no startup swing or blocked route.
		gate.angle = gate.open_angle
		gate.goal = gate.open_angle
		gate.hinge.rotation.y = gate.open_angle
		gate.state = "OPEN"
		add_child(gate)
		resident_gates[id] = gate
	_gate_player = actual_player
	_gate_world = get_parent()
	_gate_world.streaming_completed.connect(_install_controls_when_ready)
	_install_controls_when_ready()

func _install_controls_when_ready() -> void:
	if _disposed or is_instance_valid(gate_controller): return
	for coord: Vector2i in _gate_world.finite_coords:
		if not _gate_world.is_room_ready(coord): return
	# Snapshot only after original incremental resident geometry has completed.
	gate_controller = GateController.new()
	gate_controller.name = "ResidentGateController"
	add_child(gate_controller)
	gate_controller.install(_gate_player,resident_gates)
	gate_controller.set_playable(_playable)

func set_playable(value: bool) -> void:
	super.set_playable(value)
	if is_instance_valid(gate_controller): gate_controller.set_playable(_playable)

func handle_event(event: InputEvent, camera: Camera3D, excluded: Array[RID] = []) -> bool:
	if is_instance_valid(gate_controller) and gate_controller.handle_event(event,camera): return true
	return super.handle_event(event,camera,excluded)

func hint(camera: Camera3D, excluded: Array[RID] = []) -> String:
	if is_instance_valid(gate_controller):
		var id: String = gate_controller.target(camera)
		if not id.is_empty():
			var state: String = resident_gates[id].state
			if state == "STOPPED": return "检修门受阻或已暂停 · E 反向（不会自动续动）"
			if state in ["OPENING","CLOSING"]: return "检修门移动中 · E 反向 · 请让开门扇"
			return "E 关闭检修门" if state == "OPEN" else "E 打开检修门 · 请让开门扇"
	return super.hint(camera,excluded)

func diagnostics() -> Dictionary:
	var values: Dictionary = super.diagnostics()
	values.resident_gate_count = resident_gates.size()
	values.gate_states = {}
	for id: String in resident_gates: values.gate_states[id] = resident_gates[id].state
	values.gate_streaming_enabled = false
	values.gate_last_result = gate_controller.last_result.duplicate(true) if is_instance_valid(gate_controller) else {}
	return values

func dispose() -> void:
	if is_instance_valid(_gate_world) and _gate_world.streaming_completed.is_connected(_install_controls_when_ready): _gate_world.streaming_completed.disconnect(_install_controls_when_ready)
	if is_instance_valid(gate_controller):
		gate_controller.set_playable(false)
		gate_controller.free()
	gate_controller = null
	for gate: Node in resident_gates.values():
		if is_instance_valid(gate): gate.free()
	resident_gates.clear()
	super.dispose()
