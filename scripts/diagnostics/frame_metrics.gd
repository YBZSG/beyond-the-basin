class_name PoolFrameMetrics
extends RefCounted
## Wall-clock interval between main-loop callbacks, not a GPU timestamp and not
## simulated delta. Bounded ring storage makes stutter visible without logging
## every frame or allocating an unbounded history during normal play.
const CAPACITY := 600
var _samples := PackedFloat64Array()
var _cursor := 0
var _count := 0
var _last_tick_usec := 0
var total_samples := 0
var longest_ms := 0.0

func _init() -> void:
	_samples.resize(CAPACITY)

func reset() -> void:
	_cursor = 0
	_count = 0
	_last_tick_usec = 0
	total_samples = 0
	longest_ms = 0.0

func push_tick(tick_usec: int) -> void:
	if _last_tick_usec > 0 and tick_usec > _last_tick_usec:
		push_milliseconds(float(tick_usec - _last_tick_usec) * 0.001)
	_last_tick_usec = tick_usec

func push_milliseconds(milliseconds: float) -> void:
	if not is_finite(milliseconds) or milliseconds <= 0.0: return
	_samples[_cursor] = milliseconds
	_cursor = (_cursor + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)
	total_samples += 1
	longest_ms = maxf(longest_ms, milliseconds)

func summary() -> Dictionary:
	if _count == 0:
		return {"samples":0,"p50_ms":0.0,"p95_ms":0.0,"p99_ms":0.0,"max_ms":0.0,"longest_ms":longest_ms,"over_50_ms":0,"over_100_ms":0}
	var values := _samples.slice(0, _count)
	values.sort()
	var over_50 := 0
	var over_100 := 0
	for value in values:
		if value > 50.0: over_50 += 1
		if value > 100.0: over_100 += 1
	return {"samples":_count,"total_samples":total_samples,"p50_ms":_percentile(values, 0.50),"p95_ms":_percentile(values, 0.95),"p99_ms":_percentile(values, 0.99),"max_ms":values[-1],"longest_ms":longest_ms,"over_50_ms":over_50,"over_100_ms":over_100,"method":"rolling main-loop wall-clock intervals; not isolated GPU durations"}

func _percentile(sorted_values: PackedFloat64Array, p: float) -> float:
	return sorted_values[clampi(ceili(float(sorted_values.size()) * p) - 1, 0, sorted_values.size() - 1)]
