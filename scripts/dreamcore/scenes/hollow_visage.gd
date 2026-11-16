extends RefCounted
const CopingVisual=preload("res://scripts/dreamcore/scenes/hollow_coping_visual.gd")
## A physically negative mineral face cast. The nose is behind its wall plane.
## Evaluated CC0 sculpt-base provenance, reconstruction and section evidence are packaged.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const R=preload("res://scripts/dreamcore/scenes/reference_space_geometry.gd")
const FX=preload("res://scripts/dreamcore/uncanny/hollow_visage_effects.gd")
const STATION=preload("res://scripts/dreamcore/uncanny/hollow_visage_station_visuals.gd")
const TILE_RECEIVER=preload("res://scripts/dreamcore/uncanny/hollow_visage_tile_receiver.gd")
const P="hollow_visage_"
const WATER_RECT=Rect2(-22,-18,44,42)
static var _architecture:Array=[]
static func primary_route()->Array:
 return [Vector3(26,.42,10),Vector3(28,.42,32),Vector3(0,.42,37),Vector3(-28,.42,32),Vector3(-28,.42,8),Vector3(-28,.42,-20),Vector3(-28.3,.42,-26),Vector3(-28.3,.42,-41),Vector3(0,.42,-41),Vector3(28.3,.42,-41),Vector3(28.3,.42,-26),Vector3(31,.42,-20),Vector3(28,.42,8),Vector3(28,.42,32),Vector3(26,.42,10)]
static func definition()->Dictionary:
 var d=R.definition("hollow_visage","空面水殿",Vector3(26,.42,10),Vector3(-7.5,10.6,-24),1)
 d.bounds=Rect2i(-1,-1,3,3);d.retain_full_finite_scene=true
 d.subtitle="石头闭着眼 / 鼻尖在墙的另一边"
 d.goal="绕行负形面铸模，切换固定掠射灯，再沿背衬检修廊回看。"
 d.exit=Vector3(28,.4,-47.15)
 d.exit_station={"presentation":"authored","readout":false,"label":"背衬检修门","interaction_offset":Vector3(.38,1.05,.17),"interaction_pose":Vector3(28.2,.42,-45.5),"interaction_alternate_pose":Vector3(27.1,.42,-45.7)}
 d.stations=[{"id":"visage_raking","label":"固定掠射灯柄","kind":"light","presentation":"authored","readout":false,"latch_completion":true,"position":Vector3(26.2,.4,-23.26),"interaction_offset":Vector3(0,1.02,.16),"interaction_pose":Vector3(26.2,.42,-21.55),"interaction_alternate_pose":Vector3(25.1,.42,-21.8),"target":1,"state_count":2,"value_labels":["柔光","固定掠射光"],"action":"切换 / 对照铸模","clue":"鼻的负形藏在墙后。侧光不移动，脸也不转动。"}]
 d.routes=[primary_route(),[Vector3(31,.42,-20),Vector3(26.2,.42,-21.55),Vector3(25.1,.42,-21.8)],[Vector3(28.3,.42,-41),Vector3(28.2,.42,-45.5),Vector3(27.1,.42,-45.7)],[Vector3(0,.42,37),Vector3(0,.42,26),Vector3(0,.28,23.8),Vector3(0,.14,23.3),Vector3(0,.14,-17.3),Vector3(0,.28,-17.8),Vector3(0,.42,-20),Vector3(25.1,.42,-21.8)]]
 d.route_graph={"purpose":"Dry loop around both sides and the flat back of a real negative mould; optional shallow-water crossing.","nodes":{"entry":Vector3(26,.4,10),"left_portal":Vector3(-28.3,.4,-24),"rear_truth":Vector3(0,.4,-41),"raking":Vector3(26.2,.4,-21.55),"right_portal":Vector3(28.3,.4,-24)},"edges":[["entry","left_portal"],["left_portal","rear_truth"],["rear_truth","right_portal"],["right_portal","raking"],["raking","entry"]]}
 d.station_approaches=[{"id":"visage_raking","position":Vector3(26.2,.42,-21.55),"target":Vector3(26.2,1.42,-23.10)},{"id":"departure","position":Vector3(28.2,.42,-45.5),"target":Vector3(28.38,1.45,-46.98)}]
 d.cameras=[{"name":"entry","position":Vector3(26,2.02,10),"target":Vector3(-7.5,10.6,-24),"fov":62.0},{"name":"frontal_bank","position":Vector3(0,2.02,28),"target":Vector3(0,11,-24),"fov":62.0},{"name":"mid","position":Vector3(25,2.02,2),"target":Vector3(0,19,-27),"fov":62.0},{"name":"close_anatomy","position":Vector3(0,2.02,-20),"target":Vector3(0,20,-32),"fov":62.0},{"name":"side_concavity_truth","position":Vector3(23,2.02,-20),"target":Vector3(-2,19,-27),"fov":62.0},{"name":"backing_truth","position":Vector3(0,2.02,-41),"target":Vector3(0,13,-34.8),"fov":62.0},{"name":"reverse","position":Vector3(23,2.02,-20),"target":Vector3(0,10,37),"fov":62.0}]
 # Ordinary lower-face QA view: same proven-supported feet as close_anatomy,
 # only natural mouse-look changes; no zoom or camera-only geometric treatment.
 d.cameras.append({"name":"close_lips_philtrum","position":Vector3(0,2.02,-20),"target":Vector3(0,9.5,-32.5),"fov":62.0})
 d.pool_depth=.20;d.pool_floor_y=.12;d.water_surface_y=.32;d.ceiling_height=44.;d.main_clear_width_min=2.4
 d.ambient=Color("c2bfc8");d.ambient_energy=.04;d.sun_energy=0.;d.exposure=1.06;d.fog=.00045
 d.dimension_evidence={"outer_width":72.,"outer_length":96.,"ceiling_y":44.,"face_wall_plane_z":-24.,"nose_world_z":-33.879622,"backing_world_z":-34.55,"face_height_nominal":34.,"face_width_nominal":23.9807,"all_face_geometry_static":true,"no_eye_nodes":true,"no_runtime_negative_scale":true,"sampled_nose_back_thickness_m":.670378,"retained_finite_cells":9}
 return d
static func layout(coord:Vector2i)->Dictionary:
 return {"coord":coord,"water_enabled":true,"water_floor_y":.12,"water_rects":G.water_rects(coord,WATER_RECT),"solids":[],"spawn_local":Vector3(26,.42,10)-Vector3(coord.x*32,0,coord.y*32)}
static func material_specs()->Dictionary:
 var root="res://assets/dreamcore/uncanny/hollow_visage/";var out:Dictionary={}
 var stone={"albedo":root+"hollow_visage_limestone_albedo.png","normal":root+"hollow_visage_limestone_normal.png","orm":root+"hollow_visage_limestone_orm.png","period":6.4,"strength":.60,"tint":"f2e9da","roughness_channel":"g","specular":.26,"mapping":"world_triplanar","blend_sharpness":1.0}
 out[P+"cast"]=stone
 var wall:Dictionary=stone.duplicate();wall.tint="b6aeb7";wall.period=6.4;wall.strength=.32;out[P+"wall"]=wall
 var coping:Dictionary=G.pbr_specs().white.duplicate();coping.tint="c8c3bd";coping.period=1.2;out[P+"coping"]=coping
 # Owned ceramic glaze refinement; native UV/receiver hook unchanged.
 var floor_spec:Dictionary=G.pbr_specs().tile.duplicate();floor_spec.tint="c8c3bd";floor_spec.period=4.8
 floor_spec.albedo=root+"hollow_visage_glazed_tile_albedo.png";floor_spec.normal=root+"hollow_visage_glazed_tile_normal.png";floor_spec.orm=root+"hollow_visage_glazed_tile_orm.png"
 floor_spec.strength=.58;floor_spec.specular=.5;out[P+"tile"]=floor_spec
 var pool_spec:Dictionary=floor_spec.duplicate();pool_spec.tint="6daca9";out[P+"pool_tile"]=pool_spec
 var steel:Dictionary=G.pbr_specs().metal.duplicate();steel.tint="747a73";out[P+"metal"]=steel
 return out
static func _materials()->void:
 if G._mats.has(P+"cast"):return
 var specs=material_specs()
 for key:String in specs:
  var spec:Dictionary=specs[key];var m:StandardMaterial3D=G.mat("tile").duplicate()
  m.resource_name=key;m.albedo_texture=load(spec.albedo);m.albedo_color=Color(spec.tint);m.normal_texture=load(spec.normal);m.normal_scale=spec.strength;m.normal_enabled=true
  m.roughness_texture=load(spec.orm);m.metallic_texture=m.roughness_texture;m.ao_texture=m.roughness_texture;m.metallic_specular=float(spec.get("specular",.28));m.uv1_scale=Vector3.ONE/float(spec.period)
  if spec.get("mapping","")=="world_triplanar":m.uv1_triplanar=true;m.uv1_world_triplanar=true;m.uv1_triplanar_sharpness=1.
  m.set_meta("annex_pbr_spec",spec);G._mats[key]=m
 for pair in [["joint","54515a"],["brass","a8a18c"],["opal","e2d6ba"],["door","62696b"]]:
  var m=StandardMaterial3D.new();m.resource_name=P+pair[0];m.albedo_color=Color(pair[1]);m.roughness=.73
  if pair[0]=="opal":m.emission_enabled=true;m.emission=Color(pair[1]);m.emission_energy_multiplier=.5
  G._mats[P+pair[0]]=m
static func _coping_and_drain(a:Array)->void:
 # Pool-floor=.12, true decks=.40; two 14cm risers at both ends, never a .28m trap.
 for end_z in [-17.8,23.8]:a.append(G.box(Vector3(0,.19,end_z),Vector3(3.2,.14,.4),P+"pool_tile"))
 for x in [-22.14,22.14]:
  for i in 42:a.append(G.box(Vector3(x,.366,-17.5+i),Vector3(.28,.068,.988),P+"coping",false))
  a.append(G.box(Vector3(x+signf(x)*.25,.404,3),Vector3(.16,.008,42),P+"joint",false))
  for i in 420:a.append(G.box(Vector3(x+signf(x)*.25,.414,-17.95+i*.1),Vector3(.16,.02,.012),P+"metal",false))
 for z in [-18.14,24.14]:
  for i in 44:a.append(G.box(Vector3(-21.5+i,.366,z),Vector3(.988,.068,.28),P+"coping",false))
  a.append(G.box(Vector3(0,.404,z+signf(z)*.25),Vector3(44,.008,.16),P+"joint",false))
  for i in 440:a.append(G.box(Vector3(-21.95+i*.1,.414,z+signf(z)*.25),Vector3(.012,.02,.16),P+"metal",false))
 # Flush movement seals and narrow capillary-break profiles on supported dry banks.
 for x in [-24.0,24.0]:a.append(G.box(Vector3(x,.403,3),Vector3(.016,.006,45),P+"joint",false))
 for z in [-20.0,26.0]:a.append(G.box(Vector3(0,.403,z),Vector3(48,.006,.016),P+"joint",false))
static func _wall_rhythm(a:Array)->void:
 for side in [-1.,1.]:
  for z in [-33.,-18.,-3.,12.,27.,42.]:
   a.append(G.box(Vector3(side*34.78,22,z),Vector3(1.64,43.2,2.0),P+"wall"))
   a.append(G.box(Vector3(side*34.45,.83,z),Vector3(2.30,.86,2.6),P+"coping"))
   a.append(G.box(Vector3(side*34.45,42.9,z),Vector3(2.3,.7,2.6),P+"coping"))
   for dz in [-.68,0.,.68]:
    a.append(G.box(Vector3(side*33.945,22.2,z+dz),Vector3(.035,41.4,.11),P+"joint",false))
    a.append(G.box(Vector3(side*33.91,22.2,z+dz+.09),Vector3(.055,41.4,.075),P+"coping",false))
   # Recessed base uplight with a real grill and protected glass.
   a.append(G.box(Vector3(side*33.5,.62,z),Vector3(.44,.44,.5),P+"metal"))
   a.append(G.box(Vector3(side*33.5,.845,z),Vector3(.34,.014,.32),P+"opal",false))
   for dz in [-.12,-.06,0.,.06,.12]:a.append(G.box(Vector3(side*33.5,.857,z+dz),Vector3(.36,.02,.018),P+"metal",false))
  # High continuous slit windows have deep mineral reveals, not an open ceiling.
  for z in [-10.5,19.5]:
   a.append(G.box(Vector3(side*35.13,35,z),Vector3(.04,13,4.2),P+"opal",false))
   for dz in [-2.18,2.18]:a.append(G.box(Vector3(side*34.96,35,z+dz),Vector3(.4,13.4,.2),P+"coping",false))
  for y in [4.,12.,20.,28.,36.]:a.append(G.box(Vector3(side*35.19,y,0),Vector3(.014,.014,94.4),P+"joint",false))
  for z in [-40.5,-25.5,-10.5,4.5,19.5,34.5]:a.append(G.box(Vector3(side*35.185,22,z),Vector3(.02,43.2,.016),P+"joint",false))
 for z in [-33.,-3.,27.]:
  a.append(G.box(Vector3(0,43.1,z),Vector3(70.4,1.8,2.0),P+"wall"))
  for x in [-33.4,33.4]:a.append(G.box(Vector3(x,42.0,z),Vector3(3.2,.4,2.6),P+"coping"))
static func _cast_material_partitions(source:Mesh)->Dictionary:
 # Exact disjoint triangle partition of ONE closed source casting, not new shape.
 # Warm limestone belongs inside the cavity; exterior block planes match the wall.
 # This avoids an unintended cream rectangular frame around the oval reference.
 var inner=SurfaceTool.new();inner.begin(Mesh.PRIMITIVE_TRIANGLES)
 var outer=SurfaceTool.new();outer.begin(Mesh.PRIMITIVE_TRIANGLES)
 var counts=[0,0]
 for surface in source.get_surface_count():
  var arrays=source.surface_get_arrays(surface);var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
  var size:int=indices.size() if not indices.is_empty() else positions.size()
  for j in range(0,size,3):
   var triangle:Array[int]=[]
   for k in 3:triangle.append(indices[j+k] if not indices.is_empty() else j+k)
   var exterior=false
   for plane in [[0,-14.],[0,14.],[1,.4],[1,37.],[2,0.],[2,-10.55]]:
    var on_plane=true
    for index in triangle:
     if absf(positions[index][plane[0]]-plane[1])>.0001:on_plane=false;break
    if on_plane:exterior=true;break
   var target:SurfaceTool=outer if exterior else inner
   counts[1 if exterior else 0]+=1
   for index in triangle:target.set_normal(normals[index]);target.add_vertex(positions[index])
 var result={"inner":inner.commit(),"outer":outer.commit(),"triangles":counts}
 return result
static func _hero_wall(a:Array)->void:
 # The detailed cast and exact matching aperture are closed manifold source assets.
 # Neither is a convex head placed in a niche; nose-world-Z is approximately -33.88m.
 var cast_source:Mesh=load("res://assets/dreamcore/uncanny/hollow_visage/hollow_visage_cast.obj")
 var cast_parts=_cast_material_partitions(cast_source)
 a.append(G.item(cast_parts.inner,Vector3(0,0,-24),P+"cast",true))
 a.append(G.item(cast_parts.outer,Vector3(0,0,-24),P+"wall",true))
 a.append(G.item(load("res://assets/dreamcore/uncanny/hollow_visage/hollow_visage_wall_frame.obj"),Vector3(0,0,-24),P+"wall",true))
 # A grounded low barrier prevents squeezing into the closed casting seam.
 a.append(G.box(Vector3(0,.92,-23.4),Vector3(22,1.04,1.15),P+"wall"))
 a.append(G.box(Vector3(0,1.49,-23.4),Vector3(22.18,.10,1.33),P+"coping"))
 for x in [-19.3,19.3]:
  a.append(G.box(Vector3(x,22,-23.15),Vector3(1.15,43.2,1.7),P+"wall"))
  for dx in [-.28,.28]:a.append(G.box(Vector3(x+dx,22,-22.286),Vector3(.06,42,.025),P+"joint",false))
 # Backing is deliberately ordinary: a flat structural back, ribs and tie plates.
 a.append(G.box(Vector3(0,22.2,-34.96),Vector3(40,43.6,.82),P+"wall"))
 for x in [-18.,-9.,0.,9.,18.]:
  a.append(G.box(Vector3(x,22,-35.55),Vector3(.6,43.2,.36),P+"coping"))
  for y in [3.,11.,19.,27.,35.,41.]:
   a.append(G.box(Vector3(x,y,-35.78),Vector3(.82,.55,.08),P+"metal",false))
   for dx in [-.27,.27]:a.append(G.cylinder(Vector3(x+dx,y,-35.835),.035,.03,P+"brass",false,Vector3(PI*.5,0,0)))
 for y in [8.,16.,24.,32.,40.]:a.append(G.box(Vector3(0,y,-35.385),Vector3(40,.018,.012),P+"joint",false))
 # Human-scale bypass doors at both sides physically connect front and rear banks.
 for side in [-1.,1.]:
  a.append(G.box(Vector3(side*28,23.6,-24.4),Vector3(16,40.8,.8),P+"wall"))
  for pair in [[23.35,6.7],[32.95,6.1]]:a.append(G.box(Vector3(side*pair[0],1.8,-24.4),Vector3(pair[1],2.8,.8),P+"wall"))
  for x in [26.65,29.95]:a.append(G.box(Vector3(side*x,1.8,-23.94),Vector3(.12,2.8,.14),P+"coping",false))
  a.append(G.box(Vector3(side*28.3,3.24,-23.94),Vector3(3.42,.12,.14),P+"coping",false))
 # Fixed mirrored low crosslights. Both emitters are ahead of real opal lenses,
 # with grounded wall plates and bracket arms; no floating/camera-follow fill.
 for side in [-1.,1.]:
  var lamp_position=FX.HERO_POSITION if side<0. else FX.COUNTER_POSITION
  var lamp_target=FX.HERO_TARGET if side<0. else FX.COUNTER_TARGET
  var direction=(lamp_target-lamp_position).normalized()
  var lamp_rotation=Basis.looking_at(direction,Vector3.UP).get_euler()
  a.append(G.box(Vector3(side*5.8,2.7,-23.91),Vector3(.34,.60,.18),P+"metal",false))
  a.append(G.box(Vector3(side*5.8,2.7,-23.18),Vector3(.11,.12,1.34),P+"metal",false))
  a.append(G.box(Vector3(side*4.9,2.7,-22.45),Vector3(1.8,.12,.12),P+"metal",false))
  a.append(G.box(lamp_position-direction*.30,Vector3(.42,.4,.48),P+"metal",false,lamp_rotation))
  a.append(G.box(lamp_position-direction*.045,Vector3(.30,.29,.018),P+"opal",false,lamp_rotation))
 # Weak real ceiling practical, mounted against the44m roof, not floating at35m.
 a.append(G.box(Vector3(0,43.8,-20),Vector3(1.8,.4,.9),P+"metal",false))
 a.append(G.box(Vector3(0,43.585,-20),Vector3(1.5,.025,.6),P+"opal",false))
 # Rear service light directly on the plain structural backing.
 a.append(G.box(Vector3(0,5,-35.78),Vector3(.7,1.2,.3),P+"metal",false))
 a.append(G.box(Vector3(0,5,-35.95),Vector3(.52,.9,.025),P+"opal",false))
static func _devices(a:Array)->void:
 # Wall-jamb switch: authored identity at (26.2,.4,-23.26), clear of the portal.
 a.append(G.box(Vector3(26.2,1.42,-23.74),Vector3(.32,.52,.54),P+"metal"))
 # Original housing collision/solid is retained verbatim; only its visual batch is hidden.
 a.append(G.box(Vector3(26.2,1.42,-23.38),Vector3(.44,.64,.28),P+"station_collision_hold"))
 # Exact bounded visual replacement belongs to the existing scene-owned actor.
 # Rear low double door is the real exit construction; runtime owns departure.
 a.append(G.box(Vector3(28,1.62,-47.175),Vector3(2.4,2.44,.05),P+"door",false))
 for x in [26.75,29.25]:a.append(G.box(Vector3(x,1.64,-47.1),Vector3(.10,2.48,.16),P+"coping",false))
 a.append(G.box(Vector3(28,2.93,-47.1),Vector3(2.6,.10,.16),P+"coping",false))
 a.append(G.box(Vector3(28,1.62,-47.135),Vector3(.024,2.4,.015),P+"joint",false))
 a.append(G.box(Vector3(28.38,1.45,-47.04),Vector3(.035,.24,.12),P+"brass",false))
 a.append(G.box(Vector3(28,3.15,-47.10),Vector3(.68,.10,.10),P+"opal",false))
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 _materials();var a:Array=[]
 a.append(G.box(Vector3(0,-.19,0),Vector3(72,.62,96),P+"pool_tile"))
 for r in [Rect2(-36,24,72,24),Rect2(-36,-48,72,30),Rect2(-36,-18,14,42),Rect2(22,-18,14,42)]:a.append(G.box(Vector3(r.get_center().x,.26,r.get_center().y),Vector3(r.size.x,.28,r.size.y),P+"tile"))
 for x in [-35.6,35.6]:a.append(G.box(Vector3(x,22.2,0),Vector3(.8,43.6,96),P+"wall"))
 for z in [-47.6,47.6]:a.append(G.box(Vector3(0,22.2,z),Vector3(70.4,43.6,.8),P+"wall"))
 a.append(G.box(Vector3(0,44.2,0),Vector3(72,.4,96),P+"wall",false))
 _coping_and_drain(a);_wall_rhythm(a);_hero_wall(a);_devices(a)
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),true);TILE_RECEIVER.apply_chunk(room);STATION.hide_collision_visual(room)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false);TILE_RECEIVER.apply_chunk(room)
 for spec in practical_light_specs():G.lamp(room,data,spec.position,Color("eadfca"),spec.energy,spec.range)
 CopingVisual.apply(room,data,geometry())
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 _materials();var actor=FX.new();actor.name="HollowVisageFixedRakingLights";root.add_child(actor)

static func practical_light_specs()->Array:
 # Each source sits just ahead of an actual luminous aperture. These are finite,
 # fixed room practicals; window ranges64m are unshadowed and capped to this hall.
 return [
  {"label":"left_base_grill","position":Vector3(-33.5,.90,-18),"energy":16.,"range":33.,"mount_ray":Vector3.DOWN},
  {"label":"right_base_grill","position":Vector3(33.5,.90,-18),"energy":16.,"range":33.,"mount_ray":Vector3.DOWN},
  {"label":"left_high_window","position":Vector3(-34.9,35,19.5),"energy":24.,"range":64.,"mount_ray":Vector3.LEFT},
  {"label":"right_high_window","position":Vector3(34.9,35,19.5),"energy":24.,"range":64.,"mount_ray":Vector3.RIGHT},
  {"label":"ceiling_soft","position":Vector3(0,43.5,-20),"energy":.45,"range":33.,"mount_ray":Vector3.UP},
  {"label":"rear_backing_sconce","position":Vector3(0,5,-36.15),"energy":2.3,"range":33.,"mount_ray":Vector3.BACK}
 ]
