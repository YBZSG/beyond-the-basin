extends RefCounted
## Immutable native station template; runtime never reads authoring PNG/JSON files.
## Mesh/material/Texture2D resources are shared and persist while this script is loaded.
## Only the 14 instance nodes (including the handle transform) are scene-owned.
const TEMPLATE:PackedScene=preload("res://assets/dreamcore/uncanny/hollow_visage/hollow_visage_station_v7.scn")
static func build_into(actor:Node3D)->MeshInstance3D:
 var instance:Node3D=TEMPLATE.instantiate()
 var handle:MeshInstance3D
 assert(instance.transform==Transform3D.IDENTITY and instance.get_child_count()==14)
 for child in instance.get_children():
  assert(child is MeshInstance3D)
  instance.remove_child(child);child.owner=null;actor.add_child(child)
  if child.get_meta("station_v7_part","")=="handle":handle=child
 instance.free()
 assert(handle!=null)
 return handle
static func hide_collision_visual(room:Node3D)->int:
 var count=0
 for child in room.get_children():
  if child is MeshInstance3D and child.name=="Annex_hollow_visage_station_collision_hold":
   child.visible=false;child.set_meta("station_collision_visual_hold",true);count+=1
 return count
