extends Node3D
## CPU lifecycle double only. The runner installs this at the original base path
## inside a disposable test project, never in the production checkout.
## Its guard/time/material-publication order matches the protected original.
const Surface = preload("res://shaders/source_water_surface.gdshader")
var mobile_optimized := false
var _configured := false
var _disposed := false
var enabled := true
var _terrain_paused := false
var _terrain_ready := false
var _time := 0.0
var _materials: Dictionary = {}
var source_process_calls := 0
var source_surface_bind_calls := 0
var source_caustic_bind_calls := 0
var source_step_calls := 0
var source_pump_calls := 0
var wind_elapsed := 0.0
var pump_completes_ready := false

func _process(delta: float) -> void:
	source_process_calls += 1
	if not _configured: return
	source_pump_calls += 1
	if pump_completes_ready: _terrain_ready = true
	if not enabled or _terrain_paused or not _terrain_ready: return
	_time += maxf(0.0, delta)
	wind_elapsed += maxf(0.0, delta)
	source_step_calls += 1
	for material: ShaderMaterial in _materials.values(): _apply_surface(material)

func _apply_surface(material: ShaderMaterial) -> void:
	source_surface_bind_calls += 1
	material.set_shader_parameter("poolTime", _time)

func _bind_all() -> void:
	source_caustic_bind_calls += 1
	for material: ShaderMaterial in _materials.values(): _apply_surface(material)
