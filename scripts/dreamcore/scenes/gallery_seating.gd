extends RefCounted
## Two purpose-built gallery furnishings, not a shared visual bench template.
## Metres. All exposed profiles are closed meshes; runtime owns chunk collision.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
static func lime()->Array:
 var items:Array=[]
 # Continuous moulded seat and gently reclined back, with a genuine rolled bend.
 var path:Array[Vector2]=[Vector2(.452,.265),Vector2(.452,.12),Vector2(.452,-.105)]
 for i in range(1,17):
  var t=float(i)*deg_to_rad(102.)/16.
  path.append(Vector2(.567-.115*cos(t),-.105-.115*sin(t)))
 path.append(Vector2(.865,-.281))
 var profile=_thick_path(path,.024)
 items.append(G.item(_extrude(profile,[Vector2(-1.035,.96),Vector2(-1.026,.985),Vector2(-1.01,1.),Vector2(1.01,1.),Vector2(1.026,.985),Vector2(1.035,.96)]),Vector3.ZERO,"lime",true))
 # Four splayed legs, welded cross rails and actual rounded shell mounting saddles.
 for x in [-.73,.73]:
  for z in [-.155,.165]:
   var top=Vector3(x,.412,z);var bottom=Vector3(x*1.055,.014,z*1.25)
   items.append(_rod(bottom,top,.018,"metal",true))
   items.append(G.cylinder(Vector3(bottom.x,.008,bottom.z),.026,.016,"dark",true))
   items.append(G.cylinder(Vector3(x,.422,z),.05,.02,"metal",true))
  items.append(_rod(Vector3(x,.402,-.155),Vector3(x,.402,.165),.021,"metal",true))
 items.append(_rod(Vector3(-.73,.365,-.155),Vector3(.73,.365,-.155),.013,"metal",true))
 return items
static func oculus()->Array:
 var items:Array=[]
 # The arc in plan repeats the concentric architecture at an intimate scale.
 var plan=_rounded_rectangle(2.24,.61,.14)
 for i in plan.size():plan[i].y+=.11*pow(plan[i].x/1.12,2)
 var seat=_extrude(plan,[Vector2(.39,.975),Vector2(.398,.993),Vector2(.41,1.),Vector2(.442,1.),Vector2(.455,.993),Vector2(.463,.975)])
 # Extrusion local X becomes world Y; the plan profile maps to world X/Z.
 var tr=Transform3D(Basis(Vector3(0,1,0),Vector3(1,0,0),Vector3(0,0,-1)),Vector3.ZERO)
 var e=G.item(seat,Vector3.ZERO,"white",true);e.transform=tr;items.append(e)
 # Real open arch supports: no opaque block inside the portal.
 var arch:Array[Vector2]=[Vector2(.008,.23),Vector2(.16,.23)]
 for i in range(1,25):
  var t=PI*float(i)/24.;arch.append(Vector2(.16+.23*sin(t),.23*cos(t)))
 arch.append(Vector2(.008,-.23));arch.append(Vector2(.008,-.14));arch.append(Vector2(.16,-.14))
 for i in range(1,25):
  var t=PI-PI*float(i)/24.;arch.append(Vector2(.16+.14*sin(t),.14*cos(t)))
 arch.append(Vector2(.008,.14))
 for x in [-.74,.74]:
  # Shallow circular saddle spreads the crown load into the seat underside.
  items.append(G.cylinder(Vector3(x,.388,-.03),.09,.024,"white",true))
  items.append(G.item(_extrude(arch,[Vector2(-.082,.97),Vector2(-.072,1.),Vector2(.072,1.),Vector2(.082,.97)]),Vector3(x,0,-.03),"white",true))
  for z in [-.185,.185]:items.append(G.box(Vector3(x,.004,z-.03),Vector3(.12,.008,.065),"dark",true))
 # A recessed circular lime medallion is a detail, not a large bright seat slab.
 items.append(G.cylinder(Vector3(.88,.464,-.035),.055,.003,"lime",false))
 return items
static func placed(items:Array,p:Vector3,angle:float)->Array:
 var tr=Transform3D(Basis(Vector3.UP,angle),p)
 for part:Dictionary in items:part.transform=tr*part.transform
 return items
static func _rod(a:Vector3,b:Vector3,r:float,key:String,collision:bool)->Dictionary:
 var mesh=CylinderMesh.new();mesh.top_radius=r;mesh.bottom_radius=r;mesh.height=a.distance_to(b);mesh.radial_segments=20;mesh.rings=0
 var item=G.item(mesh,(a+b)*.5,key,collision);item.transform.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()));return item
static func _thick_path(path:Array[Vector2],radius:float)->Array[Vector2]:
 var profile:Array[Vector2]=[];var normals:Array[Vector2]=[]
 for i in path.size():
  var tangent=(path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]).normalized()
  normals.append(Vector2(-tangent.y,tangent.x))
 for i in path.size():profile.append(path[i]+normals[i]*radius)
 var tangent_end=(path[-1]-path[-2]).normalized()
 for j in range(1,9):
  var t=PI*float(j)/8.;profile.append(path[-1]+radius*(normals[-1]*cos(t)+tangent_end*sin(t)))
 for i in range(path.size()-2,-1,-1):profile.append(path[i]-normals[i]*radius)
 var tangent_start=(path[1]-path[0]).normalized()
 for j in range(1,8):
  var t=PI*float(j)/8.;profile.append(path[0]+radius*(-normals[0]*cos(t)-tangent_start*sin(t)))
 return profile
static func _rounded_rectangle(length:float,depth:float,r:float)->Array[Vector2]:
 var out:Array[Vector2]=[]
 for i in 4:
  var angle=float(i)*PI*.5
  var center=Vector2((length*.5-r)*(1. if i in [0,3] else -1.),(depth*.5-r)*(1. if i<2 else -1.))
  for j in 9:
   var t=angle+float(j)*PI*.5/8.;out.append(center+Vector2(cos(t),sin(t))*r)
 return out
static func _extrude(profile:Array[Vector2],layers:Array)->Mesh:
 var center=Vector2.ZERO
 for p in profile:center+=p
 center/=profile.size()
 var area=0.
 for i in profile.size():area+=profile[i].cross(profile[(i+1)%profile.size()])
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rows:Array=[]
 for layer:Vector2 in layers:
  var row:Array[Vector3]=[]
  for p in profile:
   var q=center+(p-center)*layer.y;row.append(Vector3(layer.x,q.x,q.y))
  rows.append(row)
 for r in range(rows.size()-1):
  for i in profile.size():
   var j=(i+1)%profile.size();var edge=profile[j]-profile[i]
   var outward=Vector3(0,edge.y,-edge.x)*(1. if area>0. else -1.)
   _triangle(st,rows[r][i],rows[r][j],rows[r+1][j],outward)
   _triangle(st,rows[r][i],rows[r+1][j],rows[r+1][i],outward)
 st.set_smooth_group(-1)
 var triangles=Geometry2D.triangulate_polygon(PackedVector2Array(profile))
 assert(triangles.size()>0,"Seat profile must be a simple polygon")
 for r in [0,rows.size()-1]:
  for j in range(0,triangles.size(),3):_triangle(st,rows[r][triangles[j]],rows[r][triangles[j+1]],rows[r][triangles[j+2]],Vector3.LEFT if r==0 else Vector3.RIGHT)
 st.generate_normals();return st.commit()
static func _triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,outward:Vector3)->void:
 if (b-a).cross(c-a).dot(outward)>0:
  var swap=b;b=c;c=swap
 for v in [a,b,c]:st.add_vertex(v)
