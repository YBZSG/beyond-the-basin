extends RefCounted
## Independent desktop-only optical additions. Persistence belongs to the host.
## Never merge these keys into the source solver or overwrite legacy look/wind settings.

const DEFAULT := {
	"referenceWaves": false,
	"referenceWaveStrength": 0.45,
	"referenceWaveDirection": 35.0,
	"referenceWaveScale": 1.0,
	"referenceLook": false,
	"referenceFringePx": 0.8,
	"referenceGrain": 0.006,
	"referenceVignette": 0.07,
}
const POOLROOMS_PRESET := {
	"referenceWaves":true,"referenceWaveStrength":0.82,"referenceWaveDirection":18.0,"referenceWaveScale":1.0,
	"referenceLook":true,"referenceFringePx":3.4,"referenceGrain":0.003,"referenceVignette":0.26,
}
const WAVE_KEYS := ["referenceWaves", "referenceWaveStrength", "referenceWaveDirection", "referenceWaveScale"]
const CAMERA_KEYS := ["referenceLook", "referenceFringePx", "referenceGrain", "referenceVignette"]
const RANGES := {
	"referenceWaveStrength": [0.0, 1.0],
	"referenceWaveScale": [0.6, 1.6],
	"referenceFringePx": [0.0, 8.0],
	"referenceGrain": [0.0, 0.02],
	"referenceVignette": [0.0, 0.45],
}

static func sanitize(values: Variant) -> Dictionary:
	var result := DEFAULT.duplicate()
	if not values is Dictionary: return result
	for key: String in DEFAULT:
		if not values.has(key): continue
		var value: Variant = values[key]
		if DEFAULT[key] is bool:
			if value is bool: result[key] = value
		elif (value is int or value is float) and is_finite(float(value)):
			if key == "referenceWaveDirection":
				result[key] = fposmod(float(value), 360.0)
			else:
				var bounds: Array = RANGES[key]
				result[key] = clampf(float(value), float(bounds[0]), float(bounds[1]))
	return result

static func camera_visible(values: Variant, legacy_mode: int = 0) -> bool:
	var clean := sanitize(values)
	var reference_has_effect: bool = clean.referenceLook
	return clampi(legacy_mode, 0, 3) != 0 or reference_has_effect

static func apply_camera(material: ShaderMaterial, values: Variant, legacy_mode: int = 0) -> void:
	if material == null: return
	var clean := sanitize(values)
	material.set_shader_parameter("look_mode", 0 if legacy_mode == 4 or clean.referenceLook else clampi(legacy_mode, 0, 3))
	material.set_shader_parameter("reference_look_enabled", clean.referenceLook)
	material.set_shader_parameter("reference_fringe_px", clean.referenceFringePx)
	material.set_shader_parameter("reference_grain", clean.referenceGrain)
	material.set_shader_parameter("reference_vignette", clean.referenceVignette)
