class_name SourceFormalSnapshotCache
extends RefCounted
## Static authored scenes only. Imported PackedScene content, reconstruction
## scripts, layouts, room order and geometry origin all participate in identity.
## A missing import mapping/hash, changed source, corrupt file, or partial room
## set falls back to genuine live extraction. Seeded source rooms never use this.
const Store = preload("res://scripts/water/source_terrain_disk_cache.gd")
const Identity = preload("res://scripts/water/source_terrain_identity.gd")
const Catalog = preload("res://scripts/world/formal_rooms.gd")
const BUILDERS = [Catalog, preload("res://scripts/world/formal_room_builder.gd"),
	preload("res://scripts/rendering/pool_materials.gd"), preload("res://scripts/rendering/pool_lighting.gd")]
var task_id := -1
var revision := -1
var spec: Dictionary = {}
var result: Dictionary = {}
var elapsed_ms := 0.0
var miss_reason := ""
var diagnostic: Dictionary = {}

static func eligible(layouts: Dictionary) -> bool:
	if layouts.size() != Catalog.COORDS.size(): return false
	for coord: Vector2i in Catalog.COORDS:
		if not layouts.has(coord) or not layouts[coord].get("formal", false): return false
	return true

static func specification(layouts: Dictionary, coords: Array, origin: Vector2) -> Dictionary:
	var code: Array = [Store.algorithm_signature()]
	for script: GDScript in BUILDERS: code.append(script.source_code)
	# Authored architecture and its lights are seed-independent. The seed affects
	# floating dynamic props, which the exact static collector deliberately excludes.
	# Retain every other layout field, including generated collision solids.
	var static_layouts := layouts.duplicate(true)
	for layout: Dictionary in static_layouts.values(): layout.erase("seed")
	return {"layouts": static_layouts, "coords": coords.duplicate(), "origin": origin,
		"algorithm": Identity.digest(code) if not code[0].is_empty() else "", "paths": Catalog.PATHS.duplicate()}

static func fingerprint(input: Dictionary) -> String:
	if input.algorithm.is_empty(): return ""
	var sources: Array = []
	for coord: Vector2i in input.coords:
		var path: String = input.paths.get(coord, "")
		var remap := ConfigFile.new()
		if path.is_empty() or remap.load(path + ".import") != OK: return ""
		var imported: String = remap.get_value("remap", "path", "")
		if imported.is_empty() or not FileAccess.file_exists(imported): return ""
		var digest := FileAccess.get_sha256(imported)
		if digest.is_empty(): return ""
		sources.append([coord, imported, digest])
	return Identity.digest([input.algorithm, sources, input.coords, input.origin, input.layouts])

static func bundle_path(key: String) -> String:
	return Store.BUNDLED_DIR + "rooms_" + key + ".terrain"

func build() -> void:
	var started := Time.get_ticks_usec()
	var key := fingerprint(spec)
	diagnostic = {"expected_key": key, "expected_path": bundle_path(key),
		"algorithm": spec.algorithm, "layout_digest": Identity.digest(spec.layouts),
		"coords": spec.coords, "origin": spec.origin, "exists": FileAccess.file_exists(bundle_path(key))}
	if key.is_empty():
		miss_reason = "Imported resource signature unavailable"
	else:
		var loaded := Store.read_value(bundle_path(key), key, spec.algorithm)
		if _valid(loaded, spec): result = loaded.rooms
		else:
			miss_reason = "Authored snapshot file missing for current signature" if not diagnostic.exists else "Authored snapshot header, integrity, or shape rejected"
	diagnostic.reason = miss_reason
	elapsed_ms = float(Time.get_ticks_usec() - started) / 1000.0

static func _valid(loaded: Dictionary, input: Dictionary) -> bool:
	if not loaded.get("rooms") is Dictionary or loaded.get("origin") != input.origin: return false
	if loaded.rooms.size() != input.coords.size(): return false
	for coord: Vector2i in input.coords:
		var value: Dictionary = loaded.rooms.get(coord, {})
		if value.get("geometry_origin") != input.origin or not value.get("description") is Dictionary: return false
		if not value.get("colliders") is Array or not value.get("solids") is Array or not value.get("triangles") is PackedVector3Array: return false
	return true

static func write_bundle(input: Dictionary, rooms: Dictionary) -> Dictionary:
	var key := fingerprint(input)
	if key.is_empty(): return {"success": false, "reason": "Missing imported resource signature"}
	var values: Dictionary = {}
	for coord: Vector2i in input.coords:
		values[coord] = rooms[coord].duplicate(false)
		values[coord].identity = 0
	var path := bundle_path(key)
	var success := Store.write(path, key, input.algorithm, {"rooms": values, "origin": input.origin})
	return {"success": success, "path": path, "key": key, "algorithm": input.algorithm,
		"bytes": FileAccess.get_file_as_bytes(path).size() if success else 0}
