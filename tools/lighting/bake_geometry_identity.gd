extends RefCounted
## Strict CPU signatures of rendered triangle order and attributes. UV2 is
## allowed to change only during native unwrap, never during scene roundtrip.
static func inspect(node:MeshInstance3D)->Dictionary:
 var positions:=PackedFloat32Array();var normals:=PackedFloat32Array()
 var uv0:=PackedFloat32Array();var uv2:=PackedFloat32Array();var tangents:=PackedFloat32Array()
 var surfaces:Array=[];var invalid:=0;var triangles:=0;var uv2_outside:=0
 for surface in node.mesh.get_surface_count():
  var arrays:=node.mesh.surface_get_arrays(surface)
  var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var ns:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
  var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
  var lm:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
  var ts:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
  var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
  var count:=indices.size() if not indices.is_empty() else vertices.size()
  surfaces.append({"primitive":node.mesh.surface_get_primitive_type(surface),"ordered_vertices":count,"normal":not ns.is_empty(),"uv0":not uvs.is_empty(),"uv2":not lm.is_empty(),"tangent":not ts.is_empty()})
  triangles+=count/3
  for corner in count:
   var index:=indices[corner] if not indices.is_empty() else corner
   var p:=vertices[index];positions.append_array(PackedFloat32Array([p.x,p.y,p.z]))
   if not ns.is_empty():
    var n:=ns[index];normals.append_array(PackedFloat32Array([n.x,n.y,n.z]))
   if not uvs.is_empty():uv0.append_array(PackedFloat32Array([uvs[index].x,uvs[index].y]))
   if not lm.is_empty():
    var coordinate:=lm[index];uv2.append_array(PackedFloat32Array([coordinate.x,coordinate.y]))
    if coordinate.x<0.0 or coordinate.y<0.0 or coordinate.x>1.0 or coordinate.y>1.0:uv2_outside+=1
   if not ts.is_empty():tangents.append_array(ts.slice(index*4,index*4+4))
 for values:PackedFloat32Array in [positions,normals,uv0,uv2,tangents]:
  for value in values:
   if not is_finite(value):invalid+=1
 var transform:=node.global_transform
 var transform_values:=PackedFloat32Array()
 for column:Vector3 in [transform.basis.x,transform.basis.y,transform.basis.z,transform.origin]:transform_values.append_array(PackedFloat32Array([column.x,column.y,column.z]))
 var hint:=node.mesh.lightmap_size_hint
 return {"surfaces":surfaces,"triangles":triangles,"positions_sha256":_hash(positions),"normals_sha256":_hash(normals),"uv0_sha256":_hash(uv0),"uv2_sha256":_hash(uv2),"tangents_sha256":_hash(tangents),"transform_sha256":_hash(transform_values),"nonfinite_attributes":invalid,"uv2_outside_unit_square":uv2_outside,"lightmap_size_hint":[hint.x,hint.y]}
static func compare(source:Dictionary,baked:Dictionary,include_uv2:bool=false)->Array[String]:
 var mismatches:Array[String]=[]
 for key in ["triangles","positions_sha256","normals_sha256","uv0_sha256","tangents_sha256","transform_sha256"]:
  if source[key]!=baked[key]:mismatches.append(key)
 if source.surfaces.size()!=baked.surfaces.size():mismatches.append("surface_count")
 else:
  for index in source.surfaces.size():
   for key in ["primitive","ordered_vertices","normal","uv0","tangent"]:
    if source.surfaces[index][key]!=baked.surfaces[index][key]:mismatches.append("surface_"+str(index)+"_"+key)
 if baked.nonfinite_attributes!=0:mismatches.append("nonfinite_attributes")
 if include_uv2:
  if source.uv2_sha256!=baked.uv2_sha256:mismatches.append("uv2_sha256")
  # JSON manifests decode numbers as floats. Compare each exact numeric
  # component rather than Array equality, which also compares Variant types.
  if source.lightmap_size_hint.size()!=2 or baked.lightmap_size_hint.size()!=2:
   mismatches.append("lightmap_size_hint")
  elif float(source.lightmap_size_hint[0])!=float(baked.lightmap_size_hint[0]) or float(source.lightmap_size_hint[1])!=float(baked.lightmap_size_hint[1]):
   mismatches.append("lightmap_size_hint")
 return mismatches
static func _hash(values:PackedFloat32Array)->String:
 var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
 context.update(values.to_byte_array());return context.finish().hex_encode()
