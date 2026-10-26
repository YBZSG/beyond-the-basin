extends SceneTree
const Runtime=preload("res://scripts/campaign/campaign_runtime.gd")
const World=preload("res://scripts/campaign/campaign_world.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Materials=preload("res://scripts/rendering/pool_materials.gd")
const Player=preload("res://scripts/reference_wing/reference_player.gd")
const Depth=preload("res://scripts/reference_wing/reference_depth_field.gd")
class Water extends Node:
 var profiles:Array=[]
 func depth_at(p:Vector3)->float:
  for profile:Dictionary in profiles:
   var point:=Vector2(p.x,p.z)-Vector2(profile.offset)
   if profile.bounds.grow(.001).has_point(point):return Depth.point_depth(point,profile)
  return 0.0
 func is_water_at(p:Vector3)->bool:return depth_at(p)>0
 func surface_height_at(_p:Vector3)->float:return .32
 func player_impact(_p:Vector3,_power:float)->void:pass
 func splash(_p:Vector3,_power:float,_direction:Dictionary={})->void:pass
 func wave_impact(_p:Vector3,_power:float)->void:pass
 func push(_p:Vector3,_impulse:Vector2,_radius:float)->void:pass
 func wake_dipole(_p:Vector3,_direction:Vector2,_speed:float,_radius:float)->void:pass
 func crest(_p:Vector3,_power:float)->void:pass
class Main extends Node3D:
 var player:CharacterBody3D
 var world:Node3D
 var _booted:=true
 var _switching_spawn:=false
 var menu_open:=false
 var hud_hidden:=false
var legs:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
 Engine.physics_ticks_per_second=120
 for action:String in ["move_forward","move_back","move_left","move_right","sprint","jump","crouch","interact","throw","drop"]:
  if not InputMap.has_action(action):InputMap.add_action(action)
 var main:=Main.new();root.add_child(main)
 main.player=Player.new();main.add_child(main.player)
 var runtime:=Runtime.new();runtime.main=main;runtime.active=true;runtime.state=State.new();runtime.writable=false
 var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/campaign/independent/legacy_v1_migration_fixtures.json"));runtime.state.restore(fixtures[10].save)
 main.add_child(runtime);runtime.set_process(false);runtime.set_process_input(false)
 main.world=World.new();main.world.chapter_index=3;main.world.expanded_mode=true;main.add_child(main.world);main.world.room_loaded.connect(runtime.room_loaded)
 main.world.initialize(250821,Materials.new());main.world.complete_pending_streaming()
 await runtime._place_pending();await physics_frame;await physics_frame
 var water:=Water.new();main.add_child(water);water.profiles=Depth.profiles(main.world._layouts)
 main.player.set_water(water);main.player.depth_wading_response_enabled=true
 main.player.warp_to(main.world.get_spawn_position(Vector2i.ZERO),Vector3(1.4,1,-4));main.player.set_enabled(true)
 await physics_frame;await physics_frame
 # Explicit waypoints follow authored stairs and portals. Only initial spawn warped.
 var path:Array[Vector2]=[Vector2(.5,11.2),Vector2(.5,9.2),Vector2(1.4,8.6),Vector2(1.4,.2),Vector2(2.35,.2),Vector2(2.35,-2.5),Vector2(1.4,-4.5),Vector2(0,-16),Vector2(0,-17.1),Vector2(1.4,-20),Vector2(0,-21.9),Vector2(1.4,-21.9),Vector2(1.4,-25),Vector2(0,-30.8),Vector2(0,-46),Vector2(0,-49.1),Vector2(0,-55.1)]
 var passed:=true
 for target:Vector2 in path:
  var ticks:=0;var stalled:=0
  var max_ticks:int=ceili(Vector2(main.player.position.x,main.player.position.z).distance_to(target)/.6*120)+180
  Input.action_press("move_forward")
  while Vector2(main.player.position.x,main.player.position.z).distance_to(target)>.18 and ticks<max_ticks:
   var direction:Vector2=target-Vector2(main.player.position.x,main.player.position.z)
   main.player.rotation.y=atan2(-direction.x,-direction.y)
   var before:Vector3=main.player.position
   await physics_frame
   stalled=stalled+1 if main.player.position.distance_to(before)<.00001 else 0;ticks+=1
   if stalled>120:break
  Input.action_release("move_forward")
  var reached:bool=Vector2(main.player.position.x,main.player.position.z).distance_to(target)<=.18
  var p:Vector3=main.player.position
  var collisions:Array=[]
  for i in main.player.get_slide_collision_count():collisions.append(str(main.player.get_slide_collision(i).get_collider().get_path()))
  var leg:Dictionary={"target":[target.x,target.y],"actual":[p.x,p.y,p.z],"reached":reached,"ticks":ticks,"colliders":collisions};legs.append(leg);print("WALK_LEG ",JSON.stringify(leg))
  if not reached:passed=false;break
 if passed:
  var station:Node3D=runtime._collectibles.reference_cyan_corridor
  main.player.camera.look_at(station.global_position+Vector3.UP*1.24)
  var selected:Dictionary=runtime._target()
  passed=selected.get("id","")=="reference_cyan_corridor"
  print("WALK_FINAL_INTERACTION_TARGET ",JSON.stringify(selected))
 var file:=FileAccess.open("res://independent-reference-walk.json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":passed,"scope":"actual production reference player 120Hz, production world and mounted stations; static authored depth not GPU water; only initial warp","legs":legs},"\t"));file.close()
 main.queue_free();await process_frame
 quit(0 if passed else 1)
