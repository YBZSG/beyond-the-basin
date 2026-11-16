extends RefCounted
## A finite, genuinely tapered perspective set. No camera or collision tricks.
## Dimensions and optical truth are exposed by the constant-scale side gallery.
const G = preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const R = preload("res://scripts/dreamcore/scenes/reference_space_geometry.gd")
const FX = preload("res://scripts/dreamcore/uncanny/parallax_bath_effects.gd")
const PREFIX = "parallax_bath_"
const WATER_RECT = Rect2(-5,-44,10,88)
const BAY_Z_MIN=22.0
const BAY_Z_MAX=39.0
const BAY_EXTRA_DEPTH=3.0
const GALLERY_X_CLEAR = 2.56 * 1.0049875621 # Wall-to-wall2.56m reserves the157.5mm rail/elbow, leaving>=2.4m usable width.
const BEAM_Z = [13.0,-9.0,-25.0,-37.0,-44.0,-48.0]
const BEAM_TOP = [19.2,16.4,13.7,11.9,10.7,9.8]
const BEAM_HEIGHT = [3.1,2.68,2.26,1.84,1.42,1.0]
const BEAM_DEPTH = [3.8,3.25,2.7,2.15,1.6,1.05]
static var _architecture: Array = []
static func half_width(z:float)->float:return 7.0 + clampf((z+50.0)/100.0,0,1)*10.0
static func roof_height(z:float)->float:return 12.0 + clampf((z+50.0)/100.0,0,1)*22.0
static func gallery_center(z:float)->float:return -half_width(z)-.7-GALLERY_X_CLEAR*.5
static func gallery_outer(z:float,extra:float=0.0)->float:return -half_width(z)-.7-GALLERY_X_CLEAR-extra
static func bay_route()->Array:
 return [Vector3(0,.42,53),Vector3(-4,.42,47),Vector3(-10,.42,35),Vector3(gallery_center(35),.42,35),Vector3(gallery_outer(34,BAY_EXTRA_DEPTH)+1.2,.42,34),Vector3(gallery_outer(24,BAY_EXTRA_DEPTH)+1.2,.42,24),Vector3(gallery_center(24),.42,24),Vector3(gallery_center(20),.42,20),Vector3(gallery_center(35),.42,35),Vector3(gallery_center(48),.42,48),Vector3(-18.1,.42,51),Vector3(-13,.42,53),Vector3(0,.42,53)]
static func route()->Array:
 # Authored feet roots are20mm above the unchangedY.4 deck.
 return [Vector3(0,.42,53),Vector3(8,.42,47),Vector3(8,.42,25),Vector3(8,.42,0),Vector3(7.2,.42,-25),Vector3(6,.42,-46),Vector3(0,.42,-47),Vector3(0,.42,-52),Vector3(-9.2,.42,-52),Vector3(gallery_center(-48),.42,-48),Vector3(gallery_center(-25),.42,-25),Vector3(gallery_center(0),.42,0),Vector3(gallery_center(25),.42,25),Vector3(gallery_center(48),.42,48),Vector3(-18.1,.42,51),Vector3(-13,.42,53),Vector3(0,.42,53)]
static func definition()->Dictionary:
 var d=R.definition("parallax_bath","错尺长池",Vector3(0,.42,53),Vector3(0,6,-48),2)
 d.bounds=Rect2i(-1,-2,3,5);d.retain_full_finite_scene=true
 d.subtitle="一百米的错觉 / 同一把尺的两种距离"
 d.goal="沿池岸走到尽头，展开检尺，再从等尺度侧廊返回。"
 d.exit=Vector3(-19,.4,53)
 d.exit_station={"presentation":"authored","readout":false,"label":"复核廊的门把手","interaction_offset":Vector3(.32,1.05,-.22),"interaction_pose":Vector3(-18.6,.42,51.5),"interaction_alternate_pose":Vector3(-19.3,.42,51.5)}
 d.stations=[{"id":"parallax_measure","label":"折叠检尺","kind":"measure","position":Vector3(5.8,.4,-47),"presentation":"authored","latch_completion":true,"interaction_pose":Vector3(5.8,.42,-45.45),"interaction_alternate_pose":Vector3(6.45,.42,-45.55),"interaction_offset":Vector3(0,.95,.26),"readout":false,"target":1,"state_count":2,"value_labels":["检尺收起","检尺展开"],"action":"展开 / 收起检尺","clue":"一米八的尺不会随远近变小。"}]
 d.routes=[route(),bay_route()]
 d.station_approaches=[{"id":"parallax_measure","position":Vector3(5.8,.42,-45.45),"target":Vector3(5.8,1.35,-46.74)},{"id":"departure","position":Vector3(-18.6,.42,51.5),"target":Vector3(-18.68,1.45,52.78)}]
 d.cameras=[{"name":"entry","position":Vector3(-4,2.0,47),"target":Vector3(0,6,-48),"fov":62.0},{"name":"near_join","position":Vector3(-5.9,2.0,40),"target":Vector3(-5.2,.40,40),"fov":62.0},{"name":"far_scale_truth","position":Vector3(5.8,2.0,-45.45),"target":Vector3(7.0,1.4,-47),"fov":62.0},{"name":"gallery_truth","position":Vector3(gallery_center(-26),2.0,-26),"target":Vector3(gallery_center(-6),1.8,-6),"fov":62.0},{"name":"reverse","position":Vector3(0,2.0,-47),"target":Vector3(0,10,48),"fov":62.0},{"name":"mid","position":Vector3(8,2.0,0),"target":Vector3(0,6,-48),"fov":62.0},{"name":"exit_reverse","position":Vector3(-18.6,2.0,51.5),"target":Vector3(-4,5,45),"fov":62.0},{"name":"wall_patch","position":Vector3(-13.0,2.0,18),"target":Vector3(-13.8,1.65,18),"fov":62.0},{"name":"bearing_ground","position":Vector3(8.5,2.0,13),"target":Vector3(13.3,16.0,13),"fov":62.0}]
 d.cameras.append({"name":"wall_glaze","position":Vector3(-13,2,18),"target":Vector3(-13.8,3.5,18),"fov":62.0})
 d.cameras.append({"name":"gallery_bay","position":Vector3(-20,2,34),"target":Vector3(gallery_center(20),1.8,20),"fov":62.0})
 d.technical_cameras=[{"name":"bearing_technical_NOT_PLAYER_VIEW","position":Vector3(11.2,15.3,16),"target":Vector3(13.3,16.1,13),"fov":62.0,"reachable":false}]
 d.pool_depth=.20;d.pool_floor_y=.12;d.water_surface_y=.32;d.main_clear_width_min=2.4;d.gallery_clear_width=2.4;d.gallery_clear_height=2.4;d.real_far_door=Vector3(1.4,2.2,.7);d.ceiling_height=34.0
 d.ambient=Color("c8cbd0");d.ambient_energy=.39;d.sun_energy=0.0;d.exposure=1.04;d.fog=.00045
 d.material_contract={"dry_ceramic_tint":"fbeee6","wall_ceramic_tint":"f1e8e4","dry_roughness_multiplier":.82,"opal_emission":1.8,"gallery_cornice_emission":.8,"rear_service_ceramic":"45534e","beam_soffit":"acb3ad","shadowed_existing_practicals":2,"gallery_floor_constant_pitch_m":.1,"basin_pigment":"b9d4d2","framed_opal_slot_width_m":3.8,"dry_floor_near_pitch_m":.1,"human_gallery_pitch_m":.1,"main_wall_near_pitch_m":.3,"main_wall_far_pitch_m":.075,"wall_grout_near_m":.006,"wall_grout_far_m":.0015,"wall_normal_relief_design_m_approx":.00096,"normal_relief_is_not_geometric_displacement":true}
 d.dimension_evidence={"hall_front_z":50.0,"hall_far_z":-50.0,"front_clear_width":34.0,"far_clear_width":14.0,"front_roof_y":34.0,"far_roof_y":12.0,"level_deck_y":.4,"six_beam_z":BEAM_Z,"six_beam_top_y":BEAM_TOP,"six_beam_height":BEAM_HEIGHT,"six_beam_depth":BEAM_DEPTH,"gallery_perpendicular_width":2.56,"gallery_usable_width_min":2.4,"connected_bay_z":[BAY_Z_MIN,BAY_Z_MAX],"connected_bay_extra_depth":BAY_EXTRA_DEPTH,"no_teleport":true}
 return d
static func layout(coord:Vector2i)->Dictionary:
 return {"coord":coord,"water_enabled":true,"water_floor_y":.12,"water_rects":G.water_rects(coord,WATER_RECT),"solids":[],"spawn_local":Vector3(0,.42,0)}
static func material_specs()->Dictionary:
 var out:Dictionary={};var root="res://assets/dreamcore/uncanny/parallax_bath/"
 for i in 8:
  out[PREFIX+"tile_"+str(i)]={"albedo":root+"ceramic_100mm_albedo.png","normal":root+"ceramic_100mm_normal.png","orm":root+"ceramic_100mm_orm.png","period":lerpf(.34,1.2,float(i)/7.0),"strength":.37,"tint":"fbeee6","roughness_multiplier":.82,"roughness_channel":"g","tile_pitch_m":lerpf(.34,1.2,float(i)/7.0)/12.0,"grout_m_nominal":.002*lerpf(.34,1.2,float(i)/7.0)/1.2}
  # Wall ceramic is a different authored product, not a magnified floor
  # normal. Period controls deliberate300->75mm modules /6->1.5mm joints;
  # inverse normal strength keeps approximate normal-only relief near0.96mm.
  var wall_period=lerpf(.9,3.6,float(i)/7.0)
  var wall:Dictionary=out[PREFIX+"tile_"+str(i)].duplicate()
  wall.orm=root+"wall_glaze_orm.png";wall.tint="f1e8e4";wall.roughness_multiplier=1.0;wall.period=wall_period;wall.strength=.37*1.2/wall_period
  wall.tile_pitch_m=wall_period/12.;wall.grout_m_nominal=.002*wall_period/1.2;wall.glaze_roll_width_m=.0032*wall_period/1.2;wall.normal_relief_reference_m_approx=.00096;wall.finish_role="glossy wall / real forced-perspective module"
  out[PREFIX+"wall_"+str(i)]=wall
  var ceiling:Dictionary=wall.duplicate();ceiling.orm=root+"ceramic_100mm_orm.png";ceiling.strength=.28*1.2/wall_period;ceiling.tint="ddd8d0";ceiling.normal_relief_reference_m_approx=.00073;ceiling.finish_role="dry ceiling ceramic / restrained readable joins"
  out[PREFIX+"ceiling_"+str(i)]=ceiling
 var basin:Dictionary=out[PREFIX+"tile_7"].duplicate();basin.tint="b9d4d2";basin.roughness_multiplier=1.0;basin.finish_role="pale cyan basin ceramic, physical pigment not water shader";out[PREFIX+"basin"]=basin
 var plaster:Dictionary=G.pbr_specs().ivory.duplicate();plaster.tint="c6bdbc";plaster.period=2.1;out[PREFIX+"mineral"]=plaster
 var service:Dictionary=out[PREFIX+"tile_7"].duplicate();service.tint="45534e";service.roughness_multiplier=1.0;service.finish_role="real rear crossgallery charcoal ceramic, not a false doorway";out[PREFIX+"service_tile"]=service
 var soffit:Dictionary=plaster.duplicate();soffit.tint="acb3ad";soffit.finish_role="distinct beam underside finish on disjoint actual faces";out[PREFIX+"beam_soffit"]=soffit
 var coping:Dictionary=G.pbr_specs().white.duplicate();coping.tint="d2d3c8";coping.period=.8;out[PREFIX+"coping"]=coping
 var steel:Dictionary=G.pbr_specs().metal.duplicate();steel.tint="77817e";out[PREFIX+"steel"]=steel
 return out
static func _materials()->void:
 if G._mats.has(PREFIX+"tile_0"):return
 for key:String in material_specs():
  var spec:Dictionary=material_specs()[key];var m:StandardMaterial3D=G.mat("tile").duplicate()
  m.resource_name=key;m.roughness=float(spec.get("roughness_multiplier",1.0));m.albedo_texture=load(spec.albedo);m.albedo_color=Color(spec.tint);m.normal_texture=load(spec.normal);m.normal_scale=spec.strength
  m.roughness_texture=load(spec.orm);m.metallic_texture=m.roughness_texture;m.ao_texture=m.roughness_texture;m.uv1_scale=Vector3.ONE/float(spec.period);m.metallic_specular=.32;m.set_meta("annex_pbr_spec",spec);G._mats[key]=m
 for pair in [["slot","293b3c"],["ruler","d9d3ad"],["mark","27352f"],["seal","6b716a"],["warm_glow","e4ddc5"],["cool_glow","d5e6e9"]]:
  var m=StandardMaterial3D.new();m.resource_name=PREFIX+pair[0];m.albedo_color=Color(pair[1]);m.roughness=.68
  if str(pair[0]).ends_with("glow"):m.emission_enabled=true;m.emission=Color(pair[1]);m.emission_energy_multiplier=1.8 if pair[0]=="cool_glow" else .8
  G._mats[PREFIX+pair[0]]=m
static func _face(st:SurfaceTool,points:Array,expected:Vector3)->void:
 for i in range(1,points.size()-1):
  var tri:Array=[points[0],points[i],points[i+1]]
  if (tri[1]-tri[0]).cross(tri[2]-tri[0]).dot(expected)>0:tri.reverse()
  for p:Vector3 in tri:st.set_normal(expected.normalized());st.add_vertex(p)
static func _solid(a:Array,points:Array,key:String,collision:bool=true)->void:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);var center=Vector3.ZERO
 for p:Vector3 in points:center+=p/8.0
 for ids in [[0,1,2,3],[4,7,6,5],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]]:
  var face:Array=[];var fc=Vector3.ZERO
  for index:int in ids:face.append(points[index]);fc+=points[index]*.25
  var normal:Vector3=(face[1]-face[0]).cross(face[2]-face[0]).normalized()
  if normal.dot(fc-center)<0:normal=-normal
  _face(st,face,normal)
 a.append(G.item(st.commit(),Vector3.ZERO,key,collision))
static func _prism(a:Array,foot:Array,low:Array,high:Array,key:String,collision:bool=true)->void:
 var points:Array=[]
 for i in 4:points.append(Vector3(foot[i].x,low[i],foot[i].y))
 for i in 4:points.append(Vector3(foot[i].x,high[i],foot[i].y))
 _solid(a,points,key,collision)
static func chamfer_box(pos:Vector3,size:Vector3,bevel:float,key:String,collision:bool=true,rotation:Vector3=Vector3.ZERO)->Dictionary:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);var h=size*.5;var b=minf(bevel,minf(h.x,minf(h.y,h.z))*.7)
 for axis in 3:
  var j=(axis+1)%3;var k=(axis+2)%3
  for sign_v in [-1.0,1.0]:
   var face:Array=[];var normal=Vector3.ZERO;normal[axis]=sign_v
   for pair in [[-1.,-1.],[1.,-1.],[1.,1.],[-1.,1.]]:
    var p=Vector3.ZERO;p[axis]=h[axis]*sign_v;p[j]=(h[j]-b)*pair[0];p[k]=(h[k]-b)*pair[1];face.append(p)
   _face(st,face,normal)
 for free_axis in 3:
  var j=(free_axis+1)%3;var k=(free_axis+2)%3
  for sj in [-1.,1.]:
   for sk in [-1.,1.]:
    var face:Array=[];var normal=Vector3.ZERO;normal[j]=sj;normal[k]=sk
    for pair in [[-1.,0.],[1.,0.],[1.,1.],[-1.,1.]]:
     var p=Vector3.ZERO;p[free_axis]=(h[free_axis]-b)*pair[0];p[j]=(h[j]-b*pair[1])*sj;p[k]=(h[k]-b*(1.-pair[1]))*sk;face.append(p)
    _face(st,face,normal)
 for sx in [-1.,1.]:
  for sy in [-1.,1.]:
   for sz in [-1.,1.]:_face(st,[Vector3(h.x*sx,(h.y-b)*sy,(h.z-b)*sz),Vector3((h.x-b)*sx,h.y*sy,(h.z-b)*sz),Vector3((h.x-b)*sx,(h.y-b)*sy,h.z*sz)],Vector3(sx,sy,sz))
 return G.item(st.commit(),pos,key,collision,rotation)
static func _side_wall(a:Array,z0:float,z1:float,sign_v:float,key:String,bottom:float=.4)->void:
 var x0=sign_v*half_width(z0);var x1=sign_v*half_width(z1)
 _prism(a,[Vector2(x0,z0),Vector2(x1,z1),Vector2(x1+sign_v*.7,z1),Vector2(x0+sign_v*.7,z0)],[bottom,bottom,bottom,bottom],[roof_height(z0),roof_height(z1),roof_height(z1),roof_height(z0)],key)
static func _finished_beam(items:Array,item:Dictionary)->void:
 # Partition original triangles by real downward-facing normals. No overlay,
 # duplicate triangles or changed beam volume; collision receives the same faces.
 var arrays=item.mesh.surface_get_arrays(0);var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
 var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
 var groups:Dictionary={}
 for j in range(0,indices.size() if not indices.is_empty() else verts.size(),3):
  var ix:int=indices[j] if not indices.is_empty() else j
  var key:String=PREFIX+"beam_soffit" if normals[ix].y<-.5 else PREFIX+"mineral"
  if not groups.has(key):var tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);groups[key]=tool
  var st:SurfaceTool=groups[key]
  for k in 3:
   var index:int=indices[j+k] if not indices.is_empty() else j+k
   st.set_normal(normals[index]);st.add_vertex(verts[index])
 for key:String in groups:
  var part:Dictionary=item.duplicate();part.mesh=groups[key].commit();part.material=key;items.append(part)
static func _gallery_path(points:Array,height:float,offset:float)->Array:
 var result:Array=[]
 for i in points.size():
  var before:Vector3=points[i]-points[maxi(0,i-1)];var after:Vector3=points[mini(points.size()-1,i+1)]-points[i]
  if before.length()<.01:before=after
  if after.length()<.01:after=before
  var n0=Vector3(before.z,0,-before.x).normalized();var n1=Vector3(after.z,0,-after.x).normalized();var bisector=(n0+n1).normalized()
  var point:Vector3=points[i]+bisector*(offset/maxf(bisector.dot(n0),.1));point.y=height;result.append(point)
 return result
static func _gallery(a:Array)->void:
 # Actual flared bay: deeper outer wall, full return cheeks, closed ceiling,
 # and uninterrupted human-width path. No added freestanding building.
 for run in [[-50.,BAY_Z_MIN,0.,2.8],[BAY_Z_MIN,BAY_Z_MAX,BAY_EXTRA_DEPTH,5.8],[BAY_Z_MAX,50.,0.,2.8]]:
  var za:float=run[0];var zb:float=run[1];var extra:float=run[2];var top:float=run[3]
  var xa=gallery_outer(za,extra);var xb=gallery_outer(zb,extra)
  _prism(a,[Vector2(xa,za),Vector2(xb,zb),Vector2(xb-.35,zb),Vector2(xa-.35,za)],[.4,.4,.4,.4],[top,top,top,top],PREFIX+"tile_7")
  _prism(a,[Vector2(xa-.35,za),Vector2(xb-.35,zb),Vector2(-half_width(zb)-.65,zb),Vector2(-half_width(za)-.65,za)],[top,top,top,top],[top+.25,top+.25,top+.25,top+.25],PREFIX+"mineral")
 for z in [BAY_Z_MIN,BAY_Z_MAX]:
  a.append(G.box(Vector3(gallery_outer(z)-BAY_EXTRA_DEPTH*.5,3.1,z),Vector3(BAY_EXTRA_DEPTH,5.4,.18),PREFIX+"tile_7"))
  a.append(G.box(Vector3(gallery_center(z),4.3,z),Vector3(GALLERY_X_CLEAR,3.0,.18),PREFIX+"mineral"))
 var points:Array=[]
 for pair in [[-50.,0.],[BAY_Z_MIN+.09,0.],[BAY_Z_MIN+.09,BAY_EXTRA_DEPTH],[BAY_Z_MAX-.09,BAY_EXTRA_DEPTH],[BAY_Z_MAX-.09,0.],[50.,0.]]:
  points.append(Vector3(gallery_outer(pair[0],pair[1]),0,pair[0]))
 # The1.05m handrail and2.25m cornice remain real invariant human references.
 # Mitered offsets follow both bay returns rather than floating across the recess.
 var rail=_gallery_path(points,1.45,.13);var track=_gallery_path(points,2.65,.035);var glow=_gallery_path(points,2.65,.075)
 for i in range(points.size()-1):
  R.beam(a,rail[i],rail[i+1],.04,.04,PREFIX+"steel",false)
  R.beam(a,track[i],track[i+1],.08,.08,PREFIX+"steel",false)
  R.beam(a,glow[i],glow[i+1],.008,.045,PREFIX+"warm_glow",false)
  var delta:Vector3=points[i+1]-points[i];var normal=Vector3(delta.z,0,-delta.x).normalized();var count=maxi(1,ceili(delta.length()/2.0))
  for j in count:
   var wall:Vector3=points[i].lerp(points[i+1],(float(j)+.5)/float(count));wall.y=1.37
   R.beam(a,wall+normal*.02,wall+normal*.13,.035,.035,PREFIX+"steel",false)
   a.append(G.box(wall+normal*.13+Vector3.UP*.04,Vector3(.035,.10,.035),PREFIX+"steel",false))
   a.append(G.box(wall+normal*.01,Vector3(.09,.16,.018),PREFIX+"steel",false,Vector3(0,atan2(normal.x,normal.z),0)))
 for i in range(1,rail.size()-1):a.append(G.sphere(rail[i],Vector3.ONE*.055,PREFIX+"steel"))
 R.beam(a,Vector3(gallery_outer(BAY_Z_MIN,BAY_EXTRA_DEPTH)+.035,5.65,BAY_Z_MIN),Vector3(gallery_outer(BAY_Z_MAX,BAY_EXTRA_DEPTH)+.035,5.65,BAY_Z_MAX),.08,.08,PREFIX+"steel",false)
 R.beam(a,Vector3(gallery_outer(BAY_Z_MIN,BAY_EXTRA_DEPTH)+.075,5.65,BAY_Z_MIN),Vector3(gallery_outer(BAY_Z_MAX,BAY_EXTRA_DEPTH)+.075,5.65,BAY_Z_MAX),.008,.045,PREFIX+"warm_glow",false)
 # Rear cross-gallery is 2.4m clear high/deep, continuous through the real door.
 a.append(G.box(Vector3(-4.5,2.925,-51.75),Vector3(12.0,.25,3.5),PREFIX+"mineral"))
 a.append(G.box(Vector3(-4.5,1.6,-53.5),Vector3(12.0,2.4,.3),PREFIX+"service_tile"))
 a.append(G.box(Vector3(1.5,1.6,-52),Vector3(.3,2.4,3.0),PREFIX+"service_tile"))
 a.append(G.box(Vector3(-10.5,1.6,-51.75),Vector3(.3,2.4,3.5),PREFIX+"service_tile"))
 # Entrance porch turns into gallery rather than ending in an invisible barrier.
 a.append(G.box(Vector3(-19,2.925,51.5),Vector3(4.5,.25,3.0),PREFIX+"mineral"))
 a.append(G.box(Vector3(-21.25,1.6,51.5),Vector3(.3,2.4,3.0),PREFIX+"tile_7"))
 a.append(G.box(Vector3(-19.475,1.6,53.15),Vector3(3.55,2.4,.3),PREFIX+"tile_7"))
 a.append(G.box(Vector3(-20.70,1.6,49.85),Vector3(1.1,2.4,.3),PREFIX+"tile_7"))
 # Authored fixed departure leaf and normal-size lever, not a podium.
 a.append(chamfer_box(Vector3(-19,1.49,52.94),Vector3(1.2,2.18,.08),.012,PREFIX+"mineral",false))
 for x in [-19.65,-18.35]:a.append(chamfer_box(Vector3(x,1.51,52.9),Vector3(.09,2.22,.12),.008,PREFIX+"steel",false))
 a.append(chamfer_box(Vector3(-19,2.66,52.9),Vector3(1.39,.09,.12),.008,PREFIX+"steel",false))
 a.append(G.box(Vector3(-18.68,1.45,52.84),Vector3(.20,.035,.05),PREFIX+"steel",false))
 a.append(G.box(Vector3(-18.77,1.45,52.875),Vector3(.035,.16,.05),PREFIX+"steel",false))
 for y in [.75,2.20]:a.append(G.cylinder(Vector3(-19.59,y,52.89),.019,.14,PREFIX+"steel",false))
static func _pool_details(a:Array)->void:
 # Coping and grate channels OWN their footprint: no coplanar floor overlay.
 # Real structural beds stop12mm below the rolled coping;8mm joints reveal
 # that bed. Caps are inset4mm from the tiled vertical bed faces, preventing
 # vertical as well as top coplanarity. Reachable caps have true bevel collision.
 for sign_v in [-1.,1.]:
  a.append(G.box(Vector3(sign_v*5.135,.254,0),Vector3(.27,.268,88),PREFIX+"tile_7"))
  a.append(G.box(Vector3(sign_v*5.285,.26,0),Vector3(.03,.28,88),PREFIX+"tile_7"))
  for i in 88:
   var z=-43.5+float(i)
   a.append(chamfer_box(Vector3(sign_v*5.135,.36,z),Vector3(.262,.08,.992),.012,PREFIX+"coping"))
  # The genuinely recessed channel is only18cm wide, narrower than the player
  # capsule. Fine grate slats are noncritical detail; adjacent solid banks and
  # frame own physical support, not an invisible floor plane at the grate top.
  a.append(G.box(Vector3(sign_v*5.39,.30,0),Vector3(.18,.148,88),PREFIX+"slot"))
  for i in 1100:a.append(G.box(Vector3(sign_v*5.39,.391,-43.96+float(i)*.08),Vector3(.16,.018,.014),PREFIX+"steel",false))
  for x in [5.305,5.475]:a.append(G.box(Vector3(sign_v*x,.387,0),Vector3(.01,.026,88),PREFIX+"steel"))
  for z in [-43.99,43.99]:a.append(G.box(Vector3(sign_v*5.39,.387,z),Vector3(.18,.026,.02),PREFIX+"steel"))
  a.append(G.box(Vector3(sign_v*5.6,.401,0),Vector3(.012,.006,88),PREFIX+"seal",false))
 for sign_v in [-1.,1.]:
  a.append(G.box(Vector3(0,.254,sign_v*44.135),Vector3(10,.268,.27),PREFIX+"tile_7"))
  for i in 10:a.append(chamfer_box(Vector3(-4.5+float(i),.36,sign_v*44.135),Vector3(.992,.08,.262),.012,PREFIX+"coping"))
  for sx in [-1.,1.]:
   a.append(G.box(Vector3(sx*5.135,.254,sign_v*44.135),Vector3(.27,.268,.27),PREFIX+"tile_7"))
   a.append(chamfer_box(Vector3(sx*5.135,.36,sign_v*44.135),Vector3(.262,.08,.262),.012,PREFIX+"coping"))
   a.append(G.box(Vector3(sx*5.375,.26,sign_v*44.135),Vector3(.21,.28,.27),PREFIX+"tile_7"))
  # Two14cm nominal risers meet the real recessed cap edge without a deep gap.
  a.append(G.box(Vector3(0,.19,sign_v*43.8),Vector3(3,.14,.4),PREFIX+"tile_7"))
  for x in [-1.45,1.45]:a.append(G.box(Vector3(x,.262,sign_v*43.8),Vector3(.035,.004,.38),PREFIX+"mark",false))
static func _measure_housing(a:Array)->void:
 # Authored mechanical pedestal (no runtime generic console), mounted outside route.
 a.append(chamfer_box(Vector3(5.8,.79,-47),Vector3(.32,.78,.30),.025,PREFIX+"mineral"))
 a.append(chamfer_box(Vector3(5.8,1.31,-47),Vector3(.40,.26,.33),.035,PREFIX+"steel"))
 a.append(G.cylinder(Vector3(5.8,1.35,-46.83),.035,.09,PREFIX+"steel",false,Vector3(PI*.5,0,0)))
 a.append(G.cylinder(Vector3(5.8,1.35,-46.79),.13,.045,PREFIX+"steel",false,Vector3(PI*.5,0,0)))
 a.append(G.box(Vector3(5.8,1.35,-46.755),Vector3(.045,.18,.025),PREFIX+"ruler",false))
 # A fully protected wall recess: moving ruler stays behind this fixed bezel.
 a.append(G.box(Vector3(7.30,1.38,-47),Vector3(.12,2.06,.58),PREFIX+"slot",false))
 for z in [-47.34,-46.66]:a.append(chamfer_box(Vector3(7.20,1.38,z),Vector3(.26,2.18,.10),.018,PREFIX+"coping"))
 for y in [.29,2.47]:a.append(chamfer_box(Vector3(7.20,y,-47),Vector3(.26,.10,.78),.018,PREFIX+"coping"))
 for y in [.4,1.3,2.2]:a.append(G.box(Vector3(7.12,y,-46.73),Vector3(.012,.018,.14),PREFIX+"mark",false))
 for y in [.56,2.2]:a.append(G.box(Vector3(7.5,y,-47),Vector3(.52,.10,.44),PREFIX+"steel",false))
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 _materials();var a:Array=[]
 # Exact level support; only the basin is .28m below the deck. No rotated low proxies.
 a.append(G.box(Vector3(0,-.19,0),Vector3(80,.62,128),PREFIX+"basin"))
 for i in 8:
  var z0=-50.0+i*12.5;var z1=z0+12.5;var key=PREFIX+"tile_"+str(i);var wall_key=PREFIX+"wall_"+str(i)
  var floor_z0=maxf(z0,-44.27);var floor_z1=minf(z1,44.27)
  if floor_z1>floor_z0:
   a.append(G.box(Vector3(22.74,.26,(floor_z0+floor_z1)*.5),Vector3(34.52,.28,floor_z1-floor_z0),key))
   # Disjoint equal-level deck ownership: the wall's outer edge separates the
   # forced-perspective main finish from the true100mm gallery/bay floor.
   var edge0=-half_width(floor_z0)-.7;var edge1=-half_width(floor_z1)-.7
   _prism(a,[Vector2(-5.48,floor_z0),Vector2(-5.48,floor_z1),Vector2(edge1,floor_z1),Vector2(edge0,floor_z0)],[.12,.12,.12,.12],[.4,.4,.4,.4],key)
   _prism(a,[Vector2(edge0,floor_z0),Vector2(edge1,floor_z1),Vector2(-40,floor_z1),Vector2(-40,floor_z0)],[.12,.12,.12,.12],[.4,.4,.4,.4],PREFIX+"tile_7")
  # Root-approved flared mouth recovers reference proximity without an extra
  # freestanding block. Its full opening is Z30..38 /5.4m high, with a real
  # constant-width gallery behind; dry main circulation is unchanged.
  if z1>30.0 and z0<38.0:
   if z0<30.0:_side_wall(a,z0,30.,-1.,wall_key)
   _side_wall(a,maxf(z0,30.),minf(z1,38.),-1.,wall_key,5.8)
   if z1>38.0:_side_wall(a,38.,z1,-1.,wall_key)
  else:_side_wall(a,z0,z1,-1.,wall_key)
  _side_wall(a,z0,z1,1.,wall_key)
  # Subtle pink upper tile-return band; it does not mask the real sloping ceiling.
  var w0=half_width(z0);var w1=half_width(z1)
  for sign_v in [-1.,1.]:
   var inner0=sign_v*1.9;var inner1=sign_v*1.9
   _prism(a,[Vector2(inner0,z0),Vector2(inner1,z1),Vector2(sign_v*(w1+.7),z1),Vector2(sign_v*(w0+.7),z0)],[roof_height(z0),roof_height(z1),roof_height(z1),roof_height(z0)],[roof_height(z0)+.45,roof_height(z1)+.45,roof_height(z1)+.45,roof_height(z0)+.45],PREFIX+"ceiling_"+str(i))
  # Opal roof slot is visibly framed, not an open missing roof / painted plane.
  _prism(a,[Vector2(-1.9,z0),Vector2(1.9,z0),Vector2(1.9,z1),Vector2(-1.9,z1)],[roof_height(z0)+.04,roof_height(z0)+.04,roof_height(z1)+.04,roof_height(z1)+.04],[roof_height(z0)+.12,roof_height(z0)+.12,roof_height(z1)+.12,roof_height(z1)+.12],PREFIX+"cool_glow",false)
  for x in [-1.93,1.93]:R.beam(a,Vector3(x,roof_height(z0)-.025,z0),Vector3(x,roof_height(z1)-.025,z1),.045,.08,PREFIX+"steel",false)
  a.append(G.box(Vector3(0,roof_height(z0)+.015,z0),Vector3(3.8,.045,.045),PREFIX+"steel",false))
 # Real2.5m rooflight mullions, not an unframed100m luminous strip.
 for j in range(1,40):
  var z=-50.+float(j)*2.5
  if j%5!=0:a.append(G.box(Vector3(0,roof_height(z)+.015,z),Vector3(3.8,.045,.045),PREFIX+"steel",false))
 # Rectangular end banks and supported vestibule keep the pool footprint exact.
 for r in [Rect2(-40,44.27,80,19.73),Rect2(-40,-64,80,19.73)]:a.append(G.box(Vector3(r.get_center().x,.26,r.get_center().y),Vector3(r.size.x,.28,r.size.y),PREFIX+"tile_7"))
 a.append(G.box(Vector3(17.35,17.2,55),Vector3(.7,33.6,10),PREFIX+"wall_7"))
 # The left front portal connects the dry vestibule to the human-scale gallery.
 a.append(G.box(Vector3(-17.35,1.5,56.5),Vector3(.7,2.2,7),PREFIX+"wall_7"))
 a.append(G.box(Vector3(-17.35,18.3,55),Vector3(.7,31.4,10),PREFIX+"wall_7"))
 a.append(G.box(Vector3(0,34.225,55),Vector3(35.4,.45,10),PREFIX+"ceiling_7"))
 a.append(G.box(Vector3(0,17.2,60.35),Vector3(35.4,33.6,.7),PREFIX+"wall_7"))
 # True far door has 1.4m clear width, 2.2m clear headroom, both sides finished.
 for sign_v in [-1.,1.]:a.append(G.box(Vector3(sign_v*3.85,6.2,-50.35),Vector3(6.3,11.6,.7),PREFIX+"wall_0"))
 a.append(G.box(Vector3(0,7.3,-50.35),Vector3(1.4,9.4,.7),PREFIX+"wall_0"))
 for x in [-.745,.745]:a.append(chamfer_box(Vector3(x,1.5,-49.96),Vector3(.09,2.2,.08),.008,PREFIX+"coping",false))
 a.append(chamfer_box(Vector3(0,2.645,-49.96),Vector3(1.58,.09,.08),.008,PREFIX+"coping",false))
 for i in 6:
  var z:float=BEAM_Z[i];var h:float=BEAM_HEIGHT[i];var dep:float=BEAM_DEPTH[i];var y:float=BEAM_TOP[i]-h*.5
  _finished_beam(a,chamfer_box(Vector3(0,y,z),Vector3(half_width(z+dep*.5)*2.0+.12,h,dep),lerpf(.075,.022,float(i)/5.0),PREFIX+"mineral"))
  # Raked bearing plates follow the real tapered masonry exactly. The beam
  # penetrates BOTH end walls over its full depth; no floating near corners.
  for sign_v in [-1.,1.]:
   var z0=z-dep*.5-.12;var z1=z+dep*.5+.12
   _prism(a,[Vector2(sign_v*(half_width(z0)-.10),z0),Vector2(sign_v*(half_width(z1)-.10),z1),Vector2(sign_v*(half_width(z1)+.15),z1),Vector2(sign_v*(half_width(z0)+.15),z0)],[y-h*.5-.14,y-h*.5-.14,y-h*.5-.14,y-h*.5-.14],[y+h*.5+.14,y+h*.5+.14,y+h*.5+.14,y+h*.5+.14],PREFIX+"coping",false)
   R.beam(a,Vector3(sign_v*(half_width(z0)-.105),y-h*.5-.1,z0),Vector3(sign_v*(half_width(z1)-.105),y-h*.5-.1,z1),.02,.02,PREFIX+"seal",false)
   # Genuine shallow raked corbel and compressed bed make the load path legible,
   # not a darker box merely appearing to hang in front of a blank wall.
   var low=y-h*.5
   var foot=[Vector2(sign_v*(half_width(z0)-.65),z0),Vector2(sign_v*(half_width(z1)-.65),z1),Vector2(sign_v*(half_width(z1)+.18),z1),Vector2(sign_v*(half_width(z0)+.18),z0)]
   _prism(a,foot,[low-.22,low-.22,low-.95,low-.95],[low-.025,low-.025,low-.025,low-.025],PREFIX+"coping")
   _prism(a,foot,[low-.025,low-.025,low-.025,low-.025],[low+.015,low+.015,low+.015,low+.015],PREFIX+"seal",false)
 _gallery(a);_pool_details(a);_measure_housing(a)
 # Visible transverse movement joints and capped front corners, not infinite space.
 for z in [-43.,-25.,0.,25.,44.]:
  var half=half_width(z)
  for sign_v in [-1.,1.]:a.append(G.box(Vector3(sign_v*(half+5.6)*.5,.401,z),Vector3(half-5.6,.006,.014),PREFIX+"seal",false))
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:G.build(room,data,geometry(),true)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false)
 for z in [38.,4.,-23.,-44.]:G.lamp(room,data,Vector3(0,roof_height(z)-1.2,z),Color("dce9ec"),3.5,40.)
 for z in [-38.,0.]:G.lamp(room,data,Vector3(gallery_center(z),2.45,z),Color("eee1be"),.35,25.)
 G.lamp(room,data,Vector3(gallery_outer(34.,BAY_EXTRA_DEPTH)+.28,2.45,34.),Color("eed3aa"),1.1,25.)
 G.lamp(room,data,Vector3(-3,2.4,-52),Color("eee1be"),.30,10.)
 # Room-owned practicals: diffuse illumination remains, but their invisible
 # point source does not invent round highlights beside the real rooflight.
 for child in room.get_children():
  if child is OmniLight3D:
   child.light_specular=0.0
   var world_point:Vector3=child.position+Vector3(data.coord.x*32.,0,data.coord.y*32.)
   # Root-approved bounded exception: two existing practicals gain real
   # occlusion, still8 total / unchanged energies. No renderer-only shadow.
   child.shadow_enabled=is_equal_approx(world_point.z,4.0) or (is_equal_approx(world_point.z,34.0) and world_point.x< -20.0)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 _materials();var actor=FX.new();actor.name="ParallaxMeasurement";root.add_child(actor)
