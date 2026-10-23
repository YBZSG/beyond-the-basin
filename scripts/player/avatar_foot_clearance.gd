class_name AvatarFootClearance
extends RefCounted
## One-sided coherent-ramp clearance for the new PC water-action rig.
## Intentionally not a general foot-lock or stair-placement solver.
## Call once after fresh animation/body refinement, before arm IK. Changes only
## UpperLeg/LowerLeg/Foot rotations. Never writes pelvis, root, scale, position,
## camera, physics, foot locks, or persistent overrides. No floor chasing in air.
## Flat planes are deliberately exact no-op; steps and incoherent planes reject.
const MAX_RAISE: float = 0.16
const MIN_SLOPE_Y: float = 0.8660254 # At most 30 degrees.
const FLAT_NORMAL_Y: float = 0.9993908 # Under 2 degrees: authored pose unchanged.
const PROBE_UP: float = 0.25
const PROBE_DOWN: float = 0.30
const PLANE_TOLERANCE: float = 0.010
const NORMAL_DOT: float = 0.995
const RELEASE_RATE: float = 18.0
const RELEASE_SPEED: float = 1.2
const REACH_MARGIN: float = 0.00002
var _skeleton: Skeleton3D
var _legs: Array[Dictionary] = []
var _valid: bool = false
var _epoch: int = -1

func setup(skeleton: Skeleton3D, model_root: Node) -> void:
 _skeleton = skeleton; _legs.clear(); _valid = false
 if not is_instance_valid(skeleton): return
 var hips: int = skeleton.find_bone("Hips")
 for side: String in ["L", "R"]:
  var upper: int = skeleton.find_bone("UpperLeg_"+side)
  var lower: int = skeleton.find_bone("LowerLeg_"+side)
  var foot: int = skeleton.find_bone("Foot_"+side)
  if mini(hips,mini(upper,mini(lower,foot))) < 0: return
  if skeleton.get_bone_parent(upper)!=hips or skeleton.get_bone_parent(lower)!=upper or skeleton.get_bone_parent(foot)!=lower: return
  _legs.append({"side":side,"upper":upper,"lower":lower,"foot":foot,"lift":0.0,"probes":[],
   "l1":skeleton.get_bone_global_rest(upper).origin.distance_to(skeleton.get_bone_global_rest(lower).origin),
   "l2":skeleton.get_bone_global_rest(lower).origin.distance_to(skeleton.get_bone_global_rest(foot).origin)})
 _collect(model_root)
 _valid = _legs.size()==2
 for leg: Dictionary in _legs: _valid = _valid and leg.probes.size()>0

func reset() -> void:
 for leg: Dictionary in _legs: leg.lift = 0.0
 _epoch = -1

func _collect(node: Node) -> void:
 if node is MeshInstance3D and not String(node.name).begins_with("Shadow_"):
  var instance := node as MeshInstance3D
  if instance.mesh!=null and instance.skin!=null:
   for surface: int in instance.mesh.get_surface_count():
    var arrays: Array = instance.mesh.surface_get_arrays(surface)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
    var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
    if vertices.is_empty() or weights.is_empty(): continue
    var stride: int = weights.size()/vertices.size()
    for index: int in vertices.size():
     var links: Array[Dictionary] = []; var rest_point := Vector3.ZERO
     var total: Dictionary = {"L":0.0,"R":0.0}
     for j: int in stride:
      var weight: float = weights[index*stride+j]
      if weight<=0.0001: continue
      var bind: int = joints[index*stride+j]
      var name: String = instance.skin.get_bind_name(bind)
      var bone: int = _skeleton.find_bone(name) if not name.is_empty() else instance.skin.get_bind_bone(bind)
      if bone<0: continue
      name = _skeleton.get_bone_name(bone)
      var point: Vector3 = instance.skin.get_bind_pose(bind)*vertices[index]
      links.append({"bone":bone,"point":point,"weight":weight})
      rest_point += _skeleton.get_bone_global_rest(bone)*point*weight
      for side: String in ["L","R"]:
       if name in ["Foot_"+side,"Toe_"+side]: total[side]+=weight
     if rest_point.y>=0.045: continue
     for leg: Dictionary in _legs:
      if float(total[leg.side])>0.999: leg.probes.append(links)
 for child: Node in node.get_children(): _collect(child)

func _pose(bone: int) -> Transform3D:
 return _skeleton.global_transform*_skeleton.get_bone_global_pose(bone)

func _sole(leg: Dictionary, world_poses: Dictionary) -> Array[Vector3]:
 var result: Array[Vector3] = []
 for links: Array in leg.probes:
  var point := Vector3.ZERO
  for link: Dictionary in links:
   var bone: int=link.bone
   if not world_poses.has(bone):world_poses[bone]=_pose(bone)
   point += (world_poses[bone] as Transform3D)*link.point*float(link.weight)
  result.append(point)
 return result

func _ray(start: Vector3, end: Vector3) -> Dictionary:
 var query := PhysicsRayQueryParameters3D.create(start,end,1)
 query.collide_with_areas = false; query.hit_from_inside = false
 var hit: Dictionary = _skeleton.get_world_3d().direct_space_state.intersect_ray(query)
 if not hit.is_empty() and not hit.get("collider") is StaticBody3D: return {}
 return hit

func _plane(points: Array[Vector3], query: Callable) -> Dictionary:
 var min_x: Vector3=points[0];var max_x: Vector3=points[0];var min_z: Vector3=points[0];var max_z: Vector3=points[0];var center:=Vector3.ZERO
 for p: Vector3 in points:
  center += p
  if p.x<min_x.x:min_x=p
  if p.x>max_x.x:max_x=p
  if p.z<min_z.z:min_z=p
  if p.z>max_z.z:max_z=p
 center /= float(points.size())
 var hits: Array[Dictionary]=[]
 for p: Vector3 in [center,min_x,max_x,min_z,max_z]:
  var hit: Dictionary=query.call(p+Vector3.UP*PROBE_UP,p-Vector3.UP*PROBE_DOWN)
  if hit.is_empty() or not hit.has("position") or not hit.has("normal"): return {"valid":false,"reason":"missing_support"}
  var normal: Vector3=hit.normal;var position: Vector3=hit.position
  if not normal.is_finite() or not position.is_finite() or normal.y<MIN_SLOPE_Y:return {"valid":false,"reason":"unsupported_normal"}
  hits.append(hit)
 var normal: Vector3=(hits[0].normal as Vector3).normalized();var origin: Vector3=hits[0].position
 for hit: Dictionary in hits:
  if normal.dot(hit.normal)<NORMAL_DOT or absf(normal.dot((hit.position as Vector3)-origin))>PLANE_TOLERANCE:return {"valid":false,"reason":"discontinuous_plane"}
 var min_clearance: float=INF
 for p: Vector3 in points:min_clearance=minf(min_clearance,normal.dot(p-origin)/normal.y)
 return {"valid":true,"normal":normal,"position":origin,"clearance":min_clearance,"flat":normal.y>=FLAT_NORMAL_Y}

func _set_basis(bone: int, desired: Basis) -> void:
 var parent: int=_skeleton.get_bone_parent(bone)
 var basis: Basis=_pose(parent).basis if parent>=0 else _skeleton.global_basis
 _skeleton.set_bone_pose_rotation(bone,(basis.orthonormalized().inverse()*desired.orthonormalized()).get_rotation_quaternion().normalized())

func _swing(from: Vector3, to: Vector3) -> Basis:
 var a: Vector3=from.normalized();var b: Vector3=to.normalized();var cross: Vector3=a.cross(b);var dot: float=clampf(a.dot(b),-1.0,1.0)
 return Basis(Quaternion(cross.x,cross.y,cross.z,1.0+dot).normalized() if dot>-.99999 else Quaternion(a,b))

func _solve(leg: Dictionary, lift: float) -> Dictionary:
 var upper: Transform3D=_pose(leg.upper);var lower: Transform3D=_pose(leg.lower);var foot: Transform3D=_pose(leg.foot)
 var target: Vector3=foot.origin+Vector3.UP*lift;var delta: Vector3=target-upper.origin;var reach: float=delta.length()
 var l1: float=leg.l1;var l2: float=leg.l2
 var min_reach: float=sqrt(l1*l1+l2*l2-2.0*l1*l2*cos(deg_to_rad(60.0))) # 120° maximum knee flexion.
 if reach<min_reach or reach>l1+l2-REACH_MARGIN:return {"solved":false,"reason":"unreachable_no_stretch","requested_lift":lift}
 var original_axis: Vector3=(foot.origin-upper.origin).normalized()
 var pole: Vector3=lower.origin-upper.origin;pole-=original_axis*pole.dot(original_axis)
 if pole.length_squared()<0.0000001:return {"solved":false,"reason":"undefined_authored_knee_pole"}
 var direction: Vector3=delta/reach;pole-=direction*pole.dot(direction)
 if pole.length_squared()<0.0000001:return {"solved":false,"reason":"degenerate_target_knee_pole"}
 pole= pole.normalized()
 var along: float=(l1*l1-l2*l2+reach*reach)/(2.0*reach)
 var knee: Vector3=upper.origin+direction*along+pole*sqrt(maxf(0,l1*l1-along*along))
 _set_basis(leg.upper,_swing(lower.origin-upper.origin,knee-upper.origin)*upper.basis)
 _set_basis(leg.lower,_swing(foot.origin-lower.origin,target-knee)*lower.basis)
 _set_basis(leg.foot,foot.basis)
 var result: Transform3D=_pose(leg.foot)
 return {"solved":true,"lift":lift,"target_error":result.origin.distance_to(target),
  "horizontal_error":Vector2(result.origin.x-foot.origin.x,result.origin.z-foot.origin.z).length(),
  "foot_rotation_error":result.basis.get_rotation_quaternion().angle_to(foot.basis.get_rotation_quaternion()),
  "length_error":maxf(absf(_pose(leg.upper).origin.distance_to(_pose(leg.lower).origin)-l1),absf(_pose(leg.lower).origin.distance_to(result.origin)-l2))}

func apply(delta: float, grounded: bool, gait_phase: float, moving_weight: float=1.0,
  excluded: float=0.0, motion_epoch: int=0, support_query: Callable=Callable(),
  controller_floor_normal: Vector3=Vector3.ZERO) -> Dictionary:
 if not _valid:return {"valid":false,"legs":[]}
 if motion_epoch!=_epoch:reset();_epoch=motion_epoch
 if not _skeleton.global_basis.get_scale().is_equal_approx(Vector3.ONE):reset();return {"valid":false,"reason":"unit_scale_required","legs":[]}
 var dt: float=clampf(delta,0.0,0.1) if is_finite(delta) else 0.0
 if dt<=0:return {"valid":true,"active":false,"legs":[]}
 var query: Callable=support_query if support_query.is_valid() else _ray
 var eligible: bool=grounded and excluded<.001
 # A CURRENT grounded controller normal is only an optional cheap flat hint.
 # Unknown/zero normals use the full measured-plane path. Existing lift still
 # releases smoothly; no hidden cached world-floor target is retained.
 var flat_hint: bool=eligible and controller_floor_normal.is_finite() and controller_floor_normal.length_squared()>.9 and controller_floor_normal.normalized().y>=FLAT_NORMAL_Y
 var can_probe: bool=eligible and not flat_hint
 var world_poses: Dictionary={}
 if flat_hint and float(_legs[0].lift)==0.0 and float(_legs[1].lift)==0.0:
  return {"valid":true,"active":false,"legs":[],"reason":"known_flat_zero_lift","static_ray_budget":0,"sole_vertices_evaluated":0,"pelvis_changed":false,"root_changed":false,"persistent_overrides":false}
 var result: Dictionary={"valid":true,"active":false,"legs":[],"static_ray_budget":10 if can_probe else 0,"pelvis_changed":false,"root_changed":false,"persistent_overrides":false}
 for leg: Dictionary in _legs:
  var phase: float=fposmod(gait_phase+(0.0 if leg.side=="L" else .5),1.0)
  var support: float=clampf(1.0-smoothstep(.56,.68,phase)+smoothstep(.94,1.0,phase),0.0,1.0) if moving_weight>.05 else 1.0
  var surface: Dictionary=_plane(_sole(leg,world_poses),query) if can_probe else {"valid":false,"reason":"known_flat_release" if flat_hint else "air_or_swim_no_probe"}
  var wanted: float=0.0
  if surface.get("valid",false) and not surface.flat:
   wanted=maxf(0.0,lerpf(.001,.003,support)-float(surface.clearance))
  var capped: bool=wanted>MAX_RAISE
  wanted=minf(wanted,MAX_RAISE)
  # Immediate minimal positive clearance on a continuous plane; only release is
  # rate limited. No world-floor target survives flight or water transition.
  var previous: float=leg.lift
  # Exact integration of d(lift)/dt = -min(rate*lift, speed), including
  # the linear-to-exponential crossing. Real frame time through 100 ms means
  # 15/30/60 Hz release reaches the same state at the same wall-clock time.
  var crossover: float=RELEASE_SPEED/RELEASE_RATE
  var linear_time: float=maxf(0.0,(previous-crossover)/RELEASE_SPEED)
  var released: float=previous-RELEASE_SPEED*dt if dt<=linear_time else minf(previous,crossover)*exp(-RELEASE_RATE*(dt-linear_time))
  leg.lift=maxf(wanted,released)
  if float(leg.lift)<.00002:leg.lift=0.0
  var row: Dictionary={"side":leg.side,"support_phase":support,"surface":surface,"requested_lift":wanted,"capped":capped,"previous_lift":previous,"lift":leg.lift,"sole_vertices":leg.probes.size()}
  if float(leg.lift)>0.0:
   row.solve=_solve(leg,leg.lift);result.active=result.active or bool(row.solve.solved)
  else:row.solve={"solved":true,"lift":0.0,"reason":"authored_pose_unchanged"}
  result.legs.append(row)
 return result
