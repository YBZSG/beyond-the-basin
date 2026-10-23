extends RefCounted
## Review-only in-memory A/B. No files, nodes, collisions, water or lighting changed.
## Apply after FormalRoomBuilder material assignment; prefer before optics capture.
## Pass only the target bath's FormalAuthoredArchitecture (or its room root).
const CANDIDATE_PATH := "res://assets/models/bath_junction_candidate/formal_bath_full_source_export.glb"
var _state: Dictionary = {}

func apply_to_bath(root: Node) -> Dictionary:
	if not _state.is_empty():
		return {"ok": false, "reason": "This helper already holds an active swap."}
	var walls: Array[Node] = root.find_children("Bath_Wall", "MeshInstance3D", true, false)
	var drums: Array[Node] = root.find_children("Bath_UpperDrum", "MeshInstance3D", true, false)
	if walls.size() != 1 or drums.size() != 1:
		return {"ok": false, "reason": "Expected exactly one original Bath_Wall and Bath_UpperDrum; pass the target bath root."}
	var wall: MeshInstance3D = walls[0] as MeshInstance3D
	var drum: MeshInstance3D = drums[0] as MeshInstance3D
	if wall.mesh == null or drum.mesh == null or wall.mesh.get_surface_count() != 1 or drum.mesh.get_surface_count() != 1:
		return {"ok": false, "reason": "Unexpected original wall mesh/surface layout."}
	var live_material: Material = wall.get_active_material(0)
	if live_material == null or live_material != drum.get_active_material(0):
		return {"ok": false, "reason": "Original wall and drum must share the same current plaster material."}
	var packed: PackedScene = load(CANDIDATE_PATH) as PackedScene
	if packed == null:
		return {"ok": false, "reason": "Candidate GLB is not imported/loadable."}
	var source: Node = packed.instantiate()
	var replacement: MeshInstance3D = source.find_child("Bath_Wall", true, false) as MeshInstance3D
	if replacement == null or replacement.mesh == null or replacement.mesh.get_surface_count() != 1:
		source.free()
		return {"ok": false, "reason": "Candidate wall mesh/surface layout is invalid."}
	if not replacement.transform.is_equal_approx(wall.transform):
		source.free()
		return {"ok": false, "reason": "Candidate/source local wall transforms differ; no swap performed."}
	var new_mesh: Mesh = replacement.mesh
	_state = {"wall": wall, "drum": drum, "old_mesh": wall.mesh, "new_mesh": new_mesh,
		"old_surface_override": wall.get_surface_override_material(0), "old_drum_visible": drum.visible}
	# Keep the original node, transform, material_override, shadow, GI, layer and
	# visibility properties. The only material assignment uses its current material.
	wall.mesh = new_mesh
	wall.set_surface_override_material(0, live_material)
	drum.visible = false
	source.free()
	return {"ok": true, "candidate": CANDIDATE_PATH, "changed_visible_meshes": ["Bath_Wall", "Bath_UpperDrum"],
		"same_live_material_instance": live_material.get_instance_id(), "collision_changed": false,
		"production_files_written": false, "nodes_added_or_removed": 0,
		"note": "Optics/BVH caches are not rebuilt by this narrow helper; use a fresh capture for an end-to-end A/B."}

func restore() -> Dictionary:
	if _state.is_empty():
		return {"ok": true, "restored": false, "reason": "No active swap."}
	var wall: MeshInstance3D = _state.wall as MeshInstance3D
	var drum: MeshInstance3D = _state.drum as MeshInstance3D
	if not is_instance_valid(wall) or not is_instance_valid(drum):
		_state.clear()
		return {"ok": false, "reason": "The original room no longer exists."}
	if wall.mesh != _state.new_mesh:
		return {"ok": false, "reason": "Wall mesh changed after the A/B swap; refusing to overwrite another edit."}
	wall.mesh = _state.old_mesh as Mesh
	wall.set_surface_override_material(0, _state.old_surface_override as Material)
	drum.visible = bool(_state.old_drum_visible)
	_state.clear()
	return {"ok": true, "restored": true, "collision_changed": false, "production_files_written": false}
