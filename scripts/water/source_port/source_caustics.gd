class_name SourceCaustics
extends RefCounted
## Native port of InteractiveWater photon transport at source commit 66a4543.
## Uses the GLOBAL RenderingDevice, indexed triangle rasterization and RGBA16F
## render targets. There is no CPU caustic image and no substitute sine texture.
## All GPU work is queued to the render thread; Texture2DRD exposes its targets.

const TriangleBvh = preload("res://scripts/water/source_port/source_triangle_bvh.gd")
const SOURCE_COMMIT := "66a4543602d9e774db07c2da12ce1d40d522532c"
const SHADER_DIR := "res://shaders/source_water/"
const FLOOR_RESULT_SHADER_DIR := "res://shaders/source_water/"
const QUALITY := {
	"Low": {"caustics": 256, "photons": 64, "wallPhotons": 24},
	"Medium": {"caustics": 768, "photons": 192, "wallPhotons": 48},
	"High": {"caustics": 1024, "photons": 256, "wallPhotons": 96},
	"Ultra": {"caustics": 2048, "photons": 384, "wallPhotons": 192},
}
const WALL_NORMALS := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
const MASK_SIZE := 256
const DEFAULT_PARAMS := {
	"poolCell": 0.125, "detailCell": 0.0625, "waveHeight": 1.0,
	"rippleGain": 1.0, "normalBoost": 1.0, "microStrength": 0.65,
	"simulationOn": 1.0, "ripplesOn": 1.0, "microOn": 1.0,
	"causticsScale": 1.0, "causticsSpeed": 0.6, "microOrigin": Vector2.ZERO,
	"causticsRefresh": 2, "causticGain": 1.5,
	"reflectedWallExtents": Vector2(15.7, 15.7),
	"transmittedWallExtents": Vector2(15.7, 15.7),
	# PC_NEARFIELD_BEGIN
	"pcNearfieldOn": 0.0, "pcNearfieldStrength": 1.0,
	# PC_NEARFIELD_END
}

var floor_texture := Texture2DRD.new()
var wall_texture := Texture2DRD.new()
var quality := "High"
var caustic_frames := 0
var caustic_age := 0
# Reuse exact FP32 source height/normal samples, never lower photon/atlas quality.
# The direct path stays available for native A/B fixtures and diagnosis.
var reuse_wave_samples := true
# Cache exact FP32 floor photon results once per original lattice vertex.
# Direct photons remain an independently compiled fallback, including when
# disabled, unsupported, allocation fails, or required descriptors are absent.
var reuse_floor_photon_results := not OS.get_cmdline_user_args().has("--no-caustic-floor-result-cache")
var _floor_result_ready := false
var _floor_result_error := ""
var _floor_result_bytes := 0
var _floor_result_dispatches := 0
var _floor_result_fallbacks := 0
var _floor_result_last_used := false
var _floor_result_shader: RID
var _floor_result_pipeline: RID
var _floor_result_compute_shader: RID
var _floor_result_compute_pipeline: RID
var _floor_result_buffer: RID
var _floor_result_sets: Dictionary = {}
var _floor_result_compute_sets: Dictionary = {}
var _floor_result_vertex_source := ""
var _floor_result_compute_source := ""
var skip_zero_power_visibility := true
var profile_enabled := false
var profile_samples: Array[Dictionary] = []
var cadence_counters := {"calls": 0, "disabled": 0, "settled": 0, "refresh_skips": 0, "scheduled": 0, "dirty": 0, "ready_changed": 0}
var invalidation_counters: Dictionary = {}
var last_queue_latency_ms := 0.0
var last_render_submit_ms := 0.0
var _profile_timestamp_frame := -1
var _render_sequence := 0
var _gpu_timestamps: RefCounted
var last_error := ""
var tracing_ready := false
var available := false
var water_light_power := 1.0
var _params: Dictionary = DEFAULT_PARAMS.duplicate()
var _surface: Texture2DRD
var _depth: Texture2DRD
var _detail: Texture2DRD
var _initialized := false
var _disposed := false
var _dirty := true
var _last_active := false
var _last_ready := -1
var _lamps: Array[Dictionary] = [
	{"position": Vector3(-9, 7.3, -5), "power": 95.0},
	{"position": Vector3(8, 7.3, -5), "power": 95.0},
]
var _solids: Array[AABB] = []
var _mask_pixels: Array[PackedByteArray] = []
var _mask_job_lamp := 2
var _mask_job_row := 0
var _geometry_revision := 0
var _node_bytes := PackedByteArray()
var _triangle_bytes := PackedByteArray()
# Render-thread-only state below.
var _rd: RenderingDevice
var _owned: Array[RID] = []
var _photon_sets: Dictionary = {}
var _blur_sets: Dictionary = {}
var _wave_sets: Dictionary = {}
var _wave_shader: RID
var _wave_pipeline: RID
var _wave_buffer: RID
var _wall_wave_offset := 0
var _wave_compute_source := ""
var _linear: RID
var _nearest: RID
var _ubo: RID
var _node_buffer: RID
var _triangle_buffer: RID
var _node_buffer_size:=0
var _triangle_buffer_size:=0
var geometry_buffer_allocations:=0
var geometry_buffer_reuses:=0
var _masks: Array[RID] = []
var _photon_shader: RID
var _blur_shader: RID
var _photon_pipeline: RID
var _blur_pipeline: RID
var _floor: Dictionary = {}
var _wall: Dictionary = {}
var _filter: Dictionary = {}
var _floor_indices: RID
var _wall_indices: RID
var _gpu_geometry_revision := -1
var _photon_vertex_source := ""
var _photon_fragment_source := ""
var _fullscreen_source := ""
var _blur_fragment_source := ""

# Optional startup-only PC sampling override; default QUALITY remains exact.
# No solver, receiver resolution, optical formula or frame cadence change.
var _pc_photon_grid_override := Vector2i.ZERO
var pc_photon_grid_error := ""

# PC_NEARFIELD_BEGIN
func set_pc_nearfield_enabled(enabled: bool, verified_rect := Rect2()) -> bool:
	# Only the profile, after checking the actual active authored-room layout,
	# may request this bounded floor emission. A generic set_parameters call
	# cannot enable it. No target/grid allocation or shader compilation occurs.
	if enabled:
		if _disposed or quality not in ["High", "Ultra"]: return false
		var expected := Vector2i(256,96) if quality == "High" else Vector2i(384,192)
		if photon_grid() != expected: return false
		if OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args(): return false
		if verified_rect != Rect2(-8.0, -6.0, 16.0, 12.0): return false
	var value := 1.0 if enabled else 0.0
	if _params.pcNearfieldOn != value:
		_params.pcNearfieldOn = value
		_note_invalidation("pc_nearfield_opt_in")
		_dirty = true
	return true
func set_pc_nearfield_strength(value: float) -> bool:
	if not is_finite(value) or value < 0.0 or value > 1.0: return false
	if _params.pcNearfieldStrength != value:
		_params.pcNearfieldStrength = value
		_note_invalidation("pc_nearfield_strength")
		_dirty = true
	return true
# PC_NEARFIELD_END

func set_pc_photon_grid_override(floor_segments: int, wall_segments: int) -> bool:
	if _initialized or _disposed:
		pc_photon_grid_error = "Photon sampling override must be selected before initialization"
		return false
	if OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args():
		pc_photon_grid_error = "Photon sampling override is desktop-only"
		return false
	var requested := Vector2i(floor_segments, wall_segments)
	if requested not in [Vector2i.ZERO, Vector2i(256, 160)]:
		pc_photon_grid_error = "Only original defaults or audited PC256/160 sampling are supported"
		return false
	_pc_photon_grid_override = requested
	pc_photon_grid_error = ""
	return true

func _select_pc_photon_grid_from_args(arguments: PackedStringArray) -> void:
	# A malformed, mobile or inactive-quality option never disables caustics.
	for argument: String in arguments:
		if not argument.begins_with("--pc-fine-water-photon-grid="): continue
		if argument != "--pc-fine-water-photon-grid=256x160":
			_pc_photon_grid_override = Vector2i.ZERO
			pc_photon_grid_error = "Ignored unsupported PC photon-grid option; original quality retained: " + argument
			return
		if not set_pc_photon_grid_override(256, 160): return

func photon_grid() -> Vector2i:
	if quality == "High" and _pc_photon_grid_override != Vector2i.ZERO:
		return _pc_photon_grid_override
	return Vector2i(int(QUALITY[quality].photons), int(QUALITY[quality].wallPhotons))

func _sampling_quality() -> Dictionary:
	var result: Dictionary = QUALITY[quality].duplicate()
	var grid := photon_grid()
	result.photons = grid.x
	result.wallPhotons = grid.y
	return result

func initialize(requested_quality: String = "High") -> void:
	if _initialized or _disposed:
		return
	quality = requested_quality if QUALITY.has(requested_quality) else "High"
	_select_pc_photon_grid_from_args(OS.get_cmdline_user_args())
	_initialized = true
	if OS.get_cmdline_user_args().has("--source-gpu-timings"):
		_gpu_timestamps = preload("res://scripts/water/source_port/source_gpu_timestamps.gd").new("caustic", PackedStringArray(["begin", "wave_cache", "floor_result_cache", "floor_photons", "floor_blur", "wall_photons", "wall_blur", "end"]))
		_gpu_timestamps.start()
	var uniforms := FileAccess.get_file_as_string(SHADER_DIR + "caustic_uniforms.glslinc")
	# PC_NEARFIELD_BEGIN
	var nearfield := FileAccess.get_file_as_string("res://shaders/pc_nearfield_lab/height_modes.gdshaderinc")
	# PC_NEARFIELD_END
	_photon_vertex_source = "#version 450\n" + uniforms + nearfield + FileAccess.get_file_as_string(SHADER_DIR + "shared_waves.glslinc") + FileAccess.get_file_as_string(SHADER_DIR + "caustic_bvh.glslinc") + FileAccess.get_file_as_string(SHADER_DIR + "caustic_photons.vert")
	_photon_fragment_source = "#version 450\n" + uniforms + FileAccess.get_file_as_string(SHADER_DIR + "caustic_photons.frag")
	_fullscreen_source = "#version 450\n" + FileAccess.get_file_as_string(SHADER_DIR + "caustic_fullscreen.vert")
	_blur_fragment_source = "#version 450\n" + FileAccess.get_file_as_string(SHADER_DIR + "caustic_blur.frag")
	var optical_prefix := "#version 450\n" + uniforms + nearfield + FileAccess.get_file_as_string(SHADER_DIR + "shared_waves.glslinc") + FileAccess.get_file_as_string(SHADER_DIR + "caustic_bvh.glslinc")
	_floor_result_vertex_source = optical_prefix + FileAccess.get_file_as_string(FLOOR_RESULT_SHADER_DIR + "caustic_floor_result.vert")
	_floor_result_compute_source = optical_prefix + FileAccess.get_file_as_string(FLOOR_RESULT_SHADER_DIR + "caustic_floor_result.glslinc")
	_wave_compute_source = "#version 450\n" + uniforms + nearfield + FileAccess.get_file_as_string(SHADER_DIR + "shared_waves.glslinc") + FileAccess.get_file_as_string(SHADER_DIR + "caustic_wave_cache.glslinc")
	if _mask_pixels.is_empty():
		for i in range(2):
			var pixels := PackedByteArray()
			pixels.resize(MASK_SIZE * MASK_SIZE)
			pixels.fill(255)
			_mask_pixels.append(pixels)
	RenderingServer.call_on_render_thread(_initialize_gpu)

func configure(surface: Texture2DRD, depth: Texture2DRD, detail: Texture2DRD, params: Dictionary = {}) -> void:
	_surface = surface
	_depth = depth
	_detail = detail
	set_parameters(params)
	if not _initialized:
		initialize()

func set_parameters(params: Dictionary) -> void:
	for key in DEFAULT_PARAMS:
		# PC_NEARFIELD_BEGIN
		if key in ["pcNearfieldOn", "pcNearfieldStrength"]: continue # Dedicated guarded API only.
		# PC_NEARFIELD_END
		if params.has(key) and _params[key] != params[key]:
			if key in ["reflectedWallExtents", "transmittedWallExtents"]:
				if not params[key] is Vector2 or not params[key].is_finite() or params[key].x <= 0.0 or params[key].y <= 0.0:
					push_warning("Caustic wall extents must be finite positive X/Z half-extents; previous planes retained.")
					continue
			_params[key] = params[key]
			_note_invalidation("parameter:" + str(key))
			_dirty = true

func set_wall_extents(reflected: Vector2, transmitted: Vector2) -> void:
	## Bounded authored-room adapter: only the target plane offsets change.
	## Original square-room behavior remains the default (15.7, 15.7) for both.
	## Atlas tangential/vertical scale, optical laws, BVH and photon grids do not change.
	set_parameters({"reflectedWallExtents": reflected, "transmittedWallExtents": transmitted})

func set_quality(value: String) -> void:
	if not QUALITY.has(value) or value == quality:
		return
	quality = value
	# PC_NEARFIELD_BEGIN
	if value not in ["High", "Ultra"]: set_pc_nearfield_enabled(false)
	# PC_NEARFIELD_END
	_note_invalidation("quality")
	_dirty = true
	if _initialized:
		RenderingServer.call_on_render_thread(_resize_gpu)

func set_lamps(lamps: Array) -> void:
	var total := 0.0
	for lamp in lamps:
		total += float(lamp.get("power", 0.0))
	for i in range(mini(2, lamps.size())):
		_lamps[i] = {"position": lamps[i].get("position", Vector3.ZERO), "power": float(lamps[i].get("power", 20.0)) * 4.75}
	water_light_power = minf(2.0, total / 60.0)
	_note_invalidation("lamps")
	_dirty = true
	# Same shared lamp uniform for floor + all 8 wall passes, as source {...shared}.

func set_geometry(solids: Array, triangles: PackedVector3Array) -> void:
	## Triangles must be genuine opaque mesh faces in solver-local XYZ, not AABB replacements.
	## An explicitly empty triangle list is a valid unobstructed scene. Until this
	## call, photons remain dark rather than silently omitting outgoing visibility.
	tracing_ready = false
	var packed := build_triangle_bvh(triangles)
	_node_bytes = packed.nodes
	_triangle_bytes = packed.triangles
	_geometry_revision += 1
	tracing_ready = true
	begin_occlusion(solids)
	if _initialized:
		RenderingServer.call_on_render_thread(_upload_geometry_gpu.bind(_node_bytes, _triangle_bytes, _geometry_revision))

func set_prepared_geometry(payload: Dictionary) -> bool:
	## Main-thread publication only. All expensive calculations are finished.
	## This path never exposes partial lamp masks. Marking the legacy mask job
	## complete ensures render() cannot restart or advance its CPU preparation.
	var packed: Dictionary = payload.get("packed_bvh", {})
	var masks: Array = payload.get("masks", [])
	if not packed.get("nodes") is PackedByteArray or not packed.get("triangles") is PackedByteArray:
		return false
	if packed.nodes.is_empty() or packed.nodes.size() % 48 != 0 or packed.triangles.is_empty() or packed.triangles.size() % 48 != 0 or masks.size() != 2:
		return false
	for pixels in masks:
		if not pixels is PackedByteArray or pixels.size() != MASK_SIZE * MASK_SIZE:
			return false
	var complete_masks: Array[PackedByteArray] = []
	complete_masks.assign(masks)
	var filtered: Array[AABB] = []
	filtered.assign(payload.get("filtered_solids", []))
	_node_bytes = packed.nodes
	_triangle_bytes = packed.triangles
	_mask_pixels = complete_masks
	_solids = filtered
	_mask_job_lamp = 2
	_mask_job_row = 0
	_geometry_revision += 1
	tracing_ready = true
	_note_invalidation("prepared_geometry")
	_dirty = true
	if _initialized:
		# One render callback makes the BVH plus both lamps coherent before the
		# next photon pass; its bound arrays are not read from mutable live state.
		RenderingServer.call_on_render_thread(_upload_prepared_geometry_gpu.bind(_node_bytes, _triangle_bytes, complete_masks.duplicate(), _geometry_revision))
	return true

static func filter_occlusion_solids(solids: Array) -> Array[AABB]:
	var filtered: Array[AABB] = []
	for value in solids:
		var box: AABB
		if value is AABB:
			box = value
		elif value is Dictionary and value.has("min") and value.has("max"):
			box = AABB(value.min, value.max - value.min)
		else:
			continue
		var lo := box.position
		var hi := box.end
		if hi.y > .31 and lo.y < 7.4 and hi.x > -16.6 and lo.x < 16.6 and hi.z > -16.6 and lo.z < 16.6:
			filtered.append(box)
	return filtered

static func build_occlusion_masks(solids: Array[AABB], lamps: Array, prefer_native: bool = true) -> Array[PackedByteArray]:
	## Exact original incoming-light kernel: two 256-square R8 masks, .31m
	## start plane, 32m footprint, finite segments and unchanged slab tolerances.
	assert(lamps.size() == 2, "Preparation needs the two effective source lamps.")
	if prefer_native and native_occlusion_masks_available():
		# The helper is stateless. Do not share a mutable instance between terrain
		# worker threads. Old installed extensions also fall back by method check.
		var builder: RefCounted = ClassDB.instantiate("SourceWaterReadback")
		if builder != null and builder.has_method("build_occlusion_masks"):
			var boxes := PackedFloat32Array()
			boxes.resize(solids.size() * 6)
			for i in solids.size():
				var lo := solids[i].position
				# Godot computes AABB.end in Vector3 precision BEFORE packing. Do not
				# pass size and re-add it in native binary64 slab arithmetic.
				var hi := solids[i].end
				for axis in 3:
					boxes[i * 6 + axis] = lo[axis]
					boxes[i * 6 + axis + 3] = hi[axis]
			var lights := PackedFloat32Array()
			lights.resize(6)
			for i in 2:
				var lamp: Vector3 = lamps[i].position
				for axis in 3: lights[i * 3 + axis] = lamp[axis]
			var result: Variant = builder.call("build_occlusion_masks", boxes, lights)
			if result is Array and result.size() == 2 and result[0] is PackedByteArray and result[1] is PackedByteArray and result[0].size() == MASK_SIZE * MASK_SIZE and result[1].size() == MASK_SIZE * MASK_SIZE:
				var complete: Array[PackedByteArray] = []
				complete.assign(result)
				return complete
	# Missing/disabled/old extension, unsupported Vector3 precision, or rejected
	# input uses the unchanged complete GDScript calculation, never a partial mask.
	return _build_occlusion_masks_gdscript(solids, lamps)

static func native_occlusion_masks_available() -> bool:
	# Native masks preserve the default engine's binary32 Vector3 boundaries.
	# A custom double-precision engine must not silently downcast its geometry.
	return not OS.get_cmdline_user_args().has("--no-native-water-masks") and Vector3(16777217.0, 0.0, 0.0).x == 16777216.0 and ClassDB.class_exists("SourceWaterReadback") and ClassDB.class_has_method("SourceWaterReadback", "build_occlusion_masks")

static func _build_occlusion_masks_gdscript(solids: Array[AABB], lamps: Array) -> Array[PackedByteArray]:
	var masks: Array[PackedByteArray] = []
	for lamp_id in range(2):
		var pixels := PackedByteArray()
		pixels.resize(MASK_SIZE * MASK_SIZE)
		var lamp: Vector3 = lamps[lamp_id].position
		for row in range(MASK_SIZE):
			for x in range(MASK_SIZE):
				var ray := Vector3((float(x) + .5) / 256.0 * 32.0 - 16.0, .31, (float(row) + .5) / 256.0 * 32.0 - 16.0)
				pixels[x + row * MASK_SIZE] = 0 if ray_blocked(ray, lamp, solids) else 255
		masks.append(pixels)
	return masks

func begin_occlusion(solids: Array) -> void:
	_solids = filter_occlusion_solids(solids)
	_mask_job_lamp = 0
	_mask_job_row = 0
	_note_invalidation("incoming_mask_begin")
	_dirty = true

func step_occlusion(budget_ms: float = 2.0) -> bool:
	if _mask_job_lamp >= 2 or _mask_pixels.is_empty():
		return true
	_dirty = true
	var start := Time.get_ticks_usec()
	while _mask_job_lamp < 2:
		var lamp: Vector3 = _lamps[_mask_job_lamp].position
		var pixels: PackedByteArray = _mask_pixels[_mask_job_lamp]
		while _mask_job_row < MASK_SIZE:
			for x in range(MASK_SIZE):
				var ray := Vector3((float(x) + .5) / 256.0 * 32.0 - 16.0, .31, (float(_mask_job_row) + .5) / 256.0 * 32.0 - 16.0)
				pixels[x + _mask_job_row * MASK_SIZE] = 0 if ray_blocked(ray, lamp, _solids) else 255
			_mask_job_row += 1
			if float(Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
				_mask_pixels[_mask_job_lamp] = pixels
				RenderingServer.call_on_render_thread(_upload_mask_gpu.bind(_mask_job_lamp, pixels.duplicate()))
				return false
		_mask_pixels[_mask_job_lamp] = pixels
		RenderingServer.call_on_render_thread(_upload_mask_gpu.bind(_mask_job_lamp, pixels.duplicate()))
		_mask_job_lamp += 1
		_mask_job_row = 0
	return true

func rebuild_occlusion(solids: Array) -> void:
	begin_occlusion(solids)
	while not step_occlusion(1.0e9):
		pass

func _note_invalidation(reason: String) -> void:
	invalidation_counters[reason] = int(invalidation_counters.get(reason, 0)) + 1

func invalidate() -> void:
	_note_invalidation("explicit")
	_dirty = true

func render(time: float, changed: bool, active: bool) -> bool:
	if _disposed or not _initialized:
		return false
	step_occlusion(2.0)
	if not should_render(changed, active):
		return false
	var params := _params.duplicate()
	params["poolTime"] = time
	params["rtReady"] = 1.0 if tracing_ready else 0.0
	RenderingServer.call_on_render_thread(_render_gpu.bind(params, _lamps.duplicate(true), quality, Time.get_ticks_usec()))
	return true

func should_render(changed: bool, active: bool) -> bool:
	## Exact original render() cache and causticsRefresh cadence, isolated for fixtures.
	cadence_counters.calls += 1
	if float(_params.causticGain) <= 0.0 or quality == "Low":
		cadence_counters.disabled += 1
		return false
	var ready := 1 if tracing_ready else 0
	if not changed and not active and not _last_active and not _dirty and ready == _last_ready:
		cadence_counters.settled += 1
		return false
	var every := maxi(0, roundi(float(_params.causticsRefresh)))
	if every > 0 and not _dirty and ready == _last_ready and caustic_age < every:
		caustic_age += 1
		cadence_counters.refresh_skips += 1
		return false
	caustic_age = 0
	cadence_counters.scheduled += 1
	if _dirty: cadence_counters.dirty += 1
	if ready != _last_ready: cadence_counters.ready_changed += 1
	_last_active = active
	_last_ready = ready
	_dirty = false
	return true

func bind_receiver(material: ShaderMaterial) -> void:
	material.set_shader_parameter("poolCaustics", floor_texture)
	material.set_shader_parameter("poolCausticsWalls", wall_texture)
	material.set_shader_parameter("causticGain", 0.0 if quality == "Low" else float(_params.causticGain))
	material.set_shader_parameter("reflectedWallExtents", _params.reflectedWallExtents)
	material.set_shader_parameter("transmittedWallExtents", _params.transmittedWallExtents)

func diagnostics() -> Dictionary:
	return {"pc_nearfield_enabled": float(_params.pcNearfieldOn) > .5, "pc_nearfield_floor_emission_m": Vector2(16,12) if float(_params.pcNearfieldOn) > .5 else Vector2(32,32), "photon_grid": photon_grid(), "pc_photon_grid_requested": _pc_photon_grid_override, "pc_photon_grid_error": pc_photon_grid_error, "pc_photon_grid_active": quality == "High" and _pc_photon_grid_override != Vector2i.ZERO, "gpu_timing": _gpu_timestamps.diagnostics() if _gpu_timestamps != null else {"enabled": false}, "wave_sample_cache": reuse_wave_samples, "zero_power_bvh_skip": skip_zero_power_visibility, "caustics_refresh": _params.causticsRefresh, "cadence": cadence_counters.duplicate(), "invalidations": invalidation_counters.duplicate(), "last_queue_latency_ms": last_queue_latency_ms, "last_render_submit_ms": last_render_submit_ms, "readback_bytes": 0, "available": available, "error": last_error, "frames": caustic_frames, "quality": quality, "resolution": QUALITY[quality].caustics, "filter_resolution": maxi(256, int(QUALITY[quality].caustics) / 2), "incoming_mask_complete": _mask_job_lamp >= 2, "tracing_ready": tracing_ready, "geometry_revision": _geometry_revision, "geometry_buffer_allocations":geometry_buffer_allocations,"geometry_buffer_reuses":geometry_buffer_reuses,"geometry_buffer_bytes":_node_buffer_size+_triangle_buffer_size, "reflected_wall_extents": _params.reflectedWallExtents, "transmitted_wall_extents": _params.transmittedWallExtents, "global_rendering_device": true, "hdr_format": "RGBA16F", "photon_raster": "indexed triangles with fragment derivative Jacobian", "floor_result_cache": floor_result_diagnostics()}

static func ray_blocked(start: Vector3, end: Vector3, solids: Array[AABB]) -> bool:
	var delta := end - start
	for box in solids:
		var near_t := 0.0
		var far_t := 1.0
		var outside := false
		for axis in range(3):
			if delta[axis] > -1.0e-8 and delta[axis] < 1.0e-8:
				if start[axis] < box.position[axis] or start[axis] > box.end[axis]:
					outside = true
					break
			else:
				var a: float = (box.position[axis] - start[axis]) / delta[axis]
				var b: float = (box.end[axis] - start[axis]) / delta[axis]
				near_t = maxf(near_t, minf(a, b))
				far_t = minf(far_t, maxf(a, b))
		if not outside and near_t <= far_t and near_t < .995 and far_t > .005:
			return true
	return false

static func build_triangle_bvh(vertices: PackedVector3Array, prefer_indexed: bool = true) -> Dictionary:
	# Isolated immutable input, a fresh builder per job, identical packed output.
	# The old implementation stays available for diagnostics and exact fixtures.
	if prefer_indexed and not OS.get_cmdline_user_args().has("--no-indexed-water-bvh"):
		return TriangleBvh.new().build_triangle_bvh(vertices)
	return _build_triangle_bvh_dictionary(vertices)

static func _build_triangle_bvh_dictionary(vertices: PackedVector3Array) -> Dictionary:
	var items: Array[Dictionary] = []
	for i in range(0, vertices.size() - 2, 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		if not a.is_finite() or not b.is_finite() or not c.is_finite():
			continue
		if (b - a).cross(c - a).length_squared() < 1.0e-18:
			continue
		items.append({"a": a, "b": b, "c": c, "min": a.min(b).min(c), "max": a.max(b).max(c), "center": (a + b + c) / 3.0})
	var nodes: Array[Dictionary] = []
	var ordered: Array[Dictionary] = []
	_build_bvh_node(items, nodes, ordered)
	var node_data := PackedByteArray()
	node_data.resize(nodes.size() * 48)
	for i in range(nodes.size()):
		var n: Dictionary = nodes[i]
		for axis in range(3):
			node_data.encode_float(i * 48 + axis * 4, n.min[axis])
			node_data.encode_float(i * 48 + 16 + axis * 4, n.max[axis])
		node_data.encode_s32(i * 48 + 32, n.left)
		node_data.encode_s32(i * 48 + 36, n.right)
		node_data.encode_s32(i * 48 + 40, n.start)
		node_data.encode_s32(i * 48 + 44, n.count)
	var triangle_data := PackedByteArray()
	triangle_data.resize(maxi(1, ordered.size()) * 48)
	for i in range(ordered.size()):
		for v in range(3):
			var point: Vector3 = ordered[i][["a", "b", "c"][v]]
			for axis in range(3):
				triangle_data.encode_float(i * 48 + v * 16 + axis * 4, point[axis])
	return {"nodes": node_data, "triangles": triangle_data, "node_count": nodes.size(), "triangle_count": ordered.size()}

static func _build_bvh_node(items: Array[Dictionary], nodes: Array[Dictionary], ordered: Array[Dictionary]) -> int:
	var index := nodes.size()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for item in items:
		lo = lo.min(item.min)
		hi = hi.max(item.max)
	if items.is_empty():
		lo = Vector3.ZERO
		hi = Vector3.ZERO
	nodes.append({"min": lo, "max": hi, "left": -1, "right": -1, "start": ordered.size(), "count": items.size()})
	if items.size() <= 8:
		ordered.append_array(items)
		return index
	var span := hi - lo
	var axis := 0 if span.x >= span.y and span.x >= span.z else (1 if span.y >= span.z else 2)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.center[axis] < b.center[axis])
	var middle := items.size() / 2
	var left := _build_bvh_node(items.slice(0, middle), nodes, ordered)
	var right := _build_bvh_node(items.slice(middle), nodes, ordered)
	nodes[index].left = left
	nodes[index].right = right
	nodes[index].count = 0
	return index

func _own(rid: RID) -> RID:
	if rid.is_valid():
		_owned.append(rid)
	return rid

func _initialize_gpu() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		last_error = "Global RenderingDevice unavailable; Forward+/Mobile Vulkan is required. No CPU or fake caustic replacement is used."
		available = false
		return
	var sampler := RDSamplerState.new()
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.max_lod = 32.0
	_linear = _own(_rd.sampler_create(sampler))
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_nearest = _own(_rd.sampler_create(sampler))
	_ubo = _own(_rd.uniform_buffer_create(80, PackedFloat32Array([.125, .0625, 0, 1, 1, 1, .65, 1, 1, 1, 1, .6, 0, 0, 1024, 0, 0, 1, 0, 0]).to_byte_array()))
	_photon_shader = _compile_shader(_photon_vertex_source, _photon_fragment_source, "Source photon caustics")
	_blur_shader = _compile_shader(_fullscreen_source, _blur_fragment_source, "Source strip-safe caustic filter")
	var compute_source := RDShaderSource.new()
	compute_source.source_compute = _wave_compute_source
	var compute_spirv := _rd.shader_compile_spirv_from_source(compute_source)
	var compute_error := compute_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compute_error.is_empty():
		last_error = "Source caustic wave cache: " + compute_error
		push_error(last_error)
		return
	_wave_shader = _own(_rd.shader_create_from_spirv(compute_spirv, "Source caustic FP32 wave cache"))
	_wave_pipeline = _own(_rd.compute_pipeline_create(_wave_shader))
	if not _photon_shader.is_valid() or not _blur_shader.is_valid():
		return
	for pixels in _mask_pixels:
		var format := RDTextureFormat.new()
		format.width = MASK_SIZE
		format.height = MASK_SIZE
		format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		_masks.append(_own(_rd.texture_create(format, RDTextureView.new(), [pixels])))
	var empty := build_triangle_bvh(PackedVector3Array())
	_upload_geometry_gpu(_node_bytes if not _node_bytes.is_empty() else empty.nodes, _triangle_bytes if not _triangle_bytes.is_empty() else empty.triangles, _geometry_revision)
	_create_targets_gpu()
	available = _photon_pipeline.is_valid() and _blur_pipeline.is_valid() and _wave_pipeline.is_valid()

func _compile_shader(vertex: String, fragment: String, label: String) -> RID:
	var source := RDShaderSource.new()
	source.source_vertex = vertex
	source.source_fragment = fragment
	var spirv := _rd.shader_compile_spirv_from_source(source)
	for stage in [RenderingDevice.SHADER_STAGE_VERTEX, RenderingDevice.SHADER_STAGE_FRAGMENT]:
		var error := spirv.get_stage_compile_error(stage)
		if not error.is_empty():
			last_error = label + ": " + error
			push_error(last_error)
			return RID()
	return _own(_rd.shader_create_from_spirv(spirv, label))

func _create_target(size: int, with_mips: bool) -> Dictionary:
	var format := RDTextureFormat.new()
	format.width = size
	format.height = size
	format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.mipmaps = int(floor(log(float(size)) / log(2.0))) + 1 if with_mips else 1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var texture := _own(_rd.texture_create(format, RDTextureView.new()))
	var views: Array[RID] = []
	var framebuffers: Array[RID] = []
	for level in range(format.mipmaps):
		var view := _own(_rd.texture_create_shared_from_slice(RDTextureView.new(), texture, 0, level))
		views.append(view)
		framebuffers.append(_own(_rd.framebuffer_create([view])))
	return {"texture": texture, "views": views, "framebuffers": framebuffers, "size": size}

func _create_targets_gpu() -> void:
	var q: Dictionary = _sampling_quality()
	_wall_wave_offset = (int(q.photons) + 1) * (int(q.photons) + 1)
	var sample_count := _wall_wave_offset + (int(q.wallPhotons) + 1) * (int(q.wallPhotons) + 1)
	_wave_buffer = _own(_rd.storage_buffer_create(sample_count * 32))
	_floor = _create_target(int(q.caustics), true)
	_wall = _create_target(int(q.caustics), true)
	_filter = _create_target(maxi(256, int(q.caustics) / 2), false)
	_floor_indices = _make_grid(int(q.photons))
	_wall_indices = _make_grid(int(q.wallPhotons))
	var raster := RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
	var depth_state := RDPipelineDepthStencilState.new()
	depth_state.enable_depth_test = false
	depth_state.enable_depth_write = false
	var blend := RDPipelineColorBlendState.new()
	var attachment := RDPipelineColorBlendStateAttachment.new()
	attachment.enable_blend = true
	attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	blend.attachments = [attachment]
	var framebuffer_format := _rd.framebuffer_get_format(_floor.framebuffers[0])
	_photon_pipeline = _own(_rd.render_pipeline_create(_photon_shader, framebuffer_format, RenderingDevice.INVALID_ID, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), depth_state, blend))
	var copy_blend := RDPipelineColorBlendState.new()
	copy_blend.attachments = [RDPipelineColorBlendStateAttachment.new()]
	_blur_pipeline = _own(_rd.render_pipeline_create(_blur_shader, framebuffer_format, RenderingDevice.INVALID_ID, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), depth_state, copy_blend))
	_initialize_floor_result_gpu(framebuffer_format, raster, depth_state, blend)
	floor_texture.texture_rd_rid = _floor.texture
	wall_texture.texture_rd_rid = _wall.texture

func _make_grid(segments: int) -> RID:
	var indices := PackedInt32Array()
	indices.resize(segments * segments * 6)
	var cursor := 0
	for y in range(segments):
		for x in range(segments):
			var a := x + (segments + 1) * y
			var b := x + (segments + 1) * (y + 1)
			indices[cursor] = a
			indices[cursor + 1] = b
			indices[cursor + 2] = a + 1
			indices[cursor + 3] = b
			indices[cursor + 4] = b + 1
			indices[cursor + 5] = a + 1
			cursor += 6
	var buffer := _own(_rd.index_buffer_create(indices.size(), RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, indices.to_byte_array()))
	return _own(_rd.index_array_create(buffer, 0, indices.size()))

func _upload_geometry_gpu(nodes: PackedByteArray, triangles: PackedByteArray, revision: int) -> void:
	if _rd == null or _disposed:
		return
	if _node_buffer.is_valid() and _triangle_buffer.is_valid() and _node_buffer_size==nodes.size() and _triangle_buffer_size==triangles.size():
		# Same resident architecture, different origin: retain immutable bindings
		# and update bytes in place. RD orders these writes before subsequent draws.
		_rd.buffer_update(_node_buffer,0,nodes.size(),nodes)
		_rd.buffer_update(_triangle_buffer,0,triangles.size(),triangles)
		geometry_buffer_reuses+=1
	else:
		_clear_uniform_sets(_photon_sets)
		_clear_uniform_sets(_floor_result_sets)
		_clear_uniform_sets(_floor_result_compute_sets)
		for rid in [_node_buffer, _triangle_buffer]:
			if rid.is_valid():
				_owned.erase(rid)
				_rd.free_rid(rid)
		_node_buffer = _own(_rd.storage_buffer_create(nodes.size(), nodes))
		_triangle_buffer = _own(_rd.storage_buffer_create(triangles.size(), triangles))
		_node_buffer_size=nodes.size();_triangle_buffer_size=triangles.size()
		geometry_buffer_allocations+=2
	_gpu_geometry_revision = revision

func _upload_mask_gpu(index: int, pixels: PackedByteArray) -> void:
	if _rd != null and index < _masks.size() and not _disposed:
		_rd.texture_update(_masks[index], 0, pixels)

func _upload_prepared_geometry_gpu(nodes: PackedByteArray, triangles: PackedByteArray, masks: Array[PackedByteArray], revision: int) -> void:
	if _rd == null or _disposed or revision < _gpu_geometry_revision:
		return
	_upload_geometry_gpu(nodes, triangles, revision)
	_upload_masks_gpu(masks, revision)

func _upload_masks_gpu(masks: Array[PackedByteArray], revision: int) -> void:
	if _rd == null or _disposed or revision != _gpu_geometry_revision or _masks.size() != 2:
		return
	for index in range(2):
		_rd.texture_update(_masks[index], 0, masks[index])

func _uniform(type: int, binding: int, ids: Array[RID]) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for rid in ids:
		uniform.add_id(rid)
	return uniform

func _photon_uniform_set() -> RID:
	if _surface == null or _depth == null or _detail == null:
		return RID()
	# Resolve inside the render-thread callback, AFTER the solver's queued step.
	var surface_rid := _surface.texture_rd_rid
	var depth_rid := _depth.texture_rd_rid
	var detail_rid := _detail.texture_rd_rid
	if not surface_rid.is_valid() or not depth_rid.is_valid() or not detail_rid.is_valid():
		return RID()
	var key := "%s/%s/%s/%s/%s" % [surface_rid.get_id(), depth_rid.get_id(), detail_rid.get_id(), _node_buffer.get_id(), _triangle_buffer.get_id()]
	if _photon_sets.has(key) and _rd.uniform_set_is_valid(_photon_sets[key]):
		return _photon_sets[key]
	if _photon_sets.size() > 16:
		_clear_uniform_sets(_photon_sets)
		_clear_uniform_sets(_floor_result_sets)
		_clear_uniform_sets(_floor_result_compute_sets)
	var uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_ubo]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_linear, surface_rid]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest, depth_rid]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_linear, detail_rid]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_linear, _masks[0]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_linear, _masks[1]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 6, [_node_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 7, [_triangle_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 8, [_wave_buffer]),
	]
	var set := _rd.uniform_set_create(uniforms, _photon_shader, 0)
	_photon_sets[key] = set
	return set

func _render_gpu(params: Dictionary, lamps: Array[Dictionary], render_quality: String, queued_at_usec: int = 0) -> void:
	if not available or _disposed or render_quality != quality:
		return
	var uniform_set := _photon_uniform_set()
	if not uniform_set.is_valid():
		# A first frame may race a solver's deferred allocation. Do not cache an
		# unrendered static pool forever; retry once its public RIDs are valid.
		_dirty = true
		return
	var submit_started := Time.get_ticks_usec()
	last_queue_latency_ms = float(submit_started - queued_at_usec) / 1000.0 if queued_at_usec > 0 else 0.0
	if profile_enabled:
		collect_profile_gpu()
		_render_sequence += 1
	_profile_mark("begin")
	var origin: Vector2 = params.microOrigin
	var values := PackedFloat32Array([params.poolCell, params.detailCell, params.poolTime, params.waveHeight, params.rippleGain, params.normalBoost, params.microStrength, params.simulationOn, params.ripplesOn, params.microOn, params.causticsScale, params.causticsSpeed, origin.x, origin.y, float(_floor.size), params.rtReady, float(params.get("pcNearfieldOn", 0.0)), float(params.get("pcNearfieldStrength", 1.0)), 0, 0])
	_rd.buffer_update(_ubo, 0, 80, values.to_byte_array())
	if reuse_wave_samples and not _cache_wave_samples_gpu():
		_dirty = true
		return
	_profile_mark("wave_cache")
	_draw_photons(_floor.framebuffers[0], uniform_set, lamps, false)
	_profile_mark("floor_photons")
	var f := float(_filter.size)
	# PC_NEARFIELD_BEGIN
	var floor_radius := .6 if float(params.get("pcNearfieldOn", 0.0)) > .5 else 1.4
	# PC_NEARFIELD_END
	_blur(_floor.views[0], _filter.framebuffers[0], Vector2(floor_radius / f, 0), 1.0)
	# Source code (not its stale comment) uses filter-height in this V pass.
	_blur(_filter.views[0], _floor.framebuffers[0], Vector2(0, floor_radius / f), 1.0)
	_profile_mark("floor_blur")
	_draw_photons(_wall.framebuffers[0], uniform_set, lamps, true, params.reflectedWallExtents, params.transmittedWallExtents)
	_profile_mark("wall_photons")
	_blur(_wall.views[0], _filter.framebuffers[0], Vector2(1.6 / f, 0), 4.0)
	_blur(_filter.views[0], _wall.framebuffers[0], Vector2(0, 1.2 / f), 4.0)
	_profile_mark("wall_blur")
	_generate_mips(_floor)
	_generate_mips(_wall)
	_profile_mark("end")
	last_render_submit_ms = float(Time.get_ticks_usec() - submit_started) / 1000.0
	caustic_frames += 1

func _cache_wave_samples_gpu() -> bool:
	var surface_rid := _surface.texture_rd_rid
	var depth_rid := _depth.texture_rd_rid
	var detail_rid := _detail.texture_rd_rid
	var key := "%s/%s/%s" % [surface_rid.get_id(), depth_rid.get_id(), detail_rid.get_id()]
	if not _wave_sets.has(key) or not _rd.uniform_set_is_valid(_wave_sets[key]):
		if _wave_sets.size() > 16: _clear_uniform_sets(_wave_sets)
		var uniforms: Array[RDUniform] = [
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_ubo]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_linear, surface_rid]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest, depth_rid]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_linear, detail_rid]),
			# Shared source declarations remain in Godot's SPIR-V descriptor layout.
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_linear, _masks[0]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_linear, _masks[1]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 8, [_wave_buffer]),
		]
		_wave_sets[key] = _rd.uniform_set_create(uniforms, _wave_shader, 0)
	if not _rd.uniform_set_is_valid(_wave_sets[key]):
		last_error = "Source caustic wave-cache descriptor creation failed; no stale cache was drawn."
		return false
	var compute := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute, _wave_pipeline)
	_rd.compute_list_bind_uniform_set(compute, _wave_sets[key], 0)
	for wall in range(2):
		if wall == 1 and quality == "Medium": continue
		var segments: int = photon_grid().y if wall else photon_grid().x
		var offset := _wall_wave_offset if wall else 0
		var push := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, segments, wall, 0, 0, 0, offset, 0]).to_byte_array()
		_rd.compute_list_set_push_constant(compute, push, push.size())
		_rd.compute_list_dispatch(compute, ceili(float((segments + 1) * (segments + 1)) / 64.0), 1, 1)
	_rd.compute_list_end()
	# Global RD inserts the storage-write -> vertex-read dependency from bindings.
	return true

func _profile_mark(stage: String) -> void:
	if _gpu_timestamps != null:
		var metadata := {"quality": quality, "wave_sample_cache": reuse_wave_samples, "zero_power_bvh_skip": skip_zero_power_visibility, "floor_result_cache_requested": reuse_floor_photon_results} if stage == "begin" else {}
		_gpu_timestamps.mark(_rd, stage, metadata)
	if profile_enabled: _rd.capture_timestamp("source_caustic/%d/%s" % [_render_sequence, stage])

func collect_profile_gpu() -> void:
	## Render-thread only. Reads completed timestamp queries, never texture data
	## and never waits on current GPU work. Optional diagnostics, disabled normally.
	if _rd == null: return
	var frame := _rd.get_captured_timestamps_frame()
	if frame == _profile_timestamp_frame: return
	_profile_timestamp_frame = frame
	var groups: Dictionary = {}
	for i in _rd.get_captured_timestamps_count():
		var marker := _rd.get_captured_timestamp_name(i)
		if not marker.begins_with("source_caustic/"): continue
		var parts := marker.split("/")
		if parts.size() != 3: continue
		var sequence := int(parts[1])
		if not groups.has(sequence): groups[sequence] = {"sequence": sequence, "rd_frame": frame, "gpu_ns": {}, "cpu_usec": {}}
		groups[sequence].gpu_ns[parts[2]] = _rd.get_captured_timestamp_gpu_time(i)
		groups[sequence].cpu_usec[parts[2]] = _rd.get_captured_timestamp_cpu_time(i)
	for sample in groups.values():
		if sample.gpu_ns.has("begin") and sample.gpu_ns.has("end"):
			profile_samples.append(sample)
			if profile_samples.size() > 512: profile_samples.pop_front()

func _draw_photons(framebuffer: RID, uniform_set: RID, lamps: Array[Dictionary], wall_pass: bool, reflected_extents: Vector2 = Vector2(15.7, 15.7), transmitted_extents: Vector2 = Vector2(15.7, 15.7)) -> void:
	var cached_set := RID()
	if not wall_pass:
		_floor_result_last_used = false
		if reuse_floor_photon_results:
			cached_set = _cache_floor_results_gpu(lamps)
			_floor_result_last_used = cached_set.is_valid()
			if not _floor_result_last_used: _floor_result_fallbacks += 1
		_profile_mark("floor_result_cache")
	var draw := _rd.draw_list_begin(framebuffer, RenderingDevice.DRAW_CLEAR_COLOR_0, PackedColorArray([Color(0, 0, 0, 0)]))
	if not wall_pass or quality != "Medium":
		_rd.draw_list_bind_render_pipeline(draw, _floor_result_pipeline if cached_set.is_valid() else _photon_pipeline)
		_rd.draw_list_bind_uniform_set(draw, cached_set if cached_set.is_valid() else uniform_set, 0)
		_rd.draw_list_bind_index_array(draw, _wall_indices if wall_pass else _floor_indices)
		for lamp_id in range(2):
			var lamp: Dictionary = lamps[lamp_id]
			var position: Vector3 = lamp.position
			if wall_pass:
				for strip in range(4):
					var normal: Vector3 = WALL_NORMALS[strip]
					for reflected in range(2):
						var extents := reflected_extents if reflected == 1 else transmitted_extents
						var wall_offset := -extents.x if strip < 2 else -extents.y
						var push := PackedFloat32Array([position.x, position.y, position.z, lamp.power, normal.x, normal.y, normal.z, float(strip), float(reflected), float(photon_grid().y), 1.0, float(lamp_id), wall_offset, 1.0 if reuse_wave_samples else 0.0, float(_wall_wave_offset), 1.0 if skip_zero_power_visibility else 0.0]).to_byte_array()
						_rd.draw_list_set_push_constant(draw, push, push.size())
						_rd.draw_list_draw(draw, true, 1)
			else:
				var push := PackedFloat32Array([position.x, position.y, position.z, lamp.power, 0, 0, 0, 0, 0, float(photon_grid().x), 0, float(lamp_id), -15.7, 2.0 if cached_set.is_valid() else (1.0 if reuse_wave_samples else 0.0), 0, 1.0 if skip_zero_power_visibility else 0.0]).to_byte_array()
				_rd.draw_list_set_push_constant(draw, push, push.size())
				_rd.draw_list_draw(draw, true, 1)
	_rd.draw_list_end()

func _blur(source: RID, framebuffer: RID, step: Vector2, strips: float, mip_copy: bool = false) -> void:
	var key := source.get_id()
	if not _blur_sets.has(key):
		_blur_sets[key] = _rd.uniform_set_create([_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_linear, source])], _blur_shader, 0)
	var draw := _rd.draw_list_begin(framebuffer, RenderingDevice.DRAW_IGNORE_COLOR_0)
	_rd.draw_list_bind_render_pipeline(draw, _blur_pipeline)
	_rd.draw_list_bind_uniform_set(draw, _blur_sets[key], 0)
	var push := PackedFloat32Array([step.x, step.y, strips, 1.0 if mip_copy else 0.0]).to_byte_array()
	_rd.draw_list_set_push_constant(draw, push, push.size())
	_rd.draw_list_draw(draw, false, 1, 3)
	_rd.draw_list_end()

func _generate_mips(target: Dictionary) -> void:
	for level in range(1, target.views.size()):
		_blur(target.views[level - 1], target.framebuffers[level], Vector2.ZERO, 1.0, true)

func _clear_uniform_sets(sets: Dictionary) -> void:
	for rid in sets.values():
		if _rd.uniform_set_is_valid(rid):
			_rd.free_rid(rid)
	sets.clear()

func _resize_gpu() -> void:
	if _rd == null or _disposed:
		return
	_free_gpu()
	_initialize_gpu()

func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if _gpu_timestamps != null: _gpu_timestamps.dispose()
	RenderingServer.call_on_render_thread(_free_gpu)

func _free_gpu() -> void:
	available = false
	_floor_result_ready = false
	_floor_result_last_used = false
	_floor_result_bytes = 0
	floor_texture.texture_rd_rid = RID()
	wall_texture.texture_rd_rid = RID()
	if _rd == null:
		return
	_clear_uniform_sets(_photon_sets)
	_clear_uniform_sets(_floor_result_sets)
	_clear_uniform_sets(_floor_result_compute_sets)
	_clear_uniform_sets(_blur_sets)
	_clear_uniform_sets(_wave_sets)
	for i in range(_owned.size() - 1, -1, -1):
		_rd.free_rid(_owned[i])
	_owned.clear()
	_floor_result_shader = RID()
	_floor_result_pipeline = RID()
	_floor_result_compute_shader = RID()
	_floor_result_compute_pipeline = RID()
	_floor_result_buffer = RID()
	_masks.clear()
	_node_buffer = RID()
	_triangle_buffer = RID()
	_floor.clear()
	_wall.clear()
	_filter.clear()

func floor_result_diagnostics() -> Dictionary:
	return {"requested": reuse_floor_photon_results, "available": _floor_result_ready,
		"used_last_refresh": _floor_result_last_used, "bytes": _floor_result_bytes,
		"dispatches": _floor_result_dispatches, "fallbacks": _floor_result_fallbacks,
		"error": _floor_result_error, "wave_cache_enabled": reuse_wave_samples}

func _initialize_floor_result_gpu(framebuffer_format: int, raster: RDPipelineRasterizationState, depth_state: RDPipelineDepthStencilState, blend: RDPipelineColorBlendState) -> void:
	_floor_result_ready = false
	_floor_result_error = ""
	_floor_result_bytes = 0
	if not reuse_floor_photon_results: return
	# Optional compilation never changes availability of the original shaders.
	var draw_source := RDShaderSource.new()
	draw_source.source_vertex = _floor_result_vertex_source
	draw_source.source_fragment = _photon_fragment_source
	var draw_spirv := _rd.shader_compile_spirv_from_source(draw_source)
	for stage in [RenderingDevice.SHADER_STAGE_VERTEX, RenderingDevice.SHADER_STAGE_FRAGMENT]:
		var message := draw_spirv.get_stage_compile_error(stage)
		if not message.is_empty():
			_floor_result_error = "Floor result draw shader: " + message
			return
	var compute_source := RDShaderSource.new()
	compute_source.source_compute = _floor_result_compute_source
	var compute_spirv := _rd.shader_compile_spirv_from_source(compute_source)
	var message := compute_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not message.is_empty():
		_floor_result_error = "Floor result compute shader: " + message
		return
	_floor_result_shader = _own(_rd.shader_create_from_spirv(draw_spirv, "Source exact floor result draw"))
	_floor_result_compute_shader = _own(_rd.shader_create_from_spirv(compute_spirv, "Source exact floor results"))
	if not _floor_result_shader.is_valid() or not _floor_result_compute_shader.is_valid():
		_floor_result_error = "Floor result shader allocation failed; original photons retained."
		_discard_floor_result_resources()
		return
	_floor_result_pipeline = _own(_rd.render_pipeline_create(_floor_result_shader, framebuffer_format, RenderingDevice.INVALID_ID, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), depth_state, blend))
	_floor_result_compute_pipeline = _own(_rd.compute_pipeline_create(_floor_result_compute_shader))
	if not _floor_result_pipeline.is_valid() or not _floor_result_compute_pipeline.is_valid():
		_floor_result_error = "Floor result pipeline allocation failed; original photons retained."
		_discard_floor_result_resources()
		return
	var floor_count := _wall_wave_offset
	var wall_count := (photon_grid().y + 1) * (photon_grid().y + 1)
	var bytes := 16 + 2 * floor_count * 32
	_floor_result_buffer = _own(_rd.storage_buffer_create(bytes))
	if not _floor_result_buffer.is_valid():
		_floor_result_error = "Floor result buffer allocation failed; original photons retained."
		_discard_floor_result_resources()
		return
	if _rd.buffer_update(_floor_result_buffer, 0, 16, PackedInt32Array([floor_count, wall_count, 0, 0]).to_byte_array()) != OK:
		_floor_result_error = "Floor result shape upload failed; original photons retained."
		_discard_floor_result_resources()
		return
	_floor_result_bytes = bytes
	_floor_result_ready = true

func _floor_result_uniform_set(shader: RID, sets: Dictionary) -> RID:
	if not _floor_result_ready or _surface == null or _depth == null or _detail == null: return RID()
	var surface_rid := _surface.texture_rd_rid
	var depth_rid := _depth.texture_rd_rid
	var detail_rid := _detail.texture_rd_rid
	if not surface_rid.is_valid() or not depth_rid.is_valid() or not detail_rid.is_valid(): return RID()
	var key := "%s/%s/%s/%s/%s" % [surface_rid.get_id(), depth_rid.get_id(), detail_rid.get_id(), _node_buffer.get_id(), _triangle_buffer.get_id()]
	if sets.has(key) and _rd.uniform_set_is_valid(sets[key]): return sets[key]
	if sets.size() > 16: _clear_uniform_sets(sets)
	var uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_ubo]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_linear, surface_rid]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest, depth_rid]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_linear, detail_rid]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_linear, _masks[0]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_linear, _masks[1]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 6, [_node_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 7, [_triangle_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 8, [_wave_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 9, [_floor_result_buffer]),
	]
	var group := _rd.uniform_set_create(uniforms, shader, 0)
	if group.is_valid(): sets[key] = group
	return group

func _cache_floor_results_gpu(lamps: Array[Dictionary]) -> RID:
	# A fresh cache is produced for this exact uniform/geometry/input epoch.
	# Returning an invalid RID selects the independently compiled original draw,
	# never an old cache or a missing photon pass.
	if not reuse_wave_samples or not _floor_result_ready: return RID()
	var draw_set := _floor_result_uniform_set(_floor_result_shader, _floor_result_sets)
	var compute_set := _floor_result_uniform_set(_floor_result_compute_shader, _floor_result_compute_sets)
	if not draw_set.is_valid() or not compute_set.is_valid():
		_floor_result_error = "Floor result descriptors unavailable; original photons retained."
		return RID()
	var segments: int = photon_grid().x
	var compute := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute, _floor_result_compute_pipeline)
	_rd.compute_list_bind_uniform_set(compute, compute_set, 0)
	for lamp_id in range(2):
		var lamp: Dictionary = lamps[lamp_id]
		var position: Vector3 = lamp.position
		var push := PackedFloat32Array([position.x, position.y, position.z, lamp.power, 0, 0, 0, 0, 0, float(segments), 0, float(lamp_id), -15.7, 1.0, 0, 1.0 if skip_zero_power_visibility else 0.0]).to_byte_array()
		_rd.compute_list_set_push_constant(compute, push, push.size())
		_rd.compute_list_dispatch(compute, ceili(float((segments + 1) * (segments + 1)) / 64.0), 1, 1)
	_rd.compute_list_end()
	_floor_result_dispatches += 1
	_floor_result_error = ""
	return draw_set

func _discard_floor_result_resources() -> void:
	# Roll back only the optional allocation group. The independently created
	# original photon pipeline and its availability are deliberately untouched.
	_floor_result_ready = false
	_floor_result_last_used = false
	_floor_result_bytes = 0
	_clear_uniform_sets(_floor_result_sets)
	_clear_uniform_sets(_floor_result_compute_sets)
	for rid in [_floor_result_buffer, _floor_result_compute_pipeline, _floor_result_pipeline, _floor_result_compute_shader, _floor_result_shader]:
		if rid.is_valid() and _owned.has(rid):
			_owned.erase(rid)
			_rd.free_rid(rid)
	_floor_result_buffer = RID()
	_floor_result_compute_pipeline = RID()
	_floor_result_pipeline = RID()
	_floor_result_compute_shader = RID()
	_floor_result_shader = RID()
