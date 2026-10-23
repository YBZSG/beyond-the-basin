extends RefCounted
## Native unwrap can re-encode imported compressed normal/tangent frames.
## Rebuild the new vertex indexing from ORIGINAL packed records instead. Only
## UV2 changes, using Godot's standard compressed UV representation. No engine
## modification, normal regeneration, geometric tolerance or source-file edit.
static func apply_native_uv2(source:ArrayMesh,unwrapped:ArrayMesh)->Dictionary:
 var output_surfaces:Array=[];var errors:Array[String]=[];var maximum_uv2_error:=0.0
 if source.get_surface_count()!=unwrapped.get_surface_count():return {"mesh":null,"errors":["Native unwrap changed surface count"]}
 var original_surfaces:Array=source.get("_surfaces")
 for surface in source.get_surface_count():
  var src:Dictionary=original_surfaces[surface].duplicate(false)
  var original:=source.surface_get_arrays(surface);var native:=unwrapped.surface_get_arrays(surface)
  var old_count:int=src.vertex_count;var new_count:int=native[Mesh.ARRAY_VERTEX].size()
  var old_indices:PackedInt32Array=original[Mesh.ARRAY_INDEX];var new_indices:PackedInt32Array=native[Mesh.ARRAY_INDEX]
  if old_indices.size()!=new_indices.size() or old_indices.is_empty():errors.append("Expected identical indexed triangle sequence on surface "+str(surface));continue
  var mapping:=PackedInt32Array();mapping.resize(new_count);mapping.fill(-1)
  for corner in old_indices.size():
   var new_index:=new_indices[corner]
   if mapping[new_index]==-1:mapping[new_index]=old_indices[corner]
  if -1 in mapping:errors.append("Native unwrap produced unreferenced vertices");continue
  var format:int=src.format
  var vertex_stride:=RenderingServer.mesh_surface_get_format_vertex_stride(format,old_count)
  var normal_stride:=RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,old_count)
  var attribute_stride:=RenderingServer.mesh_surface_get_format_attribute_stride(format,old_count)
  var skin_stride:=RenderingServer.mesh_surface_get_format_skin_stride(format,old_count)
  var uv2_offset:=RenderingServer.mesh_surface_get_format_offset(format,old_count,Mesh.ARRAY_TEX_UV2)
  if skin_stride!=0 or not (format & Mesh.ARRAY_FORMAT_TEX_UV2):errors.append("Only static imported meshes with original UV2 are supported");continue
  var original_vertex:PackedByteArray=src.vertex_data;var original_attribute:PackedByteArray=src.attribute_data
  var vertex:=PackedByteArray();vertex.resize(new_count*(vertex_stride+normal_stride))
  var attribute:=PackedByteArray();attribute.resize(new_count*attribute_stride)
  var compressed:bool=(format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)!=0
  var uv_scale:Vector4=src.get("uv_scale",Vector4.ZERO)
  var scaled:bool=not uv_scale.is_zero_approx()
  if compressed and scaled:uv_scale.z=2.0;uv_scale.w=2.0
  var native_uv2:PackedVector2Array=native[Mesh.ARRAY_TEX_UV2]
  for index in new_count:
   var old_index:=mapping[index]
   for byte in vertex_stride:vertex[index*vertex_stride+byte]=original_vertex[old_index*vertex_stride+byte]
   for byte in normal_stride:vertex[new_count*vertex_stride+index*normal_stride+byte]=original_vertex[old_count*vertex_stride+old_index*normal_stride+byte]
   for byte in attribute_stride:attribute[index*attribute_stride+byte]=original_attribute[old_index*attribute_stride+byte]
   var coordinate:=native_uv2[index]
   if compressed:
    var encoded:=coordinate*.5+Vector2(.5,.5) if scaled else coordinate
    attribute.encode_u16(index*attribute_stride+uv2_offset,clampi(roundi(encoded.x*65535.0),0,65535))
    attribute.encode_u16(index*attribute_stride+uv2_offset+2,clampi(roundi(encoded.y*65535.0),0,65535))
   else:
    attribute.encode_float(index*attribute_stride+uv2_offset,coordinate.x)
    attribute.encode_float(index*attribute_stride+uv2_offset+4,coordinate.y)
  var index_stride:=2 if new_count<=65536 else 4
  var index_bytes:=PackedByteArray();index_bytes.resize(new_indices.size()*index_stride)
  for index in new_indices.size():
   if index_stride==2:index_bytes.encode_u16(index*2,new_indices[index])
   else:index_bytes.encode_u32(index*4,new_indices[index])
  src.vertex_data=vertex;src.attribute_data=attribute;src.vertex_count=new_count;src.index_data=index_bytes;src.index_count=new_indices.size();src.uv_scale=uv_scale
  # Generated lower-detail indices reference the original vertex layout and
  # do not carry the new charts. This bake candidate deliberately uses full
  # original-detail geometry; it never reuses mismatched LOD/chart indices.
  src.erase("lods")
  output_surfaces.append(src)
 if not errors.is_empty():return {"mesh":null,"errors":errors}
 var result:=ArrayMesh.new();result.set("_surfaces",output_surfaces);result.lightmap_size_hint=unwrapped.lightmap_size_hint
 for surface in result.get_surface_count():
  var actual:PackedVector2Array=result.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV2]
  var expected:PackedVector2Array=unwrapped.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV2]
  for index in actual.size():maximum_uv2_error=maxf(maximum_uv2_error,maxf(absf(actual[index].x-expected[index].x),absf(actual[index].y-expected[index].y)))
 if maximum_uv2_error>2.0/65535.0:errors.append("Unexpected UV2 quantization error")
 return {"mesh":result,"errors":errors,"max_uv2_quantization_error":maximum_uv2_error,"lod_policy":"Full original-detail triangles; old LOD indices cannot address new UV2 vertices"}
