extends RefCounted
## Proposed opt-in lifecycle owner. NOT installed by Main or DesktopQuality.
## Event hooks only: no polling, rendering, GPU allocation or saved-settings I/O.
const Profile := preload("res://scripts/water/pc_fine_water_profile.gd")
const PROFILE_FLAG := "--pc-fine-water-profile=fine"
const GRID_FLAG := "--pc-fine-water-photon-grid=256x160"
var _configured := false
var _requested := false
var _manual_suspended := false
var _profile: RefCounted
var _water: WeakRef
var state := "off"
var last_error := ""

func configure(arguments: PackedStringArray) -> bool:
    if _configured: return _fail("Startup selection is immutable; restart to change the profile")
    _configured = true
    if OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in arguments:
        state = "desktop_only"; return true
    var selections := 0
    for argument: String in arguments:
        if argument.begins_with("--pc-fine-water-profile="):
            selections += 1
            if argument != PROFILE_FLAG: return _fail("Unknown optional PC fine-water profile")
    if selections > 1: return _fail("Duplicate fine-water startup selection")
    _requested = PROFILE_FLAG in arguments
    if _requested and GRID_FLAG not in arguments:
        _requested = false
        return _fail("Fine requires the explicit startup256/160 photon-grid option; no automatic cost increase")
    state = "waiting_for_water" if _requested else "off"
    return true

func before_water_change(water: Node3D, reason: String) -> bool:
    # Call BEFORE quality mutation, disposal, world replacement, or shutdown.
    # A false result is a detected integration/ownership conflict: do not mutate.
    if _profile != null:
        if _water == null or _water.get_ref() != water:
            return _fail("Wrong runtime supplied before " + reason)
        if not _profile.restore(): return _fail(reason + ": " + _profile.last_error)
        _profile = null
    _water = null
    last_error = ""
    state = "manual_override" if _manual_suspended else ("waiting_for_water" if _requested else "off")
    return true

func after_water_change(water: Node3D) -> bool:
    # Call only after saved settings and final desktop quality have been applied.
    if not _configured: return _fail("Configure startup selection first")
    if _profile != null:
        if _water == null or _water.get_ref() != water:
            return _fail("Restore the old live runtime before replacement")
        if not _profile.set_enabled(true): return _fail(_profile.last_error)
        return true # Unrelated settings: retain exact snapshot, no rebinding/allocation.
    _water = weakref(water) if is_instance_valid(water) else null
    if not _requested or _manual_suspended:
        state = "manual_override" if _manual_suspended else "off"; return true
    if water == null:
        state = "waiting_for_water"; return true
    if water.get_script() != Profile.RUNTIME: return _fail("Exact source-water runtime required")
    if water.quality != "High" or water.caustics.quality != "High":
        state = "dormant_quality"; last_error = ""; return true
    if water.caustics.photon_grid() != Vector2i(256, 160):
        state = "dormant_grid"; last_error = ""; return true
    if not water.settings.microNormals:
        state = "dormant_micro_normals"; last_error = ""; return true
    var candidate := Profile.new()
    var binding: Dictionary = candidate.bind(water, "fine")
    if not binding.get("pass", false): return _fail(binding.get("reason", "Fine binding refused"))
    if not candidate.set_enabled(true): return _fail(candidate.last_error)
    _profile = candidate
    state = "active"; last_error = ""
    return true

func before_manual_tuning(water: Node3D, parameter: String) -> bool:
    # User's overlapping advanced-water edits win for this process lifetime.
    # Unrelated sliders retain the active profile and its original snapshot.
    if parameter not in ["causticsScale", "microStrength", "micro_strength", "distortion", "microNormals"]:
        return true
    if not before_water_change(water, "manual tuning"): return false
    if _requested:
        _manual_suspended = true
        state = "manual_override"
    return true

func shutdown(water: Node3D) -> bool:
    if not before_water_change(water, "shutdown"): return false
    _requested = false; state = "off"
    return true

func status() -> Dictionary:
    var runtime: Node3D = _water.get_ref() if _water != null else null
    var grid := Vector2i.ZERO
    if runtime != null and runtime.get_script() == Profile.RUNTIME: grid = runtime.caustics.photon_grid()
    var increased_work := grid == Vector2i(256, 160)
    var label := "细水波：可选 High 专用，默认关闭"
    if state == "active": label = "细水波：已启用（可选 High）；光子三角形约1.94倍，不代表帧耗时倍数"
    elif state == "dormant_quality": label = "细水波：未启用，仅支持 High；保留当前画质，不自动提升"
    elif state == "manual_override": label = "细水波：手动水体设置优先，本次运行不再自动启用"
    elif state == "dormant_grid": label = "细水波：未启用，需要启动时选择256/160光子采样"
    elif state == "dormant_micro_normals": label = "细水波：未启用，微表面法线已关闭"
    elif state == "conflict": label = "细水波：设置所有权冲突，未覆盖现有设置"
    if increased_work and state != "active": label += "；High的额外光子采样仍有效，需重启并移除采样参数恢复默认成本"
    return {"state": state, "requested": _requested, "active": _profile != null,
        "manual_suspended": _manual_suspended, "error": last_error, "label": label,
        "effective_photon_grid": str(grid), "increased_photon_workload": increased_work,
        "issued_triangle_ratio": 1.9411764705882353 if increased_work else 1.0,
        "gpu_time_ratio_measured": false, "saved_settings_written": false,
        "automatic_install": false}

func _fail(message: String) -> bool:
    state = "conflict"; last_error = message
    return false
