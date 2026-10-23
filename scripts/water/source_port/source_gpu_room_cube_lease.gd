extends RefCounted
## This owner is render-thread only. Borrowed source/viewport/bridge RIDs never enter it.
## Free dependants before their parents; no attempt to free automatically-invalidated RIDs.
var entries: Array[Dictionary] = []
var allocations: Dictionary = {}
var releases: Dictionary = {}
var auto_releases: Dictionary = {}
var payload_bytes := 0
var released_payload_bytes := 0

func own(rid: RID, kind: String, bytes := 0) -> RID:
	if rid.is_valid():
		entries.append({"rid": rid, "kind": kind, "bytes": bytes})
		allocations[kind] = int(allocations.get(kind, 0)) + 1
		payload_bytes += bytes
	return rid

func release() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd != null:
		dispose(rd)

func dispose(rd: RenderingDevice) -> void:
	for i in range(entries.size() - 1, -1, -1):
		var item := entries[i]
		var valid := true
		if item.kind in ["cube", "source", "view"]:
			valid = rd.texture_is_valid(item.rid)
		elif item.kind == "uniform_set":
			valid = rd.uniform_set_is_valid(item.rid)
		if valid:
			rd.free_rid(item.rid)
			releases[item.kind] = int(releases.get(item.kind, 0)) + 1
		else:
			auto_releases[item.kind] = int(auto_releases.get(item.kind, 0)) + 1
		released_payload_bytes += int(item.bytes)
	entries.clear()

func diagnostics() -> Dictionary:
	return {"allocations": allocations.duplicate(), "explicit_releases": releases.duplicate(),
		"already_invalidated": auto_releases.duplicate(), "owned_live": entries.size(),
		"texture_payload_bytes": payload_bytes, "released_texture_payload_bytes": released_payload_bytes,
		"payload_is_not_measured_vram": true, "borrowed_rids_owned": 0}
