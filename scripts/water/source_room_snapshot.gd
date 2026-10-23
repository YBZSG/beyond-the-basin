class_name SourceRoomSnapshot
extends RefCounted
## Main-thread, bounded scene capture plus worker-owned value extraction.
## Live Nodes and Mesh resources never enter a worker. DFS face order and the
## scalar Transform3D multiplication match the former synchronous _collect.
const Identity = preload("res://scripts/water/source_terrain_identity.gd")
var coord := Vector2i.ZERO
var identity := 0
var geometry_origin := Vector2.ZERO
var result: Dictionary = {}
var complete := false
var cancelled := false
var elapsed_usec := 0
var slices := 0
var max_slice_usec := 0
var vertices_read := 0
var nodes_read := 0
var cpu_array_meshes := 0
var driver_face_meshes := 0
var _stack: Array[Node] = []
var _meshes: Array[Dictionary] = []
var _colliders: Array = []
var _solids: Array = []
var _job: FinalizeJob
var worker_usec := 0

class FinalizeJob extends RefCounted:
	var task_id := -1
	var meshes: Array[Dictionary] = []
	var colliders: Array = []
	var solids: Array = []
	var geometry_origin := Vector2.ZERO
	var identity := 0
	var result: Dictionary = {}
	var elapsed_usec := 0
	func build() -> void:
		var started := Time.get_ticks_usec()
		var triangles := PackedVector3Array()
		# No Nodes or Resources here. Face arrays and Transform3D values were
		# captured on the main thread; every scalar operation is unchanged.
		for entry: Dictionary in meshes:
			var faces: PackedVector3Array = entry.faces
			if entry.has("indices"):
				var indices: PackedInt32Array = entry.indices
				if not indices.is_empty():
					var expanded := PackedVector3Array(); expanded.resize(indices.size())
					for i in indices.size(): expanded[i] = faces[indices[i]]
					faces = expanded
				# Godot4.6 TriangleMesh::create (used by Mesh.get_faces) snaps
				# each position with Vector3.snappedf(.0001) before welding.
				# Welding preserves face order and the snapped position, so call
				# the same native operation without building an unused engine BVH.
				# core/math/triangle_mesh.cpp, create(), Godot4.6-stable.
				faces = faces.duplicate()
				for i in faces.size(): faces[i] = faces[i].snappedf(.0001)
			var transform: Transform3D = entry.transform
			var first := triangles.size()
			triangles.resize(first + faces.size())
			for i in faces.size():
				triangles[first + i] = transform * faces[i]
		result = {"colliders": colliders, "solids": solids, "triangles": triangles,
			"geometry_origin": geometry_origin, "identity": identity}
		result.description = Identity.describe_room(result)
		meshes.clear()
		elapsed_usec = Time.get_ticks_usec() - started

func begin(room: Node3D, room_coord: Vector2i, origin: Vector2) -> void:
	coord = room_coord
	identity = room.get_instance_id()
	geometry_origin = origin
	_stack = [room]

func advance(budget_usec: int = 2000, _vertex_budget: int = 8192, node_budget: int = 128) -> bool:
	if complete or cancelled:
		return complete
	if _job != null:
		return reap_completed()
	var started := Time.get_ticks_usec()
	var nodes := 0
	while not _stack.is_empty():
		var node: Node = _stack.pop_back()
		if is_instance_valid(node):
			_visit(node)
		nodes += 1
		nodes_read += 1
		if nodes >= node_budget or Time.get_ticks_usec() - started >= budget_usec:
			break
	if _stack.is_empty():
		_job = FinalizeJob.new()
		_job.meshes = _meshes; _meshes = []
		_job.colliders = _colliders; _colliders = []
		_job.solids = _solids; _solids = []
		_job.geometry_origin = geometry_origin; _job.identity = identity
		_job.task_id = WorkerThreadPool.add_task(_job.build, false, "Static room value extraction")
	var elapsed := Time.get_ticks_usec() - started
	elapsed_usec += elapsed
	max_slice_usec = maxi(max_slice_usec, elapsed)
	slices += 1
	return false

func has_pending_worker() -> bool:
	return _job != null

func reap_completed() -> bool:
	if _job == null:
		return complete or cancelled
	if not WorkerThreadPool.is_task_completed(_job.task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(_job.task_id)
	_job.task_id = -1
	worker_usec = _job.elapsed_usec
	if not cancelled:
		result = _job.result
		complete = true
	_job = null
	return true

func finish_shutdown() -> void:
	if _job != null:
		WorkerThreadPool.wait_for_task_completion(_job.task_id)
		_job.task_id = -1
		_job = null
	cancel()

func _visit(node: Node) -> void:
	if node is RigidBody3D or node is CharacterBody3D:
		return
	var offset := Vector3(geometry_origin.x, 0, geometry_origin.y)
	if node is CollisionShape3D and node.shape:
		var collision := node as CollisionShape3D
		var transform := collision.global_transform
		transform.origin -= offset
		var shape: Shape3D = collision.shape
		var half := Vector3.ZERO
		var center := Vector3.ZERO
		var radius := -1.0
		if shape is BoxShape3D:
			half = shape.size * .5
		elif shape is CylinderShape3D:
			half = Vector3(shape.radius, shape.height * .5, shape.radius)
			radius = shape.radius
		elif shape is SphereShape3D:
			half = Vector3.ONE * shape.radius
			radius = shape.radius
		elif shape is ConvexPolygonShape3D:
			var points: PackedVector3Array = shape.points
			if not points.is_empty():
				var bounds := AABB(points[0], Vector3.ZERO)
				for point in points:
					bounds = bounds.expand(point)
				half = bounds.size * .5
				center = bounds.get_center()
		if half.length_squared() > 0:
			var entry := {"center": transform * center, "half": half * transform.basis.get_scale().abs()}
			var rotation := transform.basis.orthonormalized().get_rotation_quaternion()
			if not rotation.is_equal_approx(Quaternion.IDENTITY):
				entry.rotation = rotation
			elif radius > 0:
				entry.radius = radius * maxf(transform.basis.get_scale().x, transform.basis.get_scale().z)
			_colliders.append(entry)
			_solids.append(transform * AABB(center - half, half * 2.0))
	if node is MeshInstance3D and node.mesh and node.visible and not String(node.name).begins_with("COLLISION_") and (node.layers & 1) != 0 and not node.get_meta("source_transmissive", false) and not node.get_meta("source_exclude_optics", false):
		var transform: Transform3D = node.global_transform
		transform.origin -= offset
		var arrays: Dictionary = node.mesh.get_meta("source_static_arrays",{})
		if arrays.get("vertices") is PackedVector3Array and arrays.get("indices") is PackedInt32Array:
			# Only immutable source architecture batches provide this handoff.
			# Indexed expansion and transforms stay on the private value worker.
			_meshes.append({"faces":arrays.vertices,"indices":arrays.indices,"transform":transform})
			vertices_read += arrays.indices.size() if not arrays.indices.is_empty() else arrays.vertices.size()
			cpu_array_meshes += 1
		else:
			var faces: PackedVector3Array = node.mesh.get_faces()
			_meshes.append({"faces": faces, "transform": transform})
			vertices_read += faces.size()
			driver_face_meshes += 1
	var children := node.get_children()
	for i in range(children.size() - 1, -1, -1):
		_stack.append(children[i])

func cancel() -> void:
	cancelled = true
	_stack.clear()
	_meshes = []
	_colliders.clear()
	_solids.clear()
	result = {}
