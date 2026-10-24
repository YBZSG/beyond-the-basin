extends RefCounted
## Reversible desktop-only authored-asset selection. No seeded RNG, light,
## collision, water or renderer setting is selected here.
const MobileProfile = preload("res://scripts/mobile/pool_mobile_profile.gd")
const ROOM_ASSETS := {
	"low_arched_bath": "res://assets/models/art_pass/low_arched_bath_crossing_runtime.glb",
	"shower_changing": "res://assets/models/art_pass/shower_changing_runtime.glb",
	"skylight_gallery": "res://assets/models/art_pass/skylight_gallery_runtime.glb",
	"service_transition": "res://assets/models/art_pass/service_transition_runtime.glb",
}

static func is_enabled() -> bool:
	return not MobileProfile.is_mobile_session() and "--legacy-art-pass" not in OS.get_cmdline_user_args()

static func room_geometry(module_key: String, original_path: String) -> String:
	if not is_enabled() or not ROOM_ASSETS.has(module_key):
		return original_path
	var selected: String = ROOM_ASSETS[module_key]
	if not ResourceLoader.exists(selected):
		push_warning("Authored art asset missing; retaining the original room: " + selected)
		return original_path
	return selected
