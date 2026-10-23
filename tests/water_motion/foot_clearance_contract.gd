extends SceneTree
const Clearance=preload("res://scripts/player/avatar_foot_clearance.gd")
const Inspector=preload("res://tests/water_motion/rig_motion_contract.gd")
var model: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var helper: RefCounted
var inspector: RefCounted
var failures: Array[String]=[]
var slope: float=1.16/3.0
var report: Dictionary={"integrated":false,"actual_static_physics_rays":true,"samples":0}
func _initialize() -> void:_run.call_deferred()
func _floor(point: Vector3) -> float:return point.z*slope
func _fresh(phase: float) -> void:
 animation.play("Wade");animation.seek(phase*1.4,true);animation.advance(0.0)
func _rotations() -> Array[Quaternion]:
 var q: Array[Quaternion]=[]
 for b: int in skeleton.get_bone_count():q.append(skeleton.get_bone_pose_rotation(b))
 return q
func _min_sole() -> float:
 var poses: Array[Transform3D]=[]
 for b: int in skeleton.get_bone_count():poses.append(skeleton.get_bone_global_pose(b))
 var value: float=INF
 for side: String in ["L","R"]:
  for point: Vector3 in inspector._skin_points("sole_"+side,poses):value=minf(value,point.y-_floor(point))
 return value

func _sole_cloud() -> Dictionary:
 var poses: Array[Transform3D]=[]
 for bone: int in skeleton.get_bone_count():poses.append(skeleton.get_bone_global_pose(bone))
 return {"L":inspector._skin_points("sole_L",poses),"R":inspector._skin_points("sole_R",poses)}

func _release_scenario(kind: String) -> Dictionary:
 # Seed a fully corrected ramp pose, then compare every skinned sole point to
 # a freshly evaluated uncorrected source pose throughout each transition.
 helper.reset()
 for tick: int in 30:
  _fresh(.52747);helper.apply(1.0/120.0,true,.52747)
 var previous_residual: Dictionary={};var max_step: float=0.0;var max_horizontal: float=0.0;var last_residual: float=INF;var max_release_rotation: float=0.0
 var last_q: Array[Quaternion]=[];var unsolved: int=0
 for tick: int in 150:
  var age: float=float(tick)/120.0
  if kind=="flat_stop":_fresh(.52747)
  elif kind=="jump":
   var clip: String="JumpRise" if age<.25 else "JumpAir"
   animation.play(clip);animation.seek(age if age<.25 else fposmod(age-.25,.60),true);animation.advance(0.0)
  else:
   animation.play("Swim");animation.seek(age,true);animation.advance(0.0)
  var baseline: Dictionary=_sole_cloud()
  var result: Dictionary=helper.apply(1.0/120.0,kind=="flat_stop",.52747,0.0,0.0 if kind=="flat_stop" else 1.0,0,Callable(),Vector3.UP if kind=="flat_stop" else Vector3.ZERO)
  if result.static_ray_budget!=0:failures.append("Release scenario performed floor probes")
  for row: Dictionary in result.legs:
   if not row.solve.solved:unsolved+=1
  var corrected: Dictionary=_sole_cloud();last_residual=0.0
  for side: String in ["L","R"]:
   var residual: Array[Vector3]=[]
   for index: int in baseline[side].size():
    var difference: Vector3=corrected[side][index]-baseline[side][index];residual.append(difference)
    last_residual=maxf(last_residual,difference.length())
    max_horizontal=maxf(max_horizontal,Vector2(difference.x,difference.z).length())
    if previous_residual.has(side):max_step=maxf(max_step,difference.distance_to(previous_residual[side][index]))
   previous_residual[side]=residual
  var q: Array[Quaternion]=_rotations()
  if not last_q.is_empty() and kind=="flat_stop":
   for bone: int in q.size():max_release_rotation=maxf(max_release_rotation,rad_to_deg(q[bone].angle_to(last_q[bone])))
  last_q=q
 if last_residual>.000025:failures.append(kind+" retained extra foot lift/hover")
 if max_step>.0101 or max_horizontal>.00002 or unsolved>0:failures.append(kind+" release continuity/chain failed")
 return {"actual_weighted_sole_vertices_per_frame":inspector.probes.sole_L.size()+inspector.probes.sole_R.size(),"maximum_residual_step_120hz_m":max_step,"maximum_horizontal_change_m":max_horizontal,"final_extra_lift_or_hover_m":last_residual,"stop_rotation_step_deg":max_release_rotation,"unreachable_frames":unsolved}

func _release_walltime() -> Dictionary:
 var samples: Dictionary={};var maximum_endpoint_difference: float=0.0
 for hz: int in [120,60,30,15]:
  helper.reset()
  for tick: int in 30:
   _fresh(.52747);helper.apply(1.0/120.0,true,.52747)
  var endpoints: Array[float]=[]
  for tick: int in hz:
   _fresh(.52747)
   var baseline: Dictionary=_sole_cloud()
   var result: Dictionary=helper.apply(1.0/float(hz),true,.52747,0.0,0.0,0,Callable(),Vector3.UP)
   if result.static_ray_budget!=0:failures.append("Wall-time release queried floor")
   if (tick+1)%(hz/5)==0:
    var corrected: Dictionary=_sole_cloud();var residual: float=0.0
    for side: String in ["L","R"]:
     for index: int in baseline[side].size():residual=maxf(residual,corrected[side][index].distance_to(baseline[side][index]))
    endpoints.append(residual)
  samples[str(hz)]=endpoints
  if hz!=120:
   for index: int in endpoints.size():maximum_endpoint_difference=maxf(maximum_endpoint_difference,absf(endpoints[index]-float(samples["120"][index])))
  if endpoints[-1]>.000025:failures.append("Release did not settle at "+str(hz)+" Hz")
 if maximum_endpoint_difference>.000005:failures.append("Frame-rate-dependent release wall time")
 return {"sample_times_seconds":[.2,.4,.6,.8,1.0],"actual_weighted_sole_max_residual_m_by_hz":samples,"maximum_endpoint_difference_m":maximum_endpoint_difference,"finite_delta_cap_seconds":.1}

func _run() -> void:
 model=load("res://assets/water_motion/explorer_water_motion.scn").instantiate();root.add_child(model);model.position.z=.13
 skeleton=model.find_children("*","Skeleton3D",true,false)[0]
 animation=model.find_children("*","AnimationPlayer",true,false)[0];animation.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 helper=Clearance.new();helper.setup(skeleton,model);inspector=Inspector.new();inspector.setup(model,skeleton)
 var floor:=StaticBody3D.new();floor.collision_layer=1;root.add_child(floor)
 var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(10,.2,40);shape.shape=box;floor.add_child(shape)
 var angle: float=atan(slope);var normal:=Vector3(0,cos(angle),-sin(angle));floor.rotation.x=-angle;floor.position=-normal*.1
 await physics_frame;await physics_frame
 var before_min: float=INF;var after_min: float=INF;var max_error: float=0.0;var max_link_error: float=0.0;var caps: int=0;var unsolved: int=0;var root_before: Transform3D=model.transform
 var max_lift_step: float=0.0
 var microseconds: Array[int]=[]
 var unexpected_bone_changes: int=0
 var allowed: Array[String]=["UpperLeg_L","LowerLeg_L","Foot_L","UpperLeg_R","LowerLeg_R","Foot_R"]
 for tick: int in 480:
  var phase: float=fposmod(float(tick)/168.0,1.0);_fresh(phase)
  var hips_before: Transform3D=skeleton.get_bone_global_pose(skeleton.find_bone("Hips"));before_min=minf(before_min,_min_sole())
  var original_rotations: Array[Quaternion]=_rotations()
  var started_usec: int=Time.get_ticks_usec()
  var result: Dictionary=helper.apply(1.0/120.0,true,phase)
  microseconds.append(Time.get_ticks_usec()-started_usec)
  for b: int in skeleton.get_bone_count():
   if not skeleton.get_bone_name(b) in allowed and skeleton.get_bone_pose_rotation(b)!=original_rotations[b]:unexpected_bone_changes+=1
  for row: Dictionary in result.legs:
   if row.capped:caps+=1
   if not row.solve.solved:unsolved+=1
   max_error=maxf(max_error,float(row.solve.get("target_error",0.0)));max_link_error=maxf(max_link_error,float(row.solve.get("length_error",0.0)))
   if tick>0:max_lift_step=maxf(max_lift_step,absf(float(row.lift)-float(row.previous_lift)))
  if skeleton.get_bone_global_pose(skeleton.find_bone("Hips"))!=hips_before:failures.append("Hips changed")
  after_min=minf(after_min,_min_sole());report.samples+=1
 microseconds.sort()
 report.software_cpu_microcost_us={"scope":"helper only, cached bone transforms, actual static rays; not target-PC FPS", "ramp_p50":microseconds[microseconds.size()/2],"ramp_p95":microseconds[int(microseconds.size()*.95)],"ramp_max":microseconds[-1]}
 report.unexpected_bone_changes=unexpected_bone_changes
 if unexpected_bone_changes>0:failures.append("Unexpected bone rotation changed")
 report.ramp={"degrees":rad_to_deg(angle),"before_min_m":before_min,"after_min_m":after_min,"max_target_error_m":max_error,"max_length_error_m":max_link_error,"capped_samples":caps,"unsolved_samples":unsolved,"max_lift_step_120hz_m":max_lift_step}
 if after_min<-.001:failures.append("Ramp penetration remains")
 if max_error>.00005 or max_link_error>.00002:failures.append("Exact chain/target constraint failed")
 if model.transform!=root_before:failures.append("Model/root changed")
 # Air release must be continuous relative correction, with no floor requests.
 for settle: int in 30:
  _fresh(.52747);helper.apply(1.0/120.0,true,.52747)
 var release_start: float=0.0;var release_step: float=0.0;var release_rotation_step: float=0.0;var previous_rotations: Array[Quaternion]=_rotations()
 for tick: int in 90:
  _fresh(.52747)
  var result: Dictionary=helper.apply(1.0/120.0,false,.52747,1.0,1.0)
  if result.static_ray_budget!=0:failures.append("Air queried floor")
  var current_rotations: Array[Quaternion]=_rotations()
  for b: int in skeleton.get_bone_count():release_rotation_step=maxf(release_rotation_step,rad_to_deg(previous_rotations[b].angle_to(current_rotations[b])))
  previous_rotations=current_rotations
  for row: Dictionary in result.legs:
   if tick==0:release_start=maxf(release_start,float(row.previous_lift))
   release_step=maxf(release_step,absf(float(row.lift)-float(row.previous_lift)))
 report.transition_release={"ramp_to_flat_stop":_release_scenario("flat_stop"),"jump":_release_scenario("jump"),"swim":_release_scenario("swim")}
 report.release_walltime=_release_walltime()
 report.air_release={"starting_lift":release_start,"max_per_tick_step_m":release_step,"max_rotation_step_120hz_deg":release_rotation_step,"last_lifts":[helper._legs[0].lift,helper._legs[1].lift]}
 # Independent flat test: no prior ramp state and every pose bit-identical.
 slope=0.0;floor.rotation=Vector3.ZERO;floor.position=Vector3(0,-.1,0);helper.reset()
 await physics_frame;await physics_frame
 var flat_changed: int=0
 for tick: int in 168:
  var phase: float=float(tick)/168.0;_fresh(phase);var before: Array[Quaternion]=_rotations();helper.apply(1.0/120.0,true,phase)
  if before!=_rotations():flat_changed+=1
 var fast_samples: Array[int]=[]
 for repeat: int in 1000:
  var started_usec: int=Time.get_ticks_usec()
  var fast: Dictionary=helper.apply(1.0/120.0,true,.5,1.0,0.0,0,Callable(),Vector3.UP)
  fast_samples.append(Time.get_ticks_usec()-started_usec)
  if fast.static_ray_budget!=0 or fast.get("sole_vertices_evaluated",-1)!=0:failures.append("Flat hint did expensive work")
 fast_samples.sort()
 report.software_cpu_microcost_us.flat_hint_p50=fast_samples[500]
 report.software_cpu_microcost_us.flat_hint_p95=fast_samples[950]
 report.software_cpu_microcost_us.flat_hint_max=fast_samples[-1]
 report.flat_changed_samples=flat_changed
 if flat_changed!=0:failures.append("Flat authored pose changed")
 report.failures=failures;report.passed=failures.is_empty()
 FileAccess.open("res://assets/water_motion/foot_clearance_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
 print("FOOT_CLEARANCE_CONTRACT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
