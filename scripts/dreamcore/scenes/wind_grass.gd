extends RefCounted
## Shared fine-leaf mesh/palettes and legacy sparse-verge implementation.
## Dense meadow scenes delegate to stable additive 8m batches in wind_meadow.gd.
## No foliage physics bodies, per-frame scripts or horizon grass copies.
const Meadow=preload("res://scripts/dreamcore/scenes/wind_meadow.gd")
const MAX_PER_BATCH := 1200
const BATCH_SIZE := 16.0
static var blade_mesh: ArrayMesh
static var materials: Dictionary = {}

static func material(style: String) -> ShaderMaterial:
	if materials.has(style): return materials[style]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/dreamcore/outdoor/wind_grass.gdshader")
	m.resource_name = "wind_grass_" + style
	if style == "courtyard":
		m.set_shader_parameter("root_color", Color("354335"))
		m.set_shader_parameter("tip_color", Color("839274"))
	elif style == "verge":
		m.set_shader_parameter("root_color", Color("343b2e"))
		m.set_shader_parameter("tip_color", Color("929074"))
	materials[style] = m
	return m

static func mesh() -> ArrayMesh:
	if blade_mesh != null: return blade_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Sixteen fine articulated leaves; every blade tapers through a bent
	# midpoint. Millimetre-scale widths avoid the old flat paper-shard look.
	for i in range(16):
		var angle := float(i) * 2.399963
		var side := Vector3(cos(angle), 0, sin(angle))
		var bend := Vector3(-sin(angle), 0, cos(angle))
		var base := bend * (.055 + float(i % 6) * .018)
		var h := .66 + float(i % 6) * .068
		var half_width := .0048 * (.9 + float(i % 6) * .02)
		var mid := base + Vector3.UP * .48 * h + bend * (.018 + float(i % 4) * .003)
		var tip := base + Vector3.UP * h + bend * (.045 + float(i % 5) * .006) + side * sin(angle) * .008
		var points: Array[Vector3] = [base-side*half_width,base+side*half_width,
			mid-side*half_width*.62,mid+side*half_width*.62,tip]
		var uv := [Vector2(0,0),Vector2(1,0),Vector2(0,.48),Vector2(1,.48),Vector2(.5,1)]
		# Godot clockwise upper fronts. The horizontal normal points to the
		# same hemisphere as the blade face; upward bias softens thin foliage.
		for index in [0,1,2,1,3,2,2,3,4]:
			st.set_uv(uv[index]);st.set_normal((Vector3.UP*.65-bend*.35).normalized())
			st.add_vertex(points[index])
	st.index() # Shared bend vertices: identical positions/normals/UVs, same triangles.
	blade_mesh = st.commit()
	return blade_mesh

static func allowed(point: Vector3, config: Dictionary) -> bool:
	# Only finite reachable ground; leave room for wind displacement at edges.
	if absf(point.x) > 141.6 or absf(point.z) > 141.6: return false
	for exclusion: Rect2 in config.exclusions:
		if exclusion.grow(.24).has_point(Vector2(point.x, point.z)): return false
	return true

static func density_at(point: Vector3, config: Dictionary) -> float:
	var density: float = config.density
	for patch: Dictionary in config.get("density_patches", []):
		var rect: Rect2 = patch.rect
		var relative := (Vector2(point.x, point.z) - rect.get_center()) / (rect.size * .5)
		var falloff := 1.0 - smoothstep(.2, 1.0, relative.length())
		density = maxf(density, float(config.density) + float(patch.boost) * falloff)
	return density

static func tint_ground(root:Node3D)->void:
	Meadow.tint_ground(root)

static func build(root: Node3D, coord: Vector2i, config: Dictionary) -> void:
	if root.get_meta("export_skip_grass",false):return # offline shell pass only
	if config.get("meadow",false):
		Meadow.tint_ground(root)
		Meadow.build(root,coord,config,mesh(),material(config.style))
		return
	var origin := Vector3(coord.x * 32.0, 0, coord.y * 32.0)
	for iz in range(2):
		for ix in range(2):
			var cell := Rect2(origin.x - 16.0 + ix * BATCH_SIZE, origin.z - 16.0 + iz * BATCH_SIZE, BATCH_SIZE, BATCH_SIZE)
			var rng := RandomNumberGenerator.new()
			rng.seed = 4527 + (coord.x + 4) * 92821 + (coord.y + 4) * 68917 + ix * 179 + iz * 389
			var transforms: Array[Transform3D] = []
			var colors: Array[Color] = []
			# Sample clipped dry surfaces directly, not the entire chunk. Narrow
			# verge strips therefore remain populated without wasting attempts.
			for patch: AABB in config.patches:
				var rect := Rect2(patch.position.x + .24, patch.position.z + .24, patch.size.x - .48, patch.size.z - .48).intersection(cell)
				if not rect.has_area(): continue
				var sampling_density: float = config.density
				for density_patch: Dictionary in config.get("density_patches", []):
					if rect.intersects(density_patch.rect):sampling_density = maxf(sampling_density, float(config.density) + float(density_patch.boost))
				var attempts := mini(MAX_PER_BATCH * 2, ceili(rect.get_area() * sampling_density))
				for _i in range(attempts):
					if transforms.size() >= MAX_PER_BATCH: break
					var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), patch.end.y + .001, rng.randf_range(rect.position.y, rect.end.y))
					if not allowed(p, config): continue
					# Broad irregular patches, not uniform planting rows.
					var fullness := .72 + .20 * sin(p.x * .19 + sin(p.z * .13) * 2.0) * sin(p.z * .27)
					if rng.randf() > fullness * density_at(p, config) / sampling_density: continue
					var height := rng.randf_range(config.height.x, config.height.y)
					var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(.75,1.3), height, rng.randf_range(.75,1.3)))
					transforms.append(Transform3D(basis, p - origin))
					colors.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
			if transforms.is_empty(): continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh()
			mm.instance_count = transforms.size()
			for i in range(transforms.size()):
				mm.set_instance_transform(i, transforms[i]); mm.set_instance_custom_data(i, colors[i])
			var node := MultiMeshInstance3D.new()
			node.name = "WindGrass_%d_%d" % [ix, iz]
			node.multimesh = mm
			node.material_override = material(config.style)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = 98.0
			# Shader smoothly shrinks blades into their matching turf before cull.
			node.custom_aabb = AABB(Vector3(cell.position.x - origin.x - .9, .3, cell.position.y - origin.z - .9), Vector3(17.8, 1.0, 17.8))
			if config.get("audit", false):
				node.set_meta("authored_transforms", transforms)
				node.set_meta("authored_custom_data", colors)
			root.add_child(node)
