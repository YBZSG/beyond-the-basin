extends SceneTree
const World=preload("res://scripts/campaign/campaign_world.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
const Materials=preload("res://scripts/rendering/pool_materials.gd")
const Lighting=preload("res://scripts/reference_wing/reference_lighting.gd")
const Corruption=preload("res://scripts/campaign/campaign_corruption.gd")
class OneRoom extends Node3D:
 var resident_rooms:Dictionary={}
var failures:Array[String]=[]
var checks:=0
var rows:Array=[]
func check(value:bool,note:String)->void:
 checks+=1
 if not value:failures.append(note);push_error(note)
func _initialize()->void:call_deferred("run")
func run()->void:
 for chapter in range(6):
  var data:Dictionary=Catalog.chapter(chapter)
  var world:=World.new();world.chapter_index=chapter;world.formal_mode=data.mode=="formal";world.expanded_mode=data.mode in ["expanded","poolrooms","reference"];world.poolrooms_mode=data.mode=="poolrooms";root.add_child(world)
  var lighting:=Lighting.new()
  world.room_loaded.connect(func(room:Node3D,_coord:Vector2i,layout:Dictionary):
   if layout.get("formal",false):lighting.add_formal_lights(room,layout)
   else:lighting.add_room_lights(room,int(layout.variant))
  )
  world.initialize(250821,Materials.new());world.complete_pending_streaming()
  await physics_frame;await physics_frame
  var camera:=Camera3D.new();world.add_child(camera)
  var first:Vector2i=data.room_specs[0].coord
  camera.global_position=world.get_spawn_position(first)+Vector3.UP*1.6
  lighting.update_active_room(first,world.get_layout(first));lighting.update_source_view(camera)
  var all:Array=world.find_children("*","Light3D",true,false)
  var corruption:=Corruption.new();corruption.apply(world,1.0,.25)
  var originals:Array=[]
  for entry:Dictionary in corruption._lights:originals.append({"light":entry.ref.get_ref(),"energy":entry.energy,"color":entry.color})
  var eligible:=0;var visible_tracked:=0;var active_tracked:=0
  var active_room:Node3D=world.resident_rooms[first]
  for entry:Dictionary in corruption._lights:
   var lamp:Light3D=entry.ref.get_ref()
   if lamp.is_visible_in_tree():visible_tracked+=1
   if active_room.is_ancestor_of(lamp):active_tracked+=1
   if entry.energy>=.15 and lamp.is_visible_in_tree() and corruption._has_redundancy(lamp):eligible+=1
  check(eligible>0,"real loaded world has eligible outage candidates chapter"+str(chapter))
  var max_off:=0;var off_samples:=0;var guards_ok:=true
  for step in range(400):
   corruption.apply(world,1.0,.25)
   var off:=0
   for entry:Dictionary in corruption._lights:
    var lamp:Light3D=entry.ref.get_ref()
    if entry.energy>=.15 and lamp.is_visible_in_tree() and lamp.light_energy<.001:
     off+=1
     if not corruption._has_redundancy(lamp):guards_ok=false
   max_off=maxi(max_off,off)
   if off>0:off_samples+=1
  check(max_off<=1,"at most one real fixture off chapter"+str(chapter))
  check(guards_ok,"every real outage retains same-room safety fixture chapter"+str(chapter))
  check(eligible==0 or off_samples>0,"eligible real-world outage actually occurs chapter"+str(chapter))
  corruption.reset()
  for entry:Dictionary in originals:
   check(entry.light.light_energy==entry.energy and entry.light.light_color==entry.color,"exact real light reset")
  corruption.reduced_effects=true
  for step in range(400):corruption.apply(world,1.0,.25)
  for entry:Dictionary in corruption._lights:
   check(entry.ref.get_ref().light_energy>=float(entry.energy)*.919,"reduced mode never blacks real fixture")
  corruption.reset()
  rows.append({"chapter":chapter,"rooms":world.resident_rooms.size(),"native_lights":all.size(),"tracked":originals.size(),"visible_tracked":visible_tracked,"active_room_tracked":active_tracked,"eligible_outage_candidates":eligible,"maximum_simultaneously_off":max_off,"off_samples":off_samples,"same_room_safety":guards_ok})
  print("LOADED_OUTAGE_CHAPTER ",JSON.stringify(rows[-1]))
  world.queue_free();await process_frame
 # Unknown ownership and single-light rigs must not invent redundancy.
 for known:bool in [false,true]:
  var host:Node3D=OneRoom.new() if known else Node3D.new();root.add_child(host)
  var room:=Node3D.new();host.add_child(room)
  var rig:=Node3D.new();rig.name="NativeLighting";room.add_child(rig)
  var lamp:=OmniLight3D.new();rig.add_child(lamp)
  if known:host.resident_rooms[Vector2i.ZERO]=room
  var corruption:=Corruption.new()
  for step in range(400):corruption.apply(host,1,.25)
  check(corruption._groups.size()==(1 if known else 0),"known resident ownership recognized")
  check(corruption._outage==null and lamp.light_energy>0,"single-light or unknown ownership safely skips blackout")
  corruption.reset();host.queue_free();await process_frame
 var file:=FileAccess.open("res://independent-loaded-corruption.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"scope":"actual loaded production campaign geometry plus exact production lighting callbacks/visibility selection; Light3D state only, no rendered-pixel or water claim"},"\t"));file.close()
 print("INDEPENDENT_LOADED_CORRUPTION ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
