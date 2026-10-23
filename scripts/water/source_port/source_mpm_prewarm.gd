extends RefCounted
## One-shot, render-thread-only execution of the ORIGINAL live MPM pipelines.
## Owns only temporary buffers/sets. No live domain, particles, presentation,
## deletion queue, event, solver clock, or production readback is involved.
## Count-zero still needs the entire grid and links[0]: gather increments it.
## A completed pass proves dispatch, NOT that every driver's JIT is exhausted.
const GRID := 80 * 80 * 80
const STEP := 1.0 / 720.0
const BINDINGS := [[1], [0, 1, 2], [0, 1, 2], [1, 2, 4], [0, 1, 2, 4], [1], [0, 1, 2, 4], [0, 1, 2, 3, 4], [0, 5]]
const BUFFER_BYTES := [80, GRID * 16, 64, 80, 4, 4]
const DISPATCH_GROUPS := [GRID / 128, 1, 1, GRID / 128, 1, GRID / 128, 1, 1, 1]
const TEMPORARY_BYTES := GRID * 16 + 232
const SENTINEL_BYTES := 4
var _rd: RenderingDevice
var _buffers: Array[RID] = []
var _groups: Array[RID] = []
var _completion := Callable()
var _state := "idle"
var _ticket := 0
var _started_usec := 0
var _report: Dictionary = {"state": "idle", "pass": false}

static func parameters() -> PackedByteArray:
	var values := PackedFloat32Array()
	values.resize(16); values.fill(0.0)
	values[1] = 0.02 # Finite positive metres/cell, even for guarded-out work.
	values[2] = STEP
	var result := values.to_byte_array()
	result.encode_u32(0, 0)
	return result

static func completion_verdict(state: String, ticket: int, current_ticket: int, bytes: PackedByteArray) -> String:
	if state != "pending" or ticket != current_ticket: return "stale"
	if bytes.size() != SENTINEL_BYTES: return "wrong_size"
	if bytes.decode_u32(0) != 1: return "wrong_counter"
	return "complete"

func rd_start(device: RenderingDevice, shaders: Array[RID], pipelines: Array[RID], completed: Callable, marker: Callable = Callable()) -> Error:
	## Must run on the global RD render thread, outside any open list.
	## completed(report) is deferred to the main thread; marker(label) is a
	## fixture-only render-thread hook at CLOSED list boundaries, normally empty.
	if _state != "idle": return ERR_ALREADY_IN_USE
	_state = "allocating"; _ticket += 1
	_started_usec = Time.get_ticks_usec()
	_completion = completed; _rd = device
	_report = {"state": _state, "pass": false, "particles": 0, "solver_steps": 0,
		"temporary_bytes": TEMPORARY_BYTES, "buffer_count": 6, "set_count": 9,
		"dispatches": 0, "dispatch_groups": DISPATCH_GROUPS.duplicate(),
		"sentinel_bytes": SENTINEL_BYTES, "sentinel_received": false,
		"stale_callbacks": 0,
		"resources_released": false, "borrowed_resources_freed": 0}
	if _rd == null or shaders.size() != 9 or pipelines.size() != 9:
		return _rd_fail("Expected initialized RD and all nine original shaders/pipelines.", ERR_INVALID_PARAMETER)
	for stage in 9:
		if not shaders[stage].is_valid() or not _rd.compute_pipeline_is_valid(pipelines[stage]):
			return _rd_fail("Invalid original pipeline at stage %d." % stage, ERR_INVALID_PARAMETER)
	for binding in BUFFER_BYTES.size():
		var size: int = BUFFER_BYTES[binding]
		var initial := PackedByteArray()
		# Stage 0 initializes EVERY grid cell before any other stage. Avoid a
		# redundant 8 MB host staging upload. All smaller buffers start valid.
		if binding != 1: initial.resize(size); initial.fill(0)
		if binding == 2: initial = parameters()
		var buffer: RID = _rd.uniform_buffer_create(size, initial) if binding == 2 else _rd.storage_buffer_create(size, initial)
		if not buffer.is_valid(): return _rd_fail("Temporary buffer allocation failed at binding %d." % binding, ERR_CANT_CREATE)
		_buffers.append(buffer)
	for stage in 9:
		var uniforms: Array[RDUniform] = []
		for binding in BINDINGS[stage]:
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER if binding == 2 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding; uniform.add_id(_buffers[binding]); uniforms.append(uniform)
		var group := _rd.uniform_set_create(uniforms, shaders[stage], 0)
		if not _rd.uniform_set_is_valid(group): return _rd_fail("Temporary uniform set allocation failed at stage %d." % stage, ERR_CANT_CREATE)
		_groups.append(group)
	_report.allocation_ms = float(Time.get_ticks_usec() - _started_usec) / 1000.0
	if marker.is_valid(): marker.call("begin")
	var encode_started := Time.get_ticks_usec()
	var list := _rd.compute_list_begin()
	for stage in 9:
		_rd.compute_list_bind_compute_pipeline(list, pipelines[stage])
		_rd.compute_list_bind_uniform_set(list, _groups[stage], 0)
		# Nonzero dispatch is deliberate even when p.count/deletions[0] == 0.
		_rd.compute_list_dispatch(list, DISPATCH_GROUPS[stage], 1, 1)
		_rd.compute_list_add_barrier(list)
		_report.dispatches += 1
	_rd.compute_list_end()
	_report.encode_ms = float(Time.get_ticks_usec() - encode_started) / 1000.0
	if marker.is_valid(): marker.call("end")
	_state = "pending"; _report.state = _state
	# Own callback, own storage, exactly four bytes. Godot invokes it after
	# that submission's fence, not merely after CPU command encoding.
	var error := _rd.buffer_get_data_async(_buffers[4], _on_sentinel.bind(_ticket), 0, SENTINEL_BYTES)
	if error != OK: return _rd_fail("Prewarm sentinel request failed: %d." % error, error)
	return OK

func _on_sentinel(bytes: PackedByteArray, ticket: int) -> void:
	# Do not rely on callback thread affinity. All RID retirement explicitly
	# goes through the render thread, including cancellation and late callbacks.
	RenderingServer.call_on_render_thread(_rd_complete.bind(bytes, ticket))

func _rd_complete(bytes: PackedByteArray, ticket: int) -> void:
	var verdict := completion_verdict(_state, ticket, _ticket, bytes)
	if verdict == "stale":
		_report.stale_callbacks = int(_report.get("stale_callbacks", 0)) + 1
		return
	_report.sentinel_received = true
	_report.sentinel_counter = bytes.decode_u32(0) if bytes.size() == SENTINEL_BYTES else -1
	if verdict != "complete":
		_rd_fail("Invalid prewarm completion: " + verdict, ERR_INVALID_DATA)
		return
	_state = "complete"; _report.pass = true; _report.state = _state
	_report.completion_wall_ms = float(Time.get_ticks_usec() - _started_usec) / 1000.0
	_rd_release_owned()
	_notify_completed()

func rd_cancel() -> void:
	## Render-thread-only, idempotent. Never claim completion on cancellation.
	## On exceptional/early retirement, Godot's free_rid queues actual driver
	## destruction in its frame ring AFTER submitted use; no manual sync needed.
	if _state in ["complete", "failed", "cancelled"]: return
	_state = "cancelled"; _ticket += 1; _completion = Callable()
	_report.state = _state; _report.pass = false
	_rd_release_owned()

func rd_diagnostics() -> Dictionary:
	## Render-thread-only. Publish copies via a deferred owner callback.
	return _report.duplicate(true)

func _rd_fail(reason: String, error: Error) -> Error:
	_state = "failed"; _ticket += 1
	_report.state = _state; _report.error = reason; _report.pass = false
	_rd_release_owned()
	_notify_completed()
	return error

func _rd_release_owned() -> void:
	if _rd != null:
		for group in _groups:
			if _rd.uniform_set_is_valid(group): _rd.free_rid(group)
		for buffer in _buffers:
			if buffer.is_valid(): _rd.free_rid(buffer)
	_groups.clear(); _buffers.clear()
	_report.resources_released = true
	_report.live_owned_buffers = 0; _report.live_owned_sets = 0
	_rd = null

func _notify_completed() -> void:
	var completed := _completion
	_completion = Callable()
	if completed.is_valid(): completed.call_deferred(_report.duplicate(true))
