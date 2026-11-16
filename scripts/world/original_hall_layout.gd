extends RefCounted
## Authored old-pool circulation. No shared controller, solver or cell-boundary edits.
const Seats=preload("res://scripts/world/original_pool_seating.gd")
const FLOOR=-.72
const DECK=.52
static func build(b:RefCounted)->void:
 _promenade(b)
 # Quiet roof rhythm retained; no isolated upper gallery demanding a purposeless climb.
 for x in [-14,-7,0,7,14]:b.box(x,8.65,0,.32,.6,31)
 for z in [-5,6]:b.box(0,8.65,z,31,.6,.4)
 for x in [-8,8]:b.box(x,(8.9+DECK)*.5,-13.7,.65,8.9-DECK,.65)
 b.sign_board(-5,2.6,-15.68,"禁止\n跳水")
 b.sign_board(10,3.4,-15.68,b.decay_text("泳池\n须知"),0,true)
 # Consume the former variant/lean draws, preserving downstream source RNG ordering.
 if b.layout.variant==2:b.rng.next()
 if b.layout.corrupt>=2:
  for i in 4:b.rng.next()
 Seats.dry_perch(b,Vector2(-14.2,-6),DECK,.98,PI/2)
 Seats.dry_perch(b,Vector2(-14.2,6),DECK,.98,PI/2)
 _ladder(b,"PoolNorthwest",Vector3(-7,-.70,-9.4),Vector3(-7,.54,-10.82),Vector3(-7,.54,-12.0))
 _ladder(b,"PoolNortheast",Vector3(7,-.70,-9.4),Vector3(7,.54,-10.82),Vector3(7,.54,-12.0))
 _pool_steps(b)
 if b.layout.variant==2:_submerged_terrace(b)
 Seats.dry_lifeguard(b,Vector2(13.7,-8),DECK,2.45)
 b.box(13.7,1.94,-7.05,1.6,.12,1.35,"pale").name="LifeguardFootLanding"
 for x in [13.,14.4]:
  for z in [-7.55,-6.5]:b.rod(Vector3(x,DECK,z),Vector3(x,1.94,z),.035)
 _ladder(b,"LifeguardService",Vector3(13.7,.54,-4.9),Vector3(13.7,2.02,-6.195),Vector3(13.7,2.02,-6.85))
 _slide(b)
 # One restrained, source-owned surreal marker outside the principal walking line.
 b.box(-5,.21,7,1.5,1.98,1.5,"pale")
 b.sphere(-5,1.9,7,.8,"chrome")
 b.sign_board(5,2.5,15.68,"出口\n不存在",PI,true)
 if b.layout.variant==1:b.sphere(-3,.87,0,1.6,"yellow")
 b.room.set_meta("original_hall_circulation","dry_ring_v1")

static func _block(b:RefCounted,x:float,z:float,w:float,d:float,top:float)->void:
 b.box(x,(FLOOR+top)*.5,z,w,top-FLOOR,d,"pale").name="PromenadeSupport"
static func _promenade(b:RefCounted)->void:
 # Four portals remain at their original floor datum. Side strips + inner landing
 # form continuous routes around each low entrance stair, not a raised doorway wall.
 for side in [-1.,1.]:
  for split in [-1.,1.]:
   _block(b,split*8.85,side*13.35,13.7,4.7,DECK)
   _block(b,side*13.35,split*6.5,4.7,9.,DECK)
  _block(b,0,side*11.4,4.,1.2,DECK)
  _block(b,side*11.4,0,1.2,4.,DECK)
  for i in 5:
   var top=FLOOR+(i+1)*(DECK-FLOOR)/5.
   var axis=13.35-i*.3
   _block(b,0,side*axis,4.,.3,top)
   _block(b,side*axis,0,.3,4.,top)
 # Thin contrasting coping stays flush, never a hidden collision lip.
 for side in [-1.,1.]:
  b.box(side*11.05,DECK+.006,0,.10,.012,22.,"tile",false)
  for split in [-1.,1.]:b.box(split*6.4,DECK+.006,side*11.05,9.2,.012,.10,"tile",false)

static func _pool_steps(b:RefCounted)->void:
 # Broad south pool stair: .207 m risers, .5 m treads, 3.2 m clear width.
 for i in 6:
  var top=DECK-(i+1)*(DECK-FLOOR)/6.
  if top>FLOOR+.001:_block(b,0,10.75-i*.5,3.2,.5,top)
 for x in [-1.75,1.75]:
  b.rod(Vector3(x,1.42,11.0),Vector3(x,.19,8.0),.035)
  for z in [8.,11.0]:b.rod(Vector3(x,FLOOR if z<9 else DECK,z),Vector3(x,.19 if z<9 else 1.42,z),.035)

static func _submerged_terrace(b:RefCounted)->void:
 # Variant2 keeps its submerged-step identity as an accessible shallow bathing
 # terrace, not an isolated plinth beneath an unrelated gallery ladder.
 _block(b,-10.75,0,.5,5.,.34)
 _block(b,-9.25,0,2.5,5.,.12)
 for i in 3:_block(b,-7.75+i*.5,0,.5,5.,-.09-i*.21)
 b.sign_board(-15.68,2.1,-3.5,"沉阶\n浅水",PI/2)

static func _ladder(b:RefCounted,label:String,base:Vector3,top:Vector3,finish:Vector3)->void:
 # Every rung TOP lies on the actual climb line; the last rung is level with
 # the receiving floor and about .20m before its supported edge.
 var floor_y=base.y-.02;var landing_y=finish.y-.02
 var rise=landing_y-floor_y;var count=int(ceil(rise/.30))
 var direction=(top-base).normalized();var last=Vector3.ZERO
 for i in range(1,count+1):
  var feet_y=floor_y+rise*float(i)/float(count)
  var t=(feet_y-base.y)/(top.y-base.y)
  var p=base.lerp(top,t)-Vector3.UP*.027
  b.rod(p+Vector3(-.43,0,0),p+Vector3(.43,0,0),.027,false)
  last=p
 for side in [-1.,1.]:
  var offset=Vector3(side*.43,0,0)
  var foot=Vector3(base.x+offset.x,floor_y,base.z)
  b.rod(foot,last+offset,.035,false)
  _anchor_flange(b,foot,label+"BottomAnchor")
  var path=_return_path(last+offset,direction,landing_y)
  var landing_foot:Vector3=path.points[-1]-Vector3.UP*.0125
  _anchor_flange(b,landing_foot,label+"LandingAnchor")
  _curved_rail(b,path,label)

 var anchor=Node3D.new();anchor.name=label;b.room.add_child(anchor);anchor.add_to_group("pool_ladders")
 for pair in [["base",base],["top",top],["exit",finish]]:
  anchor.set_meta(pair[0],b.room.to_global(pair[1]));anchor.set_meta("local_"+pair[0],pair[1])
 anchor.set_meta("purpose",label)
 anchor.set_meta("construction",{"last_rung_center":last,"last_rung_top_y":landing_y,"rung_pitch":rise/float(count),"bottom_support_y":floor_y,"landing_support_y":landing_y,"receiving_edge_gap_from_top":.18,"lower_flange_count":2,"upper_flange_count":2})

static func _anchor_flange(b:RefCounted,point:Vector3,label:String)->void:
 var n=b.cylinder(point.x,point.y+.0125,point.z,.075,.025,"metal");n.name=label
 n.set_meta("ladder_anchor",true)

static func _return_path(a:Vector3,direction:Vector3,floor_y:float)->Dictionary:
 # Tangent-continuous standard pipe bends, not a pinched freeform spline.
 # 140mm lower bend and 200mm crown radius exceed the 35mm tube radius.
 var points:Array[Vector3]=[];var normals:Array[Vector3]=[]
 var forward=signf(direction.z);var angle=atan2(direction.y,absf(direction.z))
 for i in 11:
  var phi=lerpf(angle,PI*.5,float(i)/10.)
  points.append(a+Vector3(0,.14*(cos(angle)-cos(phi)),forward*.14*(sin(phi)-sin(angle))))
  normals.append(Vector3(0,sin(phi),forward*cos(phi)).cross(Vector3.RIGHT).normalized())
 var at:Vector3=points[-1];var crown_start=Vector3(at.x,floor_y+.65,at.z)
 for i in range(1,7):
  points.append(at.lerp(crown_start,float(i)/6.));normals.append(Vector3.UP.cross(Vector3.RIGHT))
 for i in range(1,25):
  var phi=PI*float(i)/24.
  points.append(crown_start+Vector3(0,.20*sin(phi),forward*.20*(1.-cos(phi))))
  normals.append(Vector3(0,cos(phi),forward*sin(phi)).cross(Vector3.RIGHT).normalized())
 at=points[-1];var foot=Vector3(at.x,floor_y+.0125,at.z)
 for i in range(1,9):
  points.append(at.lerp(foot,float(i)/8.));normals.append(Vector3.DOWN.cross(Vector3.RIGHT))
 return {"points":points,"normals":normals}

static func _curved_rail(b:RefCounted,path:Dictionary,label:String)->void:
 var points:Array[Vector3]=path.points;var normals:Array[Vector3]=path.normals
 var steps=points.size()-1;var sides=16;var radius=.035
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in steps:
  for j in sides:
   var p:Array[Vector3]=[];var n:Array[Vector3]=[]
   for pair in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,j+1),Vector2i(i,j+1)]:
    var angle=float(pair.y)/float(sides)*TAU;var normal=Vector3.RIGHT*cos(angle)+normals[pair.x]*sin(angle)
    n.append(normal);p.append(points[pair.x]+normal*radius)
   for tri in [[0,1,2],[0,2,3]]:
    if (p[tri[1]]-p[tri[0]]).cross(p[tri[2]]-p[tri[0]]).dot(n[tri[0]])>0:
     var swap=tri[1];tri[1]=tri[2];tri[2]=swap
    for k in tri:st.set_normal(n[k]);st.set_uv(Vector2(float(j)/sides,float(i)/steps));st.add_vertex(p[k])
 st.index();st.generate_tangents()
 var mesh=MeshInstance3D.new();mesh.name=label+"ContinuousRailReturn";mesh.mesh=st.commit();mesh.material_override=b.material("metal");mesh.set_meta("source_role","metal");mesh.set_meta("source_rod",true);mesh.set_meta("minimum_bend_radius",.14);mesh.set_meta("tube_radius",radius);b.room.add_child(mesh)
 for i in steps:
  var delta=points[i+1]-points[i];var shape=CylinderShape3D.new();shape.radius=radius;shape.height=delta.length()
  b.add_shape(shape,Transform3D(Basis(Quaternion(Vector3.UP,delta.normalized())),(points[i]+points[i+1])*.5))

static func _slide(b:RefCounted)->void:
 # Launch bridge has >2.6 m headroom over the east dry promenade.
 b.box(12.0,3.22,1.1,6.,.16,1.8,"pale").name="SlideLaunchLanding"
 for x in [9.15,14.85]:
  for z in [.35,1.85]:
   var support=FLOOR if x<11 else DECK
   b.box(x,(3.14+support)*.5,z,.12,3.14-support,.12,"metal")
 b.rail(11.05,3.3,2.,3.95)
 b.rail(9.,3.3,.2,1.8,false)
 b.rail(9.,3.3,.2,3.3)
 b.rail(14.2,3.3,.2,.8)
 _ladder(b,"SlideDryAccess",Vector3(13.25,.54,-2.7),Vector3(13.25,3.32,.02),Vector3(13.25,3.32,.8))
 var start=Vector3(10,3.3,2);var end=Vector3(10,FLOOR,8)
 var slope=atan2(start.y-end.y,end.z-start.z)
 var slide=b.box(10,(start.y+end.y)*.5,5,1.65,.16,start.distance_to(end),"red",false,Vector3(slope,0,0));slide.name="WalkableSlide"
 var body=StaticBody3D.new();body.name="SlideCollision";body.collision_layer=1;body.collision_mask=0;body.add_to_group("pool_slides");body.set_meta("pool_slide",true);b.room.add_child(body)
 var shape=BoxShape3D.new();shape.size=Vector3(1.65,.16,start.distance_to(end));b.add_shape(shape,slide.transform,body)
 for side in [-1.,1.]:b.rod(start+Vector3(side*.86,.3,0),end+Vector3(side*.86,.3,0),.075)

static func filter_wet_props(b:RefCounted)->void:
 # Source RNG and prop generation remain unchanged; the new low dry deck is below
 # the legacy .65m obstacle cutoff, so reject only these now-dry spawn footprints.
 var kept:Array[Dictionary]=[]
 for spawn:Dictionary in b.layout.prop_spawns:
  var p:Vector3=spawn.position
  var dry=int(b.layout.variant)==1 and p.distance_to(Vector3(-3,.87,0))<1.88
  for a:AABB in b.solids:
   if a.position.y<.32 and a.end.y>=.32 and p.x>a.position.x-.28 and p.x<a.end.x+.28 and p.z>a.position.z-.28 and p.z<a.end.z+.28:
    dry=true;break
  if not dry:kept.append(spawn)
 b.layout.prop_spawns=kept
