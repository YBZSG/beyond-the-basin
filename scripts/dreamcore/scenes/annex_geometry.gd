extends RefCounted
## Original parametric architecture. Meshes are clipped to 32m terrain cells,
## including reachable walls/stairs. No collider survives a retired chunk.
static var _mats: Dictionary = {}
const PBR_ROOT="res://assets/materials/art_pass/textures/"
static func pbr_specs()->Dictionary:
 var tile={"albedo":PBR_ROOT+"tile_pearl_albedo_2k.png","normal":PBR_ROOT+"tile_normal_gl_2k.png","orm":PBR_ROOT+"tile_pearl_wet_orm_2k.png","period":4.8,"strength":.45,"tint":"ffffff","roughness_channel":"g"}
 var plaster={"albedo":PBR_ROOT+"plaster_oyster_albedo_2k.png","normal":PBR_ROOT+"plaster_normal_gl_2k.png","orm":PBR_ROOT+"plaster_orm_2k.png","period":2.0,"strength":.4,"tint":"ffffff","roughness_channel":"g"}
 var coping={"albedo":PBR_ROOT+"coping_ivory_albedo_1k.png","normal":PBR_ROOT+"coping_normal_gl_1k.png","orm":PBR_ROOT+"coping_orm_1k.png","period":1.0,"strength":.35,"tint":"ffffff","roughness_channel":"g"}
 var out={"tile":tile,"ivory":plaster,"white":coping,"metal":{"albedo":PBR_ROOT+"steel_brushed_albedo_512.png","normal":PBR_ROOT+"steel_normal_gl_512.png","orm":PBR_ROOT+"steel_orm_512.png","period":.25,"strength":.3,"tint":"ffffff","roughness_channel":"g"}}
 for key in ["lime","teal","dark","aqua","lime_tile"]:
  var spec:Dictionary=(tile if key=="lime_tile" else coping if key=="lime" else plaster).duplicate()
  spec.tint={"lime":"a8cf45","lime_tile":"a8cf45","teal":"177c83","dark":"284d50","aqua":"53c5ce"}[key];out[key]=spec
 out.grass={"albedo":"res://assets/dreamcore/outdoor/textures/grass_albedo.png","normal":"res://assets/dreamcore/outdoor/textures/grass_normal.png","orm":"res://assets/dreamcore/outdoor/textures/grass_roughness.png","period":4.0,"strength":.18,"tint":"ffffff","roughness_channel":"r"}
 out.reef=plaster.duplicate();out.reef.tint="246674"
 out.aquatic={"albedo":"res://assets/dreamcore/annex/aquatic_albedo.png","normal":"res://assets/dreamcore/annex/aquatic_normal.png","orm":"res://assets/dreamcore/annex/aquatic_orm.png","period":128.0,"strength":0.0,"tint":"ffffff","roughness_channel":"g","offset":[.5,.5],"emission":.48}
 return out
static func metric_uv(p:Vector3,n:Vector3)->Vector2:
 var a=n.abs()
 if a.y>=a.x and a.y>=a.z:return Vector2(p.x,p.z)
 return Vector2(p.z,p.y) if a.x>a.z else Vector2(p.x,p.y)

static func mat(key:String)->Material:
 if _mats.has(key): return _mats[key]
 var colors={"ivory":Color("e7eddf"),"lime":Color("a8cf45"),"teal":Color("177c83"),"aqua":Color("53c5ce"),"grass":Color("89a952"),"metal":Color("d6e3dc"),"dark":Color("284d50"),"white":Color("f3f4e9")}
 var m:Material
 var specs=pbr_specs()
 if specs.has(key):
  var spec:Dictionary=specs[key];var s=StandardMaterial3D.new();s.resource_name="Annex PBR / "+key
  s.albedo_texture=load(spec.albedo);s.albedo_color=Color(spec.tint)
  s.normal_enabled=true;s.normal_texture=load(spec.normal);s.normal_scale=spec.strength
  s.roughness_texture=load(spec.orm);s.roughness=1.;s.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED if spec.roughness_channel=="r" else BaseMaterial3D.TEXTURE_CHANNEL_GREEN
  if spec.roughness_channel=="g":
   s.metallic_texture=s.roughness_texture;s.metallic_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE;s.metallic=1.;s.ao_enabled=true;s.ao_texture=s.roughness_texture;s.ao_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
  s.uv1_scale=Vector3.ONE/float(spec.period)
  if spec.has("offset"):s.uv1_offset=Vector3(spec.offset[0],spec.offset[1],0)
  if spec.has("emission"):s.emission_enabled=true;s.emission=Color.WHITE;s.emission_texture=s.albedo_texture;s.emission_energy_multiplier=spec.emission
  s.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
  s.set_meta("annex_pbr_spec",spec);m=s
 else:
  var s=StandardMaterial3D.new();s.albedo_color=colors.get(key,Color.WHITE);s.roughness=.32;s.cull_mode=BaseMaterial3D.CULL_DISABLED
  if key in ["glass","clear_glass"]:
   s.albedo_color=Color(.24,.8,.85,.035 if key=="clear_glass" else .17);s.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;s.roughness=.08;s.metallic=.08
  if key=="glow":
   s.albedo_color=Color("c0f4eb");s.emission_enabled=true;s.emission=Color("93e7dd");s.emission_energy_multiplier=.7
  if key=="metal": s.metallic=.75
  if key=="grass":s.roughness=.98
  if key=="teal":s.roughness=.7
  m=s
 _mats[key]=m;return m
static func item(mesh:Mesh,pos:Vector3,key:String,collision:bool=false,rotation:Vector3=Vector3.ZERO,scale_v:Vector3=Vector3.ONE)->Dictionary:
 return {"mesh":mesh,"transform":Transform3D(Basis.from_euler(rotation).scaled(scale_v),pos),"material":key,"collision":collision}
static func box(pos:Vector3,size:Vector3,key:String,collision:bool=true,rotation:Vector3=Vector3.ZERO)->Dictionary:
 var m=BoxMesh.new();m.size=size;return item(m,pos,key,collision,rotation)
static func sphere(pos:Vector3,size:Vector3,key:String)->Dictionary:
 var m=SphereMesh.new();m.radius=.5;m.height=1.;m.radial_segments=12 if size.length()<.5 else 32;m.rings=6 if size.length()<.5 else 16;return item(m,pos,key,false,Vector3.ZERO,size)
static func ring(pos:Vector3,radius:float,tube:float,key:String,rotation:Vector3=Vector3.ZERO)->Dictionary:
 var m=TorusMesh.new();m.inner_radius=radius-tube;m.outer_radius=radius+tube;m.rings=96;m.ring_segments=12
 return item(m,pos,key,false,rotation)
static func cylinder(pos:Vector3,r:float,h:float,key:String,collision:bool=false,rot:Vector3=Vector3.ZERO)->Dictionary:
 var m=CylinderMesh.new();m.top_radius=r;m.bottom_radius=r;m.height=h;m.radial_segments=64;return item(m,pos,key,collision,rot)
static func arc(items:Array,center:Vector3,r:float,width:float,height:float,start:float,end:float,key:String,collision:bool=true,steps:int=96)->void:
 for i in steps:
  var a=lerpf(start,end,float(i)/steps);var b=lerpf(start,end,float(i+1)/steps)
  var points:Array=[]
  for y in [0.,height]:
   for rr in [r-width*.5,r+width*.5]:
    for angle in [a,b]:points.append(center+Vector3(cos(angle)*rr,y,sin(angle)*rr))
  var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
  var mid=(a+b)*.5;var radial=Vector3(cos(mid),0,sin(mid));var tangent=Vector3(-sin(mid),0,cos(mid))
  var faces=[[0,1,3,2,Vector3.DOWN],[4,6,7,5,Vector3.UP],[0,4,5,1,-radial],[2,3,7,6,radial],[0,2,6,4,-tangent],[1,5,7,3,tangent]]
  for face in faces:
   var expected:Vector3=face[4]
   for tri in [[face[0],face[1],face[2]],[face[0],face[2],face[3]]]:
    if (points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]]).dot(expected)>0:
     var tmp=tri[1];tri[1]=tri[2];tri[2]=tmp
    for index in tri:st.set_normal(expected);st.add_vertex(points[index])
  items.append(item(st.commit(),Vector3.ZERO,key,collision))
static func bench(items:Array,p:Vector3)->void:
 items.append(box(p+Vector3(0,.45,0),Vector3(1.8,.13,.55),"ivory"))
 for x in [-.65,.65]: items.append(box(p+Vector3(x,.22,0),Vector3(.09,.44,.42),"metal"))
 items.append(box(p+Vector3(0,.75,-.24),Vector3(1.8,.5,.08),"ivory"))
static func door(items:Array,p:Vector3,rot:float=0.)->void:
 items.append(box(p+Vector3(0,1.15,0),Vector3(1.1,2.3,.07),"dark",false,Vector3(0,rot,0)))
 items.append(box(p+Vector3(.33,1.08,.06),Vector3(.04,.19,.07),"metal",false))
static func _clip(poly:Array,axis:int,edge:float,greater:bool)->Array:
 var out:Array=[]
 if poly.is_empty():return out
 var prev:Vector3=poly[-1];var pin:bool=prev[axis]>=edge if greater else prev[axis]<=edge
 for cur:Vector3 in poly:
  var cin:bool=cur[axis]>=edge if greater else cur[axis]<=edge
  if cin!=pin:out.append(prev.lerp(cur,(edge-prev[axis])/(cur[axis]-prev[axis])))
  if cin:out.append(cur)
  prev=cur;pin=cin
 return out
static func build(root:Node3D,data:Dictionary,items:Array,shell:bool)->void:
 var coord:Vector2i=data.coord;var offset=Vector3(coord.x*32.,0,coord.y*32.)
 var groups:Dictionary={};var vertex_counts:Dictionary={};var coll=PackedVector3Array();var glass_coll=PackedVector3Array()
 var depth_body:StaticBody3D
 if shell:
  depth_body=StaticBody3D.new();depth_body.name="SourceDepthCompatibleProxies";depth_body.collision_layer=0;depth_body.collision_mask=0;root.add_child(depth_body)
 for e:Dictionary in items:
  if bool(e.collision)!=shell:continue
  var mesh:Mesh=e.mesh;var tr:Transform3D=e.transform;var normal_basis:Basis=tr.basis.inverse().transposed();var bounds:AABB=tr*mesh.get_aabb()
  if bounds.end.x<offset.x-16 or bounds.position.x>offset.x+16 or bounds.end.z<offset.z-16 or bounds.position.z>offset.z+16:continue
  var key:String=e.material
  if not groups.has(key):groups[key]=SurfaceTool.new();groups[key].begin(Mesh.PRIMITIVE_TRIANGLES);vertex_counts[key]=0
  var st:SurfaceTool=groups[key]
  for surf in mesh.get_surface_count():
   var arrays=mesh.surface_get_arrays(surf);var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var idx:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
   var count:int=idx.size() if idx.size()>0 else verts.size()
   for j in range(0,count,3):
    var poly:Array=[];var normals:Array=[]
    for k in 3:
     var vi:int=idx[j+k] if idx.size()>0 else j+k
     poly.append(tr*verts[vi]);normals.append((normal_basis*arrays[Mesh.ARRAY_NORMAL][vi]).normalized())
    var original:Array=poly.duplicate()
    var normal:Vector3=-(poly[1]-poly[0]).cross(poly[2]-poly[0]).normalized()
    for axis in [0,2]:
     poly=_clip(poly,axis,offset[axis]-16.,true);poly=_clip(poly,axis,offset[axis]+16.,false)
    for k in range(1,poly.size()-1):
     for v:Vector3 in [poly[0],poly[k],poly[k+1]]:
      var u:Vector3=original[1]-original[0];var w:Vector3=original[2]-original[0];var q:Vector3=v-original[0]
      var denominator:float=u.dot(u)*w.dot(w)-u.dot(w)*u.dot(w)
      if absf(denominator)>.000001:
       var wb:float=(w.dot(w)*q.dot(u)-u.dot(w)*q.dot(w))/denominator
       var wc:float=(u.dot(u)*q.dot(w)-u.dot(w)*q.dot(u))/denominator
       normal=(normals[0]*(1.-wb-wc)+normals[1]*wb+normals[2]*wc).normalized()
      st.set_normal(normal);st.set_uv(metric_uv(v,normal));st.add_vertex(v-offset);vertex_counts[key]+=1
      if shell:
       if key in ["glass","clear_glass"]:glass_coll.append(v-offset)
       else:coll.append(v-offset)
  if shell:
   var lo=Vector3(maxf(bounds.position.x,offset.x-16),bounds.position.y,maxf(bounds.position.z,offset.z-16))-offset
   var hi=Vector3(minf(bounds.end.x,offset.x+16),bounds.end.y,minf(bounds.end.z,offset.z+16))-offset
   data.solids.append(AABB(lo,hi-lo))
   # Unmodified source water collector supports analytic shapes, not trimeshes.
   # Layer-zero, disabled depth-only boxes preserve exact flat floor/deck levels;
   # clipped wall/stair bounds are conservative only outside the shallow pool.
   if bounds.position.y<=.32 and (hi-lo).x>.0001 and (hi-lo).z>.0001:
    var proxy=CollisionShape3D.new();var proxy_shape=BoxShape3D.new();proxy_shape.size=hi-lo;proxy.shape=proxy_shape;proxy.position=(lo+hi)*.5;proxy.disabled=true;proxy.set_meta("source_depth_proxy",true);depth_body.add_child(proxy)
 for key:String in groups:
  if vertex_counts[key]==0:continue
  groups[key].generate_tangents()
  var mesh:Mesh=groups[key].commit()
  if mesh==null or mesh.get_surface_count()==0:continue
  var source_arrays=mesh.surface_get_arrays(0)
  mesh.set_meta("source_static_arrays",{"vertices":source_arrays[Mesh.ARRAY_VERTEX],"indices":source_arrays[Mesh.ARRAY_INDEX] if source_arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()})
  var node=MeshInstance3D.new();node.name="Annex_"+key;node.mesh=mesh;node.material_override=mat(key);root.add_child(node)
  if key in ["glass","clear_glass"]:node.set_meta("source_transmissive",true);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 for transparent in [false,true]:
  var faces:PackedVector3Array=glass_coll if transparent else coll
  if faces.is_empty():continue
  var body=StaticBody3D.new();body.name="ChunkGlazingCollision" if transparent else "ChunkArchitectureCollision"
  if transparent:body.set_meta("dream_observation_transparent",true)
  var shape=ConcavePolygonShape3D.new();shape.set_faces(faces);shape.backface_collision=true
  var cs=CollisionShape3D.new();cs.shape=shape;body.add_child(cs);root.add_child(body)
static func horizon(root:Node3D,items:Array)->void:
 for e:Dictionary in items:
  var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
  var mesh:Mesh=e.mesh;var tr:Transform3D=e.transform;var normal_basis=tr.basis.inverse().transposed()
  for surface in mesh.get_surface_count():
   var a=mesh.surface_get_arrays(surface);var verts:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
   for i in (indices.size() if not indices.is_empty() else verts.size()):
    var j:int=indices[i] if not indices.is_empty() else i;var p:Vector3=tr*verts[j];var normal:Vector3=(normal_basis*a[Mesh.ARRAY_NORMAL][j]).normalized()
    st.set_normal(normal);st.set_uv(metric_uv(p,normal));st.add_vertex(p)
  st.generate_tangents();var n=MeshInstance3D.new();n.mesh=st.commit();n.material_override=mat(e.material);root.add_child(n)
static func water_rects(coord:Vector2i,rect:Rect2)->Array:
 var offset=Vector2(coord.x*32.,coord.y*32.);var local=rect.intersection(Rect2(offset-Vector2(16,16),Vector2(32,32)))
 return [Rect2(local.position-offset,local.size)] if local.has_area() else []

static func ribbon()->Mesh:
 # Closed 40cm-thick architectural strip: no backface holes or paper surface.
 var sections:Array=[];var centers:Array=[];var count=128
 for i in count:
  var t=float(i)*TAU/count;var center=Vector3(cos(t)*6.,sin(t)*9.,sin(t*2.)*2.5)
  var width=Vector3(cos(t)*cos(t),sin(t)*cos(t),sin(t))*2.3
  var tangent=Vector3(-6.*sin(t),9.*cos(t),5.*cos(2.*t)).normalized();var normal=tangent.cross(width).normalized()*.2
  centers.append(center);sections.append([center-width-normal,center+width-normal,center+width+normal,center-width+normal])
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in count:
  var j=(i+1)%count
  for k in 4:
   var q=(k+1)%4;var points=[sections[i][k],sections[j][k],sections[j][q],sections[i][q]]
   var expected:Vector3=(points[0]+points[1]+points[2]+points[3])*.25-(centers[i]+centers[j])*.5
   for tri in [[0,1,2],[0,2,3]]:
    if (points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]]).dot(expected)>0:
     var temp=tri[1];tri[1]=tri[2];tri[2]=temp
    for index in tri:st.add_vertex(points[index])
 st.generate_normals();return st.commit()
static func lamp(root:Node3D,data:Dictionary,point:Vector3,color:Color,energy:float,reach:float)->void:
 var c:Vector2i=data.coord
 if Vector2i(int(floor((point.x+16.)/32.)),int(floor((point.z+16.)/32.)))!=c:return
 var light=OmniLight3D.new();light.position=point-Vector3(c.x*32.,0,c.y*32.);light.light_color=color;light.light_energy=energy;light.light_specular=.25;light.omni_range=reach;light.shadow_enabled=false;root.add_child(light)
static func arch(items:Array,center:Vector3,radius:float,width:float,depth:float,key:String)->void:
 var pieces:Array=[];arc(pieces,Vector3.ZERO,radius,width,depth,0.,PI,key,true,64)
 for piece in pieces:
  piece.transform=Transform3D(Basis(Vector3.RIGHT,-PI*.5),center+Vector3(0,0,depth*.5));items.append(piece)
 for side in [-1.,1.]:items.append(box(Vector3(center.x+side*radius,center.y*.5,center.z),Vector3(width,center.y,depth),key))
static func reef(pos:Vector3,size:Vector3,phase:float)->Dictionary:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings:Array=[]
 for j in 6:
  var row:Array=[];var h=float(j)/5.
  for i in 12:
   var t=float(i)*TAU/12.;var radius=(.7+.18*sin(t*3.+phase+h*4.))*(1.-h*.52)
   row.append(Vector3(cos(t)*radius*size.x+sin(h*4.+phase)*size.x*.15,h*size.y,sin(t)*radius*size.z))
  rings.append(row)
 for j in 5:
  for i in 12:
   var k=(i+1)%12
   for v in [rings[j][i],rings[j][k],rings[j+1][i],rings[j][k],rings[j+1][k],rings[j+1][i]]:st.add_vertex(v)
 for i in 12:
  var center=Vector3(sin(4.+phase)*size.x*.15,size.y,0)
  for v in [center,rings[5][i],rings[5][(i+1)%12]]:st.add_vertex(v)
 st.generate_normals();return item(st.commit(),pos,"reef",false)
static func landscape()->Mesh:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rows:Array=[]
 for z in 49:
  var row:Array=[]
  for x in 65:
   var xx=-320.+x*10.;var zz=-70.-z*10.
   var peaks=0.
   for peak in [Vector3(-155,95,-210),Vector3(160,125,-300),Vector3(-250,70,-420),Vector3(50,55,-480)]:
    var d=Vector2(xx-peak.x,(zz-peak.z)*.8).length();peaks+=peak.y*exp(-d*d/6500.)
   var height=-15.+peaks*(.85+.12*sin(xx*.06)+.08*cos(zz*.07))
   row.append(Vector3(xx,height,zz))
  rows.append(row)
 for z in 48:
  for x in 64:
   for p in [rows[z][x],rows[z+1][x],rows[z][x+1],rows[z][x+1],rows[z+1][x],rows[z+1][x+1]]:st.add_vertex(p)
 st.generate_normals();return st.commit()
static func annulus(items:Array,center:Vector3,inner_radius:float,outer_radius:float,depth:float,key:String)->void:
 var pieces:Array=[];arc(pieces,Vector3.ZERO,(inner_radius+outer_radius)*.5,outer_radius-inner_radius,depth,0.,TAU,key,true,128)
 for piece in pieces:
  piece.transform=Transform3D(Basis(Vector3.RIGHT,-PI*.5),center+Vector3(0,0,depth*.5));items.append(piece)
