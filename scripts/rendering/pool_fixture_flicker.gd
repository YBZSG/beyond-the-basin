class_name PoolFixtureFlicker
extends Node3D
## Source-seeded ballast flicker. It updates the actual light and visible opal
## together; it never rerolls room survival or invents random gameplay state.

var seed_value := 0.0
var amplitude := 0.0
var _lights: Array[Light3D] = []
var _energies: Array[float] = []
var _opal: StandardMaterial3D
var _opal_energy := 2.8

func _ready() -> void:
	set_process(not _lights.is_empty())

func enable_flicker(seed_number: float, strength: float, opal: StandardMaterial3D) -> void:
	seed_value = seed_number
	amplitude = strength
	_opal = opal
	_opal_energy = opal.emission_energy_multiplier
	for child in get_children():
		if child is Light3D:
			_lights.append(child as Light3D)
			_energies.append((child as Light3D).light_energy)
	set_process(true)

func _process(_delta: float) -> void:
	var seconds := float(Time.get_ticks_msec())*0.001
	var buzz := 0.9+0.08*sin(seconds*47.0+seed_value*9.0)+0.04*sin(seconds*97.0+seed_value*3.0)
	var dropout := 1.0
	if sin(seconds*0.9+seed_value) > 1.55-amplitude*0.75:
		dropout = 0.12+0.25*absf(sin(seconds*29.0+seed_value))
	var value := buzz*dropout
	for i in _lights.size():
		_lights[i].light_energy = _energies[i]*value
	_opal.emission_energy_multiplier = _opal_energy*value
