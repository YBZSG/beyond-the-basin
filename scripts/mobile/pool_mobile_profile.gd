extends RefCounted
## Shared startup budgets: apply before allocating water or streaming rooms.
const WATER_QUALITY := {
	"Low": {"simulation":384, "surface":96, "ripple":192, "reflection":256},
	"Medium": {"simulation":384, "surface":192, "ripple":384, "reflection":384},
	"High": {"simulation":384, "surface":256, "ripple":384, "reflection":512},
	"Ultra": {"simulation":768, "surface":384, "ripple":768, "reflection":768},
}
const PIXEL_LIMITS := {
	"Low": Vector2(1152,648), "Medium": Vector2(1280,720),
	"High": Vector2(1600,900), "Ultra": Vector2(1920,1080),
}

static func is_mobile_session() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args()

static func initial_water_quality() -> String:
	var config := ConfigFile.new()
	var selected := "High"
	if config.load("user://mobile_settings.cfg") == OK:
		selected = str(config.get_value("graphics", "preset", "High"))
	return selected if WATER_QUALITY.has(selected) else "High"

static func render_scale(window_size: Vector2i, preset: String, user_scale: float) -> float:
	var limit: Vector2 = PIXEL_LIMITS.get(preset, PIXEL_LIMITS.High)
	var long_edge := float(maxi(1, maxi(window_size.x, window_size.y)))
	var short_edge := float(maxi(1, mini(window_size.x, window_size.y)))
	return clampf(user_scale, .5, 1.25) * minf(1.0, minf(limit.x / long_edge, limit.y / short_edge))
