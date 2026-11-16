extends RefCounted
## Render-only partition: grass islands own their footprint on the tiled apron.
## Retain original box sides/bottom, node count, collision and grass recipes.
const G=preload("res://scripts/dreamcore/scenes/outdoor_geometry.gd")
static func _subtract(rect:Rect2,cut:Rect2)->Array[Rect2]:
	var overlap:=rect.intersection(cut)
	if not overlap.has_area():return [rect]
	var parts:Array[Rect2]=[]
	# Four disjoint strips, keeping original coordinates rather than offsets.
	if overlap.position.x>rect.position.x:
		parts.append(Rect2(rect.position,Vector2(overlap.position.x-rect.position.x,rect.size.y)))
	if overlap.end.x<rect.end.x:
		parts.append(Rect2(Vector2(overlap.end.x,rect.position.y),Vector2(rect.end.x-overlap.end.x,rect.size.y)))
	if overlap.position.y>rect.position.y:
		parts.append(Rect2(Vector2(overlap.position.x,rect.position.y),Vector2(overlap.size.x,overlap.position.y-rect.position.y)))
	if overlap.end.y<rect.end.y:
		parts.append(Rect2(Vector2(overlap.position.x,overlap.end.y),Vector2(overlap.size.x,rect.end.y-overlap.end.y)))
	return parts

static func _tile(root:Node3D,coord:Vector2i,a:AABB,islands:Array[Rect2])->void:
	var clipped:AABB=G.clipped(a,coord)
	if clipped.size.x<=.001 or clipped.size.z<=.001:return
	var origin:=Vector2(coord.x*32.,coord.y*32.)
	var footprint:=Rect2(Vector2(clipped.position.x,clipped.position.z)+origin,Vector2(clipped.size.x,clipped.size.z))
	var pieces:Array[Rect2]=[footprint]
	var changed:=false
	for island:Rect2 in islands:
		if not footprint.intersection(island).has_area():continue
		changed=true
		var next:Array[Rect2]=[]
		for rect:Rect2 in pieces:next.append_array(_subtract(rect,island))
		pieces=next
	var node:MeshInstance3D=G.box(root,clipped.get_center(),clipped.size,"tile")
	if not changed:return
	# Preserve every original non-top triangle and every original attribute.
	var arrays:Array=node.mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
	var source_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	assert(source_indices.size()>0 and source_indices.size()%3==0,"Expected indexed tile box triangles")
	var indices:=PackedInt32Array()
	var top_index:=-1
	var top_triangles:=0
	for i in range(0,source_indices.size(),3):
		var ia:=source_indices[i];var ib:=source_indices[i+1];var ic:=source_indices[i+2]
		if normals[ia].y>.9 and normals[ib].y>.9 and normals[ic].y>.9:
			top_index=ia;top_triangles+=1
		else:indices.append_array(PackedInt32Array([ia,ib,ic]))
	assert(top_index>=0 and top_triangles==2,"Expected two upward tile box triangles")
	var top_tangent:=PackedFloat32Array()
	for j in range(4):top_tangent.append(tangents[top_index*4+j])
	for rect:Rect2 in pieces:
		var first:=vertices.size()
		for flat:Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			var point:=Vector3(flat.x-origin.x,clipped.end.y,flat.y-origin.y)
			var world:=root.to_global(point)
			vertices.append(point-node.position);normals.append(Vector3.UP)
			uv.append(Vector2(world.x,world.z)*.25)
			uv2.append(Vector2(world.x,world.z)/288.+Vector2(.5,.5))
			tangents.append_array(top_tangent)
		indices.append_array(PackedInt32Array([first,first+1,first+2,first,first+2,first+3]))
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	arrays[Mesh.ARRAY_TANGENT]=tangents;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);node.mesh=mesh

static func build(root:Node3D,coord:Vector2i,specs:Array)->void:
	var islands:Array[Rect2]=[]
	for a:AABB in specs:
		if a.size.x==18.:islands.append(Rect2(a.position.x,a.position.z,a.size.x,a.size.z))
	for a:AABB in specs:
		if a.size.x==18.:G.floor_patch(root,coord,a,"grass")
		else:_tile(root,coord,a,islands)
