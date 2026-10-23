extends RefCounted
## Explicit PC mainhall optical candidate. Source solver/settings stay untouched.
## Nothing installs this profile automatically. The parent/runtime owns its hooks.
const ID := "pc-nearfield-optics-v1"
const FLAG := "--pc-nearfield-water"
const MAINHALL := Vector2i(-1,-1)
const EMISSION := Rect2(-8.0,-6.0,16.0,12.0)
var last_error := ""
var _water: WeakRef
var _bound := false
var _requested := false
var _active := false
var _last_reason := "not_requested"
var _receiver_originals: Dictionary = {}
var _last_receiver_count := -1
var _saved_surface_flag: Dictionary = {}
var _saved_surface_strength: Dictionary = {}
var _saved_photon_strength := 1.0
var _strength := 1.0
var _surface_originals: Dictionary = {}

static func requested(arguments: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
    return FLAG in arguments and not OS.has_feature("android") and not OS.has_feature("ios") and "--mobile-preview" not in arguments

func bind(water: Node3D) -> Dictionary:
    if _bound: return _failure("Already bound")
    # Do not preload runtime here: the runtime may preload this helper.
    if water == null or water.get_script() == null or water.get_script().resource_path != "res://scripts/water/source_water_runtime.gd": return _failure("Exact source runtime required")
    if OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args(): return _failure("Desktop-only opt-in")
    _water = weakref(water); _bound = true
    _saved_surface_flag = {"present":water._surface_uniforms.has("pcNearfieldOn"),"value":water._surface_uniforms.get("pcNearfieldOn")}
    _saved_surface_strength = {"present":water._surface_uniforms.has("pcNearfieldStrength"),"value":water._surface_uniforms.get("pcNearfieldStrength")}
    _saved_photon_strength = float(water.caustics._params.pcNearfieldStrength)
    return describe()

func set_enabled(enabled: bool) -> bool:
    if not _bound or _water.get_ref() == null: return _fail("Unbound or freed runtime")
    _requested = enabled
    return refresh_context()

func set_strength(value: float) -> bool:
    if not is_finite(value) or value < 0.0 or value > 1.0: return _fail("Shared height/gradient strength must be finite in0..1")
    _strength = value
    if _active and _water.get_ref() != null:
        var water: Node3D = _water.get_ref()
        if not water.caustics.set_pc_nearfield_strength(value): return _fail("Photon strength refused")
        water._surface_uniforms["pcNearfieldStrength"] = value
        water._bind_all()
    return true

func restore() -> bool:
    return set_enabled(false)

func _context_reason(water: Node3D) -> String:
    if not _requested: return "not_requested"
    if water.quality not in ["High","Ultra"] or water.caustics.quality != water.quality: return "requires_High_or_Ultra"
    var expected := Vector2i(256,96) if water.quality == "High" else Vector2i(384,192)
    if water.caustics.photon_grid() != expected: return "requires_original_quality_lattice"
    if not water.settings.microNormals: return "microNormals_layer_disabled"
    if not water.is_terrain_ready() or water._terrain_dirty: return "terrain_not_committed"
    if water._requested_coord != MAINHALL: return "outside_verified_mainhall"
    if water.domain_origin != Vector2(-32.0,-32.0): return "mainhall_origin_not_verified"
    var layout: Dictionary = water._layouts.get(MAINHALL,{})
    if not layout.get("formal",false) or layout.get("water_rects",[]) != [EMISSION]: return "mainhall_water_rect_not_verified"
    if float(layout.get("ceiling",0.0)) != 4.8 or layout.get("caustic_reflected_extent",Vector2.ZERO) != Vector2(11,10): return "reflection_envelope_not_verified"
    return ""

func refresh_context() -> bool:
    ## Call before caustic render / surface binding when active room or quality
    ## may have changed. Calling each frame is safe: unchanged state performs
    ## scalar/context checks only, no GPU allocation, compilation or rebinding.
    if not _bound or _water.get_ref() == null: return _fail("Unbound or freed runtime")
    var water: Node3D = _water.get_ref()
    _last_reason = _context_reason(water)
    var wanted := _last_reason.is_empty()
    if wanted != _active:
        if not _publish(water,wanted): return false
    if _active:
        var count: int = water._library._materials.size() if water._library != null else 0
        if count != _last_receiver_count: _install_receiver_bias(water)
    last_error = ""
    return true

func refresh_bindings() -> bool:
    ## After replacing materials without changing library size, call this once.
    if not refresh_context(): return false
    if _active: _install_receiver_bias(_water.get_ref())
    return true

func _remember_surface_flags(water: Node3D) -> void:
    for material: ShaderMaterial in water._materials.values():
        var id := material.get_instance_id()
        if not _surface_originals.has(id):
            _surface_originals[id] = {"material":weakref(material),"value":material.get_shader_parameter("pcNearfieldOn"),"strength":material.get_shader_parameter("pcNearfieldStrength")}

func _publish(water: Node3D, enabled: bool) -> bool:
    if not water.caustics.set_pc_nearfield_enabled(enabled,EMISSION if enabled else Rect2()): return _fail("Guarded caustic opt-in refused")
    if enabled: _remember_surface_flags(water)
    if not water.caustics.set_pc_nearfield_strength(_strength if enabled else _saved_photon_strength): return _fail("Shared strength refused")
    water._surface_uniforms["pcNearfieldStrength"] = _strength if enabled else _saved_photon_strength
    water._surface_uniforms["pcNearfieldOn"] = 1.0 if enabled else 0.0
    water._bind_all()
    _active = enabled
    if enabled:
        _install_receiver_bias(water)
    else:
        _restore_receiver_bias()
        # New water materials created while enabled inherit the source default
        # on restore; existing materials recover their exact prior override.
        for material: ShaderMaterial in water._materials.values():
            var row: Dictionary = _surface_originals.get(material.get_instance_id(),{})
            material.set_shader_parameter("pcNearfieldOn",row.get("value"))
            material.set_shader_parameter("pcNearfieldStrength",row.get("strength"))
        _surface_originals.clear()
        if _saved_surface_flag.present: water._surface_uniforms["pcNearfieldOn"] = _saved_surface_flag.value
        else: water._surface_uniforms.erase("pcNearfieldOn")
        if _saved_surface_strength.present: water._surface_uniforms["pcNearfieldStrength"] = _saved_surface_strength.value
        else: water._surface_uniforms.erase("pcNearfieldStrength")
    return true

func _install_receiver_bias(water: Node3D) -> void:
    if water._library == null: return
    for material in water._library._materials.values():
        if not material is ShaderMaterial: continue
        var id: int = material.get_instance_id()
        if not _receiver_originals.has(id):
            _receiver_originals[id] = {"material":weakref(material),"value":material.get_shader_parameter("pcNearfieldFloorMipBias")}
        material.set_shader_parameter("pcNearfieldFloorMipBias",.25)
    _last_receiver_count = water._library._materials.size()

func _restore_receiver_bias() -> void:
    for row: Dictionary in _receiver_originals.values():
        var material: ShaderMaterial = row.material.get_ref()
        if material != null: material.set_shader_parameter("pcNearfieldFloorMipBias",row.value)
    _receiver_originals.clear(); _last_receiver_count = -1

func describe() -> Dictionary:
    return {"pass":_bound,"id":ID,"requested":_requested,"active":_active,"shared_strength":_strength,"inactive_reason":_last_reason,"last_error":last_error,
        "source_solver_changed":false,"default_enabled":false,"floor_emission_rect":EMISSION,"original_wall_transport":true,
        "floor_filter_radius":.6 if _active else 1.4,"floor_receiver_bias":.25 if _active else 1.15,
        "added_gpu_allocations_per_frame":0,"analytic_time":"Elapsed poolTime times nonnegative user causticsSpeed; amplitude times microStrength/.65; identical surface/photon coupling",
        "approximation":"Millimetre analytic relief in photon height/normals and surface optics, not coarse-mesh silhouette; finite mainhall-envelope planar hit, not captured-depth tracing",
        "native_visual_accepted":false,"supported_qualities":["High","Ultra"],"Ultra_native_verified":false}

func _failure(reason: String) -> Dictionary:
    last_error = reason
    return {"pass":false,"error":reason}
func _fail(reason: String) -> bool:
    last_error = reason
    return false
