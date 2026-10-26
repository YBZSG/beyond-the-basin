extends SceneTree
## Sampled real collision route audit, NOT a controller playthrough or swim/jump proof.
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const World=preload("res://scripts/campaign/campaign_world.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Materials=preload("res://scripts/rendering/pool_materials.gd")
class TestPlayer extends CharacterBody3D:
 var camera:Node3D
 func _ready()->void:camera=Node3D.new();add_child(camera)
class TestMain extends Node3D:
 var world:Node3D
 var player:TestPlayer
 var _booted:=true
 var _switching_spawn:=false
 var menu_open:=false
 var hud_hidden:=false
var results:Array=[]
var failures:Array[String]=[]
var space:PhysicsDirectSpaceState3D
var exclude:Array[RID]=[]
var query:=PhysicsShapeQueryParameters3D.new()
var capsule:=CapsuleShape3D.new()
func v(p:Vector3)->Array:return [snappedf(p.x,.01),snappedf(p.y,.01),snappedf(p.z,.01)]
func key(p:Vector3)->String:return "%.2f,%.1f,%.2f"%[p.x,p.y,p.z]
func ray(a:Vector3,b:Vector3)->Dictionary:return space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1,exclude))
func stand(p:Vector3)->Dictionary:
 var hit:Dictionary=ray(p+Vector3.UP*.42,p-Vector3.UP*.62)
 if hit.is_empty() or hit.normal.y<.7:return {}
 var foot:Vector3=hit.position+Vector3.UP*.035
 query.transform.origin=foot+Vector3.UP*.82
 if not space.intersect_shape(query,1).is_empty():
  var clear:=false
  for lift:float in [.04,.08,.12,.16]:
   query.transform.origin=foot+Vector3.UP*(.82+lift)
   if space.intersect_shape(query,1).is_empty():foot.y+=lift;clear=true;break
  if not clear:return {}
 for corner:Vector3 in [Vector3(.2,0,.2),Vector3(-.2,0,.2),Vector3(.2,0,-.2),Vector3(-.2,0,-.2)]:
  var support:Dictionary=ray(foot+corner+Vector3.UP*.12,foot+corner-Vector3.UP*.23)
  if support.is_empty() or support.normal.y<.7:return {}
 return {"foot":foot}
func _initialize()->void:call_deferred("run")
func run()->void:
 capsule.radius=.32;capsule.height=1.64;query.shape=capsule;query.collision_mask=1
 var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/campaign/independent/legacy_v1_migration_fixtures.json"))
 for chapter in [3]:
  var data:Dictionary=Catalog.chapter(chapter)
  var main:=TestMain.new();root.add_child(main)
  main.player=TestPlayer.new();main.add_child(main.player)
  var runtime:=Runtime.new();runtime.main=main;runtime.active=true;runtime.state=State.new();runtime.writable=false
  runtime.state.restore(fixtures[chapter*3+1].save)
  main.add_child(runtime);runtime.set_process(false);runtime.set_process_input(false)
  main.world=World.new();main.world.chapter_index=chapter;main.world.formal_mode=data.mode=="formal";main.world.expanded_mode=data.mode in ["expanded","poolrooms","reference"];main.world.poolrooms_mode=data.mode=="poolrooms"
  main.add_child(main.world);main.world.room_loaded.connect(runtime.room_loaded)
  main.world.initialize(250821,Materials.new());main.world.complete_pending_streaming()
  await runtime._place_pending();await physics_frame;await physics_frame
  space=main.player.get_world_3d().direct_space_state;exclude=[main.player.get_rid()];query.exclude=exclude
  var stations:Dictionary=runtime._collectibles.duplicate()
  stations.merge(runtime._extras)
  if is_instance_valid(runtime._gate):stations.departure=runtime._gate
  if is_instance_valid(runtime._repair):stations.repair=runtime._repair
  var spawn_rows:Array=[]
  for item:Dictionary in data.items:
   var checkpoint:Vector3=main.world.get_spawn_position(item.coord)
   query.transform.origin=checkpoint+Vector3.UP*.84
   var overlaps:Array=[]
   for hit:Dictionary in space.intersect_shape(query,16):overlaps.append(str(hit.collider.get_path()))
   spawn_rows.append({"id":item.id,"spawn":v(checkpoint),"overlaps":overlaps})
  var rows:Array=[]
  for id:String in stations:
   var node:Node3D=stations[id]
   var approach:=stand(node.global_position+Vector3(0,0,1.15))
   var row:Dictionary={"id":id,"station":v(node.global_position),"approach_clear":not approach.is_empty(),"route":false}
   if not approach.is_empty():
    var foot:Vector3=approach.foot;row.approach=v(foot)
    main.player.global_position=foot;main.player.camera.position=Vector3(0,1.55,0);main.player.camera.look_at(node.global_position+Vector3.UP*1.24)
    if runtime._repair==runtime._gate:runtime.state.elapsed=runtime.state.pressure_limit()+1 if id=="repair" else 0.0
    var targeted:Dictionary=runtime._target()
    row["los_target"]=targeted.get("id","");row["interaction_label"]=targeted.get("label","")
    if row.interaction_label in ["","检修终端"]:failures.append("GENERIC_LABEL "+id)
    if row.los_target!=id:failures.append("LOS "+id)
   else:failures.append("APPROACH "+id)
   rows.append(row)
  var spawn:Vector3=main.world.get_spawn_position(data.room_specs[0].coord)
  query.transform.origin=spawn+Vector3.UP*.84
  var spawn_hits:Array=[]
  for hit:Dictionary in space.intersect_shape(query,16):spawn_hits.append(str(hit.collider.get_path()))
  print("SPAWN_COLLIDERS ",chapter," ",JSON.stringify(spawn_hits))
  var origin:Dictionary=stand(spawn)
  var points:Array[Vector3]=[]
  var queue:Array[Vector3]=[]
  var parents:Dictionary={}
  var visited:Dictionary={}
  if not origin.is_empty():queue.append(origin.foot);visited[key(origin.foot)]=true
  var cursor:=0
  var offsets:Array[Vector3]=[Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1),Vector3(1,0,1),Vector3(-1,0,1),Vector3(1,0,-1),Vector3(-1,0,-1)]
  while cursor<queue.size() and cursor<200000:
   var current:Vector3=queue[cursor];cursor+=1;points.append(current)
   for row:Dictionary in rows:
    if row.route or not row.has("approach"):continue
    var a:Array=row.approach;var goal:=Vector3(a[0],a[1],a[2])
    if current.distance_to(goal)<1.2 and ray(current+Vector3.UP*.8,goal+Vector3.UP*.8).is_empty():
     row.route=true;row.route_endpoint=v(current)
   for offset:Vector3 in offsets:
    var candidate:Vector3=current+offset*.2
    var room:=Vector2i(floori((candidate.x+16.0)/32.0),floori((candidate.z+16.0)/32.0))
    if room not in main.world.finite_coords:continue
    var coarse:String="%.2f,%.1f,%.2f"%[candidate.x,current.y,candidate.z]
    if visited.has(coarse):continue
    visited[coarse]=true
    var target:Dictionary=stand(candidate)
    if target.is_empty():continue
    var next:Vector3=target.foot
    if not ray(current+Vector3.UP*.8,next+Vector3.UP*.8).is_empty():continue
    if not ray(current+Vector3.UP*1.5,next+Vector3.UP*1.5).is_empty():continue
    query.transform.origin=Vector3((current.x+next.x)*.5,maxf(current.y,next.y)+.82,(current.z+next.z)*.5)
    if not space.intersect_shape(query,1).is_empty():continue
    queue.append(next);parents[key(next)]=key(current)
   if cursor%1000==0:await process_frame
  var cloud:Array=[]
  for p:Vector3 in points:cloud.append(v(p))
  results.append({"chapter":chapter,"id":data.id,"spawn":v(spawn),"spawn_valid":not origin.is_empty(),"spawn_colliders":spawn_hits,"sampled_points":points.size(),"stations":rows,"room_spawns":spawn_rows,"walkable":cloud,"limit_reached":cursor>=200000})
  print("ROUTE_CHAPTER ",chapter," points=",points.size()," stations=",rows.size())
  main.queue_free();await process_frame;await physics_frame
 var file:=FileAccess.open("res://independent-route-results.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"scope":"real collision capsule/support/LOS + 0.4m eight-neighbor sampled grounded/wading graph, no jump/swim/controller/GPU claim","failures":failures,"chapters":results},"\t"));file.close()
 print("INDEPENDENT_ROUTES ",JSON.stringify({"failures":failures,"chapters":results.size()}))
 quit(0 if failures.is_empty() else 1)
