extends RefCounted
## Water-domain geometry only. Existing source vertex displacement and optics remain intact.
static func build(points:Array,density:float)->ArrayMesh:
	var polygon:=PackedVector2Array()
	for p:Array in points:polygon.append(Vector2(p[0],p[1]))
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for p:Vector2 in polygon:bounds=bounds.expand(p)
	var nx:=maxi(1,ceili(bounds.size.x*density));var nz:=maxi(1,ceili(bounds.size.y*density))
	var dx:=bounds.size.x/nx;var dz:=bounds.size.y/nz
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array()
	for z in nz:
		for x in nx:
			var lo:=bounds.position+Vector2(x*dx,z*dz)
			var quad:=PackedVector2Array([lo,lo+Vector2(dx,0),lo+Vector2(dx,dz),lo+Vector2(0,dz)])
			for clipped:PackedVector2Array in Geometry2D.intersect_polygons(quad,polygon):
				# Match PlaneMesh's upward-facing clockwise winding in XZ.
				if Geometry2D.is_polygon_clockwise(clipped):clipped.reverse()
				for j in range(1,clipped.size()-1):
					for i:int in [0,j,j+1]:
						var p:=clipped[i];vertices.append(Vector3(p.x,0,p.y));normals.append(Vector3.UP);uvs.append(p)
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
