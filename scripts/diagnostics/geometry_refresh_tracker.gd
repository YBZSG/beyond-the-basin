class_name PoolGeometryRefreshTracker
extends RefCounted
## Deduplicate only identical static-world notifications. New source rooms still
## require real SDFGI invalidation; this is not an initial-only lighting shortcut.
var _signature:Array=[]
var accepted:=0
var duplicates:=0
func request(world_id:int,counters:Dictionary)->bool:
 var signature:Array=[world_id,int(counters.get("shell_builds",0)),int(counters.get("interior_builds",0)),int(counters.get("retirements",0))]
 if signature==_signature:duplicates+=1;return false
 _signature=signature;accepted+=1;return true
func invalidate()->void:_signature.clear()
