extends RefCounted
## Scene-local exact duplicate guard-upright suppression.
## The caller uses only the fixed .025 x 1.10 x .025 BoxMesh, identity basis,
## stair_iron material and collision=false. No per-upright metadata exists.
## A fresh dictionary belongs to each uncached geometry() construction.
## Vector3 dictionary keys compare exact values; no snapping/epsilon/rounding.
static func claim(seen:Dictionary,center:Vector3)->bool:
 if seen.has(center):return false
 seen[center]=true
 return true
