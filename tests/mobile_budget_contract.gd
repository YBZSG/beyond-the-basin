extends SceneTree
const Profile := preload("res://scripts/mobile/pool_mobile_profile.gd")
var errors: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: errors.append(label)

func _initialize() -> void:
	var mobile := "--mobile-preview" in OS.get_cmdline_user_args()
	check(Profile.is_mobile_session() == mobile, "platform selection")
	var water := preload("res://scripts/water/source_water_runtime.gd").new()
	var world := preload("res://scripts/world/pool_world.gd").new()
	check(water.mobile_optimized == mobile, "water startup selection")
	check(water.quality_levels.High.simulation == (384 if mobile else 768), "SWE startup budget")
	check(water.quality_levels.High.reflection == (512 if mobile else 768), "reflection startup budget")
	check(world.stream_radius == (1 if mobile else 2), "streaming startup budget")
	for preset: String in Profile.PIXEL_LIMITS:
		for size in [Vector2i(2400,1080), Vector2i(3200,1440), Vector2i(1280,720), Vector2i(1080,2400)]:
			var scale := Profile.render_scale(size, preset, 1.0)
			var cap: Vector2 = Profile.PIXEL_LIMITS[preset]
			check(maxi(size.x,size.y)*scale <= cap.x+.01, preset + " long edge cap")
			check(mini(size.x,size.y)*scale <= cap.y+.01, preset + " short edge cap")
			check(scale > 0.0 and scale <= 1.0, preset + " finite resolution")
	check(is_equal_approx(Profile.render_scale(Vector2i(3200,1440), "High", 1.0), .5), "high DPI does not render native 1440p")
	water.free()
	world.free()
	print("MOBILE_BUDGET_CONTRACT ", JSON.stringify({"checks":checks, "pass":errors.is_empty(), "mobile":mobile, "errors":errors}))
	quit(0 if errors.is_empty() else 1)
