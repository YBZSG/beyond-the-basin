extends SceneTree
## Actual native station meshes and arrival materials at four animation samples.
## Offline asset/contact-sheet preview, not an in-game screenshot.
const Kit=preload("res://scripts/campaign/campaign_interactables.gd")
const Arrivals=preload("res://scripts/campaign/campaign_arrivals.gd")
func _initialize()->void:_run.call_deferred()
func _run()->void:
 var gallery:=Node3D.new();root.add_child(gallery)
 var modes:=["original","expanded","poolrooms","reference","quiet","formal"]
 var chapters:=["lost_shift","maintenance","return_water","five_memories","quiet_archive","daylight"]
 var kinds:=["breaker","valve","flow_selector","memory_tile","vent","mirror"]
 var samples:=[.20,.70,1.35,3.25]
 var owners:Array=[]
 for row in 4:
  for col in 6:
   var room:=Node3D.new();gallery.add_child(room);room.position=Vector3(float(col)*1.65,float(3-row)*2.15,0)
   var station:Node3D=Kit.build_station({"id":"sample_%d_%d"%[row,col],"kind":kinds[col]});room.add_child(station)
   var a:=Arrivals.new();root.add_child(a);owners.append(a)
   var index:int=8 if col==4 else 0
   a._attach_fixture(room,Arrivals.describe(chapters[col],modes[col],index))
   a._animate_fixture(samples[row])
 await process_frame
 var state:=GLTFState.new();var doc:=GLTFDocument.new();var error:=doc.append_from_scene(gallery,state)
 if error==OK:error=doc.write_to_filesystem(state,"/tmp/campaign-arrival-qa/arrivals.glb")
 print("ARRIVAL_GALLERY_EXPORT ",error)
 for a:Node in owners:a.free()
 gallery.free();quit(error)
