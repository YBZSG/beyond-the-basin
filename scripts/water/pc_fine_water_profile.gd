extends RefCounted
## Explicit desktop candidate only. Nothing installs this helper automatically.
## Reuses original shared-wave/reflection controls; no shader/solver replacement.
const RUNTIME := preload("res://scripts/water/source_water_runtime.gd")
const CANDIDATE := {"causticsScale": 1.10, "microStrength": 0.53}
const FINE := {"causticsScale": 1.50, "microStrength": 2.00, "distortion": 0.55}
const ID := "pc-fine-water-v1"
var _candidate: Dictionary = CANDIDATE.duplicate()
var _profile_name := "standard_safe"
var _expected_grid := Vector2i.ZERO
var last_error := ""
var _water: WeakRef
var _original: Dictionary = {}
var _original_tuning: Dictionary = {}
var _applied := false
var _bound := false

func bind(water: Node3D, profile_name: String = "standard_safe") -> Dictionary:
    if _bound: return _failure("Already bound")
    if water == null or water.get_script() != RUNTIME: return _failure("Exact source runtime required")
    if OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args(): return _failure("Desktop candidate only")
    if water.quality != "High" or water.caustics.quality != "High": return _failure("Audited High sampling required; no automatic quality change")
    if profile_name not in ["standard_safe", "fine"]: return _failure("Unknown bounded profile")
    if profile_name == "fine" and water.caustics.photon_grid() != Vector2i(256, 160): return _failure("Fine shared field requires explicit startup PC256/160 photon sampling")
    _profile_name = profile_name
    _expected_grid = water.caustics.photon_grid()
    _candidate = (FINE if profile_name == "fine" else CANDIDATE).duplicate()
    if not water.settings.microNormals: return _failure("Existing microNormals layer must already be enabled")
    for key: String in _candidate:
        var value: Variant = water.settings.get(key)
        if not (value is float or value is int) or not is_finite(float(value)): return _failure("Invalid live setting: " + key)
        _original[key] = value
        _original_tuning[key] = {"present": water._tuning.has(key), "value": water._tuning.get(key)}
    _water = weakref(water)
    _bound = true
    return describe()

func set_enabled(enabled: bool) -> bool:
    if not _bound or _water.get_ref() == null: return _fail("Unbound or freed source runtime")
    var water: Node3D = _water.get_ref()
    if water.quality != "High" or water.caustics.quality != "High": return _fail("High sampling changed; refusing automatic quality correction")
    if water.caustics.photon_grid() != _expected_grid: return _fail("Photon sampling changed after binding")
    var expected: Dictionary = _candidate if _applied else _original
    for key: String in _candidate:
        if water.settings[key] != expected[key]: return _fail("Another owner changed " + key + "; refusing to overwrite")
        var expected_present: bool = true if _applied else _original_tuning[key].present
        var expected_value: Variant = _candidate[key] if _applied else _original_tuning[key].value
        if water._tuning.has(key) != expected_present or (expected_present and water._tuning[key] != expected_value): return _fail("Another owner changed tuning " + key)
    if enabled == _applied: return true
    var values: Dictionary = _candidate if enabled else _original
    # The canonical setter propagates to every surface and the photon uniforms.
    # All setters run synchronously before another draw; no intermediate image.
    for key: String in _candidate: water.set_tuning(key, values[key])
    if not enabled:
        for key: String in _candidate:
            if _original_tuning[key].present: water._tuning[key] = _original_tuning[key].value
            else: water._tuning.erase(key)
    _applied = enabled
    last_error = ""
    return true

func restore() -> bool:
    return set_enabled(false)

func describe() -> Dictionary:
    var result := {"pass": _bound, "id": ID, "bound": _bound, "enabled": _applied, "candidate": _candidate.duplicate(), "profile_name": _profile_name, "original": _original.duplicate(), "last_error": last_error,
        "automatic_install": false, "production_defaults_changed": false, "shader_changes": false, "native_visual_accepted": false,
        "scope": "Shared original wave controls only. Optional Fine requires explicit High256/160 photon grid; standard_safe keeps original High grid. Existing footprint and18m surface fade retained."}
    if _bound and _water.get_ref() != null:
        var water: Node3D = _water.get_ref()
        result["live"] = {}
        result["coherent_parameter_binding"] = true
        for key: String in _candidate:
            result.live[key] = {"settings": water.settings[key], "surface": water._surface_uniforms.get("distortionScale" if key == "distortion" else key), "photons": water.caustics._params.get(key)}
            if key != "distortion": result.coherent_parameter_binding = result.coherent_parameter_binding and water.settings[key] == water._surface_uniforms.get(key) and water.settings[key] == water.caustics._params.get(key)
            else: result.coherent_parameter_binding = result.coherent_parameter_binding and water.settings[key] == water._surface_uniforms.get("distortionScale")
        result["causticsSpeed"] = water.settings.causticsSpeed
        result["causticsRefresh"] = water.settings.causticsRefresh
        result["causticsIntensity"] = water.settings.causticsIntensity
    return result

func _failure(reason: String) -> Dictionary:
    last_error = reason
    return {"pass": false, "reason": reason, "production_defaults_changed": false}

func _fail(reason: String) -> bool:
    last_error = reason
    return false
