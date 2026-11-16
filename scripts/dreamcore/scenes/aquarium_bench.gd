extends RefCounted
## Aquarium-only gallery furniture. Metres; a 460 mm seat on 36 mm sleds.
## Closed, rounded meshes are both visible geometry and exact local collision.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
static func append_to(items:Array,p:Vector3)->void:
 items.append(G.item(_seat(),p,"white",true))
 for x in [-.72,.72]:
  items.append(G.item(_sled(x),p,"metal",true))
  # Thin recessed floor glides establish actual contact rather than floating legs.
  items.append(G.box(p+Vector3(x,.004,.02),Vector3(.032,.008,.23),"dark",true))
static func _triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,outward:Vector3)->void:
 if (b-a).cross(c-a).dot(outward)>0:
  var swap=b;b=c;c=swap
 for v in [a,b,c]:st.add_vertex(v)
static func _seat()->Mesh:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rows:Array=[];var count=96
 # Quarter-round edge profile, not a square slab: 70 mm total thickness.
 for profile in [Vector2(.265,.39),Vector2(.2827,.3973),Vector2(.29,.415),Vector2(.29,.435),Vector2(.2827,.4527),Vector2(.265,.46)]:
  var row:Array=[]
  for i in count:
   var t=TAU*float(i)/count
   var x=.81*(1. if cos(t)>=0. else -1.)+profile.x*cos(t)
   row.append(Vector3(x,profile.y,profile.x*sin(t)+.10*pow(x/1.1,2)))
  rows.append(row)
 for r in range(rows.size()-1):
  for i in count:
   var j=(i+1)%count;var a:Vector3=rows[r][i];var b:Vector3=rows[r][j];var c:Vector3=rows[r+1][j];var d:Vector3=rows[r+1][i]
   var outward=Vector3((a.x+b.x)*.5,((a.y+b.y+c.y+d.y)*.25-.425)*16.,(a.z+b.z)*.5-.04)
   _triangle(st,a,b,c,outward);_triangle(st,a,c,d,outward)
 # Separate flat cap smoothing groups preserve the softly rounded rim.
 st.set_smooth_group(-1)
 for cap in [0,rows.size()-1]:
  var row:Array=rows[cap];var center=Vector3(0,row[0].y,.04)
  for i in count:_triangle(st,center,row[i],row[(i+1)%count],Vector3.DOWN if cap==0 else Vector3.UP)
 st.generate_normals();return st.commit()
static func _sled(x:float)->Mesh:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var centers:Array=[];var rows:Array=[]
 # Rounded rectangle in the side plane; floor rail, upright returns, top rail.
 for corner in [Vector2(.13,.092),Vector2(.13,.316),Vector2(-.13,.316),Vector2(-.13,.092)]:
  var start=-PI*.5 if centers.is_empty() else 0. if centers.size()==9 else PI*.5 if centers.size()==18 else PI
  for i in 9:
   var t=start+float(i)*PI*.5/8.
   centers.append(Vector3(x,corner.y+sin(t)*.066,.02+corner.x+cos(t)*.066))
 for i in centers.size():
  var tangent:Vector3=(centers[(i+1)%centers.size()]-centers[(i-1+centers.size())%centers.size()]).normalized()
  var side=tangent.cross(Vector3.RIGHT).normalized();var row:Array=[]
  for j in 12:
   var t=TAU*float(j)/12.;row.append(centers[i]+.018*(Vector3.RIGHT*cos(t)+side*sin(t)))
  rows.append(row)
 for i in rows.size():
  var next=(i+1)%rows.size()
  for j in 12:
   var k=(j+1)%12;var a:Vector3=rows[i][j];var b:Vector3=rows[next][j];var c:Vector3=rows[next][k];var d:Vector3=rows[i][k]
   var outward=(a+b+c+d)*.25-(centers[i]+centers[next])*.5
   _triangle(st,a,b,c,outward);_triangle(st,a,c,d,outward)
 st.generate_normals();return st.commit()
