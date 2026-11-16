extends RefCounted
## Pool-facility furniture, preserving source wet-floor/seat/ladder datums.
## No RNG calls, material mutations, water logic or controller changes.
const M=preload("res://scripts/world/code_seating_geometry.gd")
static func lifeguard(builder:RefCounted)->void:
 # Existing four primary legs and the existing ladder remain authored in _old_pool.
 for z in [-.36,-.18,0.,.18,.36]:
  _panel(builder,"LifeguardSeatSlat",Vector3(12,2.45,-7+z),Vector3(1,.13,.16),.02,"pale")
 # Four-degree reclining, individually rounded back slats stay INSIDE old back box.
 var rake=deg_to_rad(4.)
 for i in 6:
  var y=2.575+float(i)*.145
  _panel(builder,"LifeguardBackSlat",Vector3(12,y,-7.4-(y-2.95)*tan(rake)),Vector3(.96,.12,.035),.012,"pale",Vector3(-rake,0,0))
 _source_box_proxy(builder,Vector3(12,2.45,-7),Vector3(1,.13,.9))
 _source_box_proxy(builder,Vector3(12,2.95,-7.4),Vector3(1,.9,.1))
 for sx in [-1.,1.]:
  var x=12+sx*.4225
  # Side arm rail joins the original front/rear posts, leaving ladder frontage open.
  builder.rod(Vector3(x,2.8,-7.39),Vector3(x,2.8,-6.61),.032)
  builder.rod(Vector3(x,2.37,-7.39),Vector3(x,2.37,-6.61),.032)
  builder.rod(Vector3(x,2.8,-7.39),Vector3(x,3.37,-7.43),.026)
  for z in [-7.39,-6.61]:
   _panel(builder,"SeatFrameSaddle",Vector3(x,2.38,z),Vector3(.12,.025,.12),.01,"metal")
 # Rear cross brace stiffens the tall frame without crossing the access ladder.
 builder.rod(_primary_rear_leg(-1.,.3),_primary_rear_leg(1.,1.5),.022)
 builder.rod(_primary_rear_leg(1.,.3),_primary_rear_leg(-1.,1.5),.022)
 builder.rod(Vector3(11.5775,2.37,-7.39),Vector3(12.4225,2.37,-7.39),.032)
 for dx in [-.65,.65]:
  for dz in [-.6,.6]:_foot(builder,Vector3(12+dx,-.709,-7+dz),.075)
static func wet_perch(builder:RefCounted,z:float)->void:
 # 0.78 m seat top = 0.46 m above unchanged water at 0.32; floor remains -0.72.
 for offset in [-.22,0.,.22]:
  _panel(builder,"WetPerchRoundedSlat",Vector3(-13,.72,z+offset),Vector3(2.4,.12,.21),.025,"pale")
 _source_box_proxy(builder,Vector3(-13,.72,z),Vector3(2.4,.12,.65))
 for dx in [-.8,.8]:
  for dz in [-.22,.22]:
   builder.rod(Vector3(-13+dx*1.04,-.78,z+dz*1.1),Vector3(-13+dx,.65,z+dz),.035)
   _foot(builder,Vector3(-13+dx*1.04,-.709,z+dz*1.1),.065)
  builder.rod(Vector3(-13+dx,.625,z-.25),Vector3(-13+dx,.625,z+.25),.028)
  _panel(builder,"WetPerchMountSaddle",Vector3(-13+dx,.65,z),Vector3(.10,.025,.53),.01,"metal")
 # Foot rail intersects two crossrails exactly ON the splayed legs at y=.24.
 var t=(.24+.78)/(.65+.78);var xr=lerpf(.832,.8,t);var zr=lerpf(.242,.22,t)
 for sx in [-1.,1.]:builder.rod(Vector3(-13+sx*xr,.24,z-zr),Vector3(-13+sx*xr,.24,z+zr),.022)
 builder.rod(Vector3(-13-xr,.24,z),Vector3(-13+xr,.24,z),.022)
static func _primary_rear_leg(side:float,y:float)->Vector3:
 var t=(y+.78)/(2.8+.78)
 return Vector3(12+side*lerpf(.65,.4225,t),y,-7-lerpf(.6,.39,t))
static func _panel(builder:RefCounted,label:String,p:Vector3,size:Vector3,r:float,role:String,rotation:Vector3=Vector3.ZERO)->void:
 var n=M.node(builder.room,label,M.rounded_box(size,r),p,builder.material(role),rotation)
 n.set_meta("source_role",role);n.set_meta("seating_part",true)
static func _source_box_proxy(builder:RefCounted,p:Vector3,size:Vector3)->void:
 # Preserve exact legacy broad seat envelopes and prop/water exclusion semantics.
 var shape=BoxShape3D.new();shape.size=size;builder.add_shape(shape,Transform3D(Basis.IDENTITY,p));builder.solids.append(AABB(p-size*.5,size))
static func _foot(builder:RefCounted,p:Vector3,r:float)->void:
 var mesh=CylinderMesh.new();mesh.top_radius=r;mesh.bottom_radius=r;mesh.height=.022;mesh.radial_segments=24;mesh.rings=0
 var n=M.node(builder.room,"PoolSeatAnchorFlange",mesh,p,builder.material("metal"));n.set_meta("source_role","metal");n.set_meta("source_rod",true);n.set_meta("seating_part",true)
 var shape=CylinderShape3D.new();shape.radius=r;shape.height=.022;builder.add_shape(shape,n.transform)

## Optional dry-promenade stations. Legacy functions above remain stable for
## old-layout regression witnesses; only the hall layout owner opts into these.
static func dry_perch(builder:RefCounted,center:Vector2,support_y:float=.52,seat_top:float=.98,yaw:float=0.)->void:
 var rotate=func(point:Vector3)->Vector3:return Vector3(center.x,0,center.y)+Basis(Vector3.UP,yaw)*(point-Vector3(center.x,0,center.y))
 var x=center.x;var z=center.y;var seat_y=seat_top-.06;var leg_top=seat_top-.13
 assert(seat_top-support_y>=.40 and seat_top-support_y<=.55)
 for offset in [-.22,0.,.22]:
  _panel(builder,"DryPerchRoundedSlat",rotate.call(Vector3(x,seat_y,z+offset)),Vector3(2.4,.12,.21),.025,"pale",Vector3(0,yaw,0))
 _oriented_box_proxy(builder,rotate.call(Vector3(x,seat_y,z)),Vector3(2.4,.12,.65),yaw)
 for dx in [-.8,.8]:
  for dz in [-.22,.22]:
   builder.rod(rotate.call(Vector3(x+dx*1.04,support_y,z+dz*1.1)),rotate.call(Vector3(x+dx,leg_top,z+dz)),.035)
   _foot(builder,rotate.call(Vector3(x+dx*1.04,support_y+.011,z+dz*1.1)),.065)
  builder.rod(rotate.call(Vector3(x+dx,seat_top-.155,z-.25)),rotate.call(Vector3(x+dx,seat_top-.155,z+.25)),.028)
  _panel(builder,"DryPerchMountSaddle",rotate.call(Vector3(x+dx,leg_top,z)),Vector3(.10,.025,.53),.01,"metal",Vector3(0,yaw,0))
 var brace_y=support_y+.15;var t=(brace_y-support_y)/(leg_top-support_y);var xr=lerpf(.832,.8,t);var zr=lerpf(.242,.22,t)
 for sx in [-1.,1.]:builder.rod(rotate.call(Vector3(x+sx*xr,brace_y,z-zr)),rotate.call(Vector3(x+sx*xr,brace_y,z+zr)),.022)
 builder.rod(rotate.call(Vector3(x-xr,brace_y,z)),rotate.call(Vector3(x+xr,brace_y,z)),.022)


static func dry_lifeguard(builder:RefCounted,center:Vector2,support_y:float=.52,seat_top:float=2.45)->void:
 # Own every support: no hidden dependence on four rods in the room layout.
 var x=center.x;var z=center.y;var delta=seat_top-2.515;var arm_y=2.8+delta
 assert(seat_top-support_y>1.2)
 for dx in [-.65,.65]:
  for dz in [-.6,.6]:
   builder.rod(Vector3(x+dx,support_y,z+dz),Vector3(x+dx*.65,arm_y,z+dz*.65),.045)
   _foot(builder,Vector3(x+dx,support_y+.011,z+dz),.075)
 for offset in [-.36,-.18,0.,.18,.36]:
  _panel(builder,"DryLifeguardSeatSlat",Vector3(x,seat_top-.065,z+offset),Vector3(1,.13,.16),.02,"pale")
 var rake=deg_to_rad(4.)
 for i in 6:
  var old_y=2.575+float(i)*.145
  _panel(builder,"DryLifeguardBackSlat",Vector3(x,old_y+delta,z-.4-(old_y-2.95)*tan(rake)),Vector3(.96,.12,.035),.012,"pale",Vector3(-rake,0,0))
 _source_box_proxy(builder,Vector3(x,seat_top-.065,z),Vector3(1,.13,.9))
 _source_box_proxy(builder,Vector3(x,2.95+delta,z-.4),Vector3(1,.9,.1))
 for sx in [-1.,1.]:
  var px=x+sx*.4225
  builder.rod(Vector3(px,arm_y,z-.39),Vector3(px,arm_y,z+.39),.032)
  builder.rod(Vector3(px,2.37+delta,z-.39),Vector3(px,2.37+delta,z+.39),.032)
  builder.rod(Vector3(px,arm_y,z-.39),Vector3(px,3.37+delta,z-.43),.026)
  for zz in [z-.39,z+.39]:_panel(builder,"DrySeatFrameSaddle",Vector3(px,2.38+delta,zz),Vector3(.12,.025,.12),.01,"metal")
 var low=support_y+.3;var high=seat_top-.6
 builder.rod(_dry_rear_leg(-1.,low,center,support_y,arm_y),_dry_rear_leg(1.,high,center,support_y,arm_y),.022)
 builder.rod(_dry_rear_leg(1.,low,center,support_y,arm_y),_dry_rear_leg(-1.,high,center,support_y,arm_y),.022)
 builder.rod(Vector3(x-.4225,2.37+delta,z-.39),Vector3(x+.4225,2.37+delta,z-.39),.032)

static func _dry_rear_leg(side:float,y:float,center:Vector2,support_y:float,arm_y:float)->Vector3:
 var t=(y-support_y)/(arm_y-support_y)
 return Vector3(center.x+side*lerpf(.65,.4225,t),y,center.y-lerpf(.6,.39,t))

static func _oriented_box_proxy(builder:RefCounted,p:Vector3,size:Vector3,yaw:float)->void:
 if is_zero_approx(yaw):
  _source_box_proxy(builder,p,size)
  return
 var shape=BoxShape3D.new();shape.size=size;var transform=Transform3D(Basis(Vector3.UP,yaw),p)
 builder.add_shape(shape,transform);builder.solids.append(transform*AABB(-size*.5,size))
