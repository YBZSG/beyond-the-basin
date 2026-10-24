extends RefCounted
## Optional rebuilt-engine NR controls. A request is not proof of a native pass.
const DEFAULTS := {"nr_layers":1, "nr_intensity":1.0, "nr_tone":0.1, "nr_structure":0.5}
const CONTROL_ENV := "POOLCORE_NR_CONTROL_V1"
const STATUS_ENV := "POOLCORE_NR_STATUS_V1"
var revision := 0
var _last_request: Dictionary = {}

static func validate(key: String, value: Variant, fallback: Variant) -> Variant:
	if key == "nr_layers":
		return clampi(value, 1, 4) if value is int else fallback
	if key in ["nr_intensity", "nr_tone", "nr_structure"]:
		if (value is float or value is int) and is_finite(float(value)):
			return clampf(float(value), 0.0, 1.0)
	return fallback

static func normalize(settings: Dictionary) -> void:
	for key: String in DEFAULTS:
		settings[key] = validate(key, settings.get(key, DEFAULTS[key]), DEFAULTS[key])
	# Resolve old or hand-edited conflicting profiles without silently bypassing NR.
	if bool(settings.get("nr", false)): settings.frame_generation = false

func publish(settings: Dictionary) -> Dictionary:
	var desired := {"layers":int(settings.nr_layers), "intensity":float(settings.nr_intensity), "tone":float(settings.nr_tone), "structure":float(settings.nr_structure)}
	if revision == 0 or desired != _last_request:
		revision = maxi(revision + 1, Time.get_ticks_usec())
		_last_request = desired.duplicate()
	var message := desired.duplicate()
	message.revision = revision
	OS.set_environment(CONTROL_ENV, JSON.stringify(message))
	return message

func read_status() -> Dictionary:
	return decode_status(OS.get_environment(STATUS_ENV), OS.get_process_id(), Time.get_ticks_msec(), revision, _last_request)

static func decode_status(raw: String, process_id: int, now_msec: int, requested_revision: int, desired: Dictionary = {}) -> Dictionary:
	var missing := {"acknowledged":false, "supported":false, "capability":"unknown", "state":"unavailable", "applied_layers":0, "reason":"需要支持 NR 可调参数的新版自编译引擎；旧引擎继续使用原单层 NR。"}
	if raw.is_empty() or raw.length() > 8192: return missing
	var parser := JSON.new()
	if parser.parse(raw) != OK: return missing
	var parsed: Variant = parser.data
	if not parsed is Dictionary or parsed.get("schema") != 1 or parsed.get("process_id") != process_id: return missing
	if not parsed.get("supported") is bool: return missing
	var result: Dictionary = parsed.duplicate(true)
	result.acknowledged = true
	result.applied_layers = clampi(int(result.get("applied_layers", 0)), 0, 4)
	var age := now_msec - int(result.get("emitted_msec", -100000))
	result.fresh = age >= 0 and age <= 10000
	var fields_match := true
	if not desired.is_empty():
		var applied: Variant = result.get("applied", {})
		fields_match = applied is Dictionary
		if fields_match:
			for key: String in desired:
				var value: Variant = applied.get(key)
				if not (value is float or value is int) or not is_finite(float(value)) or not is_equal_approx(float(value), float(desired[key])):
					fields_match = false
	result.current_request_applied = bool(result.fresh) and bool(result.supported) and fields_match and result.applied_layers > 0 and result.get("state", "") == "active" and int(result.get("applied_revision", -1)) == requested_revision
	if not result.current_request_applied: result.applied_layers = 0
	return result
