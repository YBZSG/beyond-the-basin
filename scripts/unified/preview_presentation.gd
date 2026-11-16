extends RefCounted
## One shared environment, stable across real doorways. No camera/world transitions.
static func apply(main: Node) -> void:
	if not is_instance_valid(main.environment): return
	var env: Environment = main.environment.environment
	var mood: Tween = main.lighting.get("_mood_tween")
	if is_instance_valid(mood) and mood.is_valid(): mood.kill()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("91b9bd")
	sky_material.sky_horizon_color = Color("d4e0d9")
	sky_material.ground_horizon_color = Color("d4e0d9")
	sky_material.ground_bottom_color = Color("3d5048")
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_color = Color("bfcfcb")
	env.ambient_light_energy = .35
	env.tonemap_exposure = 1.05
	env.fog_enabled = false
	var sun: DirectionalLight3D = main.environment.get_node_or_null("ApertureSun")
	if sun != null: sun.light_energy = 0.0
	main.water.refresh_capture_lighting()
