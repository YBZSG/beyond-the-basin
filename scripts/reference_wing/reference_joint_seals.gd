extends RefCounted
## Close the backs of bevelled, butt-jointed solids. Never span a portal or
## alter the authored collision/UVs. One merged mesh per room, no extra lights.
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const BackingShader = preload("res://shaders/reference_wing/reference_joint_backing.gdshader")

static func build(proxies: Array) -> MeshInstance3D:
	var boxes: Array[AABB] = []
	var names: Array[String] = []
	for proxy: Dictionary in proxies:
		if str(proxy.type) != "BOX": continue
		var axes: Array = proxy.get("basis", [[1,0,0],[0,1,0],[0,0,1]])
		if not Basis(Catalog.vec3(axes[0]), Catalog.vec3(axes[1]), Catalog.vec3(axes[2])).is_equal_approx(Basis.IDENTITY): continue
		var size := Catalog.vec3(proxy.size)
		boxes.append(AABB(Catalog.vec3(proxy.center) - size * 0.5, size))
		names.append(str(proxy.get("source_object", "")).to_lower())
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var count := 0
	for i in boxes.size():
		var a := boxes[i]
		for j in range(i + 1, boxes.size()):
			var b := boxes[j]
			for axis in 3:
				var plane: float
				if absf(a.end[axis] - b.position[axis]) < 0.001:
					plane = (a.end[axis] + b.position[axis]) * 0.5
				elif absf(b.end[axis] - a.position[axis]) < 0.001:
					plane = (b.end[axis] + a.position[axis]) * 0.5
				else: continue
				var lo := a.position.max(b.position)
				var hi := a.end.min(b.end)
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				if hi[u] - lo[u] < -0.001 or hi[v] - lo[v] < -0.001: continue
				if maxf(hi[u] - lo[u], hi[v] - lo[v]) < 0.02: continue
				# Some authored L corners meet along an EDGE, with no volume
				# overlap at all. Seal that diagonal hole too, only once per pair.
				if (hi[u] - lo[u] < 0.001 and u < axis) or (hi[v] - lo[v] < 0.001 and v < axis): continue
				# Recess the backing; a 2 mm mortar overlap at wall/ceiling
				# junctions also covers secondary-ray origin offsets in native RT.
				# The original 4 mm bevel remains on exposed, non-contact edges.
				var roof_wall := (("roof" in names[i] or "ceiling" in names[i]) and "wall" in names[j]) or (("roof" in names[j] or "ceiling" in names[j]) and "wall" in names[i])
				var inset := -0.002 if roof_wall else 0.0001
				for lateral in [u, v]:
					if hi[lateral] - lo[lateral] < 0.001:
						var edge := (hi[lateral] + lo[lateral]) * 0.5
						lo[lateral] = edge - 0.008; hi[lateral] = edge + 0.008
					else:
						lo[lateral] += inset; hi[lateral] -= inset
				lo[axis] = plane - 0.008; hi[axis] = plane + 0.008
				surface.append_from(cube, 0, Transform3D(Basis.from_scale(hi - lo), (hi + lo) * 0.5))
				count += 1
	if count == 0: return null
	var grout := ShaderMaterial.new()
	grout.resource_name = "ReferenceStructuralJointBacking"
	grout.shader = BackingShader
	surface.set_material(grout)
	var result := MeshInstance3D.new()
	result.name = "ReferenceJointBacking"
	result.mesh = surface.commit()
	result.layers = 1
	result.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	result.set_meta("joint_count", count)
	return result
