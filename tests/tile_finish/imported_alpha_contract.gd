extends SceneTree
## Native imported texture decoding, NOT a rendered pixel or GPU visual test.
const ArtMaterials = preload("res://scripts/art_pass/art_pass_materials.gd")
var errors: Array[String] = []
var observations: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var library := ArtMaterials.new()
	for role: String in ArtMaterials.CERAMIC_FINISH:
		var material := library.resolve(role, null)
		var texture: Texture2D = material.get_shader_parameter("orm")
		var image := texture.get_image()
		if image == null:
			errors.append("No imported image: " + role)
			continue
		var imported_format := image.get_format()
		var mip_count := image.get_mipmap_count()
		if image.is_compressed() and image.decompress() != OK:
			errors.append("Cannot decode imported compression: " + role)
			continue
		var tile := "tile_" in role
		var samples: Array[Dictionary] = [{"label":"face", "x":128, "expected":1.0}]
		if tile:
			samples.append({"label":"joint", "x":0, "expected":0.0})
			samples.append({"label":"edge", "x":2, "expected":199.0/255.0})
		for sample: Dictionary in samples:
			var observed := image.get_pixel(int(sample.x), 128).a
			if absf(observed - float(sample.expected)) > 0.045:
				errors.append("Imported alpha mismatch: " + role + "/" + str(sample.label))
			observations.append({"role":role, "sample":sample.label, "expected":sample.expected, "observed":observed, "imported_format":imported_format, "mip_count":mip_count})
		if tile and mip_count > 0:
			var last_mip: Image = Image.create_from_data(1, 1, false, image.get_format(), image.get_data().slice(image.get_mipmap_offset(mip_count)))
			var mean_face: float = last_mip.get_pixel(0, 0).a
			if absf(mean_face - 0.9656297870710784) > 0.02:
				errors.append("Imported mip alpha lost area coverage: " + role)
			observations.append({"role":role, "sample":"last_mip", "observed":mean_face, "expected":0.9656297870710784})
		var finish: Vector3 = ArtMaterials.CERAMIC_FINISH[role]
		if not bool(material.get_shader_parameter("glazed_ceramic")) or not is_equal_approx(float(material.get_shader_parameter("glaze_roughness")), finish.x):
			errors.append("Material finish was not bound: " + role)
	print("TILE_IMPORTED_ALPHA ", JSON.stringify({"pass":errors.is_empty(), "errors":errors, "observations":observations, "scope":"Native imported texture decode and material binding only; not GPU sampling, shader execution, raster appearance or custom-engine RT acceptance."}))
	quit(0 if errors.is_empty() else 1)
