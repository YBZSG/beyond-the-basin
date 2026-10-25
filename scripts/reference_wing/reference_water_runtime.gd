extends "res://scripts/water/source_water_runtime.gd"
## Render-only PC adapter. The source runtime, cache identity, solver, original
## wind, terrain preparation, caustic dispatch and gameplay APIs stay unchanged.
const ReferenceWaves = preload("res://scripts/reference_wing/reference_wave_controller.gd")
const ReferenceSurface = preload("res://shaders/reference_wing/reference_water_surface.gdshader")
var reference_waves := ReferenceWaves.new()
var _reference_source_time := 0.0
var _reference_clock_updates := 0

func set_reference_wave_settings(values: Dictionary) -> void:
	reference_waves.set_target(values)
	# Only shader identity and three optical modes change. In particular, do not
	# invoke _apply_surface/_bind_all, rebind source textures, or tick the solver.
	# This also restores the original shader immediately while water is paused.
	for material: ShaderMaterial in _materials.values():
		_apply_reference_surface(material)

func _reference_desktop_allowed() -> bool:
	return not mobile_optimized and not OS.has_feature("android") and not OS.has_feature("ios") and not OS.get_cmdline_user_args().has("--mobile-preview")

func _reference_requested() -> bool:
	return _reference_desktop_allowed() and not _disposed and bool(reference_waves.target.referenceWaves) and float(reference_waves.target.referenceWaveStrength) > 0.0

func _apply_reference_surface(material: ShaderMaterial) -> void:
	if material == null: return
	# Do not replace a diagnostic/experimental shader installed by another tool.
	if material.shader != Surface and material.shader != ReferenceSurface: return
	var desired: Shader = ReferenceSurface if _reference_requested() else Surface
	if material.shader != desired:
		# ShaderMaterial retains uniform overrides across a shader replacement.
		# Both resources have the exact same original uniforms; source values,
		# wind modes, textures and render_priority are not rewritten here.
		material.shader = desired
	if desired == ReferenceSurface:
		reference_waves.apply_to(material)

func _sync_reference_clock() -> void:
	# Follow successful source-time publication rather than predicting whether
	# _pump_terrain() will make the source ready during this particular frame.
	# _apply_surface may run for many rooms or for quality/terrain rebinding:
	# consuming each source timestamp once prevents duplicate phase advances.
	var elapsed_source := _time - _reference_source_time
	_reference_source_time = _time
	if not _reference_desktop_allowed() or _disposed or not _configured or not enabled or _terrain_paused or not _terrain_ready: return
	if not is_finite(elapsed_source) or elapsed_source <= 0.0: return
	reference_waves.advance(elapsed_source)
	_reference_clock_updates += 1

func _apply_surface(material: ShaderMaterial) -> void:
	_sync_reference_clock()
	# Choose the known shader before the original binding so new rooms and
	# quality-driven texture changes retain the complete original publication.
	_apply_reference_surface(material)
	super._apply_surface(material)

func _process(delta: float) -> void:
	# The original loop remains the only owner of source simulation and wind.
	super._process(delta)
	# Normally _apply_surface consumed this timestamp already. This no-op-safe
	# call advances phases once even when the active source owns no surfaces.
	_sync_reference_clock()

func reference_wave_status() -> Dictionary:
	var result: Dictionary = reference_waves.describe()
	result.desktop_allowed = _reference_desktop_allowed()
	result.requested = _reference_requested()
	result.source_time = _reference_source_time
	result.clock_updates = _reference_clock_updates
	var original_count := 0
	var reference_count := 0
	var unrelated_count := 0
	for material: ShaderMaterial in _materials.values():
		if material.shader == Surface: original_count += 1
		elif material.shader == ReferenceSurface: reference_count += 1
		else: unrelated_count += 1
	result.materials = {"original": original_count, "reference": reference_count, "unrelated_preserved": unrelated_count}
	return result
