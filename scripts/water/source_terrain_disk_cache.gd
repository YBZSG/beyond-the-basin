class_name SourceTerrainDiskCache
extends RefCounted
## Optional exact authored-scene acceleration. Never a source-world fallback.
## Every load happens in a CPU worker after current geometry has been captured
## and its complete dependency key verified. Bad/stale data is a cache miss.
const Prepare = preload("res://scripts/water/source_port/source_terrain_prepare.gd")
const Identity = preload("res://scripts/water/source_terrain_identity.gd")
const ALGORITHMS = [Prepare,
	preload("res://scripts/water/source_port/source_wave_solver.gd"),
	preload("res://scripts/water/source_port/source_caustics.gd"),
	preload("res://scripts/water/source_port/source_triangle_bvh.gd"),
	preload("res://scripts/water/source_room_snapshot.gd"), Identity]
# Loaded lazily after compilation to avoid Runtime -> Store -> Runtime preload
# cycles. These coordinators determine extraction, lamp inputs and scene order.
const CONTEXT_PATHS = ["res://scripts/water/source_water_runtime.gd",
	"res://scripts/world/pool_world.gd", "res://scripts/world/source_architecture_batch.gd",
	"res://scripts/water/source_formal_snapshot_cache.gd", "res://scripts/water/source_terrain_disk_cache.gd"]
const MAGIC := "POOL_TERRAIN_2\n"
const SCHEMA := 2
const BUNDLED_DIR := "res://assets/cache/source_terrain/"
const USER_DIR := "user://source_terrain_cache/v2/"
const MAX_PAYLOAD_BYTES := 256 * 1024 * 1024

static func loaded_algorithms() -> Array:
	var scripts: Array = ALGORITHMS.duplicate()
	for path: String in CONTEXT_PATHS:
		var script := load(path) as GDScript
		if script == null: return []
		scripts.append(script)
	return scripts

static func algorithm_signature() -> String:
	var sources: Array = [SCHEMA, Engine.get_version_info().hash,
		Vector3(16777217.0, 0, 0).x == 16777217.0]
	var scripts := loaded_algorithms()
	if scripts.is_empty(): return ""
	for script: GDScript in scripts:
		# Hash the loaded Script, not a concurrently edited disk file. Source
		# is retained in release PCKs; absent source must fail closed.
		if script.source_code.is_empty(): return ""
		sources.append([script.resource_path, script.source_code])
	return Identity.digest(sources)

static func file_name(key: String) -> String:
	return Identity.digest(key) + ".terrain"

static func build(snapshot: Dictionary, progress: Callable, identity: Dictionary, algorithm: String) -> Dictionary:
	if algorithm.is_empty(): return Prepare.build(snapshot, progress)
	if progress.is_valid(): progress.call("reading_exact_cache")
	var name := file_name(identity.key)
	var started := Time.get_ticks_usec()
	for directory in [BUNDLED_DIR, USER_DIR]:
		var cached := read(directory + name, identity.key, algorithm, snapshot)
		if not cached.is_empty():
			cached.baked_timing_ms = cached.timing_ms
			var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
			cached.timing_ms = {"translate": 0.0, "depth": 0.0, "wet_mask": 0.0, "bvh": 0.0, "masks": 0.0, "total": elapsed}
			cached.revision = snapshot.revision
			cached.disk_cache_hit = true
			cached.disk_cache_source = "bundled" if directory == BUNDLED_DIR else "local"
			cached.reused_bvh = true; cached.reused_masks = true
			if progress.is_valid(): progress.call("complete")
			return cached
	var result := Prepare.build(snapshot, progress)
	result.disk_cache_hit = false
	if progress.is_valid(): progress.call("saving_exact_cache")
	write(USER_DIR + name, identity.key, algorithm, result)
	if progress.is_valid(): progress.call("complete")
	return result

static func write(path: String, key: String, algorithm: String, payload: Dictionary) -> bool:
	var bytes := var_to_bytes(payload)
	if bytes.size() > MAX_PAYLOAD_BYTES: return false
	# Built-in lossless compression only changes the container, never prepared
	# arrays. Both lengths are bounded before allocation; both hashes are checked.
	var stored := bytes.compress(FileAccess.COMPRESSION_ZSTD)
	if stored.is_empty() or stored.size() > MAX_PAYLOAD_BYTES: return false
	var header := JSON.stringify({"schema": SCHEMA, "key": key, "algorithm": algorithm,
		"bytes": bytes.size(), "sha256": _bytes_digest(bytes), "codec":"zstd",
		"stored_bytes": stored.size(), "stored_sha256": _bytes_digest(stored)}).to_utf8_buffer()
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return false
	var temporary := path + ".pending"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(MAGIC.to_utf8_buffer()); file.store_32(header.size())
	file.store_buffer(header); file.store_buffer(stored); file.flush()
	var success := file.get_error() == OK
	file.close()
	if not success: return false
	# Readers accept only the complete final file, never a half-written payload.
	return DirAccess.rename_absolute(temporary, path) == OK

static func read_value(path: String, key: String, algorithm: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	if file.get_length() < MAGIC.length() + 4 or file.get_length() > MAX_PAYLOAD_BYTES + 65536 + MAGIC.length() + 4: return {}
	if file.get_buffer(MAGIC.length()).get_string_from_utf8() != MAGIC: return {}
	var header_size := file.get_32()
	if header_size < 2 or header_size > 65536 or header_size > file.get_length() - file.get_position(): return {}
	var parsed: Variant = JSON.parse_string(file.get_buffer(header_size).get_string_from_utf8())
	if not parsed is Dictionary: return {}
	var header: Dictionary = parsed
	if header.get("schema") != SCHEMA or header.get("key") != key or header.get("algorithm") != algorithm: return {}
	var count := int(header.get("bytes", -1))
	var stored_count := int(header.get("stored_bytes", -1))
	if header.get("codec") != "zstd" or count < 1 or count > MAX_PAYLOAD_BYTES: return {}
	if stored_count < 1 or stored_count > MAX_PAYLOAD_BYTES or stored_count != file.get_length() - file.get_position(): return {}
	var stored := file.get_buffer(stored_count)
	if stored.size() != stored_count or _bytes_digest(stored) != header.get("stored_sha256", ""): return {}
	var bytes := stored.decompress(count,FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != count or _bytes_digest(bytes) != header.get("sha256", ""): return {}
	# bytes_to_var does not deserialize Objects; cached input cannot instantiate
	# a Script, Node, Resource, or callable with privileges.
	var decoded: Variant = bytes_to_var(bytes)
	if not decoded is Dictionary: return {}
	return decoded

static func read(path: String, key: String, algorithm: String, expected: Dictionary) -> Dictionary:
	var result := read_value(path, key, algorithm)
	return validate_payload(result, expected)

static func validate_payload(result: Dictionary, expected: Dictionary) -> Dictionary:
	# Shared by disk readers and the final main-thread publication gate. Validate
	# every component before rebase/depth changes, so a malformed worker result
	# cannot leave the solver moved while its old BVH/masks remain installed.
	if result.is_empty(): return {}
	if not result.get("coord") is Vector2i or not result.get("origin") is Vector2 or not result.get("size") is int or not result.get("revision") is int: return {}
	if result.get("coord") != expected.get("coord",Vector2i(roundi(expected.origin.x/32.0),roundi(expected.origin.y/32.0))): return {}
	if result.get("size") != expected.size or result.get("origin") != expected.origin or result.get("domain") != expected.get("domain", 96.0): return {}
	if not result.get("depth_data") is PackedFloat32Array or result.depth_data.size() != expected.size * expected.size: return {}
	if not result.get("packed_bvh") is Dictionary or not result.get("filtered_solids") is Array or not result.get("timing_ms") is Dictionary: return {}
	for solid in result.filtered_solids:
		if not solid is AABB: return {}
	var bvh: Dictionary = result.packed_bvh
	if not bvh.get("nodes") is PackedByteArray or not bvh.get("triangles") is PackedByteArray: return {}
	if bvh.nodes.size() < 48 or bvh.nodes.size() % 48 != 0 or bvh.triangles.size() < 48 or bvh.triangles.size() % 48 != 0: return {}
	if not result.get("masks") is Array or result.masks.size() != 2: return {}
	for mask in result.masks:
		if not mask is PackedByteArray or mask.size() != 256 * 256: return {}
	return result

static func _bytes_digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()
