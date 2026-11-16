extends RefCounted
## Hollow-only visual ownership. Original collision/depth shapes remain untouched.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const MARK="hollow_coping_faces_owned"
static func _faces(items:Array)->Array:
 var out:Array=[];var cap_count:=0
 for item:Dictionary in items:
  if item.material!="hollow_visage_coping" or item.collision or not item.mesh is BoxMesh:continue
  var size:Vector3=item.mesh.size
  if absf(size.y-.068)>.000001:continue
  if not ((absf(size.x-.28)<.000001 and absf(size.z-.988)<.000001) or (absf(size.z-.28)<.000001 and absf(size.x-.988)<.000001)):continue
  var arrays:Array=item.mesh.surface_get_arrays(0)
  var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var tr:Transform3D=item.transform
  var lo:=Vector2(INF,INF);var hi:=Vector2(-INF,-INF);var count:=0;var valid:=true
  for i in vertices.size():
   if (tr.basis*normals[i]).dot(Vector3.UP)<.9999:continue
   var point:Vector3=tr*vertices[i]
   if absf(point.y-.4)>.00001:valid=false;break
   lo=lo.min(Vector2(point.x,point.z));hi=hi.max(Vector2(point.x,point.z));count+=1
  if not valid or count<3 or hi.x<=lo.x or hi.y<=lo.y:continue
  cap_count+=1
  var footprint:=Rect2(lo,hi-lo)
  # Derive real BoxMesh face rectangles, not a second authored layout.
  # Only faces sharing the existing deck plane AND outward normal can match.
  for axis in 3:
   var u: int=(axis+1)%3;var v: int=(axis+2)%3
   for sign_v in [-1.,1.]:
    var normal:=Vector3.ZERO;normal[axis]=sign_v
    var face_lo:=Vector2(INF,INF);var face_hi:=Vector2(-INF,-INF);var plane:=0.;var face_count:=0
    for i in vertices.size():
     if (tr.basis*normals[i]).dot(normal)<.9999:continue
     var point:Vector3=tr*vertices[i]
     face_lo=face_lo.min(Vector2(point[u],point[v]));face_hi=face_hi.max(Vector2(point[u],point[v]));plane=point[axis];face_count+=1
    var allowed:bool=(axis==1 and sign_v>0. and absf(plane-.4)<.00001) or (axis==0 and ((sign_v>0. and absf(plane+22.)<.00001) or (sign_v<0. and absf(plane-22.)<.00001))) or (axis==2 and ((sign_v>0. and absf(plane+18.)<.00001) or (sign_v<0. and absf(plane-24.)<.00001)))
    if face_count>=3 and allowed:out.append({"axis":axis,"u":u,"v":v,"plane":plane,"normal":normal,"rect":Rect2(face_lo,face_hi-face_lo),"footprint":footprint})
 if cap_count!=172 or out.size()!=344:
  push_error("Hollow coping visual ownership: expected 172 caps and 344 owned faces")
  return []
 return out
static func _cuts(mask:Dictionary)->Array:
 var r:Rect2=mask.rect
 return [[mask.u,r.position.x,true],[mask.u,r.end.x,false],[mask.v,r.position.y,true],[mask.v,r.end.y,false]]
static func _overlaps(poly:Array,mask:Dictionary)->bool:
 var inside:Array=poly
 for cut:Array in _cuts(mask):inside=G._clip(inside,int(cut[0]),float(cut[1]),bool(cut[2]))
 if inside.size()<3:return false
 var area:=Vector3.ZERO
 for k in range(1,inside.size()-1):area+=(inside[k]-inside[0]).cross(inside[k+1]-inside[0])
 return area.length_squared()>.00000000000000000001
static func _outside(poly:Array,mask:Dictionary)->Array:
 var result:Array=[];var inside:Array=poly
 for cut:Array in _cuts(mask):
  if inside.size()<3:break
  var piece:Array=G._clip(inside,int(cut[0]),float(cut[1]),not bool(cut[2]))
  if piece.size()>=3:result.append(piece)
  inside=G._clip(inside,int(cut[0]),float(cut[1]),bool(cut[2]))
 return result
static func apply(room:Node3D,data:Dictionary,items:Array)->int:
 var node:=room.get_node_or_null(NodePath("Annex_hollow_visage_tile")) as MeshInstance3D
 if node==null or node.has_meta(MARK):return 0
 if not node.mesh is ArrayMesh:return 0
 var source:ArrayMesh=node.mesh
 if source.get_surface_count()!=1 or source.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES:return 0
 var faces:Array=_faces(items)
 if faces.is_empty():return 0
 var arrays:Array=node.mesh.surface_get_arrays(0)
 # These scene-built static meshes have no skinning/custom streams.
 for slot in [Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:
  if arrays[slot]!=null and arrays[slot].size()>0:
   push_warning("Hollow coping visual ownership skipped: unsupported vertex stream")
   return 0
 var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
 var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
 var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
 var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
 var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
 var original_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
 var original_count:=vertices.size()
 assert(normals.size()==original_count and uv.size()==original_count and tangents.size()==original_count*4)
 if original_indices.is_empty():
  for i in original_count:original_indices.append(i)
 var offset:=Vector3(data.coord.x*32.,0,data.coord.y*32.)
 var masks:Array=[];var chunk_rect:=Rect2(offset.x-16.,offset.z-16.,32.,32.)
 for mask:Dictionary in faces:
  if mask.footprint.intersection(chunk_rect).has_area():masks.append(mask)
 var indices:=PackedInt32Array();var changed:=0
 for start in range(0,original_indices.size(),3):
  var ids:Array=[original_indices[start],original_indices[start+1],original_indices[start+2]]
  var points:Array=[];var face_normal:=Vector3.ZERO
  for id:int in ids:points.append(vertices[id]+offset);face_normal+=normals[id]
  face_normal=face_normal.normalized()
  var pieces:Array=[points];var touched:=false
  for mask:Dictionary in masks:
   if face_normal.dot(mask.normal)<.9999:continue
   var same_plane:=true
   for point:Vector3 in points:
    if absf(point[int(mask.axis)]-float(mask.plane))>.00001:same_plane=false;break
   if not same_plane:continue
   var next:Array=[]
   for poly:Array in pieces:
    if _overlaps(poly,mask):next.append_array(_outside(poly,mask));touched=true
    else:next.append(poly)
   pieces=next
  if not touched:
   indices.append_array(PackedInt32Array(ids));continue
  # Original G.box metric mapping is constant over each planar source face.
  for id:int in ids:
   for j in range(4):
    if absf(tangents[id*4+j]-tangents[ids[0]*4+j])>.00001:
     push_warning("Hollow coping visual ownership skipped: varying planar tangent")
     return 0
  changed+=1
  # Project the actual planar triangle, then use scalar float64 determinants.
  # Vector3.dot uses float32 components and cancels badly on long thin faces.
  var plane_normal:Vector3=(points[1]-points[0]).cross(points[2]-points[0])
  var drop:int=plane_normal.abs().max_axis_index()
  var axis_u:int=(drop+1)%3;var axis_v:int=(drop+2)%3
  var ax:float=float(points[0][axis_u]);var ay:float=float(points[0][axis_v])
  var bx:float=float(points[1][axis_u])-ax;var by:float=float(points[1][axis_v])-ay
  var cx:float=float(points[2][axis_u])-ax;var cy:float=float(points[2][axis_v])-ay
  var determinant:float=bx*cy-by*cx
  # Same squared-area degeneracy bound as the former Gram determinant.
  assert(absf(determinant*determinant)>.000000000001)
  for poly:Array in pieces:
   for k in range(1,poly.size()-1):
    var tri:Array=[poly[0],poly[k],poly[k+1]]
    if (tri[1]-tri[0]).cross(tri[2]-tri[0]).length_squared()<.000000000001:continue
    for point:Vector3 in tri:
     var dx:float=float(point[axis_u])-ax;var dy:float=float(point[axis_v])-ay
     var wb:float=(dx*cy-dy*cx)/determinant
     var wc:float=(bx*dy-by*dx)/determinant
     var wa:=1.-wb-wc
     indices.append(vertices.size());vertices.append(point-offset)
     normals.append((normals[ids[0]]*wa+normals[ids[1]]*wb+normals[ids[2]]*wc).normalized())
     uv.append(uv[ids[0]]*wa+uv[ids[1]]*wb+uv[ids[2]]*wc)
     if not uv2.is_empty():uv2.append(uv2[ids[0]]*wa+uv2[ids[1]]*wb+uv2[ids[2]]*wc)
     if not colors.is_empty():colors.append(colors[ids[0]]*wa+colors[ids[1]]*wb+colors[ids[2]]*wc)
     for j in range(4):tangents.append(tangents[ids[0]*4+j])
 if changed>0:
  arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv
  if not uv2.is_empty():arrays[Mesh.ARRAY_TEX_UV2]=uv2
  if not colors.is_empty():arrays[Mesh.ARRAY_COLOR]=colors
  arrays[Mesh.ARRAY_TANGENT]=tangents;arrays[Mesh.ARRAY_INDEX]=indices
  var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  var actual:Array=mesh.surface_get_arrays(0)
  mesh.set_meta("source_static_arrays",{"vertices":actual[Mesh.ARRAY_VERTEX],"indices":actual[Mesh.ARRAY_INDEX]})
  node.mesh=mesh
 node.set_meta(MARK,true)
 return changed
