extends Node
## Root-window input bridge for the real controller inside a SubViewport.
signal finish_requested
var player: CharacterBody3D
var active := true
var delivered_events := 0

func _input(event: InputEvent) -> void:
	if not active or not is_instance_valid(player):return
	delivered_events+=1
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_F10:
			active=false
			finish_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode==KEY_ESCAPE:
			player.set_enabled(false)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and not player.enabled:
		player.set_enabled(true)
		get_viewport().set_input_as_handled()
		return
	# InputMap provides WASD/Shift state. The production event handler owns mouse
	# look and discrete jump input; this bridge does not reinterpret those actions.
	if player.enabled:player._unhandled_input(event)
	get_viewport().set_input_as_handled()
