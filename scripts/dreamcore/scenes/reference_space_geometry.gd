extends RefCounted
## Original mesh construction shared only by the three late-reference spaces.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
static func definition(id:String,title:String,spawn:Vector3,target:Vector3,extent:int,night:bool=false)->Dictionary:
 return {"id":id,"title":title,"subtitle":"原作空间 / 人的尺度与巨大的沉默","bounds":Rect2i(-extent,-extent,extent*2+1,extent*2+1),"spawn":spawn,"look_at":target,"exit":spawn+Vector3(4,0,0),"stations":[],"cameras":[{"position":spawn+Vector3(0,1.6,0),"target":target,"fov":62.0}],"sky_top":Color("0c1722") if night else Color("91b9bd"),"sky_horizon":Color("17272c") if night else Color("d4e0d9"),"ambient":Color("6e8696") if night else Color("d4d9c7"),"ambient_energy":.16 if night else .48,"sun_color":Color("c4d5dc"),"sun_energy":0.0,"sun_rotation":Vector3(-38,-110,0),"sky_shader":"res://shaders/dreamcore/annex_day_sky.gdshader","sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.05,"fog":.0025 if night else .0007}
static func station(id:String,label:String,p:Vector3,kind:String,target:Vector3=Vector3.ZERO)->Dictionary:
 return {"id":id,"label":label,"position":p,"kind":kind,"clue":"慢慢走，留意空间的回声。","target":1,"observation_target":target,"observation_radius":8.0}
static func tube(points:Array,radii:Array,segments:int=16)->Mesh:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings:Array=[]
 for i in points.size():
  var tangent:Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
  var u:Vector3=tangent.cross(Vector3.FORWARD).normalized()
  if u.length()<.1:u=tangent.cross(Vector3.UP).normalized()
  var v:Vector3=tangent.cross(u).normalized();var ring:Array=[]
  for j in segments:ring.append(points[i]+(u*cos(j*TAU/segments)+v*sin(j*TAU/segments))*radii[i])
  rings.append(ring)
 for i in range(rings.size()-1):
  for j in segments:
   var k=(j+1)%segments
   for tri in [[rings[i][j],rings[i+1][j],rings[i+1][k]],[rings[i][j],rings[i+1][k],rings[i][k]]]:
    var center:Vector3=(points[i]+points[i+1])*.5
    if (tri[1]-tri[0]).cross(tri[2]-tri[0]).dot((tri[0]+tri[1]+tri[2])/3.-center)>0:tri.reverse()
    for q in tri:st.add_vertex(q)
 for end in [0,rings.size()-1]:
  for j in segments:
   var tri=[points[end],rings[end][j],rings[end][(j+1)%segments]]
   if end==0:tri.reverse()
   for q in tri:st.add_vertex(q)
 st.generate_normals();return st.commit()
static func beam(a:Array,from:Vector3,to:Vector3,width:float,depth:float,key:String,collision:bool=true)->void:
 var d=to-from;var e=G.box((from+to)*.5,Vector3(width,depth,d.length()),key,collision)
 e.transform.basis=Basis.looking_at(d.normalized(),Vector3.UP);a.append(e)
static func enclosure(a:Array,half:Vector2,height:float,key:String)->void:
 for x in [-half.x-.5,half.x+.5]:a.append(G.box(Vector3(x,height*.5,0),Vector3(1,height,half.y*2+2),key))
 for z in [-half.y-.5,half.y+.5]:a.append(G.box(Vector3(0,height*.5,z),Vector3(half.x*2,height,1),key))
 a.append(G.box(Vector3(0,height+.5,0),Vector3(half.x*2+2,1,half.y*2+2),"dark",false))
