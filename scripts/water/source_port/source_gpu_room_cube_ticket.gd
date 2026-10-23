extends RefCounted
## CPU-only synchronization gate for immutable room cubemap captures.
## Main thread owns request/face progression. Workers may read liveness, cancel
## under the mutex and return the original Ticket after encoding the copy,
## never after pixel readback. Cancellation does not mutate any Node or renderer.
## Liveness is a point-in-time check, not a lock around a RenderingDevice command;
## the main-thread acknowledgement revalidates cancellation before advancing.

class Ticket extends RefCounted:
	# Immutable by convention. Never expose this dictionary to callers; the gate
	# also retains an independent copy to reject accidental in-place corruption.
	var _values: Dictionary

	func _init(values: Dictionary = {}) -> void:
		_values = values.duplicate(true)

	func snapshot() -> Dictionary:
		return _values.duplicate(true)

const FACE_COUNT := 6
const TICKET_FIELDS := ["generation", "revision", "room_key", "face", "draw_sequence", "source_identity", "request_identity"]

var _mutex := Mutex.new()
var _generation := 0
var _revision := 0
var _room_key := ""
var _source_identity := 0
var _request_identity := ""
var _active := false
var _next_face := 0
var _last_draw_sequence := -1
var _last_accepted_draw_sequence := -1
var _pending: Ticket
var _pending_snapshot: Dictionary = {}
var _issued: Array[Dictionary] = []
var _accepted_acks := 0
var _rejected_acks := 0
var _rejected_issues := 0
var _total_accepted_acks := 0
var _total_rejected_acks := 0
var _cancel_reason := ""

## Every begin invalidates the old request, including same-room/same-revision ABA.
## Draw sequence is lifetime-monotonic and is deliberately not reset here.
func begin(room_key: String, revision: int, source_identity: int) -> int:
	if not _on_main_thread():
		return -1
	_mutex.lock()
	_generation += 1
	_revision = revision
	_room_key = room_key
	_source_identity = source_identity
	_request_identity = "%d:%d" % [get_instance_id(), _generation]
	_active = true
	_next_face = 0
	_pending = null
	_pending_snapshot = {}
	_issued.clear()
	_accepted_acks = 0
	_rejected_acks = 0
	_rejected_issues = 0
	_cancel_reason = ""
	var result := _generation
	_mutex.unlock()
	return result

## At most one copy can be pending. Invalid issues do not consume a draw token.
func issue(face: int, draw_sequence: int) -> Ticket:
	if not _on_main_thread():
		return null
	_mutex.lock()
	if not _active or _pending != null or face != _next_face or face < 0 or face >= FACE_COUNT or draw_sequence <= _last_draw_sequence:
		_rejected_issues += 1
		_mutex.unlock()
		return null
	var values := {
		"generation": _generation,
		"revision": _revision,
		"room_key": _room_key,
		"face": face,
		"draw_sequence": draw_sequence,
		"source_identity": _source_identity,
		"request_identity": _request_identity,
	}
	var ticket := Ticket.new(values)
	_pending = ticket
	_pending_snapshot = values.duplicate(true)
	_issued.append({"ticket": ticket, "snapshot": values.duplicate(true)})
	_last_draw_sequence = draw_sequence
	_mutex.unlock()
	return ticket

## Authentic accepted tickets stay live for mip/publication work in this request.
## Forged/reconstructed tickets, altered snapshots and prior requests never do.
func is_current(ticket: Ticket) -> bool:
	_mutex.lock()
	var result := _is_current_locked(ticket)
	_mutex.unlock()
	return result

## Call on the main thread only when the worker reports copy-command encoding.
## This is neither a GPU-completion fence nor a CPU pixel-callback entry point.
func accept_copy_ack(ticket: Ticket) -> bool:
	if not _on_main_thread():
		return false
	_mutex.lock()
	var valid := _pending != null and ticket == _pending and _is_current_locked(ticket)
	if valid:
		valid = _same_snapshot(ticket.snapshot(), _pending_snapshot)
		valid = valid and int(_pending_snapshot["face"]) == _next_face
		valid = valid and int(_pending_snapshot["draw_sequence"]) == _last_draw_sequence
		valid = valid and int(_pending_snapshot["draw_sequence"]) > _last_accepted_draw_sequence
	if not valid:
		_rejected_acks += 1
		_total_rejected_acks += 1
		_mutex.unlock()
		return false
	_last_accepted_draw_sequence = int(_pending_snapshot["draw_sequence"])
	_accepted_acks += 1
	_total_accepted_acks += 1
	_next_face += 1
	_pending = null
	_pending_snapshot = {}
	_mutex.unlock()
	return true

## Any thread may cancel: immediate invalidation even with an encoded ack in flight.
func cancel(reason: String) -> void:
	_mutex.lock()
	_generation += 1
	_active = false
	_request_identity = ""
	_pending = null
	_pending_snapshot = {}
	_issued.clear()
	_cancel_reason = reason
	_mutex.unlock()

## Diagnostic copy, safe to read on either thread and safe for callers to modify.
func snapshot() -> Dictionary:
	_mutex.lock()
	var result := {
		"generation": _generation,
		"revision": _revision,
		"room_key": _room_key,
		"source_identity": _source_identity,
		"request_identity": _request_identity,
		"next_face": _next_face,
		"active": _active,
		"complete": _active and _next_face == FACE_COUNT and _pending == null,
		"pending": _pending != null,
		"pending_ticket": _pending_snapshot.duplicate(true),
		"last_draw_sequence": _last_draw_sequence,
		"last_accepted_draw_sequence": _last_accepted_draw_sequence,
		"accepted_acks": _accepted_acks,
		"rejected_acks": _rejected_acks,
		"rejected_issues": _rejected_issues,
		"total_accepted_acks": _total_accepted_acks,
		"total_rejected_acks": _total_rejected_acks,
		"cancel_reason": _cancel_reason,
		"cpu_callbacks_required": 0,
	}
	_mutex.unlock()
	return result

func _is_current_locked(ticket: Ticket) -> bool:
	if not _active or ticket == null:
		return false
	var values := ticket.snapshot()
	for record in _issued:
		if record["ticket"] != ticket:
			continue
		if not _same_snapshot(values, record["snapshot"]):
			return false
		return int(values["generation"]) == _generation and int(values["revision"]) == _revision and String(values["room_key"]) == _room_key and int(values["source_identity"]) == _source_identity and String(values["request_identity"]) == _request_identity
	return false

func _same_snapshot(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != TICKET_FIELDS.size() or right.size() != TICKET_FIELDS.size():
		return false
	for key in TICKET_FIELDS:
		if not left.has(key) or not right.has(key):
			return false
		if typeof(left[key]) != typeof(right[key]) or left[key] != right[key]:
			return false
	return true

func _on_main_thread() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()
