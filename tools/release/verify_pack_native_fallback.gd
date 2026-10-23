extends SceneTree
## CPU-only actual source/PCK readback gate. No configure(), RD or GPU calls.
const Solver = preload("res://scripts/water/source_port/source_wave_solver.gd")
var errors: Array[String] = []
var publications := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		errors.append(label)

func run() -> void:
	var expect_fallback := "--expect-fallback" in OS.get_cmdline_user_args()
	var report_path := ""
	var expected_helper := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-helper="):
			expected_helper = argument.trim_prefix("--expected-helper=")
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	var loaded_helpers: Array[String] = []
	if OS.get_name() == "Linux":
		var mappings := FileAccess.open("/proc/self/maps", FileAccess.READ)
		check(mappings != null, "Linux library mapping evidence is readable")
		if mappings:
			while not mappings.eof_reached():
				var mapping := mappings.get_line()
				if mapping.contains("source_water") and mapping.contains(".so"):
					var path_start := mapping.find("/")
					if path_start >= 0:
						var mapped_path := mapping.substr(path_start)
						if not loaded_helpers.has(mapped_path):
							loaded_helpers.append(mapped_path)
		loaded_helpers.sort()
		if expect_fallback:
			check(loaded_helpers.is_empty(), "Missing-helper process has no source-water native mapping")
		elif not expected_helper.is_empty():
			check(loaded_helpers == [expected_helper], "Helper maps from the independent delivery host, not development source")
	var available := ClassDB.class_exists("SourceWaterReadback")
	check(available != expect_fallback, "Actual helper availability matches requested branch")
	var solver := Solver.new()
	solver.physics_size = 2
	solver.physics_eta.resize(4)
	solver.physics_u.resize(4)
	solver.physics_v.resize(4)
	solver.native_readback_enabled = true
	solver.physics_updated.connect(func() -> void: publications += 1)
	var fixture := Image.create(2, 2, false, Image.FORMAT_RGBAH)
	fixture.fill(Color(0.03125, -0.125, 0.0625, 1.0))
	var payload := fixture.get_data()
	solver._receive_readback(payload, solver._generation, 0.0, true)
	var expected_backend := "gdscript" if expect_fallback else "native_exact"
	check(solver._readback_parser_backend == expected_backend, "Actual production solver uses expected parser branch")
	for index in 4:
		check(solver.physics_eta[index] == 0.03125, "Exact eta at index " + str(index))
		check(solver.physics_u[index] == -0.125, "Exact u at index " + str(index))
		check(solver.physics_v[index] == 0.0625, "Exact v at index " + str(index))
	check(publications == 1 and solver._readback_publishes == 1, "One atomic valid publication")
	var accepted := [solver.physics_eta.to_byte_array(), solver.physics_u.to_byte_array(), solver.physics_v.to_byte_array()]
	var broken := payload.duplicate()
	broken.encode_u16(3 * 8 + 6, 0)
	solver._receive_readback(broken, solver._generation, 0.0, true)
	check(solver._rejected == 1 and publications == 1, "Invalid completion marker rejected without publication")
	check(accepted == [solver.physics_eta.to_byte_array(), solver.physics_u.to_byte_array(), solver.physics_v.to_byte_array()],
		"Rejected readback preserves all completed physics fields")
	var report := {"pass": errors.is_empty(), "errors": errors,
		"native_helper_available": available, "actual_backend": solver._readback_parser_backend,
		"loaded_native_libraries": loaded_helpers, "expected_helper": expected_helper,
		"mapped_helper_sha256": FileAccess.get_sha256(expected_helper) if not expected_helper.is_empty() else "",
		"expected_fallback": expect_fallback, "publications": publications,
		"scope": "CPU production readback parser only; solver was never configured, no RenderingDevice/GPU simulation was run.",
		"expected_extension_load_diagnostics": expect_fallback, "windows_or_android_executed": false}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "  ") + "\n")
		else:
			errors.append("Cannot write requested report")
	print("PACK_NATIVE_FALLBACK ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
