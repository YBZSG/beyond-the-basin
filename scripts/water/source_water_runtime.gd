class_name OriginalSourceWater
extends Node3D
## Original 66a4543 InteractiveWater orchestration, with native renderer APIs.
## Native baseline remains in pool_water.gd for historical review, never silent fallback.
const WindWaves=preload("res://scripts/water/wind_wave_controller.gd")
const Settings=preload("res://scripts/water/source_port/source_water_settings.gd")
const Events=preload("res://scripts/water/source_port/source_wave_events.gd")
const Solver=preload("res://scripts/water/source_port/source_wave_solver.gd")
const Caustics=preload("res://scripts/water/source_port/source_caustics.gd")
const Planar=preload("res://scripts/water/source_port/source_planar.gd")
const Liquid=preload("res://scripts/water/source_port/source_liquid_mpm.gd")
const Whitewater=preload("res://scripts/water/source_port/source_whitewater_particles.gd")
const LiquidSurface=preload("res://scripts/water/source_port/source_liquid_surface.gd")
const RoomProbe=preload("res://scripts/water/source_port/source_room_probe.gd")
const FormalSnapshotCache=preload("res://scripts/water/source_formal_snapshot_cache.gd")
const TerrainDiskCache=preload("res://scripts/water/source_terrain_disk_cache.gd")
const TerrainIdentity=preload("res://scripts/water/source_terrain_identity.gd")
const RoomSnapshot=preload("res://scripts/water/source_room_snapshot.gd")
const TerrainPrepare=preload("res://scripts/water/source_port/source_terrain_prepare.gd")
const Surface=preload("res://shaders/source_water_surface.gdshader")
const NearfieldProfile=preload("res://scripts/water/pc_nearfield_water_profile.gd")
const QUALITY={"Low":{"simulation":384,"surface":96,"ripple":192,"reflection":256},"Medium":{"simulation":384,"surface":192,"ripple":384,"reflection":384},"High":{"simulation":768,"surface":384,"ripple":768,"reflection":768},"Ultra":{"simulation":1152,"surface":512,"ripple":1152,"reflection":1536}}
const MobileProfile=preload("res://scripts/mobile/pool_mobile_profile.gd")
const LEVEL=.32
var wind_waves:=WindWaves.new()
var mobile_optimized:bool=MobileProfile.is_mobile_session()
var quality_levels:Dictionary=MobileProfile.WATER_QUALITY if mobile_optimized else QUALITY
var settings:Dictionary=Settings.DEFAULT.duplicate()
var events:=Events.new()
var quality: String="High"
var _initialization_stats:Dictionary={"initial_quality":"High","solver_configure_calls":0,"quality_reconfigurations":0}
var caustics_enabled:=true
var enabled:=true
var interaction_count:=0
var ripple_returns:=0
var solver:=Solver.new()
var caustics:=Caustics.new()
var planar:Node
var domain_origin:=Vector2.ZERO
var _materials:Dictionary={}
var _surfaces:Dictionary={}
var _rooms:Dictionary={}
var _layouts:Dictionary={}
var _room_light_refs:Dictionary={}
var _library:RefCounted
var _time:=0.0
var _configured:=false
var _terrain_dirty:=false
var _terrain_age:=0.0
# Static source math is prepared once per geometry/resolution/room key. Never
# wait for an unfinished worker during gameplay; retain the valid old 96m field.
var _terrain_revision:=0
var _terrain_force_revision:=0
var _terrain_keys:Dictionary={}
var _terrain_job_force_revision:=0
var _terrain_job_identity:Dictionary={}
var _terrain_progress:RefCounted
var _terrain_requested_usec:=Time.get_ticks_usec()
var _terrain_change_frame:=0
var _requested_coord:=Vector2i.ZERO
var _terrain_ready:=false
var _terrain_applied_key:=""
var _terrain_snapshot:Dictionary={}
var _terrain_room_snapshots:Dictionary={}
var _formal_snapshot_job:RefCounted
var _formal_snapshot_attempt_revision:=-1
var _terrain_disk_algorithm:=""
var _terrain_collection:RefCounted
var _terrain_collection_jobs:Array[RefCounted]=[]
var _terrain_retired_collections:Array[RefCounted]=[]
var _terrain_collecting_coords:Dictionary={}
const TERRAIN_COLLECTION_WORKERS:=4
var _terrain_geometry_origin:=Vector2.ZERO
var _terrain_collection_usec:=0
const TERRAIN_COLLECT_BUDGET_USEC:=2000
var _terrain_cache:Dictionary={}
var _terrain_lru:Array[String]=[]
var _terrain_visited_origins:Array[Vector2i]=[]
var _terrain_thread:Thread
var _terrain_job_key:=""
var _terrain_job_coord:=Vector2i.ZERO
# At most one unfinished older job can coexist with the latest demand. Its
# immutable input/result remains owned until joined, never forcibly terminated.
var _terrain_retired_jobs:Array[Dictionary]=[]
var _terrain_paused:=false
var _prepare_suspended:=false
var _frame_stages:Dictionary={}
var _frame_stage_max:Dictionary={}
var _terrain_metrics:Dictionary={"cache_hits":0,"cache_misses":0,"jobs":0,"commits":0,"stale_results":0,"collect_ms":0.0,"commit_ms":0.0,"rebase_ms":0.0,"prepare_ms":{},"main_pump_max_ms":0.0,"collect_slice_max_ms":0.0,"collect_slices":0,"rooms_collected":0,"rooms_reused":0,"collection_cancellations":0,"validated_revision_reuses":0,"identity_ms":0.0,"identity_max_ms":0.0,"bvh_reuses":0,"mask_reuses":0,"collection_worker_max_ms":0.0,"authored_snapshot_hits":0,"authored_snapshot_misses":0,"authored_snapshot_load_ms":0.0,"disk_cache_hits":0,"cpu_array_meshes":0,"driver_face_meshes":0,"collection_nodes":0,"superseded_cache_entries":0,"capacity_evictions":0,"demand_preemptions":0,"demand_wait_frames":0,"max_workers":0,"speculative_drops":0}
const TERRAIN_CACHE_CAPACITY:=6
var _camera:Camera3D
var _liquid:RefCounted
var _particle_sampler:=Liquid.OpticalFieldSampler.new()
var _whitewater:RefCounted
var _liquid_surface:CompositorEffect
var _compositor:Compositor
var _probe:Node
var _probe_lighting_refresh_pending:=false
var _probe_capture_suspended:=false
var _probe_schedule_counts:={"deferred_lighting_refreshes":0,"suspensions":0,"resumes":0,"cancelled_partial_captures":0}
var _disposed:=false
var _tuning:Dictionary={}
var last_error:=""
var _nearfield_profile:RefCounted
var _surface_uniforms:Dictionary={"waveHeight":1.0,"rippleGain":1.0,"microStrength":.65,"normalBoost":1.0,"refractionStrength":.7,"absorptionStrength":.7,"fresnelStrength":1.0,"causticGain":1.5,"foamStrength":1.0,"debugView":0.0}
func configure(library:RefCounted)->void:
 _library=library
 if _configured:return
 _configured=true
 _configure_initial_fields()
 # Android retains SWE/ripples/optics, without allocating any 3D splash pipeline.
 if mobile_optimized:return
 _liquid=Liquid.new();_whitewater=Whitewater.new()
 _refresh_particle_sampler()
 _whitewater.configure(_particle_sampler.surface_at,_particle_sampler.depth_at,func(x:float,z:float)->Vector2:return solver.flow_at(Vector2(x,z)))
 add_child(_whitewater.submerged_mesh);_whitewater.submerged_mesh.layers=4
 _liquid.configure(_particle_sampler.surface_at,_particle_sampler.depth_at)
 _liquid.failed.connect(_failed);_liquid.droplet_released.connect(_whitewater.release);_liquid.return_ripple.connect(drop_ripple);_whitewater.return_ripple.connect(drop_ripple)
 _liquid_surface=LiquidSurface.new();_liquid_surface.configure(solver.get_state_texture(),solver.get_depth_texture(),solver.get_detail_texture())
 if not OS.has_feature("android") and not OS.has_feature("ios"):
  _nearfield_profile=NearfieldProfile.new()
  _nearfield_profile.bind(self)
  _nearfield_profile.set_enabled(NearfieldProfile.requested())
func _configure_initial_fields()->void:
 # This is cold zero-state initialization, not a live-water quality change.
 # Keep the existing configure(library) API for callers and fixture overrides.
 quality=quality if quality_levels.has(quality) else "High"
 settings.quality=quality
 _initialization_stats.initial_quality=quality
 solver.ready.connect(_solver_ready)
 solver.failed.connect(_failed)
 var selected:Dictionary=quality_levels[quality]
 var depth:=Image.create(int(selected.simulation),int(selected.simulation),false,Image.FORMAT_RF);depth.fill(Color(0,0,0))
 solver.configure(depth,int(selected.simulation),96.0,int(selected.ripple))
 _initialization_stats.solver_configure_calls+=1
 events.configure(solver,settings)
 _apply_settings()
 caustics.initialize(quality)
 caustics.configure(solver.get_state_texture(),solver.get_depth_texture(),solver.get_detail_texture())
func set_nearfield_water(value:bool,strength:float=.25)->bool:
 if _nearfield_profile==null:return false
 if _nearfield_profile.has_method("set_strength"):_nearfield_profile.set_strength(strength)
 return _nearfield_profile.set_enabled(value)
func nearfield_status()->Dictionary:
 return _nearfield_profile.describe() if _nearfield_profile else {"active":false,"reason":"desktop_only"}
func _refresh_particle_sampler()->void:
 # Refresh references at every simulation/creation entry, not cross-frame values.
 # Async SWE publication and room/quality rebases may replace packed arrays.
 _particle_sampler.refresh(solver,bool(settings.simulation),float(settings.waveHeight),LEVEL)
func _failed(reason:String)->void:
 last_error=reason;push_error("Original source water unavailable: "+reason)
func configure_camera(camera:Camera3D,environment:Environment)->void:
 _camera=camera
 planar=Planar.new()
 if mobile_optimized:
  planar.resolution=int(quality_levels[quality].reflection)
  planar.capture_msaa=Viewport.MSAA_2X
 planar.name="SourcePlanarReflection";add_child(planar);planar.configure(camera,environment);planar.set_quality(quality_levels[quality].reflection)
 _compositor=Compositor.new()
 if _liquid_surface:_compositor.compositor_effects=[_liquid_surface]
 camera.compositor=_compositor
 # This cubemap is consumed only by the volumetric splash compositor.
 if mobile_optimized:return
 _probe=RoomProbe.new();_probe.name="OriginalRoomCubemap";add_child(_probe);_probe.configure(camera,environment);_probe.completed.connect(_liquid_surface.configure_environment)
func refresh_capture_lighting()->void:
 if is_instance_valid(planar):planar.refresh_lighting()
 _invalidate_probe_capture_lighting(true)
func _probe_target_committed()->bool:
 # A retained 96m terrain field deliberately remains usable while its adjacent
 # replacement prepares. That does not authorize capturing the OLD origin.
 return not _disposed and _terrain_ready and not _terrain_dirty and domain_origin==Vector2(_requested_coord)*32.0
func _suspend_probe_capture()->void:
 if not _probe_capture_suspended:_probe_schedule_counts.suspensions+=1
 _probe_capture_suspended=true
 if is_instance_valid(_probe) and _probe.cancel_pending_capture():
  _probe_schedule_counts.cancelled_partial_captures+=1
func _invalidate_probe_capture_lighting(request_current:bool)->void:
 _probe_lighting_refresh_pending=true
 if not _probe_target_committed():
  _probe_schedule_counts.deferred_lighting_refreshes+=1
  _suspend_probe_capture()
  return
 if not is_instance_valid(_probe):return
 _probe.refresh_lighting()
 _probe_lighting_refresh_pending=false
 if request_current:_request_probe_for_committed_target()
func _request_probe_for_committed_target()->void:
 if not is_instance_valid(_probe) or not _probe_target_committed():return
 if _probe_lighting_refresh_pending:
  _probe.refresh_lighting()
  _probe_lighting_refresh_pending=false
 if _probe_capture_suspended:_probe_schedule_counts.resumes+=1
 _probe_capture_suspended=false
 _probe.request(domain_origin)
func _update_probe_capture()->void:
 if not is_instance_valid(_probe):return
 if not _probe_target_committed():
  _suspend_probe_capture()
  return
 if _probe_capture_suspended or _probe_lighting_refresh_pending:
  _request_probe_for_committed_target()
 _probe.update()
func _probe_has_current_texture()->bool:
 if mobile_optimized:return _probe_target_committed()
 # Kept output can still be displayed during preparation; QA/readiness must not
 # mistake that old-domain image for a completed requested-domain capture.
 return _probe_target_committed() and not _probe_capture_suspended and not _probe_lighting_refresh_pending and is_instance_valid(_probe) and _probe.texture!=null
func _probe_scheduling_diagnostics()->Dictionary:
 var result:=_probe_schedule_counts.duplicate()
 result.merge({"target_committed":_probe_target_committed(),"suspended":_probe_capture_suspended,"lighting_refresh_pending":_probe_lighting_refresh_pending,"requested_coord":_requested_coord,"committed_origin":domain_origin})
 return result
func _solver_ready()->void:
 _terrain_dirty=true
 _terrain_change_frame=Engine.get_process_frames()
 _bind_all()
func add_room(room:Node3D,coord:Vector2i,layout:Dictionary)->void:
 if not _configured:configure(_library)
 remove_room(coord)
 _rooms[coord]=weakref(room);_layouts[coord]=layout
 var refs:Array[WeakRef]=[]
 for candidate in room.find_children("*","OmniLight3D",true,false):refs.append(weakref(candidate))
 _room_light_refs[coord]=refs
 if _rooms.size()==1:
  domain_origin=Vector2(coord)*32.0;_requested_coord=coord
  _terrain_geometry_origin=domain_origin
 var material:=ShaderMaterial.new();material.shader=Surface;material.render_priority=0
 _materials[coord]=material
 var group:=Node3D.new();group.name="SourceWaterSurface";room.add_child(group);_surfaces[coord]=group
 var rects:Array=layout.get("water_rects",[Rect2(-16,-16,32,32)])
 if not layout.get("water_enabled",true):rects=[]
 for rect:Rect2 in rects:
  var mesh:=PlaneMesh.new();mesh.size=rect.size
  # Preserve original96m surface vertex density, allocate to actual bounded region.
  var density:float=float(quality_levels[quality].surface)/96.0
  mesh.subdivide_width=maxi(1,ceili(rect.size.x*density));mesh.subdivide_depth=maxi(1,ceili(rect.size.y*density))
  var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=material;instance.position=Vector3(rect.get_center().x,LEVEL,rect.get_center().y);instance.layers=2;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;instance.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;instance.extra_cull_margin=.4;group.add_child(instance)
 _refresh_surface_visibility()
 room.tree_exiting.connect(_on_room_exit.bind(coord,room.get_instance_id()),CONNECT_ONE_SHOT)
 _apply_surface(material)
 _invalidate_terrain(coord)
func _on_room_exit(coord:Vector2i,identity:int)->void:
 var weak:WeakRef=_rooms.get(coord)
 if weak and is_instance_valid(weak.get_ref()) and weak.get_ref().get_instance_id()==identity:remove_room(coord)
func remove_room(coord:Vector2i)->void:
 if not _rooms.has(coord):return
 if _surfaces.has(coord) and is_instance_valid(_surfaces[coord]):_surfaces[coord].queue_free()
 _surfaces.erase(coord);_materials.erase(coord);_rooms.erase(coord);_layouts.erase(coord);_room_light_refs.erase(coord)
 _invalidate_terrain(coord)
func _invalidate_terrain(changed_coord:Variant=null)->void:
 _terrain_revision+=1;_terrain_dirty=true;_terrain_age=0.0
 _terrain_change_frame=Engine.get_process_frames()
 _terrain_snapshot={};_terrain_keys.clear()
 _terrain_metrics.rooms_reused+=maxi(0,_terrain_room_snapshots.size()-(1 if _terrain_room_snapshots.has(changed_coord) else 0))
 # A completed room is static. Retain its extracted value arrays when a
 # different room streams, rather than visiting every unchanged mesh again.
 if changed_coord==null:
  _terrain_force_revision+=1
  _terrain_room_snapshots.clear();_terrain_cache.clear();_terrain_lru.clear()
 else:
  _terrain_room_snapshots.erase(changed_coord)
 if _terrain_collection and (changed_coord==null or _terrain_collection.coord==changed_coord):
  _terrain_collection.cancel();_terrain_collection=null
  _terrain_metrics.collection_cancellations+=1
 for index in range(_terrain_collection_jobs.size()-1,-1,-1):
  var job:RefCounted=_terrain_collection_jobs[index]
  if changed_coord==null or job.coord==changed_coord:
   job.cancel();_terrain_retired_collections.append(job)
   _terrain_collecting_coords.erase(job.coord);_terrain_collection_jobs.remove_at(index)
   _terrain_metrics.collection_cancellations+=1
func set_active_room(coord:Vector2i)->void:
 if coord!=_requested_coord:_terrain_requested_usec=Time.get_ticks_usec()
 _requested_coord=coord
 _terrain_dirty=_terrain_applied_key!=_terrain_key(coord)
 if not _probe_target_committed():_suspend_probe_capture()
 # A warm crossing publishes cached immutable data without rebuilding geometry.
 var key:=_terrain_key(coord)
 if _terrain_cache.has(key) and solver.is_ready:
  _terrain_metrics.cache_hits+=1
  _commit_terrain(_terrain_cache[key],key)
func set_paused(value:bool)->void:
 _terrain_paused=value
func suspend_preparation(value:bool)->void:
 _prepare_suspended=value
func preparation_pending()->bool:
 return _terrain_thread!=null or not _terrain_retired_jobs.is_empty()
func is_terrain_ready()->bool:
 var offset:Vector2=(Vector2(_requested_coord)*32.0-domain_origin).abs()
 # Adjacent crossings stay covered by the previous 96m domain. A long-distance
 # destination must wait for its own field rather than pretending dry/unknown
 # coordinates are valid buoyancy data.
 return not _disposed and solver.is_ready and _terrain_ready and maxf(offset.x,offset.y)<=32.0
func _terrain_key(coord:Vector2i)->String:
 # Incomplete extraction cannot validate a cache hit. Keep the old field live,
 # but never pretend its geometry has already been checked against new rooms.
 if _terrain_snapshot.is_empty():return "pending:%d:%d:%d:%d"%[coord.x,coord.y,_terrain_revision,solver.size]
 var lamps:=_effective_lamps(coord)
 var lookup:="%d:%d:%d:%s"%[coord.x,coord.y,solver.size,TerrainIdentity.digest(lamps)]
 if not _terrain_keys.has(lookup):
  var started:=Time.get_ticks_usec()
  # Keep the same insertion order as the prepared snapshot's BVH room list.
  var ordered:Dictionary={}
  for room_coord:Vector2i in _rooms:ordered[room_coord]=_terrain_room_snapshots[room_coord]
  _terrain_keys[lookup]=TerrainIdentity.components(coord,solver.size,_terrain_geometry_origin,ordered,_layouts,lamps,_terrain_force_revision)
  _terrain_metrics.identity_ms=float(Time.get_ticks_usec()-started)/1000.0
  _terrain_metrics.identity_max_ms=maxf(_terrain_metrics.identity_max_ms,_terrain_metrics.identity_ms)
 return _terrain_keys[lookup].key
func _terrain_identity(coord:Vector2i)->Dictionary:
 _terrain_key(coord)
 var lookup:="%d:%d:%d:%s"%[coord.x,coord.y,solver.size,TerrainIdentity.digest(_effective_lamps(coord))]
 return _terrain_keys.get(lookup,{})
func _lamp_inputs(coord:Vector2i)->Array:
 var layout:Dictionary=_layouts.get(coord,{})
 var fixtures:Array=layout.get("fixtures",[])
 if fixtures.is_empty():return [{"position":Vector3(-9,7.3,-5),"power":20.0},{"position":Vector3(8,7.3,-5),"power":20.0}]
 var lamps:Array=[]
 for fixture:Dictionary in fixtures:
  if not fixture.get("alive",true):continue
  var lamp:Dictionary=fixture.duplicate(true)
  # Source layout stores PointLight power; engine c.lamps stores power/4.75.
  if not layout.get("formal",false):lamp.power=float(lamp.power)/4.75
  lamps.append(lamp)
 return lamps
func _effective_lamps(coord:Vector2i)->Array:
 var fallback:Array=[]
 for lamp:Dictionary in caustics._lamps:fallback.append({"position":lamp.position,"power":float(lamp.power)/4.75})
 var lamps:=_lamp_inputs(coord)
 for i in mini(2,lamps.size()):fallback[i]=lamps[i].duplicate(true)
 return fallback
func _pump_terrain()->void:
 var pump_start:=Time.get_ticks_usec()
 _advance_terrain()
 _terrain_metrics.main_pump_max_ms=maxf(_terrain_metrics.main_pump_max_ms,float(Time.get_ticks_usec()-pump_start)/1000.0)
func _advance_terrain()->void:
 for index in range(_terrain_retired_jobs.size()-1,-1,-1):
  var job:Dictionary=_terrain_retired_jobs[index]
  if job.thread.is_alive():continue
  var result:Variant=job.thread.wait_to_finish()
  _terrain_retired_jobs.remove_at(index)
  _accept_terrain_result(result,job.key,job.identity,job.force_revision)
 if _terrain_thread and not _terrain_thread.is_alive():
  var result:Variant=_terrain_thread.wait_to_finish();_terrain_thread=null;_terrain_progress=null
  _accept_terrain_result(result,_terrain_job_key,_terrain_job_identity,_terrain_job_force_revision)
  _terrain_job_key=""
 if _prepare_suspended or _rooms.is_empty():return
 # Extraction overlaps GPU startup, interior streaming and worker preparation.
 # Each slice is bounded and only the completed room value is ever published.
 _pump_room_snapshots()
 if not solver.is_ready:return
 # Streaming installs one room per frame. Debounce by frames, not wall time,
 # so a slow GPU does not cause three increasingly obsolete initial builds.
 if not _geometry_debounce_ready():return
 if _terrain_snapshot.is_empty():
  if _terrain_room_snapshots.size()!=_rooms.size():return
  var collect_start:=Time.get_ticks_usec()
  var colliders:Array=[];var solids:Array=[];var triangles:=PackedVector3Array();var triangles_by_room:Dictionary={}
  # Preserve the former room/DFS order exactly; only the timing is different.
  for coord:Vector2i in _rooms:
   var values:Dictionary=_terrain_room_snapshots[coord]
   colliders.append_array(values.colliders);solids.append_array(values.solids)
   triangles_by_room[coord]=values.triangles
   triangles.append_array(values.triangles)
  _terrain_snapshot={"colliders":colliders,"solids":solids,"triangles":triangles,"triangles_by_room":triangles_by_room,"geometry_origin":_terrain_geometry_origin,"layouts":_layouts.duplicate(true)}
  _terrain_metrics.collect_ms=float(_terrain_collection_usec+Time.get_ticks_usec()-collect_start)/1000.0
  _terrain_collection_usec=0
  print("SOURCE_TERRAIN_SNAPSHOT ",JSON.stringify({"revision":_terrain_revision,"ms":_terrain_metrics.collect_ms,"slice_max_ms":_terrain_metrics.collect_slice_max_ms,"triangles":triangles.size()/3,"colliders":colliders.size()}))
  _invalidate_probe_capture_lighting(false)
 var requested_key:=_terrain_key(_requested_coord)
 # Streaming may restore the exact already-applied terrain identity. No upload
 # is needed, but its old dirty latch must not keep the room probe suspended.
 # Solver readiness, complete snapshot and quiet-frame checks precede this.
 if _terrain_dirty and _terrain_ready and _terrain_applied_key==requested_key and domain_origin==Vector2(_requested_coord)*32.0:
  _terrain_dirty=false
  _request_probe_for_committed_target()
 if _terrain_applied_key!=requested_key and _terrain_cache.has(requested_key):
  _terrain_metrics.cache_hits+=1;_commit_terrain(_terrain_cache[requested_key],requested_key)
 if _terrain_thread:
  if not _terrain_cache.has(requested_key) and _terrain_job_key!=requested_key and _terrain_retired_jobs.is_empty():
   # Demand never queues behind an unrelated speculative origin when the
   # bounded second slot is free. Rapid navigation only replaces _requested_coord;
   # it cannot spawn a third worker or forcibly interrupt a running kernel.
   _terrain_retired_jobs.append({"thread":_terrain_thread,"key":_terrain_job_key,"coord":_terrain_job_coord,
    "identity":_terrain_job_identity,"force_revision":_terrain_job_force_revision,"progress":_terrain_progress})
   _terrain_thread=null;_terrain_progress=null;_terrain_job_key=""
   _terrain_metrics.demand_preemptions+=1
  else:
   if not _terrain_cache.has(requested_key) and _terrain_job_key!=requested_key:_terrain_metrics.demand_wait_frames+=1
   return
 # A newly requested origin may already be the retired worker. Do not duplicate
 # that same immutable job, even if the foreground slot has become free.
 if _terrain_retired_key(requested_key):return
 var next_coord:=_requested_coord
 var needs_job:=not _terrain_cache.has(requested_key)
 if not needs_job:
  # Keep the spare slot available for demand, not a second concurrent prewarm.
  if not _terrain_retired_jobs.is_empty():return
  # The formal suite is resident. Prewarm its other static origins while the
  # player explores; legacy streaming uses bounded nearest-room cache entries.
  var candidates:Array=_rooms.keys()
  candidates.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return (a-_requested_coord).length_squared()<(b-_requested_coord).length_squared())
  var desired:Dictionary={}
  for cached:Dictionary in _terrain_cache.values():
   if cached.get("coord") in _terrain_visited_origins:desired[cached.coord]=true
  # Reserve real visits first, then select only as many deterministic nearest
  # prewarms as actually fit. Otherwise missing neighbors evict one another
  # forever when protected historical visits occupy part of the six slots.
  for candidate:Vector2i in candidates:
   if desired.size()>=TERRAIN_CACHE_CAPACITY:break
   desired[candidate]=true
  for candidate:Vector2i in candidates:
   if not desired.has(candidate):continue
   if not _terrain_cache.has(_terrain_key(candidate)) and not _terrain_retired_key(_terrain_key(candidate)) and _can_prewarm(candidate):
    next_coord=candidate;needs_job=true;break
 if needs_job:
  var snapshot:=_terrain_snapshot.duplicate(false)
  snapshot.merge({"coord":next_coord,"revision":_terrain_revision,"origin":Vector2(next_coord)*32.0,"size":solver.size,"domain":96.0,"lamps":_effective_lamps(next_coord)})
  _terrain_job_identity=_terrain_identity(next_coord)
  for cached:Dictionary in _terrain_cache.values():
   var identity:Dictionary=cached.get("identity",{})
   if identity.get("bvh_key","")==_terrain_job_identity.bvh_key:snapshot.prepared_bvh=cached.packed_bvh
   if identity.get("mask_key","")==_terrain_job_identity.mask_key:snapshot.prepared_occlusion={"masks":cached.masks,"filtered_solids":cached.filtered_solids}
   if snapshot.has("prepared_bvh") and snapshot.has("prepared_occlusion"):break
  _terrain_job_force_revision=_terrain_force_revision
  _terrain_job_coord=next_coord
  _terrain_job_key=_terrain_key(next_coord);_terrain_metrics.cache_misses+=1;_terrain_metrics.jobs+=1
  _terrain_thread=Thread.new();_terrain_progress=TerrainPrepare.Progress.new()
  var build:Callable=TerrainPrepare.build.bind(snapshot,_terrain_progress.mark)
  if _configured and FormalSnapshotCache.eligible(_layouts):
   if _terrain_disk_algorithm.is_empty():_terrain_disk_algorithm=TerrainDiskCache.algorithm_signature()
   build=TerrainDiskCache.build.bind(snapshot,_terrain_progress.mark,_terrain_job_identity,_terrain_disk_algorithm)
  var error:=_terrain_thread.start(build,Thread.PRIORITY_LOW)
  if error!=OK:_terrain_thread=null;_failed("Could not start static terrain worker: "+str(error))
  else:_terrain_metrics.max_workers=maxi(_terrain_metrics.max_workers,1+_terrain_retired_jobs.size())
func _terrain_retired_key(key:String)->bool:
 for job:Dictionary in _terrain_retired_jobs:
  if job.key==key:return true
 return false
func _accept_terrain_result(value:Variant,key:String,identity:Dictionary,force_revision:int)->void:
 if not value is Dictionary or not value.get("coord") is Vector2i or not value.get("size") is int:
  _failed("Static terrain worker returned an incomplete result");return
 var result:Dictionary=value
 result.identity=identity
 if result.get("disk_cache_hit",false):_terrain_metrics.disk_cache_hits+=1
 if result.get("reused_bvh",false):_terrain_metrics.bvh_reuses+=1
 if result.get("reused_masks",false):_terrain_metrics.mask_reuses+=1
 if force_revision!=_terrain_force_revision or result.size!=solver.size:
  _terrain_metrics.stale_results+=1;return
 if not _valid_terrain_payload(result):_failed("Static terrain worker returned an incomplete payload");return
 var current_key:=_terrain_key(result.coord)
 if key!=current_key:
  for cached_key:String in _terrain_cache:
   var cached:Dictionary=_terrain_cache[cached_key]
   if cached.get("coord")==result.coord and (cached_key==current_key or int(cached.get("revision",-1))>int(result.get("revision",-1))):
    # An older retired job must not replace a newer cached revision after the
    # player has already moved elsewhere. Exact semantic reversion still wins.
    _terrain_metrics.stale_results+=1;return
 _terrain_cache[key]=result
 _terrain_metrics.prepare_ms=result.timing_ms
 # Only the current, semantically revalidated demand can publish. Older results
 # may be cached, but never move the active field after newer navigation.
 if result.coord==_requested_coord and key==current_key:_commit_terrain(result,key)
 _touch_terrain_key(key)
func _geometry_debounce_ready()->bool:
 if Engine.get_process_frames()-_terrain_change_frame>=3:return true
 # The authored catalog is finite and every room is already atomically
 # complete. Waiting three rendered frames cannot improve this immutable
 # snapshot. Dynamic/source streaming retains its original quiet-frame guard.
 if not _configured or not FormalSnapshotCache.eligible(_layouts) or _rooms.size()!=_layouts.size():return false
 for weak:WeakRef in _rooms.values():
  var room:Node3D=weak.get_ref()
  if not is_instance_valid(room) or not room.get_meta("complete",false):return false
 return true
func _pump_room_snapshots()->void:
 if _configured and _terrain_room_snapshots.is_empty() and not _rooms.is_empty() and bool(_layouts.values()[0].get("formal",false)):
  if _formal_snapshot_job:
   if not WorkerThreadPool.is_task_completed(_formal_snapshot_job.task_id):return
   WorkerThreadPool.wait_for_task_completion(_formal_snapshot_job.task_id)
   _formal_snapshot_job.task_id=-1
   _terrain_metrics.authored_snapshot_load_ms=_formal_snapshot_job.elapsed_ms
   _terrain_metrics.authored_snapshot_diagnostic=_formal_snapshot_job.diagnostic.duplicate(true)
   if _formal_snapshot_job.revision==_terrain_revision and not _formal_snapshot_job.result.is_empty():
    for coord:Vector2i in _rooms:
     var value:Dictionary=_formal_snapshot_job.result[coord].duplicate(false)
     value.identity=_rooms[coord].get_ref().get_instance_id()
     _terrain_room_snapshots[coord]=value
    _terrain_metrics.authored_snapshot_hits+=1
   else:_terrain_metrics.authored_snapshot_misses+=1
   _formal_snapshot_job=null
   if not _terrain_room_snapshots.is_empty():return
  if _formal_snapshot_attempt_revision!=_terrain_revision:
   if not FormalSnapshotCache.eligible(_layouts) or not _geometry_debounce_ready():return
   _formal_snapshot_attempt_revision=_terrain_revision
   _formal_snapshot_job=FormalSnapshotCache.new();_formal_snapshot_job.revision=_terrain_revision
   _formal_snapshot_job.spec=FormalSnapshotCache.specification(_layouts,_rooms.keys(),_terrain_geometry_origin)
   _formal_snapshot_job.task_id=WorkerThreadPool.add_task(_formal_snapshot_job.build,false,"Validate exact authored room snapshot")
   return
 var started:=Time.get_ticks_usec()
 var performed:=false
 for index in range(_terrain_retired_collections.size()-1,-1,-1):
  if _terrain_retired_collections[index].reap_completed():_terrain_retired_collections.remove_at(index)
 for index in range(_terrain_collection_jobs.size()-1,-1,-1):
  var job:RefCounted=_terrain_collection_jobs[index]
  if not job.reap_completed():continue
  var room:Node3D=_rooms[job.coord].get_ref() if _rooms.has(job.coord) else null
  if is_instance_valid(room) and room.get_instance_id()==job.identity:
   _terrain_room_snapshots[job.coord]=job.result
   _terrain_metrics.rooms_collected+=1
   _terrain_metrics.cpu_array_meshes+=job.cpu_array_meshes
   _terrain_metrics.driver_face_meshes+=job.driver_face_meshes
   _terrain_metrics.collection_nodes+=job.nodes_read
   _terrain_metrics.collection_worker_max_ms=maxf(_terrain_metrics.collection_worker_max_ms,float(job.worker_usec)/1000.0)
  else:_terrain_metrics.collection_cancellations+=1
  _terrain_collecting_coords.erase(job.coord);_terrain_collection_jobs.remove_at(index)
 var remaining:=TERRAIN_COLLECT_BUDGET_USEC-(Time.get_ticks_usec()-started)
 while remaining>0 and _terrain_collection_jobs.size()<TERRAIN_COLLECTION_WORKERS:
  if not _terrain_collection:
   var candidates:Array=_rooms.keys()
   candidates.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return (a-_requested_coord).length_squared()<(b-_requested_coord).length_squared())
   for coord:Vector2i in candidates:
    if _terrain_room_snapshots.has(coord) or _terrain_collecting_coords.has(coord):continue
    var room:Node3D=_rooms[coord].get_ref()
    if not is_instance_valid(room):continue
    _terrain_collection=RoomSnapshot.new()
    _terrain_collection.begin(room,coord,_terrain_geometry_origin)
    break
   if not _terrain_collection:break
  performed=true
  _terrain_collection.advance(remaining)
  _terrain_metrics.collect_slices+=1
  if not _terrain_collection.has_pending_worker():break
  _terrain_collecting_coords[_terrain_collection.coord]=true
  _terrain_collection_jobs.append(_terrain_collection);_terrain_collection=null
  remaining=TERRAIN_COLLECT_BUDGET_USEC-(Time.get_ticks_usec()-started)
 var elapsed:=Time.get_ticks_usec()-started
 if performed:_terrain_collection_usec+=elapsed
 _terrain_metrics.collect_slice_max_ms=maxf(_terrain_metrics.collect_slice_max_ms,float(elapsed)/1000.0)
func _touch_terrain_key(key:String)->void:
 if not _terrain_cache.has(key):return
 _terrain_lru.erase(key);_terrain_lru.append(key)
 var payload:Dictionary=_terrain_cache[key]
 # A streamed edge can change depth while BVH/masks remain identical. Keep
 # the latest completed revision per origin, not six versions of fewer rooms.
 for previous:String in _terrain_lru.duplicate():
  if previous==key or previous==_terrain_applied_key:continue
  if _same_cached_origin(payload,_terrain_cache[previous]):
   _terrain_lru.erase(previous);_terrain_cache.erase(previous)
   _terrain_metrics.superseded_cache_entries+=1
 while _terrain_lru.size()>TERRAIN_CACHE_CAPACITY:
  var victim_index:=0
  if _terrain_lru[victim_index]==_terrain_applied_key:victim_index=1
  # Real visits take priority over speculative completion time. If all six
  # origins were visited, an unvisited prewarm evicts itself, not player history.
  for index in _terrain_lru.size():
   var candidate:String=_terrain_lru[index]
   if candidate!=_terrain_applied_key and _terrain_cache[candidate].get("coord") not in _terrain_visited_origins:
    victim_index=index;break
  # A speculative revision of the still-applied origin must not evict a
  # distinct reusable room. The live field remains represented until commit.
  for index in _terrain_lru.size():
   var candidate:String=_terrain_lru[index]
   if candidate==_terrain_applied_key:continue
   if _terrain_cache.has(_terrain_applied_key) and _same_cached_origin(_terrain_cache[candidate],_terrain_cache[_terrain_applied_key]):
    victim_index=index;break
  var oldest:String=_terrain_lru[victim_index]
  if oldest==key and payload.get("coord") not in _terrain_visited_origins:_terrain_metrics.speculative_drops+=1
  _terrain_lru.remove_at(victim_index);_terrain_cache.erase(oldest)
  _terrain_metrics.capacity_evictions+=1
func _mark_terrain_visit(coord:Vector2i)->void:
 _terrain_visited_origins.erase(coord);_terrain_visited_origins.append(coord)
 while _terrain_visited_origins.size()>TERRAIN_CACHE_CAPACITY:_terrain_visited_origins.pop_front()
func _can_prewarm(coord:Vector2i)->bool:
 if _terrain_cache.size()<TERRAIN_CACHE_CAPACITY:return true
 for key:String in _terrain_lru:
  var cached_coord:Variant=_terrain_cache[key].get("coord")
  if cached_coord==coord:return true
  if key!=_terrain_applied_key and cached_coord not in _terrain_visited_origins:return true
 return false
func _same_cached_origin(first:Dictionary,second:Dictionary)->bool:
 return first.has("coord") and second.has("coord") and first.coord==second.coord
func _valid_terrain_payload(payload:Dictionary)->bool:
 if not payload.get("coord") is Vector2i:return false
 return not TerrainDiskCache.validate_payload(payload,{"coord":payload.coord,"origin":Vector2(payload.coord)*32.0,"size":solver.size,"domain":96.0}).is_empty()
func _commit_terrain(payload:Dictionary,key:String)->void:
 if not _valid_terrain_payload(payload):_failed("Incomplete static source terrain payload before publication");return
 if key==_terrain_applied_key:
  _mark_terrain_visit(payload.coord)
  _request_probe_for_committed_target()
  return
 if key!=_terrain_key(payload.coord) or payload.size!=solver.size:return
 if payload.revision!=_terrain_revision:_terrain_metrics.validated_revision_reuses+=1
 var started:=Time.get_ticks_usec()
 var next:Vector2=payload.origin
 var shift:=next-domain_origin
 solver.rebase(shift.x,shift.y)
 if _liquid:_liquid.rebase(Vector3(shift.x,0,shift.y))
 if _whitewater:_whitewater.rebase(Vector3(shift.x,0,shift.y))
 _terrain_metrics.rebase_ms=float(Time.get_ticks_usec()-started)/1000.0
 domain_origin=next
 _refresh_surface_visibility()
 solver.set_depth_image(Image.create_from_data(payload.size,payload.size,false,Image.FORMAT_RF,payload.depth_data.to_byte_array()))
 _set_lamps(payload.coord)
 if not caustics.set_prepared_geometry(payload):_failed("Incomplete static source terrain payload");return
 if _liquid_surface:_liquid_surface.configure_shadow_bvh({"nodes":caustics._node_bytes,"triangles":caustics._triangle_bytes})
 if _whitewater:_whitewater.submerged_mesh.global_position=Vector3(domain_origin.x,0,domain_origin.y)
 _terrain_ready=true;_terrain_dirty=false;_terrain_applied_key=key;_mark_terrain_visit(payload.coord);_touch_terrain_key(key)
 _set_liquid_lights();_bind_all()
 _request_probe_for_committed_target()
 _terrain_metrics.commits+=1;_terrain_metrics.commit_ms=float(Time.get_ticks_usec()-started)/1000.0
 print("SOURCE_TERRAIN_COMMIT ",JSON.stringify({"coord":payload.coord,"ms":_terrain_metrics.commit_ms,"rebase_ms":_terrain_metrics.rebase_ms,"cached":_terrain_cache.size(),"prepare_worker_ms":payload.timing_ms}))
func _set_lamps(coord:Vector2i)->void:
 var layout:Dictionary=_layouts.get(coord,{})
 caustics.set_lamps(_lamp_inputs(coord))
 var reflected:=Vector2(15.7,15.7);var transmitted:=Vector2(15.7,15.7)
 if layout.get("formal",false):
  if coord==Vector2i(-1,-1):reflected=Vector2(11,10);transmitted=Vector2(8,6)
  elif coord==Vector2i(-1,0):reflected=Vector2(7,7);transmitted=Vector2(4,4)
 reflected=layout.get("caustic_reflected_extent",reflected)
 transmitted=layout.get("caustic_transmitted_extent",transmitted)
 caustics.set_wall_extents(reflected,transmitted)
 if _library and _library.has_method("set_source_wall_extents"):_library.set_source_wall_extents(reflected,transmitted)
func set_source_fog(density:float,active:bool)->void:
 _surface_uniforms.sourceFogEnabled=1.0 if active else 0.0
 _surface_uniforms.sourceFogDensity=density
 _surface_uniforms.sourceFogColor=Color("22343d").srgb_to_linear()
 # Low has sceneReady=0; its fallback output must receive source FogExp2 itself.
 for material in _materials.values():
  material.set_shader_parameter("sourceFogEnabled",_surface_uniforms.sourceFogEnabled)
  material.set_shader_parameter("sourceFogDensity",density)
  material.set_shader_parameter("sourceFogColor",_surface_uniforms.sourceFogColor)
func _apply_surface(material:ShaderMaterial)->void:
 if not OS.has_feature("android") and not OS.has_feature("ios") and not OS.get_cmdline_user_args().has("--mobile-preview"):wind_waves.apply_to(material)
 material.set_shader_parameter("poolSurface",solver.get_state_texture());material.set_shader_parameter("poolDepth",solver.get_depth_texture());material.set_shader_parameter("poolDetail",solver.get_detail_texture());material.set_shader_parameter("poolCell",solver.cell);material.set_shader_parameter("detailCell",solver.detail_cell)
 material.set_shader_parameter("domain_origin",domain_origin);material.set_shader_parameter("microOrigin",domain_origin);material.set_shader_parameter("poolTime",_time);material.set_shader_parameter("poolCaustics",caustics.floor_texture)
 material.set_shader_parameter("ripplesOn",0.0 if quality=="Low" else 1.0);material.set_shader_parameter("microOn",1.0 if quality in ["High","Ultra"] else 0.0);material.set_shader_parameter("foamOn",0.0 if quality=="Low" else 1.0)
 for key in _surface_uniforms:material.set_shader_parameter(key,_surface_uniforms[key])
 if is_instance_valid(planar):
  material.set_shader_parameter("mirrorSampler",planar.output);material.set_shader_parameter("textureMatrix",planar.texture_matrix);material.set_shader_parameter("reflectionReady",1.0 if planar.capture_ready else 0.0);material.set_shader_parameter("reflectionSize",float(planar.resolution))
func _bind_all()->void:
 for material in _materials.values():_apply_surface(material)
 var gain:float=float(_surface_uniforms.causticGain) if caustics_enabled and settings.caustics and quality!="Low" else 0.0
 if _library and _library.has_method("set_source_water_uniforms"):_library.set_source_water_uniforms(caustics.floor_texture,caustics.wall_texture,domain_origin,gain)
 var params:=_surface_uniforms.duplicate();params.merge({"poolCell":solver.cell,"detailCell":solver.detail_cell,"microOrigin":domain_origin},true);params.causticGain=gain;caustics.set_parameters(params)
func _stage(label:String,started:int)->int:
 var now:=Time.get_ticks_usec();var ms:=float(now-started)/1000.0
 _frame_stages[label]=ms;_frame_stage_max[label]=maxf(float(_frame_stage_max.get(label,0.0)),ms)
 return now
func _process(delta:float)->void:
 if not _configured:return
 var stage_started:=Time.get_ticks_usec()
 _pump_terrain()
 stage_started=_stage("static_prepare_poll",stage_started)
 _update_probe_capture()
 stage_started=_stage("cubemap_update",stage_started)
 # Refresh after terrain commits, even while paused; do not hook _bind_all
 # because the profile itself publishes/restores through that method.
 if _nearfield_profile:_nearfield_profile.refresh_context()
 if not enabled or _terrain_paused or not _terrain_ready:return
 _time+=maxf(0.0,delta)
 var wind_anchor:=Vector2(_camera.global_position.x,_camera.global_position.z) if is_instance_valid(_camera) else domain_origin
 if not OS.has_feature("android") and not OS.has_feature("ios") and not OS.get_cmdline_user_args().has("--mobile-preview"):wind_waves.advance(delta,wind_anchor)
 if _liquid:_refresh_particle_sampler()
 var focus:=_local(_camera.global_position) if is_instance_valid(_camera) else Vector2.ZERO
 if _liquid:events.crest_spray(minf(delta,.05),func(x:float,z:float,power:float,_foam:float)->void:
  if _liquid:
   var flow:=solver.flow_at(Vector2(x,z));_liquid.crest(x,z,power,{"u":flow.x,"v":flow.y}),focus)
 if _liquid:_liquid.frame(delta)
 if _whitewater:_whitewater.frame(delta) # Each host owns its bounded PC/original timing policy.
 stage_started=_stage("particles_host",stage_started)
 if _liquid_surface:
  _set_liquid_lights()
  var params:=_surface_uniforms.duplicate();params.merge({"poolCell":solver.cell,"detailCell":solver.detail_cell,"poolTime":_time,"microOrigin":domain_origin,"domainOrigin":domain_origin,"ripplesOn":_surface_uniforms.ripplesOn,"microOn":_surface_uniforms.microOn},true)
  _liquid_surface.frame(_liquid,_whitewater,params)
 stage_started=_stage("liquid_lighting_submit",stage_started)
 events.environmental_drips(_time)
 var changed:bool=solver.step(minf(delta,.25))
 stage_started=_stage("wave_solver_submit",stage_started)
 var active:bool=not solver.settled or (solver.detail_active() and bool(settings.ripples)) or (bool(settings.microNormals) and quality in ["High","Ultra"] and settings.microStrength>0.0 and settings.causticsSpeed>0.0)
 if caustics_enabled and quality!="Low":caustics.render(_time,changed,active)
 stage_started=_stage("caustic_submit",stage_started)
 if is_instance_valid(planar):planar.update()
 stage_started=_stage("planar_update",stage_started)
 for material in _materials.values():_apply_surface(material)
 _stage("surface_uniforms",stage_started)
func _local(pos:Vector3)->Vector2:return Vector2(pos.x,pos.z)-domain_origin
func depth_at(pos:Vector3)->float:return solver.depth_at(_local(pos))
func is_water_at(pos:Vector3)->bool:return enabled and depth_at(pos)>0.0
func surface_height_at(pos:Vector3)->float:return LEVEL+solver.height_at(_local(pos))
func current_velocity_at(pos:Vector3)->Vector2:return solver.flow_at(_local(pos))
func slope_at(pos:Vector3,radius:float=.38)->Vector4:return solver.slope_at(_local(pos),radius)*float(settings.wavePush)
func optical_surface_at(p:Vector2)->float:
 if not settings.simulation:return LEVEL
 var sum:float=4.0*solver.height_at(p)
 for v:Vector2 in [Vector2(.22,0),Vector2(-.22,0),Vector2(0,.22),Vector2(0,-.22)]:sum+=2.0*solver.height_at(p+v)
 for v:Vector2 in [Vector2(.16,.16),Vector2(-.16,-.16),Vector2(-.16,.16),Vector2(.16,-.16)]:sum+=solver.height_at(p+v)
 return LEVEL+sum/16.0*float(settings.waveHeight)
func wave_impact(pos:Vector3,power:float)->void:
 if not enabled or not pos.is_finite() or not is_finite(power) or power<=0.0 or not is_water_at(pos):return
 var p:=_local(pos);solver.impact(p.x,p.y,power);interaction_count+=1
 var depth:=minf(1.0,solver.depth_at(p)/.5)
 solver.queue_detail_impact(p.x,p.y,minf(.005,power*.016)*solver.impact_scale*depth)
 if power>.22:
  for i in range(9):
   var angle:float=i*2.39996+interaction_count*.73;var radius:float=.18+.32*float(i%3)/2.0;var q:=p+Vector2(cos(angle),sin(angle))*radius
   if not solver.is_land(q):solver.queue_detail_impact(q.x,q.y,.0014*depth*solver.impact_scale,.12)
func impact(pos:Vector3,power:float)->void:
 # Compatibility tap API; original gameplay call sites use explicit source paths.
 splash(pos,power,{})
func splash(pos:Vector3,power:float,direction:Dictionary={})->void:
 if not enabled or not is_water_at(pos):return
 wave_impact(pos,power)
 if not _liquid and not _whitewater:return
 _refresh_particle_sampler()
 var p:=_local(pos);var current:=solver.flow_at(p)
 var flow:Dictionary={"u":current.x,"v":current.y}
 if not direction.is_empty():
  flow.u+=clampf(float(direction.get("u",0.0))*.22,-1.5,1.5);flow.v+=clampf(float(direction.get("v",0.0))*.22,-1.5,1.5)
 var spray:=flow.duplicate()
 if not direction.is_empty():
  spray=direction.duplicate();spray.u=float(direction.get("u",0.0))+flow.u*.2;spray.v=float(direction.get("v",0.0))+flow.v*.2
 if _liquid:_liquid.impact(p.x,p.y,power,spray)
 if power>.25 and _whitewater:_whitewater.bubbles(p.x,optical_surface_at(p),p.y,roundi(power*10.0),flow)
func player_impact(pos:Vector3,power:float)->void:
 wave_impact(pos,power)
 if power>.22 and _liquid:
  _refresh_particle_sampler()
  var p:=_local(pos);var flow:=solver.flow_at(p);_liquid.impact(p.x,p.y,power,{"u":flow.x,"v":flow.y})
func crest(pos:Vector3,power:float)->void:
 if not _liquid or not enabled:return
 _refresh_particle_sampler()
 var p:=_local(pos);var flow:=solver.flow_at(p);_liquid.crest(p.x,p.y,power,{"u":flow.x,"v":flow.y})
func drop_ripple(pos:Vector2,amplitude:float)->void:
 if amplitude>0.0 and not solver.is_land(pos):solver.queue_detail_impact(pos.x,pos.y,amplitude*solver.impact_scale,.075);ripple_returns+=1
func push(pos:Vector3,impulse:Vector2,sigma:float)->void:
 var p:=_local(pos);solver.push(p.x,p.y,impulse.x*solver.impact_scale,impulse.y*solver.impact_scale,sigma)
 if not solver.is_land(p):solver.queue_detail_impact(p.x,p.y,impulse.length()*.018*solver.impact_scale,.14)
func push_wake(pos:Vector3,impulse:Vector2,sigma:float)->void:
 var p:=_local(pos);solver.push(p.x,p.y,impulse.x,impulse.y,sigma)
func wake_dipole(pos:Vector3,direction:Vector2,speed:float,sigma:float)->void:
 var p:=_local(pos);solver.wake_dipole(p.x,p.y,direction.x,direction.y,speed,sigma)
 if not solver.is_land(p):solver.queue_detail_impact(p.x-direction.x*sigma,p.y-direction.y*sigma,minf(.001,speed*.00012),.14)
func wake(pos:Vector3,relative:Vector2,power:float)->void:
 # Legacy caller compatibility; current player/props use distance/drag impulses directly.
 if relative.length_squared()>0.0:push(pos,relative.normalized()*power,.26)
func _refresh_surface_visibility()->void:
 var center:=Vector2i(roundi(domain_origin.x/32),roundi(domain_origin.y/32))
 for coord:Vector2i in _surfaces:
  var group:Node3D=_surfaces[coord]
  if not is_instance_valid(group):continue
  var delta:=coord-center
  group.visible=enabled and (_layouts.get(coord,{}).get("formal",false) or maxi(absi(delta.x),absi(delta.y))<=1)
func set_enabled(value:bool)->void:
 enabled=value
 _refresh_surface_visibility()
 if is_instance_valid(planar):planar.enabled=value and bool(settings.reflection)
func set_caustics(value:bool)->void:caustics_enabled=value;_bind_all()
func set_debug_view(value:int)->void:settings.debugView=clampi(value,0,11);_surface_uniforms.debugView=float(settings.debugView);_bind_all()
func set_tuning(parameter:String,value:Variant)->void:
 var aliases={"wave_height":"waveHeight","ripple_gain":"rippleGain","micro_strength":"microStrength","normal_boost":"normalBoost","refraction_strength":"refractionStrength","absorption_strength":"absorptionStrength","reflection_strength":"fresnelStrength","caustics_intensity":"causticsIntensity","foam_strength":"foamStrength","debug_view":"debugView","refraction_enabled":"refraction","ssr_enabled":"reflection"}
 var key:String=aliases.get(parameter,parameter)
 if key in WindWaves.DEFAULT:
  var desired:Dictionary=settings.duplicate();desired[key]=value
  var checked:Dictionary=Settings.sanitize_wind_settings(desired)
  for wind_key:String in WindWaves.DEFAULT:settings[wind_key]=checked[wind_key]
  wind_waves.set_target(settings);_tuning[parameter]=settings[key]
  return # Do not rebind photons, reset a field or touch physics for a wind slider.
 if Settings.LAYERS.has(key):settings[key]=bool(value)
 elif key=="debugView":settings[key]=clampi(int(value),0,11)
 else:
  for row:Dictionary in Settings.SLIDERS:
   if row.key==key and (value is float or value is int) and is_finite(float(value)):settings[key]=clampf(float(value),row.min,row.max)
 _tuning[parameter]=value;_apply_settings();_bind_all()
func _apply_settings()->void:
 wind_waves.set_target(settings)
 for row:Dictionary in Settings.SLIDERS:_surface_uniforms[row.key]=settings[row.key]
 _surface_uniforms.distortionScale=settings.distortion;_surface_uniforms.causticGain=settings.causticsIntensity;_surface_uniforms.debugView=float(settings.debugView)
 for layer:String in Settings.LAYERS:
  var key:String="microOn" if layer=="microNormals" else layer+"On"
  _surface_uniforms[key]=1.0 if settings[layer] else 0.0
 _surface_uniforms.ripplesOn=1.0 if settings.ripples and quality!="Low" else 0.0
 _surface_uniforms.microOn=1.0 if settings.microNormals and quality in ["High","Ultra"] else 0.0
 _surface_uniforms.foamOn=1.0 if settings.foam and quality!="Low" else 0.0
 _surface_uniforms.sceneReady=0.0 if quality=="Low" else 1.0
 solver.impact_scale=settings.impact;solver.ring_waves=settings.ringWaves;solver.wave_speed=settings.waveSpeed;solver.damping=settings.damping;solver.viscosity=settings.viscosity;solver.wall_loss=settings.wallLoss;solver.max_steps=roundi(settings.solverSteps);solver.detail_max_steps=roundi(settings.rippleSteps);solver.foam_decay=1.0/maxf(settings.foamLife,.25);solver.detail_frequency=settings.rippleFrequency;solver.detail_enabled=settings.ripples and quality!="Low"
 events.apply_settings(settings)
 if is_instance_valid(planar):planar.enabled=enabled and bool(settings.reflection)
func set_quality(value:String)->void:
 if not quality_levels.has(value):return
 var changed:=quality!=value;quality=value;settings.quality=value
 # Unrelated quality-panel controls may reapply this preset. Do not reset
 # reflection overrides, resize meshes or churn targets when nothing changed.
 if not changed:return
 if changed:
  var image:Image=solver.get_depth_image();image.resize(quality_levels[value].simulation,quality_levels[value].simulation,Image.INTERPOLATE_NEAREST)
  _initialization_stats.quality_reconfigurations+=1
  _initialization_stats.solver_configure_calls+=1
  var previous=solver
  solver=Solver.new();solver.ready.connect(_solver_ready);solver.failed.connect(_failed)
  solver.configure(image,quality_levels[value].simulation,96.0,quality_levels[value].ripple)
  solver.inherit(previous);previous.dispose();events.set_solver(solver)
  caustics.configure(solver.get_state_texture(),solver.get_depth_texture(),solver.get_detail_texture())
  if _liquid_surface:_liquid_surface.configure(solver.get_state_texture(),solver.get_depth_texture(),solver.get_detail_texture())
  for group in _surfaces.values():
   for instance:MeshInstance3D in group.get_children():
    var mesh:=instance.mesh as PlaneMesh;var density:float=float(quality_levels[value].surface)/96.0;mesh.subdivide_width=maxi(1,ceili(mesh.size.x*density));mesh.subdivide_depth=maxi(1,ceili(mesh.size.y*density))
 _apply_settings()
 caustics.set_quality(value)
 if is_instance_valid(planar):planar.set_quality(quality_levels[value].reflection)
 _bind_all()
func _rebuild_terrain()->void:
 # Retained synchronous reference for regression fixtures only. Live gameplay
 # uses _pump_terrain plus immutable prepared cache publication above.
 var started:=Time.get_ticks_msec()
 var colliders:Array=[];var solids:Array=[];var triangles:=PackedVector3Array()
 for weak:WeakRef in _rooms.values():
  var room:Node3D=weak.get_ref()
  if is_instance_valid(room):_collect(room,colliders,solids,triangles)
 print("SOURCE_TERRAIN_COLLECT_MS ",Time.get_ticks_msec()-started," faces=",triangles.size()/3," colliders=",colliders.size())
 solver.set_terrain(colliders)
 # Authored rooms are bounded separate bodies. The original solver remains the
 # same; dry exterior cells encode geometry rather than allowing cross-wall impulses.
 var authored:=false
 for layout in _layouts.values():authored=authored or layout.get("formal",false)
 if authored:
  var image:Image=solver.get_depth_image()
  for z in solver.size:
   for x in solver.size:
    var world_point:=Vector2((x+.5)*solver.cell-48.0,(z+.5)*solver.cell-48.0)+domain_origin
    var coord:=Vector2i(floori((world_point.x+16)/32),floori((world_point.y+16)/32))
    var layout:Dictionary=_layouts.get(coord,{})
    var wet:=false
    if layout.get("water_enabled",false):
     for rect:Rect2 in layout.get("water_rects",[]):
      if rect.has_point(world_point-Vector2(coord)*32):wet=true;break
    if not wet:image.set_pixel(x,z,Color(0,0,0))
  solver.set_depth_image(image)
 print("SOURCE_TERRAIN_DEPTH_MS ",Time.get_ticks_msec()-started)
 caustics.set_geometry(solids,triangles)
 print("SOURCE_TERRAIN_BVH_MS ",Time.get_ticks_msec()-started)
 if _liquid_surface:_liquid_surface.configure_shadow_bvh({"nodes":caustics._node_bytes,"triangles":caustics._triangle_bytes})
 _set_lamps(Vector2i(roundi(domain_origin.x/32),roundi(domain_origin.y/32)))
 # Native scheduling adaptation only: finish the same source AABB visibility
 # mask before publishing photons. GDScript's per-row cost is higher than JS;
 # a 2ms budget otherwise leaves early frames partially unoccluded.
 caustics.rebuild_occlusion(solids)
 print("SOURCE_TERRAIN_MASK_COMPLETE_MS ",Time.get_ticks_msec()-started)
 _set_liquid_lights()
 _request_probe_for_committed_target()
 _bind_all()
func _collect(node:Node,colliders:Array,solids:Array,triangles:PackedVector3Array)->void:
 # Source terrain describes the fixed architecture only. Floating actors use
 # the original two-way force/splash coupling; baking their initial collision
 # shape into this field makes their own water cell dry and sinks them.
 if node is RigidBody3D or node is CharacterBody3D:return
 var offset:=Vector3(domain_origin.x,0,domain_origin.y)
 if node is CollisionShape3D and node.shape:
  var c:=node as CollisionShape3D;var tr:=c.global_transform;tr.origin-=offset
  var shape:Shape3D=c.shape;var half:=Vector3.ZERO;var center:=Vector3.ZERO;var radius:float=-1.0
  if shape is BoxShape3D:half=shape.size*.5
  elif shape is CylinderShape3D:half=Vector3(shape.radius,shape.height*.5,shape.radius);radius=shape.radius
  elif shape is SphereShape3D:half=Vector3.ONE*shape.radius;radius=shape.radius
  elif shape is ConvexPolygonShape3D:
   var points:PackedVector3Array=shape.points
   if not points.is_empty():
    var aabb:=AABB(points[0],Vector3.ZERO)
    for point in points:aabb=aabb.expand(point)
    half=aabb.size*.5;center=aabb.get_center()
  if half.length_squared()>0:
   var scaled_half:=half*tr.basis.get_scale().abs();var entry:Dictionary={"center":tr*center,"half":scaled_half}
   var rotation:=tr.basis.orthonormalized().get_rotation_quaternion()
   if not rotation.is_equal_approx(Quaternion.IDENTITY):entry.rotation=rotation
   elif radius>0:entry.radius=radius*maxf(tr.basis.get_scale().x,tr.basis.get_scale().z)
   colliders.append(entry);solids.append(tr*AABB(center-half,half*2.0))
 if node is MeshInstance3D and node.mesh and node.visible and not String(node.name).begins_with("COLLISION_") and (node.layers&1)!=0 and not node.get_meta("source_transmissive",false) and not node.get_meta("source_exclude_optics",false):
  var transform:Transform3D=node.global_transform;transform.origin-=offset
  for vertex:Vector3 in node.mesh.get_faces():triangles.append(transform*vertex)
 for child in node.get_children():_collect(child,colliders,solids,triangles)
func _set_liquid_lights()->void:
 if not _liquid_surface:return
 var lights:Array=[];var tubes:Array=[]
 var focus:Vector3=_camera.global_position if is_instance_valid(_camera) else Vector3.ZERO
 var direction:Vector3=-_camera.global_basis.z if is_instance_valid(_camera) else Vector3.FORWARD
 var offset:=Vector3(domain_origin.x,0,domain_origin.y)
 for coord:Vector2i in _room_light_refs:
  for reference:WeakRef in _room_light_refs[coord]:
   var light:=reference.get_ref() as OmniLight3D
   if not is_instance_valid(light):continue
   if not light.visible:continue
   if not light.has_meta("source_shadow_managed") and light.global_position.distance_to(offset)>24.0:continue
   var entry:Dictionary={"position":light.global_position-offset,"color":light.light_color.srgb_to_linear(),"intensity":light.light_energy*float(light.get_meta("source_power_per_energy",1.0)),"range":light.omni_range,"decay":2.0,"casts_shadow":light.shadow_enabled}
   var relative:=light.global_position-focus;var along:float=relative.dot(direction);entry.score=relative.length_squared()-along*along+(2500.0 if along<0.0 else 0.0)
   if coord==Vector2i(roundi(domain_origin.x/32.0),roundi(domain_origin.y/32.0)) and light.get_meta("source_shadow_priority",false):tubes.append(entry)
   else:lights.append(entry)
 lights.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.score<b.score)
 var selected:Array=tubes+lights
 _liquid_surface.set_lights(selected.slice(0,27))
func get_preparation_status()->Dictionary:
 var worker:Dictionary=_terrain_progress.read() if _terrain_progress else {}
 var pending:=_terrain_applied_key!=_terrain_key(_requested_coord)
 var worker_coord:Variant=_terrain_job_coord if _terrain_thread else null
 if pending and _terrain_job_key!=_terrain_key(_requested_coord):
  worker={};worker_coord=null
  for job:Dictionary in _terrain_retired_jobs:
   if job.key==_terrain_key(_requested_coord):worker=job.progress.read();worker_coord=job.coord;break
 var stage:="ready"
 if _disposed:stage="disposed"
 elif not last_error.is_empty():stage="error"
 elif _prepare_suspended:stage="suspended"
 elif not solver.is_ready:stage="starting_solver"
 elif _formal_snapshot_job:stage="reading_exact_snapshot"
 elif _terrain_room_snapshots.size()!=_rooms.size():stage="collecting_geometry"
 elif not _geometry_debounce_ready():stage="streaming_geometry"
 elif pending:stage=worker.get("stage","queued")
 elif _terrain_thread:stage="prewarming"
 return {"stage":stage,"ready":is_terrain_ready(),"pending":pending,
  "requested_coord":_requested_coord,"rooms_collected":_terrain_room_snapshots.size(),"rooms_total":_rooms.size(),
  "collection_room":_terrain_collection.coord if _terrain_collection else _requested_coord,
  "collection_vertices":_terrain_collection.vertices_read if _terrain_collection else 0,
  "collection_slices":_terrain_metrics.collect_slices,"rooms_collecting":_terrain_collection_jobs.size()+(1 if _terrain_collection else 0),
  "elapsed_ms":float(Time.get_ticks_usec()-_terrain_requested_usec)/1000.0,
  "worker_coord":worker_coord,"worker_count":(1 if _terrain_thread else 0)+_terrain_retired_jobs.size(),
  "background_workers":_terrain_retired_jobs.size(),"demand_queued":pending and worker.is_empty(),
  "worker":worker,"probe_scheduling":_probe_scheduling_diagnostics(),"probe":_probe.diagnostics() if is_instance_valid(_probe) else {},"error":last_error}
func debug_stats()->Dictionary:
 var result:Dictionary=solver.debug()
 result.initialization=_initialization_stats.duplicate()
 result.preparation=get_preparation_status()
 result.nearfield=nearfield_status()
 result.mobile_optimized=mobile_optimized
 result.volumetric_splashes=not mobile_optimized
 result.cubemap_required=not mobile_optimized
 result.surface_budget=quality_levels[quality].duplicate()
 result.merge({"terrain_ready":is_terrain_ready(),"terrain_pending":_terrain_applied_key!=_terrain_key(_requested_coord),"terrain_coord":Vector2i(roundi(domain_origin.x/32),roundi(domain_origin.y/32)),"requested_coord":_requested_coord,"terrain_cache_hits":_terrain_metrics.cache_hits,"terrain_cache_misses":_terrain_metrics.cache_misses,"terrain_jobs":_terrain_metrics.jobs,"terrain_commits":_terrain_metrics.commits,"terrain_cache_entries":_terrain_cache.size(),"terrain_stage_ms":_terrain_metrics.duplicate(true),"cpu_frame_stages_ms":_frame_stages.duplicate(),"cpu_frame_stage_max_ms":_frame_stage_max.duplicate(),"terrain_worker_running":preparation_pending(),"probe_scheduling":_probe_scheduling_diagnostics(),"probe":_probe.diagnostics() if is_instance_valid(_probe) else {}})
 result.merge({"rooms":_rooms.size(),"quality":quality,"field_resolution":solver.size,"impacts":interaction_count,"droplet_returns":ripple_returns,"caustics":caustics_enabled,"caustic_frames":caustics.caustic_frames,"caustic_error":caustics.last_error,"caustic_diagnostics":caustics.diagnostics(),"planar_ready":is_instance_valid(planar) and planar.capture_ready,"liquid":_liquid.stats() if _liquid else {},"whitewater":_whitewater.stats() if _whitewater else {},"liquid_render_frames":_liquid_surface.rendered_frames if _liquid_surface else 0,"liquid_shadow_buffer_allocations":_liquid_surface.shadow_buffer_allocations if _liquid_surface else 0,"liquid_shadow_buffer_reuses":_liquid_surface.shadow_buffer_reuses if _liquid_surface else 0,"liquid_error":_liquid_surface.last_error if _liquid_surface else "","cubemap_ready":_probe_has_current_texture(),"cubemap_available":is_instance_valid(_probe) and _probe.texture!=null,"source_commit":Solver.SOURCE_COMMIT,"last_error":last_error},true);return result
func dispose()->void:
 if _disposed:return
 _disposed=true;enabled=false;set_process(false)
 if _nearfield_profile:_nearfield_profile.restore();_nearfield_profile=null
 # Only shutdown may join outstanding CPU work; frame/transition paths never do.
 if _terrain_thread:_terrain_thread.wait_to_finish();_terrain_thread=null
 for job:Dictionary in _terrain_retired_jobs:job.thread.wait_to_finish()
 _terrain_retired_jobs.clear();_terrain_visited_origins.clear()
 _terrain_progress=null;_terrain_job_identity.clear();_terrain_keys.clear()
 if _formal_snapshot_job:
  WorkerThreadPool.wait_for_task_completion(_formal_snapshot_job.task_id);_formal_snapshot_job.task_id=-1;_formal_snapshot_job=null
 _terrain_cache.clear();_terrain_lru.clear();_terrain_snapshot.clear();_terrain_room_snapshots.clear()
 if _terrain_collection:_terrain_collection.finish_shutdown();_terrain_collection=null
 for job:RefCounted in _terrain_collection_jobs+_terrain_retired_collections:job.finish_shutdown()
 _terrain_collection_jobs.clear();_terrain_retired_collections.clear();_terrain_collecting_coords.clear()
 # Detach Godot RenderingServer material aliases before retiring native RD textures.
 for material:ShaderMaterial in _materials.values():
  for parameter:String in ["poolSurface","poolDepth","poolDetail","poolCaustics","mirrorSampler"]:material.set_shader_parameter(parameter,null)
 if _library and _library.has_method("set_source_water_uniforms"):_library.set_source_water_uniforms(null,null,domain_origin,0.0)
 if is_instance_valid(_camera):_camera.compositor=null
 if _compositor:_compositor.compositor_effects=[]
 if _liquid_surface:_liquid_surface.dispose()
 if _whitewater:_whitewater.dispose()
 if is_instance_valid(_probe):_probe.dispose()
 solver.dispose();caustics.dispose()
 if is_instance_valid(planar):planar.dispose()
 if _liquid:_liquid.dispose()

func _exit_tree()->void:dispose()
