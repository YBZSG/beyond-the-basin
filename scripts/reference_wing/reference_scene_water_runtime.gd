extends "res://scripts/reference_wing/reference_water_runtime.gd"
## Only the finite new wing uses authored polygon depth. Original/formal/random
## rooms, their algorithms and prepared caches are never routed through this adapter.
const DepthField=preload("res://scripts/reference_wing/reference_depth_field.gd")
const SurfaceMesh=preload("res://scripts/reference_wing/reference_surface_mesh.gd")
var _reference_depth_thread:Thread
var _reference_depth_jobs:Array=[]
var _reference_depth_current:Dictionary={}
var _reference_depth_metrics:Dictionary={}

func add_room(room:Node3D,coord:Vector2i,layout:Dictionary)->void:
	super.add_room(room,coord,layout)
	if not layout.get("reference_wing",false):return
	# The original collector is Omni-only. Reference spots remain one native
	# light each; admit them to the unchanged point-input liquid approximation
	# rather than inventing a second renderer-visible Omni at the same fixture.
	var refs:Array[WeakRef]=[]
	for candidate in room.find_children("*","Light3D",true,false):
		if candidate is OmniLight3D or candidate is SpotLight3D:refs.append(weakref(candidate))
	_room_light_refs[coord]=refs
	_replace_surface_meshes(coord,layout)

func _set_liquid_lights()->void:
	if not _liquid_surface:return
	var lights:Array=[];var tubes:Array=[]
	var focus:Vector3=_camera.global_position if is_instance_valid(_camera) else Vector3.ZERO
	var direction:Vector3=-_camera.global_basis.z if is_instance_valid(_camera) else Vector3.FORWARD
	var offset:=Vector3(domain_origin.x,0,domain_origin.y)
	for coord:Vector2i in _room_light_refs:
		for reference:WeakRef in _room_light_refs[coord]:
			var light:=reference.get_ref() as Light3D
			if not is_instance_valid(light) or not (light is OmniLight3D or light is SpotLight3D):continue
			if not light.visible:continue
			if not light.has_meta("source_shadow_managed") and light.global_position.distance_to(offset)>24.0:continue
			var light_range:float=light.omni_range if light is OmniLight3D else light.spot_range
			# Intentionally identical to the source point-light formula and ranking.
			# Neither liquid/droplet shaders nor the photon solver accept a cone.
			var entry:Dictionary={"position":light.global_position-offset,"color":light.light_color.srgb_to_linear(),"intensity":light.light_energy*float(light.get_meta("source_power_per_energy",1.0)),"range":light_range,"decay":2.0,"casts_shadow":light.shadow_enabled}
			var relative:=light.global_position-focus;var along:float=relative.dot(direction);entry.score=relative.length_squared()-along*along+(2500.0 if along<0.0 else 0.0)
			if coord==Vector2i(roundi(domain_origin.x/32.0),roundi(domain_origin.y/32.0)) and light.get_meta("source_shadow_priority",false):tubes.append(entry)
			else:lights.append(entry)
	lights.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.score<b.score)
	var selected:Array=tubes+lights
	_liquid_surface.set_lights(selected.slice(0,27))

func _replace_surface_meshes(coord:Vector2i,layout:Dictionary)->void:
	var group:Node3D=_surfaces[coord]
	for child:Node3D in group.get_children():child.hide();child.queue_free()
	for region:Dictionary in layout.get("reference_water_regions",[]):
		var surface:=MeshInstance3D.new()
		surface.name="ExactBasinSurface"
		surface.mesh=SurfaceMesh.build(region.polygon_xz,float(quality_levels[quality].surface)/96.0)
		surface.material_override=_materials[coord];surface.position.y=LEVEL;surface.layers=2
		surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;surface.extra_cull_margin=.4
		group.add_child(surface)

func _terrain_key(coord:Vector2i)->String:
	var original:=super._terrain_key(coord)
	if _terrain_snapshot.is_empty():return original
	var lookup:="%d:%d:%d:%s"%[coord.x,coord.y,solver.size,TerrainIdentity.digest(_effective_lamps(coord))]
	var identity:Dictionary=_terrain_keys[lookup]
	if not identity.has("reference_depth_revision"):
		identity.depth_key=TerrainIdentity.digest([identity.depth_key,DepthField.REVISION,DepthField.profiles(_layouts)])
		identity.key="%d:%d:%d:%s"%[coord.x,coord.y,solver.size,TerrainIdentity.digest([identity.depth_key,identity.bvh_key,identity.mask_key])]
		identity.reference_depth_revision=DepthField.REVISION
	return identity.key

func _accept_terrain_result(value:Variant,key:String,identity:Dictionary,force_revision:int)->void:
	if not value is Dictionary or not value.get("coord") is Vector2i or not value.get("size") is int:
		super._accept_terrain_result(value,key,identity,force_revision);return
	# A valid worker from an old quality/revision is stale, not corrupt.
	if force_revision!=_terrain_force_revision or int(value.size)!=solver.size:
		_terrain_metrics.stale_results+=1;return
	if not _valid_terrain_payload(value):
		_failed("Incomplete source payload before authored polygon correction");return
	# Profiles must match the captured job identity, not a newer streamed layout.
	if key!=_terrain_key(value.coord):
		_terrain_metrics.stale_results+=1;return
	# At most the existing source foreground + retired result can arrive in one
	# pass. Queue immutable values, never Nodes, GPU buffers or source callbacks.
	_reference_depth_jobs.append({"payload":value,"key":key,"identity":identity,"force":force_revision,"profiles":DepthField.profiles(_layouts)})
	assert(_reference_depth_jobs.size()<=2,"Unbounded authored depth queue")
	# Stop the remainder of this synchronous base scheduling pass from launching
	# a duplicate job before the corrected payload has been published. Restored
	# by our outer _advance_terrain immediately, not an asynchronous user flag.
	_prepare_suspended=true

func _advance_terrain()->void:
	if _reference_depth_thread!=null:
		if _reference_depth_thread.is_alive():return
		var result:Variant=_reference_depth_thread.wait_to_finish();_reference_depth_thread=null
		var job:=_reference_depth_current;_reference_depth_current={}
		_reference_depth_metrics=result.get("reference_depth",{}) if result is Dictionary else {}
		super._accept_terrain_result(result,job.key,job.identity,job.force)
	if not _reference_depth_jobs.is_empty():
		_start_reference_depth();return
	var user_suspended:=_prepare_suspended
	super._advance_terrain()
	_prepare_suspended=user_suspended
	if not _reference_depth_jobs.is_empty():_start_reference_depth()

func _start_reference_depth()->void:
	_reference_depth_current=_reference_depth_jobs.pop_front()
	_reference_depth_thread=Thread.new()
	var error:=_reference_depth_thread.start(DepthField.build.bind(_reference_depth_current.payload,_reference_depth_current.profiles),Thread.PRIORITY_LOW)
	if error!=OK:
		_reference_depth_thread=null;_reference_depth_current={};_reference_depth_jobs.clear()
		_failed("Could not start authored polygon depth worker: "+str(error))

func set_quality(value:String)->void:
	if not quality_levels.has(value) or value==quality:
		super.set_quality(value);return
	# The source implementation mutates PlaneMesh subdivision in-place. Keep
	# its solver/caustic/reflection setup intact, but exclude this new ArrayMesh
	# list for that synchronous call and then recreate only our surface geometry.
	var surfaces:Dictionary=_surfaces
	_surfaces={}
	super.set_quality(value)
	_surfaces=surfaces
	for coord:Vector2i in _surfaces:
		_replace_surface_meshes(coord,_layouts[coord])
	_refresh_surface_visibility()

func preparation_pending()->bool:
	return _reference_depth_thread!=null or not _reference_depth_jobs.is_empty() or super.preparation_pending()

func get_preparation_status()->Dictionary:
	var result:=super.get_preparation_status()
	result.reference_depth=_reference_depth_metrics.duplicate()
	result.reference_depth_queued=_reference_depth_jobs.size()
	if _reference_depth_thread!=null:
		result.stage="authored_polygon_depth"
		result.pending=true
		result.worker_count=int(result.worker_count)+1
	return result

func dispose()->void:
	if _reference_depth_thread!=null:
		_reference_depth_thread.wait_to_finish();_reference_depth_thread=null
	_reference_depth_jobs.clear();_reference_depth_current={}
	super.dispose()
