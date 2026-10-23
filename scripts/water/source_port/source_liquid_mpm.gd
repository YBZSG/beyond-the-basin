class_name SourceLiquidMPM
extends RefCounted
## Source equation port of liquid-mpm.ts + liquid-mpm-shader.ts at 66a4543.
## PC scheduling is bounded and asynchronous; original host mode remains for A/B.
## No CPU MPM substitute. Global RD work is queued to the render thread.
## CPU callbacks are sampled in solver-local XZ metres, matching source.
signal ready
signal failed(reason: String)
signal droplet_released(position: Vector3, velocity: Vector3, size: float)
signal return_ripple(position: Vector2, strength: float)
signal snapshot_updated

const SOURCE_COMMIT := "66a4543602d9e774db07c2da12ce1d40d522532c"
const LIMIT := 18000
const MAX_PATCHES := 3
const GRID := 80 * 80 * 80
const STEP := 1.0 / 720.0
# These are host scheduling bounds, NOT solver resolution/quality controls.
const SNAPSHOT_SLOTS := 3
const MAX_PRESENTATION_SAMPLES := 4
const MAX_QUEUED_BATCHES := 2
const MAX_BATCHES_PER_FRAME := 2
const MAX_BACKLOG_SECONDS := 0.25
const MAX_FEEDBACK_LEAD_STEPS := 108 # 150 ms; stop rather than diverge indefinitely.
const MAX_PIPELINE_FEEDBACK_STEPS := 216 # PC only: at most300ms of timestamped CPU coupling delay.
const IDLE_CADENCE_SAMPLES := 32
const IDLE_CADENCE_MIN_SAMPLES := 8
const IDLE_CADENCE_MIN_SPAN_USEC := 250000
const IDLE_CADENCE_MAX_PERIOD_USEC := 100000 # At most a known10FPS pre-impact baseline.
const IDLE_CADENCE_MAX_DEADLINE_USEC := 400000
const IDLE_CADENCE_FRESH_USEC := 1000000
const MAX_LIFETIME_STEPS := 1080 # The source's same 1.5 s domain lifetime.
const MAX_UNCOPIED_SNAPSHOT_USEC := 100000 # Let Godot progress frame-delayed copies under overload.
const RECOVERY_STEPS_PER_FRAME := 12 # Smaller admissions, never altered STEP/equations.
const RECOVERY_TIMELY_FRAMES := 3 # Distinct frames proving the current work tier, not domain count.
const PREWARM_TIMEOUT_SECONDS := 15.0 # Startup only; fail open after owned-resource retirement.
const FINISH_TIMEOUT_USEC := 3000000 # Fail-safe cleanup if final callbacks never arrive.
# Selected when a patch is created. Never switch an active patch between modes.
var independent_scheduling := (OS.has_feature("windows") or OS.has_feature("linuxbsd") or OS.has_feature("macos")) and not OS.has_feature("android") and not OS.has_feature("ios") and not OS.get_cmdline_user_args().has("--source-mpm-original-scheduling")
var prewarm_enabled := independent_scheduling and not OS.get_cmdline_user_args().has("--source-mpm-no-prewarm")
var _prewarm_requested := false
var _prewarm_pending := false
var _prewarm_timeout_queued := false
var _prewarm_report: Dictionary = {"state": "not_started", "pass": false}
var copy_backpressure_enabled := not OS.get_cmdline_user_args().has("--source-mpm-no-copy-backpressure")
var copy_recovery_enabled := not OS.get_cmdline_user_args().has("--source-mpm-no-copy-recovery")
var idle_cadence_enabled := independent_scheduling and not OS.get_cmdline_user_args().has("--source-mpm-no-idle-cadence")
var pipeline_feedback_enabled := independent_scheduling and not OS.get_cmdline_user_args().has("--source-mpm-fixed-feedback-lead")
var _idle_samples: Array[int] = []
var _idle_previous_usec := 0
var _idle_previous_frame := -1
var _idle_qualified_usec := -1
var _idle_raw_period_usec := 0
var _idle_cadence_rejections := 0
var _idle_retirement_frame := -1
var _pacing_active := false
var _pacing_calibrated := false
var _pacing_idle_period_usec := 0
var _pacing_raw_period_usec := 0
var _pacing_sample_count := 0
var _pacing_generation := 0
var _pacing_configuration := ""
var _configured_period_usec := 0
var _configured_copy_deadline := MAX_UNCOPIED_SNAPSHOT_USEC
var _feedback_lead_steps := MAX_FEEDBACK_LEAD_STEPS
var _feedback_limited_domain_frames := 0
var _recovery_admission_steps := RECOVERY_STEPS_PER_FRAME
var _recovery_generation := 0
var _recovery_latest_copy_usec := 0
var _recovery_probe_transitions := 0
var _recovery_backoffs := 0
var _copy_recovery_active := false
var _copy_recovery_entries := 0
var _copy_recovery_exits := 0
var _copy_recovery_frames := 0
var _recovery_limited_domain_frames := 0
var _recovery_timely_frames := 0
var _recovery_started_frame := -1
var _recovery_observed_frame := -1
var _copy_backpressure_active := false
var _copy_backpressure_frames := 0
var _uncopied_snapshot_age_ms := 0.0
var _copy_latency_ms := 0.0
var _copy_latency_max_ms := 0.0
var _stale_copy_notifications := 0
var _async_frame_delay := clampi(int(ProjectSettings.get_setting("rendering/rendering_device/vsync/frame_queue_size", 3)), 1, 16)
var _async_frame_delay_actual := false
var _copy_deadline_usec := MAX_UNCOPIED_SNAPSHOT_USEC
var _display_refresh_hz := 0.0
var _refresh_probe_after_usec := 0
var _configured_vsync := false
var _snapshots_stale := 0
var _simulation_only_batches := 0
var _queue_backpressure_frames := 0
var _feedback_backpressure_frames := 0
var _presentation_samples_pruned := 0
var _finish_timeouts := 0
const ENTRIES := ["clear", "mass", "pressure", "velocity", "gather", "resetHeads", "link", "exportState", "deleteParticles"]
const BINDINGS := [[1], [0, 1, 2], [0, 1, 2], [1, 2, 4], [0, 1, 2, 4], [1], [0, 1, 2, 4], [0, 1, 2, 3, 4], [0, 5]]

var status := "initializing"
var last_error := ""
var released := 0
var returns := 0
var ripples := 0
var readback_bytes := 0
var upload_bytes := 0
var visible_count := 0
# Exact complete-grid zero initialization; original compute clear remains a
# diagnostic/unsupported-driver fallback. This never changes MPM substeps.
var transfer_grid_clear := not OS.get_cmdline_user_args().has("--no-transfer-mpm-clear")
var _grid_clear_fallbacks := 0
# Optional exact CPU prefix test. Only wholly inert domains bypass the host
# loop; every domain with a candidate executes the unchanged loop from zero.
var native_particle_gate := not OS.get_cmdline_user_args().has("--no-native-water-particle-gate")
var _native_particle_gate: RefCounted
var _native_particle_gate_checked := false
var _native_particle_gate_available := false
var _native_gate_calls := 0
var _native_gate_skipped_domains := 0
var _native_gate_skipped_particles := 0
var _native_gate_fallbacks := 0
var _native_gate_ms := 0.0
var _gpu_timestamps: RefCounted
# Bounded diagnostics only, never a timing input or a quality control.
var _frame_serial := 0
var _steps_dispatched := 0
var _batches_dispatched := 0
var _snapshots_received := 0
var _host_frame_ms := 0.0
var _host_frame_max_ms := 0.0
var _host_pack_ms := 0.0
var _source_build_ms := 0.0
var _readback_latency_ms := 0.0
var _readback_latency_max_ms := 0.0
var _readback_pending_max_frames := 0
var _render_encode_ms := 0.0
var _render_encode_max_ms := 0.0
var _render_queue_ms := 0.0
var _supplied_delta := 0.0
var _accepted_delta := 0.0
var _last_frame_steps := 0
## Each kernel: row0=(basis.x.x,basis.y.x,basis.z.x,origin.x), row1, row2.
var instance_rows := PackedFloat32Array()
var bounds := AABB()
var depth_mesh: ArrayMesh
var _patches: Array[Dictionary] = []
var _sources: Array[Dictionary] = []
var _surface: Callable
var _depth: Callable
var _serial := 0
var _rng := 0
var _initialized := false
var _disposed := false
var _epoch := 0
# Render-thread only.
var _prewarm: RefCounted
var _rd: RenderingDevice
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []
var _gpu_patches: Dictionary = {}

func initialize() -> void:
	if _initialized or _disposed:
		return
	_initialized = true
	if OS.get_cmdline_user_args().has("--source-gpu-timings"):
		_gpu_timestamps = preload("res://scripts/water/source_port/source_gpu_timestamps.gd").new("mpm", PackedStringArray(["begin", "end"]))
		_gpu_timestamps.start()
	depth_mesh = sphere_geometry(10, 8)
	var code := FileAccess.get_file_as_string("res://shaders/source_water/liquid_mpm.glslinc")
	_prewarm_requested = should_prewarm(independent_scheduling, prewarm_enabled,
		OS.has_feature("windows") or OS.has_feature("linuxbsd") or OS.has_feature("macos"),
		OS.has_feature("android") or OS.has_feature("ios"))
	_prewarm_pending = _prewarm_requested
	_prewarm_report = {"state": "pending" if _prewarm_requested else "disabled", "pass": false}
	# Capture selection before crossing threads. Pending impacts remain bounded
	# by MAX_PATCHES and cannot consume solver time while status is initializing.
	RenderingServer.call_on_render_thread(_rd_initialize.bind(code, _epoch, _prewarm_requested))
	if _prewarm_requested:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.create_timer(PREWARM_TIMEOUT_SECONDS, true, false, true).timeout.connect(_prewarm_timeout.bind(_epoch), CONNECT_ONE_SHOT)

static func should_prewarm(independent: bool, enabled: bool, desktop: bool, mobile: bool) -> bool:
	return independent and enabled and desktop and not mobile

func _prewarm_finished(report: Dictionary, epoch: int, frame_delay: int) -> void:
	if _disposed or epoch != _epoch or not _prewarm_pending or status != "initializing":
		return
	_prewarm_pending = false
	_prewarm_report = report.duplicate(true)
	# Performance preparation failure is not solver failure. The helper has
	# already retired its isolated resources before this main-thread callback.
	_finish_initialize(epoch, frame_delay)

func _prewarm_timeout(epoch: int) -> void:
	if _disposed or epoch != _epoch or not _prewarm_pending or _prewarm_timeout_queued:
		return
	_prewarm_timeout_queued = true
	_prewarm_report = {"state": "cancelling_timeout", "pass": false}
	RenderingServer.call_on_render_thread(_rd_timeout_prewarm.bind(epoch))

func _rd_timeout_prewarm(epoch: int) -> void:
	var report := {"state": "timeout", "pass": false, "resources_released": true,
		"error": "Startup prewarm completion deadline; continuing with the unchanged solver."}
	if _prewarm != null:
		_prewarm.rd_cancel()
		var retired: Dictionary = _prewarm.rd_diagnostics()
		for key in retired:
			if key not in ["state", "pass", "error"]: report[key] = retired[key]
	var frame_delay := int(_rd.get_frame_delay()) if _rd != null and _rd.has_method("get_frame_delay") else 0
	_prewarm_finished.call_deferred(report, epoch, frame_delay)

func configure(surface_at: Callable, depth_at: Callable) -> void:
	_surface = surface_at
	_depth = depth_at
	initialize()

func impact(x: float, z: float, power: float, flow: Dictionary = {"u": 0.0, "v": 0.0}) -> void:
	for value in [x, z, power, flow.get("u", 0.0), flow.get("v", 0.0), flow.get("radius", 0.1), flow.get("vertical", 0.0)]:
		if not is_finite(float(value)):
			return
	if power < 0.08 or _sources.size() + _patches.size() >= MAX_PATCHES:
		return
	_serial += 1
	_sources.append({"x": x, "z": z, "power": minf(1.2, power), "flow": flow.duplicate(), "crest": false, "seed": _serial})

func crest(x: float, z: float, power: float, flow: Dictionary) -> void:
	if power < 0.28 or _sources.size() + _patches.size() >= MAX_PATCHES:
		return
	for patch in _patches:
		if sqrt((x - float(patch.x)) ** 2 + (z - float(patch.z)) ** 2) < 0.6:
			return
	_serial += 1
	_sources.append({"x": x, "z": z, "power": minf(0.45, power), "flow": flow.duplicate(), "crest": true, "seed": _serial})

func _random() -> float:
	_rng = (_rng * 1664525 + 1013904223) & 0xffffffff
	return float(_rng) / 4294967296.0

## Public fixture entry: source host initialization without any GPU execution.
## Input seed, flow and source must be identical to the baseline for byte parity.
func build_source(source: Dictionary, surface_at: Callable, depth_at: Callable) -> Dictionary:
	var x := float(source.x)
	var z := float(source.z)
	var power := float(source.power)
	var flow: Dictionary = source.flow
	var is_crest := bool(source.crest)
	var body_radius := float(flow.get("radius", 0.075 + power * 0.06 if power > 0.22 and not is_crest else 0.0))
	var radius := clampf(body_radius * 2.5, 0.16, 0.34) if body_radius > 0.0 else 0.085 + power * 0.23
	var h := maxf(0.014, radius / 12.0)
	var spacing := h * 0.65
	# Source flow/impulse are immutable for this queued spawn. Reuse exact
	# binary64 values rather than re-reading/converting them per particle.
	var flow_u := float(flow.get("u", 0.0))
	var flow_v := float(flow.get("v", 0.0))
	var impulse := 0.0 if body_radius > 0.0 else sqrt(power) * 1.6
	var base := float(surface_at.call(x, z))
	var raw := PackedFloat32Array()
	raw.resize(LIMIT * 20)
	raw.fill(0.0)
	_rng = (int(source.seed) * 1664525 + 1013904223) & 0xffffffff
	var count := 0
	var ix := -radius
	while ix < radius:
		var iz := -radius
		while iz < radius:
			var distance := sqrt(ix * ix + iz * iz)
			if distance <= radius and float(depth_at.call(x + ix, z + iz)) > 0.0:
				# Every vertical particle in a source XZ column has the same
				# envelope and impulse. Arithmetic and RNG order are unchanged.
				var q := distance / radius
				var envelope := exp(-q * q * 3.5)
				var upward := impulse * envelope if is_crest else -impulse * envelope * 0.55
				var outward := impulse * envelope * 0.35 if is_crest else 0.0
				var iy := -h * 8.0
				while iy < -0.001:
					if count >= LIMIT:
						break
					var px := ix + (_random() - 0.5) * spacing * 0.35
					var pz := iz + (_random() - 0.5) * spacing * 0.35
					var py := iy + (_random() - 0.5) * spacing * 0.25
					var j := count * 20
					raw[j] = 40.0 + px / h
					raw[j + 1] = 12.0 + py / h
					raw[j + 2] = 40.0 + pz / h
					raw[j + 3] = 3.64133
					raw[j + 4] = (flow_u * 0.35 + (px / distance if distance > 0.001 else 0.0) * outward) / h
					raw[j + 5] = upward / h
					raw[j + 6] = (flow_v * 0.35 + (pz / distance if distance > 0.001 else 0.0) * outward) / h
					raw[j + 7] = 1.0
					count += 1
					iy += spacing
			iz += spacing
		ix += spacing
	raw.resize(count * 20)
	var params := PackedFloat32Array()
	params.resize(16)
	params.fill(0.0)
	params[1] = h
	params[2] = STEP
	params[4] = float(flow.get("u", 0.0))
	params[5] = float(flow.get("v", 0.0))
	params[8] = 40.0
	params[9] = 12.0 + body_radius * 0.85 / h
	params[10] = 40.0
	params[11] = body_radius
	params[12] = float(flow.get("u", 0.0))
	params[13] = minf(-1.0, float(flow.get("vertical", -sqrt(power) * 4.0)))
	params[14] = float(flow.get("v", 0.0))
	var packed_params := params.to_byte_array()
	packed_params.encode_u32(0, count)
	return {"x": x, "z": z, "base": base, "h": h, "count": count, "raw": raw, "params": packed_params}

func _create(source: Dictionary) -> void:
	var p := build_source(source, _surface, _depth)
	if int(p.count) == 0:
		return
	var data: PackedFloat32Array = p.raw.duplicate()
	for i in int(p.count):
		data[i * 20 + 8] = 0.64
		data[i * 20 + 13] = 0.64
		data[i * 20 + 18] = 0.64
	var removed := PackedByteArray()
	removed.resize(int(p.count))
	removed.fill(0)
	var deletions := PackedInt32Array()
	deletions.resize(int(p.count) + 1)
	deletions.fill(0)
	p.merge({"id": int(source.seed), "age": 0.0, "elapsed": 0.0, "pending": false, "disposed": false, "data": data, "previous": data.duplicate(), "sample_age": 0.0, "sample_delta": STEP, "blend_elapsed": 0.0, "removed": removed, "emerged": removed.duplicate(), "deletions": deletions, "independent": independent_scheduling})
	_patches.append(p)
	var raw: PackedFloat32Array = p.raw
	upload_bytes += raw.size() * 4
	RenderingServer.call_on_render_thread(_rd_create_patch.bind(int(p.id), raw.to_byte_array(), p.params, _epoch, SNAPSHOT_SLOTS if bool(p.independent) else 1))
	p.erase("raw")

func _ensure_native_particle_gate() -> void:
	if not _native_particle_gate_checked:
		_native_particle_gate_checked = true
		_native_particle_gate_available = ClassDB.class_exists("SourceWaterReadback") and ClassDB.class_has_method("SourceWaterReadback", "find_next_particle_candidate")
	if native_particle_gate and _native_particle_gate_available and _native_particle_gate == null:
		_native_particle_gate = ClassDB.instantiate("SourceWaterReadback")
		if _native_particle_gate == null:
			_native_particle_gate_available = false

func native_particle_gate_diagnostics() -> Dictionary:
	return {"requested": native_particle_gate, "probed": _native_particle_gate_checked,
		"available": _native_particle_gate_available,
		"enabled": native_particle_gate and _native_particle_gate != null,
		"calls_last_frame": _native_gate_calls, "scan_ms_last_frame": _native_gate_ms,
		"skipped_domains_last_frame": _native_gate_skipped_domains,
		"skipped_particles_last_frame": _native_gate_skipped_particles,
		"fallbacks_last_frame": _native_gate_fallbacks}

func frame(delta: float) -> void:
	if _disposed or not _surface.is_valid() or not _depth.is_valid():
		return
	var frame_started := Time.get_ticks_usec()
	_update_idle_pacing(frame_started, Engine.get_frames_drawn())
	_frame_serial += 1
	_supplied_delta = maxf(0.0, delta) if is_finite(delta) else 0.0
	var dt := minf(_supplied_delta, MAX_BACKLOG_SECONDS if independent_scheduling else 0.05)
	_accepted_delta = dt
	_last_frame_steps = 0
	if status == "ready" and dt > 0.0:
		for source in _sources:
			_create(source)
		_sources.clear()
	elif status != "initializing" and status != "ready":
		_sources.clear()
	_update_copy_backpressure(dt)
	_native_gate_calls = 0
	_native_gate_skipped_domains = 0
	_native_gate_skipped_particles = 0
	_native_gate_fallbacks = 0
	_native_gate_ms = 0.0
	if not _patches.is_empty(): _ensure_native_particle_gate()
	var pack_started := Time.get_ticks_usec()
	_source_build_ms = float(pack_started - frame_started) / 1000.0
	# Allocate only for existing domains, not 2.6 MB even when no splash exists.
	# Each published frame owns its array: queued render callbacks must not see
	# it mutated by the next main-thread frame (PackedArrays are references).
	var capacity := 0
	for patch in _patches:
		capacity += int(patch.count)
	var rows := PackedFloat32Array()
	rows.resize(capacity * 12)
	var visible := 0
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for patch in _patches:
		# The original JS host uses locals. Dictionary/Variant conversions in
		# GDScript's 18k-particle loop are materially more expensive than the
		# arithmetic, so keep stable patch values in typed locals too.
		var patch_x := float(patch.x)
		var patch_z := float(patch.z)
		var base := float(patch.base)
		var independent := bool(patch.get("independent", independent_scheduling))
		if independent:
			_ensure_schedule_state(patch)
			_prepare_presentation(patch, dt)
		# CPU detachment uses the presentation/interaction time, not the GPU's
		# newer submitted frontier. Late snapshots cannot emit drops prematurely.
		var age := float(patch.render_age) if independent else float(patch.age)
		patch.supplied_seconds = float(patch.get("supplied_seconds", 0.0)) + _supplied_delta
		patch.accepted_seconds = float(patch.get("accepted_seconds", 0.0)) + dt
		if bool(patch.pending):
			var oldest_frame := int(patch.get("submitted_frame", _frame_serial))
			for request: Dictionary in patch.get("snapshot_requests", {}).values():
				oldest_frame = mini(oldest_frame, int(request.frame))
			_readback_pending_max_frames = maxi(_readback_pending_max_frames, _frame_serial - oldest_frame)
		if float(_depth.call(patch_x, patch_z)) <= 0.0:
			_destroy_patch(patch)
			continue
		var data: PackedFloat32Array = patch.data
		var previous: PackedFloat32Array = patch.previous
		var h := float(patch.h)
		if not independent:
			patch.blend_elapsed = float(patch.blend_elapsed) + dt
		var blend := minf(1.0, float(patch.blend_elapsed) / float(patch.sample_delta))
		var removed: PackedByteArray = patch.removed
		var emerged: PackedByteArray = patch.emerged
		var deletion_list: PackedInt32Array = patch.deletions
		var deleted := deletion_list[0]
		var scan_count := int(patch.count)
		if native_particle_gate and _native_particle_gate != null and scan_count > 0:
			var scan_started := Time.get_ticks_usec()
			var candidate: int = _native_particle_gate.find_next_particle_candidate(data, previous, removed, emerged, 0, blend, base, h)
			_native_gate_ms += float(Time.get_ticks_usec() - scan_started) / 1000.0
			_native_gate_calls += 1
			if candidate < 0:
				_native_gate_fallbacks += 1
			elif candidate >= scan_count:
				_native_gate_skipped_domains += 1
				_native_gate_skipped_particles += scan_count
				scan_count = 0
		for i in scan_count:
			var j := i * 20
			if removed[i] != 0 or data[j + 7] < 0.5:
				continue
			var y := base + (lerpf(previous[j + 1], data[j + 1], blend) - 12.0) * h
			# Same submerged-reservoir rejection, before unused XZ work.
			if y < base - 0.06 and emerged[i] == 0:
				continue
			var x := patch_x + (lerpf(previous[j], data[j], blend) - 40.0) * h
			var z := patch_z + (lerpf(previous[j + 2], data[j + 2], blend) - 40.0) * h
			var level := float(_surface.call(x, z))
			var velocity := Vector3(data[j + 4] * h, data[j + 5] * h, data[j + 6] * h)
			if not is_finite(y) or float(_depth.call(x, z)) <= 0.0:
				removed[i] = 1
				deleted += 1
				deletion_list[deleted] = i
				continue
			if y > level + 0.025:
				emerged[i] = 1
			if dt > 0.0 and emerged[i] != 0 and y < level + 0.003 and velocity.y < 0.0:
				removed[i] = 1
				deleted += 1
				deletion_list[deleted] = i
				returns += 1
				if i % 24 == 0:
					return_ripple.emit(Vector2(x, z), clampf(h * h * h * absf(velocity.y) * 600.0, 0.000025, 0.002))
					ripples += 1
				continue
			if dt > 0.0 and data[j + 7] < 8.0 and emerged[i] != 0 and age > 0.08:
				removed[i] = 1
				deleted += 1
				deletion_list[deleted] = i
				droplet_released.emit(Vector3(x, y, z), velocity, h * 0.72)
				released += 1
				continue
			if y + h * 0.55 < level:
				continue
			var k := visible * 12
			# Same column-major source kernel -> row-major native 3x4, without
			# nine nested Variant loop/index calculations per visible particle.
			rows[k] = lerpf(previous[j + 8], data[j + 8], blend) * h
			rows[k + 1] = lerpf(previous[j + 12], data[j + 12], blend) * h
			rows[k + 2] = lerpf(previous[j + 16], data[j + 16], blend) * h
			rows[k + 4] = lerpf(previous[j + 9], data[j + 9], blend) * h
			rows[k + 5] = lerpf(previous[j + 13], data[j + 13], blend) * h
			rows[k + 6] = lerpf(previous[j + 17], data[j + 17], blend) * h
			rows[k + 8] = lerpf(previous[j + 10], data[j + 10], blend) * h
			rows[k + 9] = lerpf(previous[j + 14], data[j + 14], blend) * h
			rows[k + 10] = lerpf(previous[j + 18], data[j + 18], blend) * h
			rows[k + 3] = x + lerpf(previous[j + 11], data[j + 11], blend) * h
			rows[k + 7] = y + lerpf(previous[j + 15], data[j + 15], blend) * h
			rows[k + 11] = z + lerpf(previous[j + 19], data[j + 19], blend) * h
			var origin := Vector3(rows[k + 3], rows[k + 7], rows[k + 11])
			var extent := Vector3(Vector3(rows[k], rows[k + 1], rows[k + 2]).length(), Vector3(rows[k + 4], rows[k + 5], rows[k + 6]).length(), Vector3(rows[k + 8], rows[k + 9], rows[k + 10]).length())
			low = low.min(origin - extent)
			high = high.max(origin + extent)
			visible += 1
		# Packed arrays are shared references in GDScript. Batch the deletion
		# count write rather than re-entering a Dictionary helper per contact.
		deletion_list[0] = deleted
		patch.emerged = emerged
		patch.removed = removed
		patch.deletions = deletion_list
		_advance_patch(patch, dt)
	_patches = _patches.filter(func(p: Dictionary) -> bool: return not bool(p.disposed))
	rows.resize(visible * 12)
	instance_rows = rows
	visible_count = visible
	bounds = AABB(low, high - low) if visible > 0 else AABB()
	upload_bytes += visible * 48
	var finished := Time.get_ticks_usec()
	_host_pack_ms = float(finished - pack_started) / 1000.0
	_host_frame_ms = float(finished - frame_started) / 1000.0
	_host_frame_max_ms = maxf(_host_frame_max_ms, _host_frame_ms)

## Main-thread only. GPU simulation does not wait for every readback. Its lead
## over the newest CPU interaction snapshot and its render queue are bounded.
## CPU contacts cannot be retroactively applied to already submitted substeps;
## this is a deliberate latency tradeoff, not exact original-host equivalence.
func _advance_patch(patch: Dictionary, dt: float) -> void:
	var independent := bool(patch.get("independent", independent_scheduling))
	var backlog_limit := MAX_BACKLOG_SECONDS if independent else 0.05
	var accumulated := float(patch.elapsed) + dt
	patch.catchup_discarded_seconds = float(patch.get("catchup_discarded_seconds", 0.0)) + maxf(0.0, accumulated - backlog_limit)
	patch.input_discarded_seconds = float(patch.get("input_discarded_seconds", 0.0)) + maxf(0.0, _supplied_delta - dt)
	patch.elapsed = minf(backlog_limit, accumulated)
	if independent and bool(patch.get("finishing", false)):
		_finish_or_retire(patch)
		return
	if dt <= 0.0 or (not independent and bool(patch.pending)):
		return
	if not independent:
		var original_steps := mini(36, floori(float(patch.elapsed) / STEP))
		if original_steps > 0:
			_submit_batch(patch, original_steps, -1, false)
		return
	_ensure_schedule_state(patch)
	# An encoding ACK is not GPU completion. Avoid adding catch-up work
	# ahead of an overdue frame-delayed copy; never block presentation here.
	if _copy_backpressure_active:
		return
	var queue_room := MAX_QUEUED_BATCHES - int(patch.queued_batches)
	if queue_room <= 0:
		_queue_backpressure_frames += 1
		return
	# Integer substep frontier avoids a float residual shortening the bound.
	var interaction_steps := floori((float(patch.render_age) + STEP * 1e-9) / STEP)
	var feedback_room := int(patch.feedback_lead_steps) - (int(patch.sim_steps) - interaction_steps)
	if feedback_room <= 0:
		_feedback_limited_domain_frames += 1
		_feedback_backpressure_frames += 1
		return
	var wanted := floori((float(patch.elapsed) + STEP * 1e-9) / STEP)
	var lifetime_room := MAX_LIFETIME_STEPS - int(patch.sim_steps)
	if feedback_room < mini(lifetime_room, mini(wanted, mini(queue_room, MAX_BATCHES_PER_FRAME) * 36)):
		_feedback_limited_domain_frames += 1
	var budget := mini(lifetime_room, mini(wanted, mini(feedback_room, mini(queue_room, MAX_BATCHES_PER_FRAME) * 36)))
	if _copy_recovery_active and budget > _recovery_admission_steps:
		_recovery_limited_domain_frames += 1
		budget = _recovery_admission_steps
	var admitted_frame_steps := budget
	while budget > 0:
		var steps := mini(36, budget)
		budget -= steps
		# One owned export per host frame, after its final sub-batch. If all
		# slots are busy, advance only the solver, within the feedback bound.
		var slot := _free_snapshot_slot(patch) if budget == 0 else -1
		# A terminal state MUST be exported. Do not consume the final steps
		# while every output slot is owned by an older asynchronous readback.
		if int(patch.sim_steps) + steps == MAX_LIFETIME_STEPS and slot < 0:
			_feedback_backpressure_frames += 1
			break
		if not _submit_batch(patch, steps, slot, true, admitted_frame_steps):
			break

func _update_copy_backpressure(dt: float) -> void:
	_copy_backpressure_active = false
	_uncopied_snapshot_age_ms = 0.0
	var now := Time.get_ticks_usec()
	_copy_deadline_usec = _configured_copy_deadline_usec(now)
	var has_independent_domain := false
	for patch: Dictionary in _patches:
		if bool(patch.disposed) or not bool(patch.get("independent", independent_scheduling)):
			continue
		has_independent_domain = true
		for request: Dictionary in patch.get("snapshot_requests", {}).values():
			if bool(request.get("copied", false)):
				continue
			var age := maxi(0, now - int(request.queued_usec))
			_uncopied_snapshot_age_ms = maxf(_uncopied_snapshot_age_ms, float(age) / 1000.0)
			if copy_backpressure_enabled and age > int(request.get("copy_deadline_usec", _copy_deadline_usec)):
				_copy_backpressure_active = true
	if not copy_recovery_enabled or not copy_backpressure_enabled or not has_independent_domain:
		_copy_recovery_active = false
		_recovery_timely_frames = 0
	elif _copy_backpressure_active:
		_enter_copy_recovery()
	if dt > 0.0:
		if _copy_backpressure_active: _copy_backpressure_frames += 1
		if _copy_recovery_active: _copy_recovery_frames += 1

func _enter_copy_recovery() -> void:
	if not _copy_recovery_active:
		_copy_recovery_active = true
		_copy_recovery_entries += 1
	elif _recovery_admission_steps > RECOVERY_STEPS_PER_FRAME:
		_recovery_backoffs += 1
	_recovery_admission_steps = RECOVERY_STEPS_PER_FRAME
	_recovery_generation += 1
	# Only work submitted after the latest genuine stall can establish health.
	_recovery_started_frame = _frame_serial
	_recovery_observed_frame = _frame_serial
	_recovery_timely_frames = 0

func _observe_recovery_copy(submitted_frame: int, latency_usec: int, tested_work: int = 0, requested_tier: int = 0, generation: int = -1, copied_usec: int = 0, owned_deadline_usec: int = -1, pacing_generation: int = -1) -> void:
	if not copy_recovery_enabled or not copy_backpressure_enabled:
		return
	# Callback notification order is not GPU completion order. A genuinely
	# later late copy backs down even if its submission preceded promotion;
	# an older actual completion cannot undo a newer health observation.
	if copied_usec > 0:
		if copied_usec < _recovery_latest_copy_usec: return
		_recovery_latest_copy_usec = copied_usec
	var deadline := owned_deadline_usec if owned_deadline_usec > 0 else _copy_deadline_usec
	if latency_usec > deadline:
		# A late copy can arrive between host calls before the watchdog sees
		# it. Even a successful lower-work tier cannot prove a large burst.
		_enter_copy_recovery()
		return
	# A previous pacing regime cannot prove capacity under a changed deadline.
	if pacing_generation >= 0 and pacing_generation != _pacing_generation:
		return
	if not _copy_recovery_active or submitted_frame <= _recovery_started_frame or submitted_frame < _recovery_observed_frame or generation != _recovery_generation:
		return
	if submitted_frame > _recovery_observed_frame:
		if requested_tier == _recovery_admission_steps and tested_work == _recovery_admission_steps:
			_recovery_timely_frames += 1
		else:
			# Low-work samples do not establish capacity at the current tier.
			_recovery_timely_frames = 0
	_recovery_observed_frame = submitted_frame
	if _recovery_timely_frames >= RECOVERY_TIMELY_FRAMES:
		if _recovery_admission_steps < MAX_BATCHES_PER_FRAME * 36:
			_recovery_admission_steps = mini(MAX_BATCHES_PER_FRAME * 36, _recovery_admission_steps + RECOVERY_STEPS_PER_FRAME)
			_recovery_probe_transitions += 1
			_recovery_generation += 1
			_recovery_started_frame = _frame_serial
			_recovery_observed_frame = _frame_serial
			_recovery_timely_frames = 0
		else:
			_copy_recovery_active = false
			_copy_recovery_exits += 1

static func copy_deadline_for_pacing(frame_delay: int, max_fps: int, refresh_hz: float, vsync_enabled: bool) -> int:
	# Async copies require rendered frames, not just GPU execution time.
	# Use only configured pacing, never a large observed delta as a speed guess.
	var interval := 1000000.0 / max_fps if max_fps > 0 else 0.0
	if vsync_enabled and is_finite(refresh_hz) and refresh_hz > 0.0:
		interval = maxf(interval, 1000000.0 / refresh_hz)
	return maxi(MAX_UNCOPIED_SNAPSHOT_USEC, ceili((maxi(1, frame_delay) + 1) * interval))

func _reset_idle_cadence() -> void:
	_idle_samples.clear()
	_idle_previous_frame = -1
	_idle_qualified_usec = -1
	_idle_raw_period_usec = 0

## Only READY, empty, actually rendered frames may establish external pacing.
## This narrow clock boundary is injectable in CPU fixtures; dt is never used.
func _observe_idle_cadence(now_usec: int, rendered_frame: int, eligible: bool) -> void:
	if not eligible or not idle_cadence_enabled or not independent_scheduling:
		_reset_idle_cadence()
		return
	if _idle_previous_frame < 0:
		_idle_previous_usec = now_usec
		_idle_previous_frame = rendered_frame
		return
	if rendered_frame == _idle_previous_frame:
		return
	var interval := now_usec - _idle_previous_usec
	var consecutive := rendered_frame == _idle_previous_frame + 1
	_idle_previous_usec = now_usec
	_idle_previous_frame = rendered_frame
	if not consecutive or interval < 2000 or interval > 250000:
		_idle_samples.clear()
		_idle_qualified_usec = -1
		_idle_raw_period_usec = 0
		_idle_cadence_rejections += 1
		return
	_idle_samples.append(interval)
	if _idle_samples.size() > IDLE_CADENCE_SAMPLES:
		_idle_samples.pop_front()
	var low := interval
	var high := interval
	var span := 0
	for sample: int in _idle_samples:
		low = mini(low, sample)
		high = maxi(high, sample)
		span += sample
	if float(high) > float(low) * 1.5:
		# A loading spike/rate discontinuity requires a new stable window.
		_idle_samples.assign([interval])
		_idle_qualified_usec = -1
		_idle_raw_period_usec = 0
		_idle_cadence_rejections += 1
		return
	if _idle_samples.size() < IDLE_CADENCE_MIN_SAMPLES or span < IDLE_CADENCE_MIN_SPAN_USEC:
		return
	var ordered := _idle_samples.duplicate()
	ordered.sort()
	_idle_raw_period_usec = int(ordered[ceili(float(ordered.size()) * 0.75) - 1])
	_idle_qualified_usec = now_usec

func _update_idle_pacing(now_usec: int, rendered_frame: int) -> void:
	var empty_ready := status == "ready" and _patches.is_empty() and _sources.is_empty() and not _prewarm_pending
	if not independent_scheduling:
		_observe_idle_cadence(now_usec, rendered_frame, false)
		return
	if empty_ready:
		# Main-thread removal precedes render-thread resource retirement. Allow
		# the device frame ring to drain before collecting a new idle window.
		if rendered_frame < _idle_retirement_frame:
			_observe_idle_cadence(now_usec, rendered_frame, false)
			return
		if _pacing_active:
			_pacing_active = false
			_pacing_calibrated = false
			_pacing_idle_period_usec = 0
			_pacing_raw_period_usec = 0
			_pacing_sample_count = 0
			_reset_idle_cadence()
		_observe_idle_cadence(now_usec, rendered_frame, true)
		return
	if not _pacing_active and status == "ready" and not _prewarm_pending:
		_pacing_active = true
		_pacing_generation += 1
		_pacing_calibrated = idle_cadence_enabled and _idle_qualified_usec >= 0 and now_usec >= _idle_qualified_usec and now_usec - _idle_qualified_usec <= IDLE_CADENCE_FRESH_USEC
		_pacing_raw_period_usec = _idle_raw_period_usec if _pacing_calibrated else 0
		_pacing_idle_period_usec = mini(IDLE_CADENCE_MAX_PERIOD_USEC, _pacing_raw_period_usec)
		_pacing_sample_count = _idle_samples.size() if _pacing_calibrated else 0
	# Active stalls, queued sources and prewarm can NEVER excuse themselves.
	_observe_idle_cadence(now_usec, rendered_frame, false)

func _configured_copy_deadline_usec(now: int) -> int:
	_configured_vsync = false
	if DisplayServer.get_name() != "headless":
		_configured_vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
		if now >= _refresh_probe_after_usec:
			_display_refresh_hz = DisplayServer.screen_get_refresh_rate()
			_refresh_probe_after_usec = now + 1000000
	var period := 1.0 / float(Engine.max_fps) if Engine.max_fps > 0 else 0.0
	if _configured_vsync and is_finite(_display_refresh_hz) and _display_refresh_hz > 0.0:
		period = maxf(period, 1.0 / _display_refresh_hz)
	_configured_period_usec = ceili(period * 1000000.0)
	_configured_copy_deadline = copy_deadline_for_pacing(_async_frame_delay, Engine.max_fps, _display_refresh_hz, _configured_vsync)
	var configuration := "%d/%d/%s/%s" % [_async_frame_delay, Engine.max_fps, str(_configured_vsync), str(_display_refresh_hz)]
	if configuration != _pacing_configuration:
		_pacing_configuration = configuration
		_pacing_generation += 1
		_recovery_timely_frames = 0
		_recovery_observed_frame = _frame_serial
	var frames := _async_frame_delay + 1
	var idle_deadline := mini(IDLE_CADENCE_MAX_DEADLINE_USEC, frames * _pacing_idle_period_usec)
	_feedback_lead_steps = MAX_FEEDBACK_LEAD_STEPS
	if independent_scheduling and pipeline_feedback_enabled:
		var known_period := maxi(_configured_period_usec, _pacing_idle_period_usec)
		_feedback_lead_steps = clampi(ceili(float(frames * known_period) * 720.0 / 1000000.0), MAX_FEEDBACK_LEAD_STEPS, MAX_PIPELINE_FEEDBACK_STEPS)
	return maxi(_configured_copy_deadline, idle_deadline)

func _snapshot_copied(id: int, epoch: int, sequence: int, sample_age: float, slot: int, byte_count: int, copied_usec: int) -> void:
	# Main-thread notification of actual RD bytes, distinct from publication.
	# It NEVER releases a slot or changes CPU interactions/presentation.
	if epoch != _epoch or _disposed:
		return
	for patch: Dictionary in _patches:
		if int(patch.id) != id or bool(patch.disposed) or not bool(patch.get("independent", independent_scheduling)):
			continue
		if not patch.get("snapshot_requests", {}).has(sequence):
			_stale_copy_notifications += 1
			return
		var request: Dictionary = patch.snapshot_requests[sequence]
		if int(request.slot) != slot or not is_equal_approx(float(request.age), sample_age) or byte_count != int(patch.count) * 80 or copied_usec < int(request.queued_usec):
			_patch_failed(id, "MLS-MPM copied snapshot ownership/length/timestamp mismatch.", epoch)
			return
		if bool(request.get("copied", false)):
			_stale_copy_notifications += 1
			return
		request.copied = true
		request.copied_usec = copied_usec
		_copy_latency_ms = float(copied_usec - int(request.queued_usec)) / 1000.0
		_copy_latency_max_ms = maxf(_copy_latency_max_ms, _copy_latency_ms)
		_observe_recovery_copy(int(request.frame), copied_usec - int(request.queued_usec), int(request.get("frame_steps", 0)), int(request.get("recovery_tier", 0)), int(request.get("recovery_generation", -1)), copied_usec, int(request.get("copy_deadline_usec", _copy_deadline_usec)), int(request.get("pacing_generation", _pacing_generation)))
		return

func _finish_or_retire(patch: Dictionary) -> void:
	if float(patch.render_age) >= MAX_LIFETIME_STEPS * STEP - 1e-9:
		_destroy_patch(patch)
	elif Time.get_ticks_usec() - int(patch.finish_started_usec) > FINISH_TIMEOUT_USEC:
		_finish_timeouts += 1
		last_error = "MLS-MPM final snapshot/presentation drain timed out; domain retired safely."
		_destroy_patch(patch)

func _ensure_schedule_state(patch: Dictionary) -> void:
	if not patch.has("feedback_lead_steps"):
		# A domain owns its coupling limit for its lifetime. Later configuration
		# changes cannot retroactively invalidate already-admitted lead.
		patch.feedback_lead_steps = _feedback_lead_steps
	if patch.has("snapshot_requests"):
		return
	patch.snapshot_requests = {}
	patch.next_snapshot = 0
	patch.published_snapshot = 0
	patch.queued_batches = 0
	patch.sim_steps = roundi(float(patch.age) / STEP)
	patch.sample_steps = roundi(float(patch.sample_age) / STEP)
	patch.render_age = float(patch.sample_age)
	patch.presentation_samples = [{"age": float(patch.sample_age), "data": patch.data}]

func _prepare_presentation(patch: Dictionary, dt: float) -> void:
	var samples: Array = patch.presentation_samples
	# Never extrapolate. Once data arrives, the display advances by elapsed
	# time from its held point; callback bursts do not jump its clock forward.
	patch.render_age = minf(float(patch.sample_age), float(patch.render_age) + dt)
	while samples.size() > 1 and float(samples[1].age) <= float(patch.render_age):
		samples.pop_front()
	var before: Dictionary = samples[0]
	var after: Dictionary = samples[1] if samples.size() > 1 else before
	patch.previous = before.data
	patch.data = after.data
	patch.sample_delta = maxf(STEP, float(after.age) - float(before.age))
	patch.blend_elapsed = maxf(0.0, float(patch.render_age) - float(before.age))
	patch.presentation_samples = samples

func _free_snapshot_slot(patch: Dictionary) -> int:
	var occupied := PackedByteArray([0, 0, 0])
	for request: Dictionary in patch.snapshot_requests.values():
		occupied[int(request.slot)] = 1
	for slot in SNAPSHOT_SLOTS:
		if occupied[slot] == 0:
			return slot
	return -1

func _submit_batch(patch: Dictionary, steps: int, slot: int, independent: bool, admitted_frame_steps: int = 0) -> bool:
	var start_age := float(patch.age)
	var end_age := start_age + steps * STEP
	if independent:
		end_age = (int(patch.sim_steps) + steps) * STEP
	# Keep source lifetime. Never enqueue a batch beyond its domain lifetime.
	if end_age > MAX_LIFETIME_STEPS * STEP:
		if not independent:
			# The legacy branch retains the original immediate-retirement rule.
			patch.elapsed = float(patch.elapsed) - steps * STEP
			patch.age = end_age
		_destroy_patch(patch)
		return false
	patch.elapsed = maxf(0.0, float(patch.elapsed) - steps * STEP)
	# Every render command owns its bytes. Reusing patch.params across queued
	# commands would allow a future main-thread mutation to change older work.
	var params: PackedByteArray = patch.params.duplicate()
	params.encode_float(12, start_age)
	var deletion_list: PackedInt32Array = patch.deletions
	var deleted := deletion_list[0]
	var deletion_bytes := deletion_list.slice(0, deleted + 1).to_byte_array()
	deletion_list[0] = 0
	patch.deletions = deletion_list
	patch.age = end_age
	var submitted_usec := Time.get_ticks_usec()
	var sequence := 0
	if independent:
		patch.sim_steps = int(patch.sim_steps) + steps
		if int(patch.sim_steps) == MAX_LIFETIME_STEPS:
			patch.finishing = true
			patch.finish_started_usec = submitted_usec
		patch.queued_batches = int(patch.queued_batches) + 1
		if slot >= 0:
			patch.next_snapshot = int(patch.next_snapshot) + 1
			sequence = int(patch.next_snapshot)
			patch.snapshot_requests[sequence] = {"slot": slot, "age": end_age, "steps": int(patch.sim_steps), "queued_usec": submitted_usec, "frame": _frame_serial, "copied": false, "frame_steps": admitted_frame_steps if admitted_frame_steps > 0 else steps, "recovery_tier": _recovery_admission_steps if _copy_recovery_active else 0, "recovery_generation": _recovery_generation, "copy_deadline_usec": _copy_deadline_usec, "pacing_generation": _pacing_generation, "feedback_lead_steps": int(patch.feedback_lead_steps)}
		else:
			_simulation_only_batches += 1
		patch.pending = not patch.snapshot_requests.is_empty()
	else:
		patch.pending = true
	patch.submitted_frame = _frame_serial
	patch.submitted_usec = submitted_usec
	_steps_dispatched += steps
	_last_frame_steps += steps
	_batches_dispatched += 1
	upload_bytes += 64 + ((deleted + 1) * 4 if deleted > 0 else 0)
	if not independent or slot >= 0:
		readback_bytes += int(patch.count) * 80
	_queue_step(int(patch.id), steps, params, deletion_bytes, _epoch, submitted_usec, sequence, end_age, slot, independent)
	return true

## Narrow queue boundary is overridable by the CPU-only scheduling fixture.
func _queue_step(id: int, steps: int, params: PackedByteArray, deletions: PackedByteArray, epoch: int, queued_usec: int, sequence: int, sample_age: float, slot: int, independent: bool) -> void:
	RenderingServer.call_on_render_thread(_rd_step.bind(id, steps, params, deletions, epoch, queued_usec, sequence, sample_age, slot, independent))

func _batch_encoded(id: int, epoch: int) -> void:
	if epoch != _epoch or _disposed:
		return
	for patch in _patches:
		if int(patch.id) == id and not bool(patch.disposed):
			patch.queued_batches = maxi(0, int(patch.get("queued_batches", 0)) - 1)
			return

func _remove(patch: Dictionary, index: int) -> void:
	var removed: PackedByteArray = patch.removed
	if removed[index] != 0:
		return
	removed[index] = 1
	patch.removed = removed
	var deletions: PackedInt32Array = patch.deletions
	deletions[0] += 1
	deletions[deletions[0]] = index
	patch.deletions = deletions

func _destroy_patch(patch: Dictionary) -> void:
	if bool(patch.disposed):
		return
	patch.disposed = true
	if bool(patch.get("independent", false)):
		_idle_retirement_frame = Engine.get_frames_drawn() + _async_frame_delay + 1
		if patch.has("snapshot_requests"): patch.snapshot_requests.clear()
		if patch.has("presentation_samples"): patch.presentation_samples.clear()
		patch.pending = false
		patch.queued_batches = 0
	RenderingServer.call_on_render_thread(_rd_destroy_patch.bind(int(patch.id)))

func rebase(shift: Vector3) -> void:
	for p in _patches:
		p.x = float(p.x) - shift.x
		p.z = float(p.z) - shift.z
	for s in _sources:
		s.x = float(s.x) - shift.x
		s.z = float(s.z) - shift.z

func stats() -> Dictionary:
	var count := 0
	var ages: Array[float] = []
	var domains: Array[Dictionary] = []
	var now := Time.get_ticks_usec()
	for p in _patches:
		count += int(p.count)
		ages.append(float(p.age))
		var submitted := int(p.get("submitted_usec", 0))
		var submitted_frame := int(p.get("submitted_frame", _frame_serial))
		var uncopied := 0
		for request: Dictionary in p.get("snapshot_requests", {}).values():
			submitted = mini(submitted, int(request.queued_usec))
			submitted_frame = mini(submitted_frame, int(request.frame))
			if not bool(request.get("copied", false)): uncopied += 1
		domains.append({"id":int(p.id), "particles":int(p.count), "suppliedSeconds":float(p.get("supplied_seconds",0.0)), "acceptedSeconds":float(p.get("accepted_seconds",0.0)), "simulatedSeconds":float(p.age), "snapshotSeconds":float(p.sample_age), "sampleDelta":float(p.sample_delta), "blendElapsed":float(p.blend_elapsed), "catchupDiscardedSeconds":float(p.get("catchup_discarded_seconds",0.0)), "inputDiscardedSeconds":float(p.get("input_discarded_seconds",0.0)), "backlogSeconds":float(p.elapsed), "schedulingMode":"independent" if bool(p.get("independent", independent_scheduling)) else "original", "presentedSeconds":float(p.get("render_age", p.sample_age)), "feedbackLeadSeconds":maxf(0.0,float(p.age)-float(p.get("render_age", p.sample_age))), "feedbackLeadLimitSeconds":int(p.get("feedback_lead_steps", MAX_FEEDBACK_LEAD_STEPS))*STEP, "snapshotLagSeconds":maxf(0.0,float(p.sample_age)-float(p.get("render_age", p.sample_age))), "queuedBatches":int(p.get("queued_batches",0)), "pendingSnapshots":p.get("snapshot_requests",{}).size(), "uncopiedSnapshots":uncopied, "copiedUnpublishedSnapshots":p.get("snapshot_requests",{}).size()-uncopied, "presentationSamples":p.get("presentation_samples",[]).size(), "publishedSnapshot":int(p.get("published_snapshot",0)), "finishing":bool(p.get("finishing",false)), "pending":bool(p.pending), "pendingFrames":_frame_serial-submitted_frame if bool(p.pending) else 0, "pendingWallMs":float(now-submitted)/1000.0 if bool(p.pending) and submitted>0 else 0.0})
	return {"backend":status, "error":last_error, "domains":_patches.size(), "fluidParticles":visible_count, "released":released, "returns":returns, "ripples":ripples, "ages":ages, "simulatedParticles":count, "readbackBytes":readback_bytes, "uploadBytes":upload_bytes,
		"prewarm":{"enabled":prewarm_enabled, "requested":_prewarm_requested, "pending":_prewarm_pending, "report":_prewarm_report.duplicate(true)},
		"nativeParticleGate": native_particle_gate_diagnostics(),
		"pacing":{"idleCadenceEnabled":idle_cadence_enabled, "pipelineFeedbackEnabled":pipeline_feedback_enabled,
			"activeEpisode":_pacing_active, "qualifiedIdleBaseline":_pacing_calibrated, "idleSamples":_idle_samples.size(),
			"frozenIdleSamples":_pacing_sample_count, "idlePeriodMs":_pacing_idle_period_usec/1000.0,
			"rawIdlePeriodMs":_pacing_raw_period_usec/1000.0, "idlePeriodClipped":_pacing_raw_period_usec>_pacing_idle_period_usec,
			"idleCadenceRejections":_idle_cadence_rejections, "pacingGeneration":_pacing_generation,
			"retirementQuietFramesRemaining":maxi(0,_idle_retirement_frame-Engine.get_frames_drawn()),
			"configuredCopyDeadlineMs":_configured_copy_deadline/1000.0,
			"newDomainFeedbackLimitSeconds":_feedback_lead_steps*STEP,
			"baseFeedbackLeadSeconds":MAX_FEEDBACK_LEAD_STEPS*STEP,
			"hardFeedbackLeadSeconds":MAX_PIPELINE_FEEDBACK_STEPS*STEP,
			"feedbackLimitedDomainFrames":_feedback_limited_domain_frames},
		"scheduling":{"requestedMode":"independent" if independent_scheduling else "original", "copyRecoveryEnabled":copy_recovery_enabled, "copyRecoveryActive":_copy_recovery_active, "copyRecoveryEntries":_copy_recovery_entries, "copyRecoveryExits":_copy_recovery_exits, "copyRecoveryFrames":_copy_recovery_frames, "recoveryLimitedDomainFrames":_recovery_limited_domain_frames, "recoveryTimelyFrames":_recovery_timely_frames, "recoveryTimelyFramesRequired":RECOVERY_TIMELY_FRAMES, "maxRecoveryStepsPerDomainFrame":MAX_BATCHES_PER_FRAME * 36, "recoveryInitialStepsPerDomainFrame":RECOVERY_STEPS_PER_FRAME, "recoveryAdmissionStepsPerDomainFrame":_recovery_admission_steps if _copy_recovery_active else MAX_BATCHES_PER_FRAME * 36, "recoveryProbeTransitions":_recovery_probe_transitions, "recoveryBackoffs":_recovery_backoffs, "recoveryGeneration":_recovery_generation, "copyBackpressureEnabled":copy_backpressure_enabled, "copyBackpressureActive":_copy_backpressure_active, "copyBackpressureFrames":_copy_backpressure_frames, "maxUncopiedSnapshotMs":float(_copy_deadline_usec)/1000.0, "baseUncopiedSnapshotMs":float(MAX_UNCOPIED_SNAPSHOT_USEC)/1000.0, "asyncFrameDelay":_async_frame_delay, "asyncFrameDelayFromDevice":_async_frame_delay_actual, "configuredMaxFps":Engine.max_fps, "configuredVsync":_configured_vsync, "displayRefreshHz":_display_refresh_hz, "oldestUncopiedSnapshotMs":_uncopied_snapshot_age_ms, "gpuCopiedLatencyMs":_copy_latency_ms, "gpuCopiedLatencyMaxMs":_copy_latency_max_ms, "staleCopyNotifications":_stale_copy_notifications, "snapshotSlots":SNAPSHOT_SLOTS, "maxQueuedBatches":MAX_QUEUED_BATCHES, "maxBatchesPerFrame":MAX_BATCHES_PER_FRAME, "maxBacklogSeconds":MAX_BACKLOG_SECONDS, "maxFeedbackLeadSeconds":MAX_PIPELINE_FEEDBACK_STEPS*STEP if independent_scheduling and pipeline_feedback_enabled else MAX_FEEDBACK_LEAD_STEPS*STEP, "simulationOnlyBatches":_simulation_only_batches, "staleCallbacks":_snapshots_stale, "queueBackpressureFrames":_queue_backpressure_frames, "feedbackBackpressureFrames":_feedback_backpressure_frames, "presentationSamplesPruned":_presentation_samples_pruned, "finishTimeouts":_finish_timeouts},
		"timing":{"gpu": _gpu_timestamps.diagnostics() if _gpu_timestamps != null else {"enabled": false}, "hostFrameMs":_host_frame_ms, "hostFrameMaxMs":_host_frame_max_ms, "hostPackMs":_host_pack_ms, "sourceBuildMs":_source_build_ms, "suppliedDelta":_supplied_delta, "acceptedDelta":_accepted_delta, "stepsLastFrame":_last_frame_steps, "stepsDispatched":_steps_dispatched, "simulatedDomainSeconds":_steps_dispatched*STEP, "batchesDispatched":_batches_dispatched, "snapshotsReceived":_snapshots_received, "readbackLatencyMs":_readback_latency_ms, "readbackLatencyMaxMs":_readback_latency_max_ms, "readbackPendingMaxFrames":_readback_pending_max_frames, "renderThreadEncodeMs":_render_encode_ms, "renderThreadEncodeMaxMs":_render_encode_max_ms, "renderQueueMs":_render_queue_ms, "transferGridClear":transfer_grid_clear, "gridClearFallbacks":_grid_clear_fallbacks, "patches":domains}}

func _rd_initialize(code: String, epoch: int, prewarm_requested: bool = false) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_error.call_deferred("RenderingDevice unavailable: the original MLS-MPM requires an RD renderer and graphics context.", epoch)
		return
	for stage in 9:
		var source := RDShaderSource.new()
		source.source_compute = "#version 450\n#define STAGE %d\n" % stage + code
		var spirv := _rd.shader_compile_spirv_from_source(source)
		var error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():
			_error.call_deferred(ENTRIES[stage] + ": " + error, epoch)
			return
		var shader := _rd.shader_create_from_spirv(spirv, "Original MLS-MPM " + ENTRIES[stage])
		_shaders.append(shader)
		_pipelines.append(_rd.compute_pipeline_create(shader))
	var frame_delay := int(_rd.get_frame_delay()) if _rd.has_method("get_frame_delay") else 0
	if prewarm_requested:
		_prewarm = preload("res://scripts/water/source_port/source_mpm_prewarm.gd").new()
		# Success AND failure defer exactly one guarded completion. Never also
		# finish from rd_start's return value or from an encoding acknowledgement.
		_prewarm.rd_start(_rd, _shaders, _pipelines, _prewarm_finished.bind(epoch, frame_delay))
	else:
		_finish_initialize.call_deferred(epoch, frame_delay)

func _finish_initialize(epoch: int, frame_delay: int = 0) -> void:
	if epoch != _epoch or _disposed:
		return
	if frame_delay > 0:
		_async_frame_delay = frame_delay
		_async_frame_delay_actual = true
	status = "ready"
	ready.emit()

func _error(message: String, epoch: int) -> void:
	if epoch != _epoch or _disposed:
		return
	if _prewarm_pending:
		_prewarm_pending = false
		_prewarm_report = {"state": "initialization_failed", "pass": false, "error": message}
	status = "unavailable"
	last_error = message
	failed.emit(message)
	for patch in _patches:
		_destroy_patch(patch)
	_patches.clear()
	_sources.clear()

func _rd_create_patch(id: int, raw: PackedByteArray, params: PackedByteArray, epoch: int, snapshot_slots: int = 1) -> void:
	if epoch != _epoch or _disposed or _rd == null or _pipelines.size() != 9:
		return
	var count := raw.size() / 80
	var zero_links := PackedByteArray()
	zero_links.resize((count + 1) * 4)
	zero_links.fill(0)
	var buffers: Array[RID] = [
		_rd.storage_buffer_create(raw.size(), raw),
		_rd.storage_buffer_create(GRID * 16),
		_rd.uniform_buffer_create(64, params),
		_rd.storage_buffer_create(raw.size()),
		_rd.storage_buffer_create(zero_links.size(), zero_links),
		_rd.storage_buffer_create(zero_links.size(), zero_links),
	]
	for buffer in buffers:
		if not buffer.is_valid():
			for allocated in buffers:
				if allocated.is_valid(): _rd.free_rid(allocated)
			_patch_failed.call_deferred(id, "MLS-MPM buffer allocation failed.", epoch)
			return
	var groups: Array[RID] = []
	for stage in 9:
		var uniforms: Array[RDUniform] = []
		for binding in BINDINGS[stage]:
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER if binding == 2 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(buffers[binding])
			uniforms.append(uniform)
		groups.append(_rd.uniform_set_create(uniforms, _shaders[stage], 0))
	var snapshot_buffers: Array[RID] = [buffers[3]]
	var snapshot_groups: Array[RID] = [groups[7]]
	for slot in range(1, snapshot_slots):
		var output := _rd.storage_buffer_create(raw.size())
		var uniforms: Array[RDUniform] = []
		for binding in BINDINGS[7]:
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER if binding == 2 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(output if binding == 3 else buffers[binding])
			uniforms.append(uniform)
		snapshot_buffers.append(output)
		snapshot_groups.append(_rd.uniform_set_create(uniforms, _shaders[7], 0))
	_gpu_patches[id] = {"count": count, "buffers": buffers, "groups": groups,
		"snapshot_buffers": snapshot_buffers, "snapshot_groups": snapshot_groups}
	var valid := true
	for group in groups:
		valid = valid and _rd.uniform_set_is_valid(group)
	for group in snapshot_groups:
		valid = valid and _rd.uniform_set_is_valid(group)
	for buffer in snapshot_buffers:
		valid = valid and buffer.is_valid()
	if not valid:
		_rd_destroy_patch(id)
		_patch_failed.call_deferred(id, "MLS-MPM snapshot allocation or binding failed.", epoch)

func _rd_step(id: int, steps: int, params: PackedByteArray, deletions: PackedByteArray, epoch: int, queued_usec: int = 0, sequence: int = 0, sample_age: float = -1.0, slot: int = -1, independent: bool = false) -> void:
	if epoch != _epoch or _disposed or not _gpu_patches.has(id):
		return
	var encode_started := Time.get_ticks_usec()
	if _gpu_timestamps != null: _gpu_timestamps.mark(_rd, "begin", {"domain": id, "steps": steps, "transfer_clear": transfer_grid_clear})
	var p: Dictionary = _gpu_patches[id]
	if steps < 1 or steps > 36 or (independent and (slot < -1 or slot >= p.snapshot_buffers.size())):
		_patch_failed.call_deferred(id, "MLS-MPM invalid queued batch or export slot.", epoch)
		return
	var buffers: Array[RID] = p.buffers
	# Godot disallows buffer_update while a compute list is active.
	_rd.buffer_update(buffers[2], 0, 64, params)
	var removed := deletions.decode_u32(0)
	if removed > 0:
		_rd.buffer_update(buffers[5], 0, deletions.size(), deletions)
	var export_slot := slot if independent else 0
	_rd_encode_steps(p, steps, int(removed), transfer_grid_clear, export_slot)
	if _gpu_timestamps != null: _gpu_timestamps.mark(_rd, "end")
	if export_slot >= 0:
		var result := _rd.buffer_get_data_async(p.snapshot_buffers[export_slot], _rd_received.bind(id, epoch, sequence, sample_age, slot, queued_usec), 0, int(p.count) * 80)
		if result != OK:
			_patch_failed.call_deferred(id, "MLS-MPM readback request failed: %d" % result, epoch)
	if independent:
		_batch_encoded.call_deferred(id, epoch)
	_record_submission.call_deferred(float(Time.get_ticks_usec() - encode_started) / 1000.0, float(encode_started - queued_usec) / 1000.0 if queued_usec > 0 else 0.0, epoch)

## Render-thread only. Clear exactly GRID * 16 bytes, the same four zero
## uints written by source stage 0. Godot tracks transfer/compute dependencies;
## buffer_clear must be outside a compute list. All other dispatches/barriers
## and their order are unchanged. No host staging buffer or GPU readback added.
func _rd_encode_steps(p: Dictionary, steps: int, removed: int, transfer: bool, export_slot: int = 0) -> void:
	var groups: Array[RID] = p.groups
	var particles := ceili(float(p.count) / 64.0)
	var list := -1
	if not transfer or removed > 0:
		list = _rd.compute_list_begin()
	if removed > 0:
		_dispatch(list, 8, groups[8], ceili(float(removed) / 64.0))
		if transfer:
			_rd.compute_list_end()
	for _step in steps:
		var cleared := false
		if transfer:
			cleared = _rd.buffer_clear(p.buffers[1], 0, GRID * 16) == OK
			if not cleared:
				_grid_clear_fallbacks += 1
			list = _rd.compute_list_begin()
		if not cleared:
			_dispatch(list, 0, groups[0], GRID / 128)
		for stage in range(1, 5):
			_dispatch(list, stage, groups[stage], GRID / 128 if stage == 3 else particles)
		if transfer:
			_rd.compute_list_end()
	if export_slot >= 0:
		if transfer:
			list = _rd.compute_list_begin()
		for stage in range(5, 8):
			var group: RID = p.snapshot_groups[export_slot] if stage == 7 else groups[stage]
			_dispatch(list, stage, group, GRID / 128 if stage == 5 else particles)
	if not transfer or export_slot >= 0:
		_rd.compute_list_end()

func _record_submission(encode_ms: float, queue_ms: float, epoch: int) -> void:
	if epoch != _epoch or _disposed:
		return
	_render_encode_ms = encode_ms
	_render_encode_max_ms = maxf(_render_encode_max_ms, encode_ms)
	_render_queue_ms = queue_ms

func _dispatch(list: int, stage: int, group: RID, count: int) -> void:
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[stage])
	_rd.compute_list_bind_uniform_set(list, group, 0)
	_rd.compute_list_dispatch(list, count, 1, 1)
	_rd.compute_list_add_barrier(list)

func _rd_received(bytes: PackedByteArray, id: int, epoch: int, sequence: int = 0, sample_age: float = -1.0, slot: int = -1, queued_usec: int = 0) -> void:
	_snapshot_copied.call_deferred(id, epoch, sequence, sample_age, slot, bytes.size(), Time.get_ticks_usec())
	_receive.call_deferred(bytes, id, epoch, sequence, sample_age, slot, queued_usec)

func _receive(bytes: PackedByteArray, id: int, epoch: int, sequence: int = 0, sample_age: float = -1.0, slot: int = -1, queued_usec: int = 0) -> void:
	if epoch != _epoch or _disposed:
		return
	for p in _patches:
		if int(p.id) != id or bool(p.disposed):
			continue
		var independent := bool(p.get("independent", independent_scheduling))
		var request: Dictionary = {}
		if independent:
			# Match ownership before releasing a slot, even for late duplicates.
			# An older callback must never release a slot reused by a newer copy.
			if not p.has("snapshot_requests") or not p.snapshot_requests.has(sequence):
				_snapshots_stale += 1
				return
			request = p.snapshot_requests[sequence]
			if int(request.slot) != slot or not is_equal_approx(float(request.age), sample_age):
				_patch_failed(id, "MLS-MPM readback ownership mismatch.", epoch)
				return
			p.snapshot_requests.erase(sequence)
			p.pending = not p.snapshot_requests.is_empty()
			if sequence <= int(p.published_snapshot):
				_snapshots_stale += 1
				return
		if bytes.size() != int(p.count) * 80:
			_patch_failed(id, "MLS-MPM readback byte count mismatch.", epoch)
			return
		var submitted := int(request.queued_usec) if independent else int(p.get("submitted_usec", queued_usec))
		if submitted > 0:
			_readback_latency_ms = float(Time.get_ticks_usec() - submitted) / 1000.0
			_readback_latency_max_ms = maxf(_readback_latency_max_ms, _readback_latency_ms)
		var submitted_frame := int(request.frame) if independent else int(p.get("submitted_frame", _frame_serial))
		_readback_pending_max_frames = maxi(_readback_pending_max_frames, _frame_serial - submitted_frame)
		_snapshots_received += 1
		var published_age := float(request.age) if independent else float(p.age)
		if independent:
			var samples: Array = p.presentation_samples
			samples.append({"age": published_age, "data": bytes.to_float32_array()})
			# Preserve the actual interpolation bracket, not only its left
			# anchor. Replacing the right endpoint could shift a curved path
			# at an unchanged render_age. Drop only later interior samples;
			# never the newest (including the terminal) snapshot.
			while samples.size() > MAX_PRESENTATION_SAMPLES:
				var left := -1
				var right := -1
				for i in samples.size():
					if float(samples[i].age) <= float(p.render_age):
						left = i
					else:
						right = i
						break
				if left < 0 or right < 0 or right + 1 >= samples.size() - 1:
					_patch_failed(id, "MLS-MPM invalid presentation bracket; refusing unsafe pruning.", epoch)
					return
				samples.remove_at(right + 1)
				_presentation_samples_pruned += 1
			p.presentation_samples = samples
			p.published_snapshot = sequence
			p.sample_steps = int(request.steps)
		else:
			p.previous = p.data
			p.data = bytes.to_float32_array()
			p.sample_delta = maxf(STEP, published_age - float(p.sample_age))
			p.blend_elapsed = 0.0
			p.pending = false
		p.sample_age = published_age
		# Removed/emerged masks and queued deletions are monotonic CPU state;
		# never overwrite them from an old GPU snapshot (no resurrection).
		snapshot_updated.emit()
		return

func _patch_failed(id: int, message: String, epoch: int) -> void:
	if epoch != _epoch or _disposed:
		return
	last_error = message
	for p in _patches:
		if int(p.id) == id:
			_destroy_patch(p)
	failed.emit(message)

func _rd_destroy_patch(id: int) -> void:
	if not _gpu_patches.has(id):
		return
	var p: Dictionary = _gpu_patches[id]
	for group: RID in p.groups:
		if _rd.uniform_set_is_valid(group):
			_rd.free_rid(group)
	for slot in range(1, p.snapshot_groups.size()):
		if _rd.uniform_set_is_valid(p.snapshot_groups[slot]):
			_rd.free_rid(p.snapshot_groups[slot])
		if p.snapshot_buffers[slot].is_valid(): _rd.free_rid(p.snapshot_buffers[slot])
	for buffer: RID in p.buffers:
		if buffer.is_valid(): _rd.free_rid(buffer)
	_gpu_patches.erase(id)

func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if _prewarm_pending: _prewarm_report = {"state": "cancelled", "pass": false}
	_prewarm_pending = false
	_native_particle_gate = null
	if _gpu_timestamps != null: _gpu_timestamps.dispose()
	_epoch += 1
	_sources.clear()
	_patches.clear()
	instance_rows.clear()
	visible_count = 0
	RenderingServer.call_on_render_thread(_rd_dispose)

func _rd_dispose() -> void:
	# Cancel isolated work before freeing the borrowed live pipelines/shaders.
	if _prewarm != null:
		_prewarm.rd_cancel()
		_prewarm = null
	for id in _gpu_patches.keys():
		_rd_destroy_patch(int(id))
	if _rd != null:
		for pipeline in _pipelines:
			_rd.free_rid(pipeline)
		for shader in _shaders:
			_rd.free_rid(shader)
	_pipelines.clear()
	_shaders.clear()

## Three SphereGeometry topology, preserving original tessellation and winding.
static func sphere_geometry(width_segments: int, height_segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for iy in height_segments + 1:
		var v := float(iy) / height_segments
		for ix in width_segments + 1:
			var u := float(ix) / width_segments
			var vertex := Vector3(-cos(u * TAU) * sin(v * PI), cos(v * PI), sin(u * TAU) * sin(v * PI))
			vertices.append(vertex)
			normals.append(vertex.normalized())
	for iy in height_segments:
		for ix in width_segments:
			var a := iy * (width_segments + 1) + ix + 1
			var b := iy * (width_segments + 1) + ix
			var c := (iy + 1) * (width_segments + 1) + ix
			var d := (iy + 1) * (width_segments + 1) + ix + 1
			if iy != 0:
				indices.append_array(PackedInt32Array([a, b, d]))
			if iy != height_segments - 1:
				indices.append_array(PackedInt32Array([b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Main-thread adapter for the production nine-tap optical height callback.
## Caller MUST refresh once before each particle frame, after terrain/field or
## settings changes. Packed arrays are shared current field references, never
## duplicate grids or temporally cached sample values. Nothing approximated:
## every original tap, wet/dry test, Float32 Vector2 rounding and lerp remains.
class OpticalFieldSampler extends RefCounted:
	const EAST=Vector2(.22,0)
	const WEST=Vector2(-.22,0)
	const NORTH=Vector2(0,.22)
	const SOUTH=Vector2(0,-.22)
	const NE=Vector2(.16,.16)
	const SW=Vector2(-.16,-.16)
	const NW=Vector2(-.16,.16)
	const SE=Vector2(.16,-.16)
	var heights:=PackedFloat32Array()
	var depths:=PackedFloat32Array()
	var half_domain:=48.0
	var depth_cell:=.125
	var width:=768
	var physics_cell:=.25
	var physics_width:=384
	var physics_last:=382
	var simulation:=true
	var gain:=1.0
	var level:=.32
	func refresh(solver:RefCounted,on:bool,wave_height:float,water_level:float=.32)->void:
		heights=solver.physics_eta
		depths=solver._depth
		half_domain=float(solver.domain)*.5
		depth_cell=solver.cell
		width=solver.size
		physics_width=solver.physics_size
		physics_last=physics_width-2
		physics_cell=float(solver.domain)/physics_width
		simulation=on
		gain=wave_height
		level=water_level
	func surface_at(x:float,z:float)->float:
		if not simulation:return level
		var p:=Vector2(x,z)
		var sum:=4.0*_height(p)
		sum+=2.0*_height(p+EAST)
		sum+=2.0*_height(p+WEST)
		sum+=2.0*_height(p+NORTH)
		sum+=2.0*_height(p+SOUTH)
		sum+=_height(p+NE)
		sum+=_height(p+SW)
		sum+=_height(p+NW)
		sum+=_height(p+SE)
		return level+sum/16.0*gain
	func depth_at(x:float,z:float)->float:
		var p:=Vector2(x,z)
		var ix:=floori((float(p.x)+half_domain)/depth_cell)
		var iz:=floori((float(p.y)+half_domain)/depth_cell)
		return depths[ix+iz*width] if ix>=0 and iz>=0 and ix<width and iz<width and not depths.is_empty() else 0.0
	func _height(p:Vector2)->float:
		var x:=float(p.x)
		var z:=float(p.y)
		var dx:=floori((x+half_domain)/depth_cell)
		var dz:=floori((z+half_domain)/depth_cell)
		if dx<0 or dz<0 or dx>=width or dz>=width or depths.is_empty() or depths[dx+dz*width]<=0.0:return 0.0
		var gx:=(x+half_domain)/physics_cell-.5
		var gz:=(z+half_domain)/physics_cell-.5
		var ix:=clampi(floori(gx),0,physics_last)
		var iz:=clampi(floori(gz),0,physics_last)
		var fx:=clampf(gx-ix,0.0,1.0)
		var fz:=clampf(gz-iz,0.0,1.0)
		var i:=ix+iz*physics_width
		return lerpf(lerpf(heights[i],heights[i+1],fx),lerpf(heights[i+physics_width],heights[i+physics_width+1],fx),fz)
