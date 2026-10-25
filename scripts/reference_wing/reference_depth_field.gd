extends RefCounted
## Exact static authored basin profiles. Geometry adaptation, not a fluid solver.
## All input polygons are derived from the exported visible/collision surfaces.
const Catalog=preload("res://scripts/reference_wing/reference_catalog.gd")
const REVISION="reference-polygon-depth-v1"

static func polygon(values:Array)->PackedVector2Array:
	var result:=PackedVector2Array()
	for value:Array in values:result.append(Vector2(value[0],value[1]))
	return result

static func profiles(layouts:Dictionary)->Array:
	var result:Array=[]
	for coord:Vector2i in layouts:
		var layout:Dictionary=layouts[coord]
		if not layout.get("reference_wing",false):continue
		var data:Dictionary=layout.geometry_contract
		var steps:Array=[];var exclusions:Array=[]
		for step:Dictionary in data.get("water_steps",[]):
			steps.append({"polygon":polygon(step.footprint_xz),"bounds":Catalog.bounds_xz(step.footprint_xz),"top":float(step.top_y)})
		for exclusion:Dictionary in data.get("water_exclusions",[]):
			exclusions.append({"polygon":polygon(exclusion.polygon_xz),"bounds":Catalog.bounds_xz(exclusion.polygon_xz)})
		for region:Dictionary in data.get("water_regions",[]):
			result.append({"offset":Vector2(coord)*32.0,"polygon":polygon(region.polygon_xz),"bounds":Catalog.bounds_xz(region.polygon_xz),
				"bottom":float(region.bottom_y),"surface":float(region.surface_y),"steps":steps,"exclusions":exclusions})
	return result

static func point_depth(local:Vector2,profile:Dictionary)->float:
	if not Geometry2D.is_point_in_polygon(local,profile.polygon):return 0.0
	for exclusion:Dictionary in profile.exclusions:
		if exclusion.bounds.grow(.000001).has_point(local) and Geometry2D.is_point_in_polygon(local,exclusion.polygon):return 0.0
	var floor_y:float=profile.bottom
	for step:Dictionary in profile.steps:
		if step.bounds.grow(.000001).has_point(local) and Geometry2D.is_point_in_polygon(local,step.polygon):floor_y=maxf(floor_y,step.top)
	return maxf(0.0,profile.surface-floor_y)

static func build(payload:Dictionary,authored:Array)->Dictionary:
	var started:=Time.get_ticks_usec()
	var result:=payload.duplicate(false)
	var size:int=payload.size
	var domain:float=payload.get("domain",96.0)
	var origin:Vector2=payload.origin
	var cell:=domain/size
	var depth:=PackedFloat32Array();depth.resize(size*size);depth.fill(0.0)
	var visited:=0
	for profile:Dictionary in authored:
		var relative:Vector2=profile.offset-origin
		var bounds:Rect2=profile.bounds
		var lo:Vector2=bounds.position+relative
		var hi:Vector2=bounds.end+relative
		var x0:=maxi(0,ceili((lo.x+domain*.5)/cell-.5));var x1:=mini(size-1,floori((hi.x+domain*.5)/cell-.5))
		var z0:=maxi(0,ceili((lo.y+domain*.5)/cell-.5));var z1:=mini(size-1,floori((hi.y+domain*.5)/cell-.5))
		for z in range(z0,z1+1):
			for x in range(x0,x1+1):
				var local:=Vector2((x+.5)*cell-domain*.5,(z+.5)*cell-domain*.5)-relative
				depth[x+z*size]=point_depth(local,profile);visited+=1
	result.depth_data=depth
	result.reference_depth={"revision":REVISION,"samples":visited,"worker_ms":float(Time.get_ticks_usec()-started)/1000.0}
	return result
