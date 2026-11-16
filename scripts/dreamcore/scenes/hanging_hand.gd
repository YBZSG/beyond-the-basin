extends RefCounted
## Custom-posed CC0 anatomical hand by Dan Ulrich (Blender Human Base Meshes).
## See assets/dreamcore/late_references/ANATOMICAL_HAND_PROVENANCE.md.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const R=preload("res://scripts/dreamcore/scenes/reference_space_geometry.gd")
const SanctuaryMaterial=preload("res://assets/dreamcore/materials/hand_sanctuary_tile_planar_clip.tres")
static var _architecture:Array=[]
static func definition()->Dictionary:
 var d=R.definition("hanging_hand","悬手浅池",Vector3(-9,.42,26),Vector3(0,7,-4),2)
 d.stations=[R.station("hand_light","顶光的温度",Vector3(-19,.4,19),"light"),R.station("hand_flow","指尖下的涟漪",Vector3(18,.4,12),"flow"),R.station("hand_observe","五根手指的影子",Vector3(0,.4,19),"observe",Vector3(0,6.529871,-1.687115))]
 d.routes=[[Vector3(0,.4,28),Vector3(-24,.4,20),Vector3(-24,.4,-22),Vector3(24,.4,-22),Vector3(24,.4,20),Vector3(0,.4,28)]]
 # hand_height is descriptive highest world Y, not the 12.902373 m mesh extent.
 d.pool_depth=.45;d.pool_floor_y=-.13;d.water_surface_y=.32;d.water_depth_geometry_version="hand-wade045-horizontal-steps-v1";d.hand_height=13.582358
 # Optional wading paths supplement, never replace, the unchanged dry circuit.
 d.routes.append([Vector3(0,.42,13),Vector3(0,.24,11.6),Vector3(0,.06,10.8),Vector3(0,-.11,9.6)])
 d.routes.append([Vector3(-12,.42,-21),Vector3(-12,.24,-19.6),Vector3(-12,.06,-18.8),Vector3(-12,-.11,-17.6)])
 return d
static func pool_steps()->Array[AABB]:
 # Single source for real geometry and the compatibility water_field reader.
 return [AABB(Vector3(-1.6,-.13,11.2),Vector3(3.2,.35,.8)),AABB(Vector3(-1.6,-.13,10.4),Vector3(3.2,.17,.8)),AABB(Vector3(-13.6,-.13,-20),Vector3(3.2,.35,.8)),AABB(Vector3(-13.6,-.13,-19.2),Vector3(3.2,.17,.8))]
static func layout(coord:Vector2i)->Dictionary:
 var steps:Array[AABB]=[]
 for step:AABB in pool_steps():
  for rect:Rect2 in G.water_rects(coord,Rect2(Vector2(step.position.x,step.position.z),Vector2(step.size.x,step.size.z))):
   steps.append(AABB(Vector3(rect.position.x,step.position.y,rect.position.y),Vector3(rect.size.x,step.size.y,rect.size.y)))
 return {"coord":coord,"water_enabled":true,"water_floor_y":-.13,"water_steps":steps,"water_rects":G.water_rects(coord,Rect2(-18,-20,36,32)),"solids":[],"spawn_local":Vector3(0,.42,28)}
static func material_spec()->Dictionary:
 var spec:Dictionary=G.pbr_specs().tile.duplicate();spec.albedo="res://assets/dreamcore/late_references/sanctuary_tile_ai_albedo.png";spec.period=1.2;return spec
static func sculpture_spec()->Dictionary:
 return {"albedo":"res://assets/dreamcore/late_references/hanging_hand_stone_albedo.png","normal":"res://assets/dreamcore/late_references/hanging_hand_stone_normal.png","orm":"res://assets/dreamcore/late_references/hanging_hand_stone_orm.png","period":4.8,"strength":.32,"tint":"ffffff","roughness_channel":"g","specular":.3,"mapping":"world_triplanar","blend_sharpness":1.0}
static func _materials_ready()->void:
 if G._mats.has("sanctuary_tile"):return
 # Official Godot-generated PBR, unchanged main view; marker-only planar underside clip.
 assert(SanctuaryMaterial is ShaderMaterial,"Hand sanctuary requires the exact installed planar-clip ShaderMaterial")
 G._mats["sanctuary_tile"]=SanctuaryMaterial
 var spec:Dictionary=sculpture_spec();var stone:StandardMaterial3D=G.mat("ivory").duplicate()
 stone.resource_name="Hand / neutral weathered limestone";stone.albedo_color=Color(spec.tint);stone.albedo_texture=load(spec.albedo)
 stone.normal_texture=load(spec.normal);stone.normal_scale=spec.strength;stone.roughness_texture=load(spec.orm);stone.metallic_texture=stone.roughness_texture;stone.ao_texture=stone.roughness_texture;stone.metallic_specular=spec.specular
 stone.uv1_scale=Vector3.ONE/spec.period;stone.uv1_triplanar=true;stone.uv1_world_triplanar=true;stone.uv1_triplanar_sharpness=spec.blend_sharpness
 stone.set_meta("annex_pbr_spec",spec);G._mats["sculpted_stone"]=stone
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 _materials_ready()
 # Replace the original slab, never overlay it: top -.13, bottom -.75.
 # Same authored material/UV scale, source collision and depth proxy all derive
 # from these exact boxes through G.build; no legacy top .12 collider remains.
 var a:Array=[G.box(Vector3(0,-.44,0),Vector3(64,.62,72),"sanctuary_tile")]
 for b in [Rect2(-32,12,64,24),Rect2(-32,-36,64,16),Rect2(-32,-20,14,32),Rect2(18,-20,14,32)]:a.append(G.box(Vector3(b.get_center().x,.135,b.get_center().y),Vector3(b.size.x,.53,b.size.y),"sanctuary_tile"))
 # Dry banks retain top .40, but their structural sides now reach -.13.
 # Two independent reversible entries: 3.2m clear width, .8m treads,
 # .40 -> .22 -> .04 -> -.13, without touching sculpture or doorway sweeps.
 # Each tread rests on the new base and owns only its horizontal interval.
 for step:AABB in pool_steps():a.append(G.box(step.get_center(),step.size,"sanctuary_tile"))
 R.enclosure(a,Vector2(32,36),38,"sanctuary_tile")
 a.append(G.box(Vector3(0,37.9,0),Vector3(64,.15,72),"sanctuary_tile",false))
 # Turquoise inlaid lanes remain flush and do not interrupt shallow-water bounds.
 for x in [-21.,21.]:a.append(G.box(Vector3(x,.405,0),Vector3(1.6,.01,58),"teal",false))
 for z in [-24.,18.]:a.append(G.box(Vector3(0,.405,z),Vector3(44,.01,1.6),"teal",false))
 # Monumental forward portico frames the hand from human eye height.
 for x in [-22.,22.]:a.append(G.box(Vector3(x,17,14),Vector3(3,34,4),"sanctuary_tile"))
 a.append(G.box(Vector3(0,34,14),Vector3(47,4,4),"sanctuary_tile"))
 for z in [-21.,8.]:a.append(G.box(Vector3(0,37.75,z),Vector3(38,.15,3),"glow",false))
 for x in [-31.8,31.8]:
  for z in [-18.,4.,24.]:a.append(G.box(Vector3(x,10,z),Vector3(.15,5,1),"glow",false))
 # Compact C4: rearward rounded wrist, broad palm, four independent tapered
 # fingers with source-landmark bone poses, and an opposed lateral thumb.
 var hand_mesh:Mesh=load("res://assets/dreamcore/late_references/hanging_hand_original.obj")
 a.append(G.item(hand_mesh,Vector3.ZERO,"sculpted_stone",true))
 # The exact stone mesh has collision; reachable fingertips cannot be walked
 # through. There is no unexplained pedestal or fake submerged proxy cube.
 # Deliberately suspended like the reference; no roof-attachment claim.
 # This south-wall door faces the room (-Z); keep its handle on that side.
 var door_origin:=Vector3(8,.4,35.9)
 a.append(G.box(door_origin+Vector3(0,1.15,0),Vector3(1.1,2.3,.07),"dark",false,Vector3.ZERO))
 a.append(G.box(door_origin+Vector3(.33,1.08,-.06),Vector3(.04,.19,.07),"metal",false))
 _architecture=a;return a
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:G.build(room,data,geometry(),true)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 G.build(room,data,geometry(),false)
 for p in [Vector3(-14,24,8),Vector3(14,24,8),Vector3(0,29,-20)]:G.lamp(room,data,p,Color("fff4d8"),5.,48.)
static func build_horizon(_root:Node3D,_materials:RefCounted)->void:pass
