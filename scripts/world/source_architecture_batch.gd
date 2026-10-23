class_name PoolSourceArchitectureBatch
extends RefCounted
## Native equivalent of original static-geometry.ts: bake immutable direct-child
## architecture into room-local arrays, grouped by live material/shadow/layers.
## Collision, notices, fixtures, props and any parented/animated meshes stay intact.

static func key_for(mesh: MeshInstance3D, indexed: bool) -> String:
	return "%s/%s/%s/%s/%s/%s" % [mesh.material_override.get_instance_id() if mesh.material_override else 0,mesh.cast_shadow,mesh.layers,mesh.gi_mode,indexed,mesh.get_meta("source_exclude_optics",false)]

static func primitive_record(mesh: MeshInstance3D) -> Dictionary:
	var record:Dictionary={"position":mesh.position,"role":mesh.get_meta("source_role","missing"),"rotation":mesh.quaternion}
	if record.role=="wall":record.role="tile"
	if mesh.has_meta("source_arch"):
		record.merge(mesh.get_meta("source_arch"),true);record.kind="arch"
	elif mesh.mesh is BoxMesh:record.kind="box";record.size=mesh.mesh.size
	elif mesh.mesh is CylinderMesh:record.kind="cylinder";record.radius=mesh.mesh.top_radius;record.height=mesh.mesh.height
	elif mesh.mesh is SphereMesh:record.kind="sphere";record.radius=mesh.mesh.radius
	return record

static func batch(room: Node3D) -> Dictionary:
	# A shell may already be batched when its interior arrives. Rebatch only
	# after new generator-owned primitives are added, and include existing
	# batches in those groups so steady-state draw counts do not increase.
	var previous:Dictionary=room.get_meta("source_architecture_batch",{})
	var pending:Array[MeshInstance3D]=[]
	for child in room.get_children():
		if child is MeshInstance3D and child.mesh!=null and child.visible and child.mesh.get_surface_count()==1 and child.has_meta("source_role") and not child.has_meta("source_batch") and not child.has_meta("source_batch_recorded"):
			pending.append(child)
	if pending.is_empty() and not previous.is_empty():return previous
	var groups:Dictionary={}
	# Read each source surface once per atomic batch. Later grouping/counting
	# uses the same immutable arrays, not repeated RenderingServer readbacks.
	var input_arrays:Dictionary={}
	var primitives:Array=room.get_meta("source_primitives",[]).duplicate()
	for child in pending:
		primitives.append(primitive_record(child))
		child.set_meta("source_batch_recorded",true)
	var original_count:int=0
	var triangles_before:int=0
	for child in room.get_children():
		if child is not MeshInstance3D or child.mesh==null or not child.visible:continue
		# Only generator-owned immutable primitives are eligible. Nested signs,
		# imported GLBs and dynamic descendants are never traversed or flattened.
		if not child.has_meta("source_role") and not child.has_meta("source_batch"):continue
		if child.mesh.get_surface_count()!=1:continue
		var arrays:Array=child.mesh.surface_get_arrays(0)
		input_arrays[child.get_instance_id()]=arrays
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var indexed:bool=not indices.is_empty()
		var key:String=key_for(child,indexed)
		if not groups.has(key):groups[key]=[]
		groups[key].append(child)
		original_count+=child.get_meta("source_primitives",[]).size() if child.has_meta("source_batch") else 1
		triangles_before+=(indices.size() if indexed else arrays[Mesh.ARRAY_VERTEX].size())/3
	var batches:int=0
	var result_count:int=0
	var triangles_after:int=0
	for key:String in groups:
		var members:Array=groups[key]
		if members.size()<2:
			var arrays:Array=input_arrays[members[0].get_instance_id()]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			triangles_after+=(indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
			result_count+=1
			if members[0].has_meta("source_batch"):batches+=1
			continue
		var positions:=PackedVector3Array()
		var normals:=PackedVector3Array()
		var uvs:=PackedVector2Array()
		var indices:=PackedInt32Array()
		var records:Array=[]
		for member:MeshInstance3D in members:
			var arrays:Array=input_arrays[member.get_instance_id()]
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var source_normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var source_uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var source_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var offset:int=positions.size()
			var transform:Transform3D=member.transform
			var normal_basis:Basis=transform.basis.inverse().transposed()
			for i in vertices.size():
				positions.append(transform*vertices[i])
				normals.append((normal_basis*source_normals[i]).normalized())
				uvs.append(source_uvs[i] if i<source_uvs.size() else Vector2.ZERO)
			for index in source_indices:indices.append(offset+index)
			if member.has_meta("source_batch"):
				records.append_array(member.get_meta("source_primitives",[]))
			else:
				records.append(primitive_record(member))
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs
		if not indices.is_empty():arrays[Mesh.ARRAY_INDEX]=indices
		var combined:=ArrayMesh.new();combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		# These generator-owned meshes are immutable. Preserve the exact pre-upload
		# positions/index order for CPU water extraction instead of reading the
		# RenderingServer vertex buffer back on a later transition frame. Packed
		# arrays share storage copy-on-write; the worker never mutates these values.
		combined.set_meta("source_static_arrays", {"vertices":positions,"indices":indices})
		var first:MeshInstance3D=members[0]
		var batch_mesh:=MeshInstance3D.new()
		batch_mesh.name="SourceArchitectureBatch_"+str(records[0].role if not records.is_empty() else "architecture")
		batch_mesh.mesh=combined
		batch_mesh.material_override=first.material_override
		batch_mesh.cast_shadow=first.cast_shadow
		batch_mesh.layers=first.layers
		batch_mesh.gi_mode=first.gi_mode
		batch_mesh.set_meta("source_exclude_optics",first.get_meta("source_exclude_optics",false))
		batch_mesh.set_meta("source_batch",true)
		batch_mesh.set_meta("source_primitives",records)
		room.add_child(batch_mesh)
		for member:MeshInstance3D in members:
			room.remove_child(member)
			member.free()
		batches+=1;result_count+=1
		triangles_after+=(indices.size() if not indices.is_empty() else positions.size())/3
	var report:Dictionary={"source_meshes":original_count,"result_meshes":result_count,"batches":batches,"triangles_before":triangles_before,"triangles_after":triangles_after,"passes":int(previous.get("passes",0))+1}
	room.set_meta("source_primitives",primitives)
	room.set_meta("source_architecture_batch",report)
	return report
