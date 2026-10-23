class_name SourceRoomProbe
extends Node
## Source six-face, 1024-square linear HDR capture with immutable per-room caching.
## GPU capture is opt-in until actual-room validation. Unsupported devices use
## the existing global-RD asynchronous readback, never ViewportTexture.get_image().
## CPU mip generation runs only on private worker-owned Images. These ordinary
## mipmaps preserve the existing port, and are NOT Three's GGX PMREM convolution.
signal completed(texture: TextureLayered)
var texture: TextureLayered
var resolution := 1024
var cache_capacity := 6
var last_error := ""
# Change the default only after native actual-room and lifetime acceptance.
var gpu_capture_enabled := OS.get_cmdline_user_args().has("--source-gpu-room-cube")
const GpuCubeDevice = preload("res://scripts/water/source_port/source_gpu_room_cube_device.gd")
const GpuCubeGate = preload("res://scripts/water/source_port/source_gpu_room_cube_ticket.gd")
var _gpu_gate := GpuCubeGate.new()
var _gpu_worker: RefCounted
var _gpu_ticket: RefCounted
var _gpu_attempted := false
var _gpu_disabled_reason := ""
var _gpu_state := "idle"
var _gpu_generation := -1
var _gpu_key := Vector3.ZERO
var _gpu_revision := -1
var _gpu_draw_sequence := 0
var _gpu_inspect_after_frame := -1
var _gpu_stage_started_usec := 0
var _gpu_stats := {"captures_completed": 0, "faces_copied": 0, "fallbacks": 0,
	"stale_events_rejected": 0, "last_mip_encode_ms": 0.0, "last_failure": ""}
var _viewport: SubViewport
var _camera: Camera3D
var _source_environment: Environment
var _cache: Dictionary = {}
var _cache_clock := 0
var _lighting_revision := 0
var _generation := 0
var _disposed := false
var _requested_key := Vector3(INF, INF, INF)
var _requested_revision := -1
var _position := Vector3(0, 3.4, 0)
var _index := -1
var _pending := false
var _readback: FaceReadback
var _last_readback_watchdog: Dictionary = {}
var _raw_faces: Array[Dictionary] = []
var _mip_job: MipJob
var _retired_jobs: Array[MipJob] = []
var _capture_started_usec := 0
var _counters := {"requests": 0, "deduplicated": 0, "cache_hits": 0,
	"cache_misses": 0, "captures_started": 0, "captures_completed": 0,
	"captures_cancelled": 0, "faces_read": 0, "cache_evictions": 0,
	"lighting_invalidations": 0, "room_invalidations": 0, "errors": 0}
var _timings := {"last_capture_ms": 0.0, "last_readback_ms": 0.0,
	"max_readback_ms": 0.0, "last_mip_worker_ms": 0.0,
	"last_upload_ms": 0.0, "max_upload_ms": 0.0,
	"last_update_ms": 0.0, "max_update_ms": 0.0,
	"last_capture_callback_ms": 0.0, "max_capture_callback_ms": 0.0}
const DIRECTIONS = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const UPS = [Vector3.DOWN, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD, Vector3.DOWN, Vector3.DOWN]
const READBACK_TIMEOUT_USEC := 30000000
const READBACK_HARD_TIMEOUT_USEC := 120000000
const READBACK_FRAME_MARGIN := 2

## No Node or scene-tree access from the render-thread callback. The queued
## callable owns this ticket even if its probe/viewport is disposed meanwhile.
class FaceReadback extends RefCounted:
	var mutex := Mutex.new()
	var result: Dictionary = {}
	var cancelled := false
	var started_usec := Time.get_ticks_usec()
	var submitted_usec := -1
	var submitted_draw_frame := -1
	var frame_delay := -1

	func mark_submitted(now_usec: int, drawn_frame: int, delay: int) -> void:
		mutex.lock()
		submitted_usec = now_usec
		submitted_draw_frame = drawn_frame
		frame_delay = maxi(1, delay)
		mutex.unlock()

	func watchdog_state(now_usec: int, drawn_frame: int) -> Dictionary:
		mutex.lock()
		var age := maxi(0, now_usec - started_usec)
		var submitted := submitted_draw_frame >= 0
		var submission_age := maxi(0, now_usec - submitted_usec) if submitted else 0
		var elapsed_frames := maxi(0, drawn_frame - submitted_draw_frame) if submitted else 0
		var required_frames := frame_delay + READBACK_FRAME_MARGIN if submitted else -1
		# Global-RD callbacks are retired when their frame slot is reused. A
		# slow but progressing renderer must first get that many drawn frames,
		# plus the render/main callback-boundary allowance, before the soft
		# wall deadline can classify a missing callback. An independent hard
		# bound still handles stopped rendering or a never-submitted ticket.
		var reason := ""
		if not cancelled and result.is_empty():
			if age > READBACK_HARD_TIMEOUT_USEC:
				reason = "hard_ticket_deadline"
			elif submitted and submission_age > READBACK_TIMEOUT_USEC and elapsed_frames >= required_frames:
				reason = "delivery_window_exhausted"
		var value := {"timed_out":not reason.is_empty(), "reason":reason,
			"age_ms":float(age)/1000.0, "submission_age_ms":float(submission_age)/1000.0,
			"submitted":submitted, "frames_since_submission":elapsed_frames,
			"frame_delay":frame_delay, "required_drawn_frames":required_frames,
			"soft_timeout_ms":READBACK_TIMEOUT_USEC/1000, "hard_timeout_ms":READBACK_HARD_TIMEOUT_USEC/1000}
		mutex.unlock()
		return value

	func cancel() -> void:
		mutex.lock()
		cancelled = true
		result.clear()
		mutex.unlock()

	func take_result() -> Dictionary:
		mutex.lock()
		var value := result
		result = {}
		mutex.unlock()
		return value

	func finish(value: Dictionary) -> void:
		mutex.lock()
		if not cancelled:
			result = value
		mutex.unlock()

	func queue_on_render_thread(server_texture: RID, expected_size: int) -> void:
		mutex.lock()
		var obsolete := cancelled
		mutex.unlock()
		if obsolete:
			return
		var rd := RenderingServer.get_rendering_device()
		if rd == null:
			finish({"error": "Room probes require Forward+/Mobile RenderingDevice; no synchronous fallback."})
			return
		var rid := RenderingServer.texture_get_rd_texture(server_texture, false)
		if not rid.is_valid() or not rd.texture_is_valid(rid):
			finish({"error": "Room probe viewport has no valid RD texture."})
			return
		var format := rd.texture_get_format(rid)
		var image_format := -1
		var bytes_per_pixel := 0
		match format.format:
			RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
				image_format = Image.FORMAT_RGBAH
				bytes_per_pixel = 8
			RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
				image_format = Image.FORMAT_RGBAF
				bytes_per_pixel = 16
		if image_format < 0:
			finish({"error": "Unsupported room-probe HDR format: %s; refusing lossy conversion." % format.format})
			return
		if format.width != expected_size or format.height != expected_size or format.samples != RenderingDevice.TEXTURE_SAMPLES_1:
			finish({"error": "Room-probe RD texture has unexpected dimensions or multisampling."})
			return
		if not (format.usage_bits & RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT):
			finish({"error": "Room-probe RD texture cannot be asynchronously copied."})
			return
		var output_format := RenderingServer.texture_get_format(server_texture)
		if output_format not in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]:
			finish({"error": "Room-probe logical texture format is not HDR."})
			return
		mark_submitted(Time.get_ticks_usec(), Engine.get_frames_drawn(), rd.get_frame_delay())
		var error := rd.texture_get_data_async(rid, 0, receive.bind(expected_size, image_format, bytes_per_pixel, output_format))
		if error != OK:
			finish({"error": "Room-probe async readback failed: %s" % error})

	func receive(bytes: PackedByteArray, size: int, image_format: int, bytes_per_pixel: int, output_format: int = -1) -> void:
		var expected_bytes := size * size * bytes_per_pixel
		if bytes.size() < expected_bytes:
			finish({"error": "Room-probe async readback returned incomplete face data."})
			return
		finish({"bytes": bytes, "size": size, "format": image_format,
			"output_format": image_format if output_format < 0 else output_format,
			"base_bytes": expected_bytes, "readback_ms": (Time.get_ticks_usec() - started_usec) / 1000.0})

## Only this worker mutates its Images. The main thread reads output after the
## task is complete and reaped, and no worker ever accesses the live scene tree.
class MipJob extends RefCounted:
	var faces: Array[Dictionary] = []
	var images: Array[Image] = []
	var task_id := -1
	var generation := -1
	var revision := -1
	var key := Vector3.ZERO
	var elapsed_ms := 0.0
	var error := ""

	func build() -> void:
		var started := Time.get_ticks_usec()
		for face in faces:
			var bytes: PackedByteArray = face.bytes
			# A viewport may contain extra mips; reproduce the old base-face
			# generate_mipmaps() path rather than trusting its unspecified mips.
			if bytes.size() != int(face.base_bytes):
				bytes = bytes.slice(0, int(face.base_bytes))
			var image := Image.create_from_data(face.size, face.size, false, face.format, bytes)
			if image == null or image.is_empty():
				error = "Unable to decode room-probe HDR face."
				break
			# ViewportTexture.get_image() performs this logical-format conversion
			# too (opaque HDR targets are RGBH backed by RGBAH GPU storage).
			var output_format: int = face.get("output_format", face.format)
			if image.get_format() != output_format:
				image.convert(output_format)
			var result := image.generate_mipmaps()
			if result != OK:
				error = "Unable to generate room-probe mipmaps: %s" % result
				break
			images.append(image)
		faces.clear()
		elapsed_ms = (Time.get_ticks_usec() - started) / 1000.0

func configure(source: Camera3D, environment: Environment) -> void:
	if is_instance_valid(_viewport):
		dispose()
	_disposed = false
	_gpu_disabled_reason = ""
	_source_environment = environment
	_viewport = SubViewport.new()
	_viewport.name = "SourceRoomCubemapFace"
	_viewport.size = Vector2i(resolution, resolution)
	_viewport.use_hdr_2d = true
	_viewport.world_3d = source.get_world_3d()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.cull_mask = 1
	_camera.current = true
	_camera.fov = 90
	_camera.near = 0.1
	_camera.far = 65
	_viewport.add_child(_camera)
	_copy_capture_environment()
	if not RenderingServer.frame_post_draw.is_connected(_capture_completed):
		RenderingServer.frame_post_draw.connect(_capture_completed)

func _copy_capture_environment() -> void:
	if not is_instance_valid(_camera) or _source_environment == null:
		return
	var capture: Environment = _source_environment.duplicate(true)
	capture.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	capture.tonemap_exposure = 1.0
	capture.glow_enabled = false
	capture.adjustment_enabled = false
	_camera.environment = capture

## Explicit invalidation, not a per-request helper. All environment properties
## are refreshed, not just GI flags; callers request the active origin afterward.
## Stop superseded work without invalidating an already published cube/cache.
## The runtime uses this while its next terrain domain is not yet committed.
## A later request restarts cancelled faces; no partial cubemap is published.
func cancel_pending_capture() -> bool:
	if _index < 0 and not _pending and _readback == null and _mip_job == null and _gpu_worker == null:
		return false
	_cancel_capture()
	return true

func refresh_lighting() -> void:
	_lighting_revision += 1
	_counters.lighting_invalidations += 1
	_cache.clear()
	_cancel_capture()
	_requested_revision = -1
	_copy_capture_environment()
	_clear_texture()

## Use when geometry/fixtures at an already known room origin actually change.
func invalidate_room(origin: Vector2) -> void:
	_counters.room_invalidations += 1
	for key: Vector3 in _cache.keys():
		if Vector2(key.x, key.y) == origin:
			_cache.erase(key)
	if Vector2(_requested_key.x, _requested_key.y) == origin:
		_cancel_capture()
		_requested_revision = -1
		_clear_texture()

func request(origin: Vector2) -> void:
	if _disposed or not origin.is_finite():
		return
	_counters.requests += 1
	var key := Vector3(origin.x, origin.y, float(resolution))
	if key == _requested_key and _requested_revision == _lighting_revision and (texture != null or _index >= 0 or _mip_job != null):
		_counters.deduplicated += 1
		return
	_cancel_capture()
	_requested_key = key
	_requested_revision = _lighting_revision
	_position = Vector3(origin.x, 3.4, origin.y)
	last_error = ""
	_last_readback_watchdog = {}
	if _cache.has(key):
		var entry: Dictionary = _cache[key]
		if int(entry.revision) == _lighting_revision:
			_cache_clock += 1
			entry.stamp = _cache_clock
			texture = entry.texture
			_counters.cache_hits += 1
			completed.emit(texture)
			return
	_counters.cache_misses += 1
	_counters.captures_started += 1
	_capture_started_usec = Time.get_ticks_usec()
	_gpu_attempted = false
	_clear_texture()
	_index = 0
	if is_instance_valid(_viewport):
		_viewport.size = Vector2i(resolution, resolution)

func update() -> void:
	var started := Time.get_ticks_usec()
	_reap_retired_jobs()
	_advance_capture()
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	_timings.last_update_ms = elapsed
	_timings.max_update_ms = maxf(_timings.max_update_ms, elapsed)

func _advance_capture() -> void:
	if _disposed or not is_instance_valid(_viewport):
		return
	if _gpu_worker != null:
		_advance_gpu_capture()
		return
	if _index == 0 and gpu_capture_enabled and not _gpu_attempted and _gpu_disabled_reason.is_empty():
		_begin_gpu_capture()
		return
	if _mip_job != null:
		if WorkerThreadPool.is_task_completed(_mip_job.task_id):
			_finish_mip_job()
		return
	if _readback != null:
		var result := _readback.take_result()
		if result.is_empty():
			_last_readback_watchdog = _readback.watchdog_state(Time.get_ticks_usec(), Engine.get_frames_drawn())
			if _last_readback_watchdog.timed_out:
				_fail("Room-probe asynchronous readback timed out: %s" % JSON.stringify(_last_readback_watchdog))
			return
		_readback = null
		if result.has("error"):
			_fail(result.error)
			return
		_raw_faces.append(result)
		_counters.faces_read += 1
		_timings.last_readback_ms = result.readback_ms
		_timings.max_readback_ms = maxf(_timings.max_readback_ms, result.readback_ms)
		_index += 1
		if _index == 6:
			_mip_job = MipJob.new()
			_mip_job.faces = _raw_faces
			_raw_faces = []
			_mip_job.generation = _generation
			_mip_job.revision = _lighting_revision
			_mip_job.key = _requested_key
			_mip_job.task_id = WorkerThreadPool.add_task(_mip_job.build, false, "Room probe HDR mip chain")
			_index = -1
			return
	if _pending or _index < 0 or _index >= 6:
		return
	_camera.global_position = _position
	_camera.look_at(_position + DIRECTIONS[_index], UPS[_index])
	_pending = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _capture_completed() -> void:
	if not _pending or _disposed or not is_instance_valid(_viewport):
		return
	var started := Time.get_ticks_usec()
	_pending = false
	if _gpu_worker != null:
		_gpu_state = "copy_pending"
		_gpu_stage_started_usec = Time.get_ticks_usec()
		RenderingServer.call_on_render_thread(_gpu_worker.copy_viewport.bind(_gpu_ticket))
	else:
		_readback = FaceReadback.new()
		RenderingServer.call_on_render_thread(_readback.queue_on_render_thread.bind(_viewport.get_texture().get_rid(), resolution))
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	_timings.last_capture_callback_ms = elapsed
	_timings.max_capture_callback_ms = maxf(_timings.max_capture_callback_ms, elapsed)

func _finish_mip_job() -> void:
	var job := _mip_job
	_mip_job = null
	# This is nonblocking: the caller has already checked is_task_completed().
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	job.task_id = -1
	if job.generation != _generation or job.revision != _lighting_revision or job.key != _requested_key or _disposed:
		return
	_timings.last_mip_worker_ms = job.elapsed_ms
	if not job.error.is_empty() or job.images.size() != 6:
		_fail(job.error if not job.error.is_empty() else "Incomplete room-probe mip chain.")
		return
	# Only final GPU upload/resource publication remains on the main thread.
	# Do not claim this removes rendering/transfer bandwidth or all frame costs.
	var started := Time.get_ticks_usec()
	var candidate := Cubemap.new()
	var error := candidate.create_from_images(job.images)
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	_timings.last_upload_ms = elapsed
	_timings.max_upload_ms = maxf(_timings.max_upload_ms, elapsed)
	if error != OK:
		_fail("Room cubemap creation failed: %s" % error)
		return
	_publish_texture(candidate, job.key, job.revision)

func _publish_texture(candidate: TextureLayered, key: Vector3, revision: int) -> void:
	texture = candidate
	_cache_clock += 1
	_cache[key] = {"texture": candidate, "revision": revision, "stamp": _cache_clock}
	_trim_cache()
	_counters.captures_completed += 1
	_timings.last_capture_ms = (Time.get_ticks_usec() - _capture_started_usec) / 1000.0
	completed.emit(texture)

func _begin_gpu_capture() -> void:
	_gpu_attempted = true
	_gpu_generation = _generation
	_gpu_revision = _lighting_revision
	_gpu_key = _requested_key
	_gpu_gate.begin(str(_gpu_key), _gpu_revision, _viewport.get_texture().get_rid().get_id())
	_gpu_worker = GpuCubeDevice.new()
	_gpu_worker.configure(_gpu_gate, _viewport.get_texture().get_rid())
	_gpu_state = "allocating"
	_gpu_stage_started_usec = Time.get_ticks_usec()
	RenderingServer.call_on_render_thread(_gpu_worker.allocate.bind(resolution))

func _advance_gpu_capture() -> void:
	for event in _gpu_worker.take_events():
		if _gpu_generation != _generation or _gpu_revision != _lighting_revision or _gpu_key != _requested_key:
			_gpu_stats.stale_events_rejected += 1
			continue
		var value: Dictionary = event.value
		match String(event.kind):
			"error":
				_fallback_gpu_capture(String(value.reason))
				return
			"allocated":
				_gpu_state = "capture"
			"copy_ack":
				if not _gpu_gate.accept_copy_ack(value.ticket):
					_gpu_stats.stale_events_rejected += 1
					continue
				_gpu_stats.faces_copied += 1
				_index += 1
				_gpu_state = "capture"
				if _index == 6:
					_gpu_state = "mips"
					RenderingServer.call_on_render_thread(_gpu_worker.encode_mips.bind(_gpu_ticket))
			"mips_encoded":
				_gpu_stats.last_mip_encode_ms = float(value.encoding_usec) / 1000.0
				_gpu_state = "wrapper"
				RenderingServer.call_on_render_thread(_gpu_worker.initialize_wrapper.bind(_gpu_ticket))
			"wrapper_queued":
				_gpu_state = "wrapper_wait"
				_gpu_inspect_after_frame = Engine.get_frames_drawn() + 1
			"ready":
				if not _gpu_gate.is_current(value.ticket):
					_gpu_stats.stale_events_rejected += 1
					continue
				var candidate: TextureLayered = value.texture
				_index = -1
				_gpu_stats.captures_completed += 1
				_stop_gpu_capture("immutable cube published")
				_publish_texture(candidate, _requested_key, _lighting_revision)
				return
		_gpu_stage_started_usec = Time.get_ticks_usec()
	if _gpu_state == "wrapper_wait" and Engine.get_frames_drawn() >= _gpu_inspect_after_frame:
		_gpu_state = "inspect"
		RenderingServer.call_on_render_thread(_gpu_worker.inspect_wrapper.bind(_gpu_ticket))
	if Time.get_ticks_usec() - _gpu_stage_started_usec > READBACK_HARD_TIMEOUT_USEC:
		_fallback_gpu_capture("GPU copy/publication ticket stopped progressing")
		return
	if _gpu_state != "capture" or _pending or _index < 0 or _index >= 6:
		return
	_gpu_draw_sequence += 1
	_gpu_ticket = _gpu_gate.issue(_index, _gpu_draw_sequence)
	if _gpu_ticket == null:
		_fallback_gpu_capture("Unable to issue ordered GPU room face")
		return
	_camera.global_position = _position
	_camera.look_at(_position + DIRECTIONS[_index], UPS[_index])
	_pending = true
	_gpu_state = "draw_pending"
	_gpu_stage_started_usec = Time.get_ticks_usec()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _stop_gpu_capture(reason: String) -> void:
	_gpu_gate.cancel(reason)
	if _gpu_worker != null:
		RenderingServer.call_on_render_thread(_gpu_worker.dispose)
	_gpu_worker = null
	_gpu_ticket = null
	_gpu_state = "idle"

func _fallback_gpu_capture(reason: String) -> void:
	# Restart all faces via the unchanged asynchronous CPU path. Never publish
	# a mixture of GPU/CPU faces, reduce precision, or read synchronously.
	_gpu_stats.fallbacks += 1
	_gpu_stats.last_failure = reason
	_gpu_disabled_reason = reason
	_stop_gpu_capture("GPU unsupported; restart exact async CPU capture")
	_generation += 1
	_pending = false
	_raw_faces.clear()
	_index = 0
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _trim_cache() -> void:
	while _cache.size() > maxi(1, cache_capacity):
		var oldest_key: Vector3 = _cache.keys()[0]
		var oldest_stamp: int = _cache[oldest_key].stamp
		for key: Vector3 in _cache:
			if int(_cache[key].stamp) < oldest_stamp:
				oldest_key = key
				oldest_stamp = _cache[key].stamp
		_cache.erase(oldest_key)
		_counters.cache_evictions += 1

func _clear_texture() -> void:
	if texture != null:
		texture = null
		completed.emit(null)

func _cancel_capture() -> void:
	if _index >= 0 or _mip_job != null or _readback != null or _pending or _gpu_worker != null:
		_counters.captures_cancelled += 1
	_stop_gpu_capture("capture cancelled or replaced")
	_generation += 1
	_index = -1
	_pending = false
	_raw_faces.clear()
	if _readback != null:
		_readback.cancel()
		_readback = null
	if _mip_job != null:
		_retired_jobs.append(_mip_job)
		_mip_job = null
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _reap_retired_jobs() -> void:
	for i in range(_retired_jobs.size() - 1, -1, -1):
		var job := _retired_jobs[i]
		if WorkerThreadPool.is_task_completed(job.task_id):
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			job.task_id = -1
			_retired_jobs.remove_at(i)

func _fail(reason: String) -> void:
	last_error = reason
	_counters.errors += 1
	_cancel_capture()
	push_error(reason)

func diagnostics() -> Dictionary:
	var result := _counters.duplicate()
	result.merge(_timings)
	result.merge({"resolution": resolution, "cache_entries": _cache.size(),
		"cache_capacity": cache_capacity, "lighting_revision": _lighting_revision,
		"generation": _generation, "face_index": _index, "draw_pending": _pending,
		"readback_pending": _readback != null, "mip_pending": _mip_job != null,
		"readback_watchdog": _last_readback_watchdog if _readback == null else _readback.watchdog_state(Time.get_ticks_usec(), Engine.get_frames_drawn()),
		"retired_workers": _retired_jobs.size(), "texture_ready": texture != null,
		"synchronous_readbacks": 0, "main_thread_mip_generations": 0,
		"last_error": last_error, "gpu_capture_enabled": gpu_capture_enabled,
		"gpu_capture_pending": _gpu_worker != null, "gpu_state": _gpu_state,
		"gpu_disabled_reason": _gpu_disabled_reason, "gpu_stats": _gpu_stats.duplicate(),
		"texture_backend": "gpu_copy" if texture is TextureCubemapRD else "cpu_async" if texture != null else "none"})
	return result

func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_cancel_capture()
	# Shutdown only: reap every CPU job, never wait for GPU readback. Tickets
	# retained by RD callbacks are isolated RefCounteds and cannot touch this Node.
	for job in _retired_jobs:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		job.task_id = -1
	_retired_jobs.clear()
	if RenderingServer.frame_post_draw.is_connected(_capture_completed):
		RenderingServer.frame_post_draw.disconnect(_capture_completed)
	if is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_camera = null
	_source_environment = null
	_cache.clear()
	texture = null
	_requested_key = Vector3(INF, INF, INF)
	_requested_revision = -1

func _exit_tree() -> void:
	dispose()
