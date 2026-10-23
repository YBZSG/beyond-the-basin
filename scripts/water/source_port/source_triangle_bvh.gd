extends RefCounted
## Exact storage optimization of SourceCaustics' original median-split builder.
## Same Godot sort_custom algorithm, comparison values, unstable tie ordering,
## leaf threshold, traversal, triangle order and 48-byte output layout.
## A new builder belongs to one CPU job; no shared mutable or engine resources.
## Packed Float64 centers retain the already-computed Vector3 values exactly,
## including custom double-precision builds (those builds are not yet executed).
## See frozen-reference fixtures and docs/SOURCE-WATER-EXACT-OPTIMIZATION.md.
var _vertices := PackedVector3Array()
var _mins := PackedVector3Array()
var _maxs := PackedVector3Array()
var _centers: Array[PackedFloat64Array] = []
var _nodes: Array[Dictionary] = []
var _ordered: Array[int] = []
func build_triangle_bvh(vertices: PackedVector3Array) -> Dictionary:
	_vertices = vertices
	_nodes.clear(); _ordered.clear(); _centers.clear()
	var count := vertices.size() / 3
	_mins.resize(count); _maxs.resize(count)
	var centers_x := PackedFloat64Array(); centers_x.resize(count)
	var centers_y := PackedFloat64Array(); centers_y.resize(count)
	var centers_z := PackedFloat64Array(); centers_z.resize(count)
	var items: Array[int] = []
	for i in range(0, vertices.size() - 2, 3):
		var a := vertices[i]; var b := vertices[i + 1]; var c := vertices[i + 2]
		if not a.is_finite() or not b.is_finite() or not c.is_finite(): continue
		if (b - a).cross(c - a).length_squared() < 1.0e-18: continue
		var index := i / 3
		_mins[index] = a.min(b).min(c); _maxs[index] = a.max(b).max(c)
		var center := (a + b + c) / 3.0
		centers_x[index] = center.x; centers_y[index] = center.y; centers_z[index] = center.z
		items.append(index)
	_centers = [centers_x, centers_y, centers_z]
	_build_node(items)
	var node_data := PackedByteArray(); node_data.resize(_nodes.size() * 48)
	for i in _nodes.size():
		var n: Dictionary = _nodes[i]
		for axis in 3:
			node_data.encode_float(i * 48 + axis * 4, n.min[axis])
			node_data.encode_float(i * 48 + 16 + axis * 4, n.max[axis])
		node_data.encode_s32(i * 48 + 32, n.left); node_data.encode_s32(i * 48 + 36, n.right)
		node_data.encode_s32(i * 48 + 40, n.start); node_data.encode_s32(i * 48 + 44, n.count)
	var values := PackedFloat32Array(); values.resize(maxi(1, _ordered.size()) * 12)
	for i in _ordered.size():
		var vertex := _ordered[i] * 3
		var a := _vertices[vertex]; var b := _vertices[vertex + 1]; var c := _vertices[vertex + 2]; var n := i * 12
		values[n] = a.x; values[n + 1] = a.y; values[n + 2] = a.z
		values[n + 4] = b.x; values[n + 5] = b.y; values[n + 6] = b.z
		values[n + 8] = c.x; values[n + 9] = c.y; values[n + 10] = c.z
	var triangle_data := values.to_byte_array()
	return {"nodes": node_data, "triangles": triangle_data, "node_count": _nodes.size(), "triangle_count": _ordered.size()}
func _build_node(items: Array[int]) -> int:
	var index := _nodes.size(); var lo := Vector3(INF, INF, INF); var hi := Vector3(-INF, -INF, -INF)
	for item in items: lo = lo.min(_mins[item]); hi = hi.max(_maxs[item])
	if items.is_empty(): lo = Vector3.ZERO; hi = Vector3.ZERO
	_nodes.append({"min": lo, "max": hi, "left": -1, "right": -1, "start": _ordered.size(), "count": items.size()})
	if items.size() <= 8:
		_ordered.append_array(items); return index
	var span := hi - lo
	var axis := 0 if span.x >= span.y and span.x >= span.z else (1 if span.y >= span.z else 2)
	var centers: PackedFloat64Array = _centers[axis]
	items.sort_custom(func(a: int, b: int) -> bool: return centers[a] < centers[b])
	var middle := items.size() / 2
	var left_items: Array[int] = items.slice(0, middle)
	var left := _build_node(left_items)
	var right_items: Array[int] = items.slice(middle)
	var right := _build_node(right_items)
	_nodes[index].left = left; _nodes[index].right = right; _nodes[index].count = 0
	return index
