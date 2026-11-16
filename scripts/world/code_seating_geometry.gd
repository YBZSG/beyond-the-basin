extends RefCounted
## Small constructed-furniture primitives. No scene/gameplay/material ownership.
static func rounded_box(size:Vector3,radius:float)->Mesh:
 var half=size*.5;var r=minf(radius,minf(half.x,minf(half.y,half.z))*.95)
 var core=half-Vector3.ONE*r;var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for axis in 3:
  var u=(axis+1)%3;var v=(axis+2)%3
  var us=[-half[u],-half[u]+r*.293,-half[u]+r,0.,half[u]-r,half[u]-r*.293,half[u]]
  var vs=[-half[v],-half[v]+r*.293,-half[v]+r,0.,half[v]-r,half[v]-r*.293,half[v]]
  for sign_value in [-1.,1.]:
   for i in 6:
    for j in 6:
     var points:Array=[];var normals:Array=[]
     for ij in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,j+1),Vector2i(i,j+1)]:
      var p=Vector3.ZERO;p[axis]=half[axis]*sign_value;p[u]=us[ij.x];p[v]=vs[ij.y]
      var q=p.clamp(-core,core);var n=(p-q).normalized();points.append(q+n*r);normals.append(n)
     for tri in [[0,1,2],[0,2,3]]:
      if (points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]])[axis]*sign_value>0:
       var swap=tri[1];tri[1]=tri[2];tri[2]=swap
      for k in tri:
       st.set_normal(normals[k]);st.set_uv(Vector2(points[k][u],points[k][v]));st.add_vertex(points[k])
 st.index();st.generate_tangents();return st.commit()
static func node(parent:Node3D,label:String,mesh:Mesh,position:Vector3,material:Material,rotation:Vector3=Vector3.ZERO)->MeshInstance3D:
 var n=MeshInstance3D.new();n.name=label;n.mesh=mesh;n.position=position;n.rotation=rotation;n.material_override=material;n.gi_mode=GeometryInstance3D.GI_MODE_STATIC;parent.add_child(n);return n
