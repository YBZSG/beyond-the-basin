extends RefCounted
## Optional asynchronous diagnostics, never an input to simulation or quality.
## Godot 4.6.3's Vulkan driver returns GPU nanoseconds and CPU microseconds.
## Mark only BETWEEN closed compute/draw lists. No sync or data readback here.
const MAX_PENDING := 128
const MAX_SAMPLES := 64
const EXPIRY_FRAMES := 32
var enabled := false
var _prefix := ""
var _stages := PackedStringArray()
var _sequence := 0
var _active_sequence := -1
var _pending: Dictionary = {}
var _samples: Array[Dictionary] = []
var _aggregate: Dictionary = {}
var _last_frame := -1
var _harvest_serial := 0
var _completed := 0
var _missing := 0
var _invalid := 0
var _dropped := 0
var _rd: RenderingDevice
var _published: Dictionary = {"enabled": true, "status": "awaiting_completed_queries", "completed_samples": 0}

func _init(label: String, stages: PackedStringArray) -> void:
	assert(stages.size() >= 2 and stages[0] == "begin" and stages[-1] == "end")
	_prefix = "source_water_gpu/%s_%d/" % [label, get_instance_id()]
	_stages = stages.duplicate()

func start() -> void:
	if enabled: return
	enabled = true
	if not RenderingServer.frame_post_draw.is_connected(_queue_collection):
		RenderingServer.frame_post_draw.connect(_queue_collection)

func dispose() -> void:
	enabled = false
	if RenderingServer.frame_post_draw.is_connected(_queue_collection):
		RenderingServer.frame_post_draw.disconnect(_queue_collection)

func diagnostics() -> Dictionary:
	var report := _published.duplicate(true)
	report.enabled = enabled
	return report

func mark(rd: RenderingDevice, stage: String, metadata: Dictionary = {}) -> void:
	## Render-thread only, at command-list boundaries. Disabled owners do not
	## construct this object, connect a frame hook, or call timestamp methods.
	if not enabled or rd == null: return
	_rd = rd
	if stage == "begin": _active_sequence = _begin_sample(metadata)
	if _active_sequence < 0 or not _stages.has(stage): return
	rd.capture_timestamp(_prefix + str(_active_sequence) + "/" + stage)
	if stage == "end": _active_sequence = -1

func _begin_sample(metadata: Dictionary = {}) -> int:
	_sequence += 1
	if _pending.size() >= MAX_PENDING:
		_pending.erase(_pending.keys()[0])
		_dropped += 1
	_pending[_sequence] = {"sequence": _sequence, "created_harvest": _harvest_serial, "metadata": metadata.duplicate(true), "gpu_ns": {}, "cpu_usec": {}}
	return _sequence

func _queue_collection() -> void:
	if enabled: RenderingServer.call_on_render_thread(_collect)

func _collect() -> void:
	## Reads Godot's already-finished timestamp window. It never waits for the
	## currently submitted work, nor calls RenderingDevice.submit()/sync().
	if not enabled or _rd == null: return
	var frame := _rd.get_captured_timestamps_frame()
	if frame == _last_frame: return
	var entries: Array[Dictionary] = []
	for i in _rd.get_captured_timestamps_count():
		var marker := _rd.get_captured_timestamp_name(i)
		if marker.begins_with(_prefix):
			entries.append({"name": marker, "gpu_ns": _rd.get_captured_timestamp_gpu_time(i), "cpu_usec": _rd.get_captured_timestamp_cpu_time(i)})
	_ingest_frame(frame, entries)

func _ingest_frame(frame: int, entries: Array[Dictionary]) -> void:
	## Separate ingestion permits deterministic CPU tests for missing, delayed,
	## duplicate and out-of-order queries without pretending those are GPU data.
	if frame == _last_frame: return
	_last_frame = frame
	_harvest_serial += 1
	var changed := false
	for entry in entries:
		var marker: String = entry.name
		if not marker.begins_with(_prefix): continue
		var parts := marker.trim_prefix(_prefix).split("/")
		if parts.size() != 2 or not parts[0].is_valid_int(): continue
		var sequence := int(parts[0])
		var stage: String = parts[1]
		if not _pending.has(sequence) or not _stages.has(stage): continue
		var sample: Dictionary = _pending[sequence]
		sample.gpu_ns[stage] = int(entry.gpu_ns)
		sample.cpu_usec[stage] = int(entry.cpu_usec)
		sample.rd_frame = frame
	for sequence in _pending.keys():
		var sample: Dictionary = _pending[sequence]
		if sample.gpu_ns.size() == _stages.size():
			_finish_sample(sample)
			_pending.erase(sequence)
			changed = true
		elif _harvest_serial - int(sample.created_harvest) > EXPIRY_FRAMES:
			_missing += 1
			_pending.erase(sequence)
			changed = true
	if changed:
		var report := {"enabled": true, "status": "available" if _completed > 0 else "no_valid_completed_samples", "gpu_unit": "nanoseconds", "cpu_unit": "microseconds", "completed_samples": _completed, "pending_samples": _pending.size(), "missing_samples": _missing, "invalid_samples": _invalid, "dropped_samples": _dropped, "retained_samples": _samples.size(), "stages": _aggregate.duplicate(true), "latest": _samples[-1].duplicate(true) if not _samples.is_empty() else {}}
		_publish.call_deferred(report)

func _finish_sample(sample: Dictionary) -> void:
	var gpu: Dictionary = sample.gpu_ns
	var cpu: Dictionary = sample.cpu_usec
	var previous_gpu: int = gpu[_stages[0]]
	var previous_cpu: int = cpu[_stages[0]]
	# Unsupported/zero timestamps must not masquerade as free GPU work.
	if previous_gpu <= 0 or int(gpu.end) <= previous_gpu:
		_invalid += 1
		return
	for stage in _stages:
		if int(gpu[stage]) < previous_gpu or int(cpu[stage]) < previous_cpu:
			_invalid += 1
			return
		previous_gpu = int(gpu[stage]); previous_cpu = int(cpu[stage])
	sample.erase("created_harvest")
	sample.gpu_ms = {}; sample.cpu_encode_ms = {}
	for i in range(1, _stages.size()):
		var stage: String = _stages[i]
		var before: String = _stages[i - 1]
		sample.gpu_ms[stage] = float(int(gpu[stage]) - int(gpu[before])) / 1.0e6
		sample.cpu_encode_ms[stage] = float(int(cpu[stage]) - int(cpu[before])) / 1000.0
	sample.gpu_ms.total = float(int(gpu.end) - int(gpu.begin)) / 1.0e6
	sample.cpu_encode_ms.total = float(int(cpu.end) - int(cpu.begin)) / 1000.0
	for stage in sample.gpu_ms:
		var value: float = sample.gpu_ms[stage]
		if not _aggregate.has(stage): _aggregate[stage] = {"count": 0, "sum_ms": 0.0, "max_ms": 0.0, "last_ms": 0.0}
		var aggregate: Dictionary = _aggregate[stage]
		aggregate.count += 1; aggregate.sum_ms += value
		aggregate.max_ms = maxf(float(aggregate.max_ms), value)
		aggregate.last_ms = value; aggregate.mean_ms = float(aggregate.sum_ms) / int(aggregate.count)
	_completed += 1
	_samples.append(sample)
	if _samples.size() > MAX_SAMPLES: _samples.pop_front()

func _publish(report: Dictionary) -> void:
	_published = report
