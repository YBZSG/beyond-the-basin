extends RefCounted
## Reversible desktop Forward+ profile owned by DesktopQuality.
## Reallocate near cascades without reducing the existing 120 m coverage.
## The preliminary 64 m study remains explicitly named diagnostic-only.
## Preserve the authored 1 degree PCSS sun, biases, opacity and caster masks.
const LIGHT_PROPERTIES: Array[String] = [
	"directional_shadow_mode", "directional_shadow_max_distance",
	"directional_shadow_split_1", "directional_shadow_split_2",
	"directional_shadow_split_3", "directional_shadow_blend_splits"]
const FILTER_SETTING := "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
var _sun: WeakRef
var _authored: Dictionary = {}
var _filter_applied := -1
var _filter_original := -1

static func profile_for(preset: String, coverage: String = "preserve120") -> Dictionary:
	if preset not in ["Medium", "High", "Ultra"]: return {}
	if coverage not in ["preserve120", "indoor64"]: return {}
	var distance := 120.0 if coverage == "preserve120" else 64.0
	var third := 60.0 if coverage == "preserve120" else 32.0
	return {"coverage":coverage, "diagnostic_only":coverage=="indoor64",
		"max_distance":distance, "split_1":5.0 / distance,
		"split_2":14.0 / distance, "split_3":third / distance,
		"filter_quality":RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if preset == "Medium" else RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"cascade_ends_m":[5.0,14.0,third,distance]}

static func snapshot(light: DirectionalLight3D) -> Dictionary:
	var result: Dictionary = {}
	for property: String in LIGHT_PROPERTIES: result[property] = light.get(property)
	return result

static func restore_light(light: DirectionalLight3D, values: Dictionary) -> void:
	for property: String in LIGHT_PROPERTIES:
		if values.has(property): light.set(property, values[property])

static func apply_light_profile(light: DirectionalLight3D, preset: String, coverage: String = "preserve120") -> Dictionary:
	# Pure node-property operation also used by the headless contract. The
	# production-facing configure() below owns the platform/renderer guard.
	var profile := profile_for(preset, coverage)
	if profile.is_empty() or not is_instance_valid(light): return {}
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = profile.max_distance
	light.directional_shadow_split_1 = profile.split_1
	light.directional_shadow_split_2 = profile.split_2
	light.directional_shadow_split_3 = profile.split_3
	light.directional_shadow_blend_splits = true
	return profile

func configure(light: DirectionalLight3D, preset: String, enabled: bool = true, coverage: String = "preserve120") -> Dictionary:
	var allowed := not (OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args())
	allowed = allowed and RenderingServer.get_current_rendering_method() == "forward_plus"
	if not enabled or not allowed or profile_for(preset, coverage).is_empty() or not is_instance_valid(light):
		restore()
		return {"applied":false}
	if _sun == null or _sun.get_ref() != light:
		restore()
		_sun = weakref(light)
		_authored = snapshot(light)
	var profile := apply_light_profile(light, preset, coverage)
	var filter_quality: int = int(profile.filter_quality)
	if _filter_original < 0:
		# Before integration, no other runtime code changes this global filter.
		# Keep ownership in DesktopQuality, not in a per-room light constructor.
		_filter_original = int(ProjectSettings.get_setting(FILTER_SETTING, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM))
	if _filter_applied != filter_quality:
		RenderingServer.directional_soft_shadow_filter_set_quality(filter_quality)
		_filter_applied = filter_quality
	return {"applied":true, "preset":preset, "profile":profile, "light":snapshot(light),
		"atlas_memory_changed":false, "bias_changed":false, "sun_size_changed":false}

func restore() -> void:
	if _sun != null:
		var previous := _sun.get_ref() as DirectionalLight3D
		if is_instance_valid(previous): restore_light(previous, _authored)
	if _filter_original >= 0 and _filter_applied != _filter_original:
		RenderingServer.directional_soft_shadow_filter_set_quality(_filter_original)
	_sun = null
	_authored.clear()
	_filter_applied = -1
	_filter_original = -1
