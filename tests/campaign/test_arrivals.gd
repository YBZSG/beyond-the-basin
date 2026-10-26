extends SceneTree
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
const Objectives=preload("res://scripts/campaign/campaign_objectives.gd")
const Kit=preload("res://scripts/campaign/campaign_interactables.gd")
const Arrivals=preload("res://scripts/campaign/campaign_arrivals.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,note:String)->void:
 checks+=1
 if not value:failures.append(note);push_error(note)
func room(mode:String,index:int)->Node3D:
 var result:=Node3D.new();result.set_meta("campaign_source_mode",mode);result.set_meta("campaign_source_index",index);root.add_child(result);return result
func enter(a:Node,r:Node3D,id:String,ready:bool=true,allowed:bool=true,frames:int=4)->void:
 for n in range(frames):a.update_room(r,id,ready,allowed,.1)
func _initialize()->void:
 call_deferred("run")
func run()->void:
 var titles:Dictionary={};var count:=0
 for chapter:String in Arrivals.CHAPTER_MODES:
  var mode:String=Arrivals.CHAPTER_MODES[chapter]
  for i in range(Arrivals.ROOMS[mode].size()):
   var source_index:int=i+8 if mode=="quiet" else i
   var d:Dictionary=Arrivals.describe(chapter,mode,source_index)
   check(not d.is_empty() and not titles.has(d.title),"unique grounded room "+str(count));titles[d.title]=true;count+=1
   var wav:AudioStreamWAV=Arrivals.make_signature(d)
   check(wav.data.size()==19200 and wav.mix_rate==8000 and wav.loop_mode==AudioStreamWAV.LOOP_DISABLED,"bounded one-shot signature")
 check(count==28,"exactly 28 source archetypes")
 check(Arrivals.describe("quiet_archive","formal",8).is_empty(),"formal/quiet source identity never conflated")
 check(Arrivals.describe("quiet_archive","quiet",0).is_empty(),"quiet uses real source indices 8..10")
 check(Arrivals.describe("bad","original",0).is_empty(),"unknown chapter rejected")
 var a:=Arrivals.new();root.add_child(a);a.configure("lost_shift",1)
 var r:=room("original",0)
 enter(a,r,"lost_shift:0,0",false,true,20)
 check(a.diagnostics().seen==0,"unready has no effect")
 enter(a,r,"lost_shift:0,0",true,false,20)
 check(a.diagnostics().seen==0,"pause/loading not marked seen")
 a.update_room(r,"lost_shift:0,0",true,true,100.0)
 check(a.diagnostics().seen==0,"long frame not treated as stable dwell")
 a.set_suspended(true);enter(a,r,"lost_shift:0,0")
 check(a.diagnostics().seen==0,"suspended suppresses cue")
 a.set_suspended(false);enter(a,r,"lost_shift:0,0")
 check(a.diagnostics().starts==1 and a.diagnostics().layer_count==1,"stable first entry starts one title")
 check(a.diagnostics().voice_count==0,"audio opt-in by default")
 enter(a,r,"lost_shift:0,0",true,true,60)
 check(a.diagnostics().layer_count==0 and a.diagnostics().starts==1,"title expires and repeat stays seen")
 var r1:=room("original",1)
 enter(a,r1,"lost_shift:1,0",true,true,2)
 enter(a,r,"lost_shift:0,0",true,true,2)
 enter(a,r1,"lost_shift:1,0",true,true,2)
 check(a.diagnostics().starts==1,"doorway oscillation never accumulates dwell")
 enter(a,r1,"lost_shift:1,0")
 check(a.diagnostics().starts==2,"second room starts after stable entry")
 a.configure("lost_shift",2)
 check(a.diagnostics().seen==2 and a.diagnostics().layer_count==0,"same-chapter epoch preserves seen cleans transient")
 a.restore_seen(["lost_shift:2,0","daylight:3,0","lost_shift:not-a-coordinate"])
 check(a.diagnostics().seen==3,"restore only valid current chapter identities")
 a.set_audio_enabled(true)
 var r3:=room("original",3);enter(a,r3,"lost_shift:3,0")
 check(a.diagnostics().voice_count==1,"optional audio bounded to one voice")
 a.set_suspended(true)
 check(a.diagnostics().voice_count==0 and a.diagnostics().layer_count==0,"pause frees audio and UI immediately")
 a.set_suspended(false)
 a.configure("quiet_archive",3)
 check(a.diagnostics().seen==0,"new chapter clears first-entry epoch")
 var q:=room("quiet",8);enter(a,q,"quiet_archive:0,0")
 check(a.diagnostics().seen==1,"quiet source8 recognized")
 q.free();await process_frame;await process_frame
 check(a.diagnostics().layer_count==0 and a.diagnostics().voice_count==0,"unload cleanup does not require coordinator tick")
 a.update_room(null,"quiet_archive:0,0",true,true,.1)
 check(a.diagnostics().layer_count==0 and a.diagnostics().voice_count==0,"freed room safely clears cue")
 a.configure("lost_shift",4)
 enter(a,r,"daylight:0,0")
 check(a.diagnostics().seen==0,"foreign chapter identity rejected")
 for i in range(40):enter(a,r,"lost_shift:%d,0"%i)
 check(a.diagnostics().seen==28 and a.diagnostics().voice_count<=1 and a.diagnostics().layer_count<=1,"hard memory and active voice/UI budgets")
 a.clear();a.configure("maintenance",5)
 var m:=room("expanded",0)
 enter(a,m,"maintenance:0,0",true,true,2)
 enter(a,m,"maintenance:0,0",false,true,1)
 enter(a,m,"maintenance:0,0",true,true,2)
 check(a.diagnostics().seen==0,"unready resets partial dwell")
 enter(a,m,"maintenance:0,0")
 paused=true;await process_frame;await process_frame
 check(a.diagnostics().layer_count==0 and a.diagnostics().voice_count==0,"tree pause cleans effects without coordinator tick")
 paused=false;m.free()
 a.clear();check(a.diagnostics().seen==0 and a.diagnostics().layer_count==0 and a.diagnostics().voice_count==0,"clear releases all state and effects")
 var patterns:Dictionary={}
 for mode:String in Arrivals.ROOMS:
  var sample:Dictionary=Arrivals.visual_sample(mode,0,.8)
  patterns[sample.pattern]=true
  var previous:=0.0
  for step in range(381):
   sample=Arrivals.visual_sample(mode,0,float(step)/100.0)
   check(sample.energy>=0.0 and sample.energy<=.581,"bounded local courtesy light")
   check(absf(float(sample.energy)-previous)<.04,"slow continuous illumination, never flashing")
   previous=float(sample.energy)
  check(Arrivals.visual_sample(mode,0,3.8).energy==0.0,"all patterns neutral at end")
  check(Arrivals.visual_sample(mode,0,1.0,true).tilt==Vector3.ZERO,"reduced effects disables physical motion")
 check(patterns.size()==6,"six distinct spatial-temporal fixture patterns")
 a.configure("maintenance",6)
 var froom:=room("expanded",0)
 var station:Node3D=Kit.build_station({"id":"arrival_test","kind":"valve"});froom.add_child(station)
 var lens:=station.get_node("ArrivalLamp0") as MeshInstance3D
 var original:Material=lens.material_override
 var wheel:Node3D=station.get_node("Wheel");var rotation_before:=wheel.rotation
 var vane:Node3D=station.get_node("ArrivalVane")
 enter(a,froom,"maintenance:0,0");enter(a,froom,"maintenance:0,0",true,true,10)
 check(a.diagnostics().fixture_count==1 and a.diagnostics().light_count==1,"actual physical station courtesy reveal attached")
 check(lens.material_override!=original and lens.material_override.emission_energy_multiplier>0.0,"private lens glows visibly")
 check(wheel.rotation==rotation_before,"objective wheel pose untouched")
 check(vane.rotation!=Vector3.ZERO,"separate mechanical inspection vane moves")
 a.set_suspended(true)
 check(lens.material_override==original and original.emission_energy_multiplier==0.0 and vane.rotation==Vector3.ZERO,"pause restores exact neutral fixture material and pose")
 check(a.diagnostics().light_count==0,"pause frees additive local light")
 a.set_suspended(false);a.configure("maintenance",7)
 # Newly arrived room with a station that becomes available after its title.
 var delayed:=room("expanded",1);enter(a,delayed,"maintenance:1,0")
 var delayed_station:Node3D=Kit.build_station({"id":"delayed","kind":"valve"});delayed.add_child(delayed_station)
 enter(a,delayed,"maintenance:1,0",true,true,1)
 check(a.diagnostics().fixture_count==1,"late collision-ready station receives remaining reveal")
 check(a._accent.light_energy==0.0,"late fixture begins from dark rather than jumping to active phase")
 var replacement:=StandardMaterial3D.new()
 var late_lens:=delayed_station.get_node("ArrivalLamp0") as MeshInstance3D
 late_lens.material_override=replacement
 a.clear()
 check(late_lens.material_override==replacement,"cleanup cannot overwrite newer material owner")
 froom.free();delayed.free()
 for chapter_index in 6:
  var chapter:Dictionary=Catalog.chapter(chapter_index)
  a.configure(chapter.id,20+chapter_index)
  var specs:Array=Objectives.specs(chapter_index,Catalog.DEFAULT_SEED)
  for source_index in specs.size():
   var spec:Dictionary=specs[source_index]
   var source:Dictionary=chapter.room_specs[source_index]
   var ar:=room(source.source_mode,source.source_index)
   var fixture:Node3D=Kit.build_station(spec);ar.add_child(fixture)
   var identity:String=chapter.id+":"+Catalog.room_key(spec.coord)
   enter(a,ar,identity);enter(a,ar,identity,true,true,12)
   check(a.diagnostics().fixture_count==1 and a.diagnostics().light_count==1,"every actual catalog station receives physical reveal: "+spec.id)
   a.set_suspended(true)
   for lens_index in 3:
    var actual_lens:=fixture.get_node("ArrivalLamp%d"%lens_index) as MeshInstance3D
    check(actual_lens.material_override.emission_energy_multiplier==0.0,"neutral restored for "+spec.id)
   a.set_suspended(false);ar.free()
 a.free();r.free();r1.free();r3.free()
 print("CAMPAIGN_ARRIVALS_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
