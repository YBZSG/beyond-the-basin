class_name PoolWaterField
extends RefCounted
## Native, connected finite-volume shallow-water field. Inspired by the source
## C-grid solver, but deliberately CPU bounded rather than a WebGL pass port.
## Each tile has a one-cell halo. All velocity passes finish before height
## passes, so room iteration order cannot cause water to flow across a seam twice.

const ROOM_SIZE: float = 32.0
const LEVEL: float = 0.32
const FLOOR: float = -0.78
const STEP: float = 1.0 / 60.0
const GRAVITY: float = 9.81
const MAX_HEIGHT: float = 0.24
const MAX_FLOW: float = 1.8

class Tile extends RefCounted:
	var coord: Vector2i
	var n: int
	var stride: int
	var height: PackedFloat32Array
	var next_height: PackedFloat32Array
	var flow_x: PackedFloat32Array
	var flow_z: PackedFloat32Array
	var next_x: PackedFloat32Array
	var next_z: PackedFloat32Array
	var depth: PackedFloat32Array
	var foam: PackedFloat32Array
	var texture: ImageTexture
	var image: Image
	var energy: float = 0.0
	var awake: float = 0.0
	var layout: Dictionary

var tiles: Dictionary = {}
var resolution: int = 32
var _accumulator: float = 0.0
var _upload_elapsed: float = 0.0
var step_count: int = 0

func add_room(coord: Vector2i, layout: Dictionary) -> ImageTexture:
	if tiles.has(coord):
		return (tiles[coord] as Tile).texture
	var tile := Tile.new()
	tile.coord = coord
	tile.n = resolution
	tile.stride = resolution + 2
	tile.layout = layout.duplicate(false)
	if not tile.layout.has("water_steps"):
		var steps: Array[AABB] = []
		for solid in layout.get("solids", []):
			if solid is AABB and solid.end.y < LEVEL and solid.end.y > FLOOR and solid.position.y < LEVEL:
				steps.append(solid)
		tile.layout["water_steps"] = steps
	var count: int = tile.stride * tile.stride
	for field in ["height", "next_height", "flow_x", "flow_z", "next_x", "next_z", "depth", "foam"]:
		var values := PackedFloat32Array()
		values.resize(count)
		values.fill(0.0)
		tile.set(field, values)
	var cell: float = ROOM_SIZE / float(tile.n)
	for z in range(1, tile.n + 1):
		for x in range(1, tile.n + 1):
			var p := Vector2((float(x) - 0.5) * cell - 16.0, (float(z) - 0.5) * cell - 16.0)
			tile.depth[z * tile.stride + x] = _rest_depth(p, tile.layout)
	tile.image = Image.create(tile.stride, tile.stride, false, Image.FORMAT_RGBAF)
	tile.image.fill(Color(0.0, 0.0, 0.0, 0.0))
	tile.texture = ImageTexture.create_from_image(tile.image)
	tiles[coord] = tile
	_sync_halos(false)
	return tile.texture

func remove_room(coord: Vector2i) -> void:
	tiles.erase(coord)

func clear() -> void:
	tiles.clear()
	_accumulator = 0.0

func _rest_depth(p: Vector2, layout: Dictionary) -> float:
	var floor_y: float = float(layout.get("water_floor_y", FLOOR))
	if layout.get("water_enabled", true) == false:
		return 0.0
	var rects: Array = layout.get("water_rects", [])
	if not rects.is_empty():
		var inside := false
		for value in rects:
			if value is Rect2 and value.has_point(p):
				inside = true
		if not inside:
			return 0.0
	for value in layout.get("water_exclusions", []):
		if value is Rect2 and value.has_point(p):
			return 0.0
		if value is AABB and value.position.y <= LEVEL and value.end.y >= LEVEL:
			if Rect2(Vector2(value.position.x, value.position.z), Vector2(value.size.x, value.size.z)).has_point(p):
				return 0.0
	for value in layout.get("water_steps", []):
		if value is AABB and Rect2(Vector2(value.position.x, value.position.z), Vector2(value.size.x, value.size.z)).has_point(p):
			floor_y = maxf(floor_y, value.end.y)
	return maxf(0.0, LEVEL - floor_y)

func _edge_open(tile: Tile, cell: int, direction: Vector2i) -> bool:
	var span: float = (float(cell) - 0.5) * ROOM_SIZE / float(tile.n) - 16.0
	var width: float = float(tile.layout.get("water_door_width", 8.0))
	var closed: Array = tile.layout.get("water_closed_edges", [])
	if direction in closed:
		return false
	return absf(span) < width * 0.5

func _sync_halos(next_velocity: bool) -> void:
	for tile_value in tiles.values():
		var tile: Tile = tile_value
		for side in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Tile = tiles.get(tile.coord + side)
			for c in range(1, tile.n + 1):
				var dst: int
				var src: int
				var centre: int
				if side == Vector2i.LEFT:
					dst = c * tile.stride
					src = c * tile.stride + tile.n
					centre = dst + 1
				elif side == Vector2i.RIGHT:
					dst = c * tile.stride + tile.n + 1
					src = c * tile.stride + 1
					centre = dst - 1
				elif side == Vector2i.UP:
					dst = c
					src = tile.n * tile.stride + c
					centre = dst + tile.stride
				else:
					dst = (tile.n + 1) * tile.stride + c
					src = tile.stride + c
					centre = dst - tile.stride
				var open: bool = other != null and _edge_open(tile, c, side) and _edge_open(other, c, -side)
				if open:
					tile.depth[dst] = other.depth[src]
					if next_velocity:
						tile.next_x[dst] = other.next_x[src]
						tile.next_z[dst] = other.next_z[src]
					else:
						tile.height[dst] = other.height[src]
						tile.flow_x[dst] = other.flow_x[src]
						tile.flow_z[dst] = other.flow_z[src]
						tile.foam[dst] = other.foam[src]
				else:
					tile.depth[dst] = 0.0
					tile.height[dst] = tile.height[centre]
					tile.next_x[dst] = 0.0
					tile.next_z[dst] = 0.0
					tile.flow_x[dst] = 0.0
					tile.flow_z[dst] = 0.0

func advance(delta: float) -> void:
	_accumulator += clampf(delta, 0.0, 0.10)
	_upload_elapsed += delta
	var steps := 0
	while _accumulator >= STEP and steps < 6:
		_step(STEP)
		_accumulator -= STEP
		steps += 1
	if _upload_elapsed >= 1.0 / 30.0:
		_sync_halos(false)
		for value in tiles.values():
			var tile: Tile = value
			if tile.awake > 0.0:
				_upload(tile)
		_upload_elapsed = 0.0

func _step(dt: float) -> void:
	var active := false
	for value in tiles.values():
		var tile: Tile = value
		if tile.awake > 0.0:
			active = true
	if not active:
		return
	_sync_halos(false)
	var dx: float = ROOM_SIZE / float(resolution)
	var inv_dx: float = 1.0 / dx
	var damp: float = exp(-0.48 * dt)
	for value in tiles.values():
		var tile: Tile = value
		var s: int = tile.stride
		# Neighbours are woken together by impact(), preventing inactive seams.
		if tile.awake <= 0.0:
			continue
		for z in range(1, tile.n + 1):
			for x in range(1, tile.n + 1):
				var i: int = z * s + x
				if tile.depth[i] <= 0.0:
					continue
				tile.next_x[i] = clampf((tile.flow_x[i] - GRAVITY * dt * (tile.height[i] - tile.height[i - 1]) * inv_dx) * damp, -MAX_FLOW, MAX_FLOW) if tile.depth[i - 1] > 0.0 else 0.0
				tile.next_z[i] = clampf((tile.flow_z[i] - GRAVITY * dt * (tile.height[i] - tile.height[i - s]) * inv_dx) * damp, -MAX_FLOW, MAX_FLOW) if tile.depth[i - s] > 0.0 else 0.0
	_sync_halos(true)
	for value in tiles.values():
		var tile: Tile = value
		if tile.awake <= 0.0:
			continue
		var s: int = tile.stride
		var energy := 0.0
		for z in range(1, tile.n + 1):
			for x in range(1, tile.n + 1):
				var i: int = z * s + x
				var d: float = tile.depth[i]
				if d <= 0.0:
					continue
				var west: float = minf(d, tile.depth[i - 1]) * tile.next_x[i]
				var east: float = minf(d, tile.depth[i + 1]) * tile.next_x[i + 1]
				var south: float = minf(d, tile.depth[i - s]) * tile.next_z[i]
				var north: float = minf(d, tile.depth[i + s]) * tile.next_z[i + s]
				var divergence: float = (east - west + north - south) * inv_dx
				var h: float = clampf(tile.height[i] - dt * divergence, -minf(d * 0.40, MAX_HEIGHT), minf(d * 0.40, MAX_HEIGHT))
				tile.next_height[i] = h
				var speed: float = Vector2(tile.next_x[i], tile.next_z[i]).length()
				tile.foam[i] = clampf(tile.foam[i] * exp(-dt * 1.3) + maxf(0.0, h - 0.035) * maxf(0.0, speed - 0.18) * dt * 1.2, 0.0, 0.65)
				energy += absf(h) + speed * 0.1
		tile.energy = energy
		tile.awake = maxf(0.0, tile.awake - dt)
		var old_h := tile.height
		tile.height = tile.next_height
		tile.next_height = old_h
		var old_x := tile.flow_x
		tile.flow_x = tile.next_x
		tile.next_x = old_x
		var old_z := tile.flow_z
		tile.flow_z = tile.next_z
		tile.next_z = old_z
	step_count += 1

func _upload(tile: Tile) -> void:
	var pixels := PackedFloat32Array()
	pixels.resize(tile.stride * tile.stride * 4)
	for i in range(tile.stride * tile.stride):
		pixels[i * 4] = tile.height[i]
		pixels[i * 4 + 1] = tile.flow_x[i]
		pixels[i * 4 + 2] = tile.flow_z[i]
		pixels[i * 4 + 3] = tile.foam[i]
	tile.image.set_data(tile.stride, tile.stride, false, Image.FORMAT_RGBAF, pixels.to_byte_array())
	tile.texture.update(tile.image)

func impact(p: Vector2, power: float) -> void:
	var coord := room_coord(p)
	if not tiles.has(coord):
		return
	# The impact footprint can cross a doorway. Stimulate both tiles, not just
	# the room containing its centre. Raised architecture is excluded by depth.
	for value in tiles.values():
		var tile: Tile = value
		if tile.coord.distance_to(coord) <= 2.9:
			tile.awake = 24.0
		var local: Vector2 = p - Vector2(tile.coord) * ROOM_SIZE
		if absf(local.x) > 18.0 or absf(local.y) > 18.0:
			continue
		var dx: float = ROOM_SIZE / float(tile.n)
		var cx: int = clampi(int((local.x + 16.0) / dx) + 1, 1, tile.n)
		var cz: int = clampi(int((local.y + 16.0) / dx) + 1, 1, tile.n)
		for z in range(maxi(1, cz - 2), mini(tile.n + 1, cz + 3)):
			for x in range(maxi(1, cx - 2), mini(tile.n + 1, cx + 3)):
				var i: int = z * tile.stride + x
				if tile.depth[i] <= 0.0:
					continue
				var offset := Vector2((float(x) - 0.5) * dx - 16.0, (float(z) - 0.5) * dx - 16.0) - local
				var r2: float = offset.length_squared() / maxf(0.24, dx * dx * 1.2)
				# A Mexican-hat pressure source approximately conserves volume.
				var impulse: float = (1.0 - r2) * exp(-r2) * power * 0.065
				tile.height[i] = clampf(tile.height[i] + impulse, -MAX_HEIGHT, MAX_HEIGHT)
				tile.foam[i] = minf(0.55, tile.foam[i] + exp(-r2 * 1.8) * maxf(0.0, power - 0.35) * 0.16)

static func room_coord(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x + 16.0) / ROOM_SIZE), floori((p.y + 16.0) / ROOM_SIZE))

func sample(p: Vector2) -> Vector4:
	var coord := room_coord(p)
	var tile: Tile = tiles.get(coord)
	if tile == null:
		return Vector4.ZERO
	var q: Vector2 = (p - Vector2(coord) * ROOM_SIZE + Vector2(16.0, 16.0)) / ROOM_SIZE * float(tile.n) + Vector2(0.5, 0.5)
	var x: int = clampi(floori(q.x), 0, tile.n)
	var z: int = clampi(floori(q.y), 0, tile.n)
	var f := Vector2(q.x - float(x), q.y - float(z)).clamp(Vector2.ZERO, Vector2.ONE)
	var result := Vector4.ZERO
	for dz in range(2):
		for dx in range(2):
			var i: int = (z + dz) * tile.stride + x + dx
			var w: float = (f.x if dx == 1 else 1.0 - f.x) * (f.y if dz == 1 else 1.0 - f.y)
			result += Vector4(tile.height[i], tile.flow_x[i], tile.flow_z[i], tile.foam[i]) * w
	return result

func depth_at(p: Vector2) -> float:
	var coord := room_coord(p)
	var tile: Tile = tiles.get(coord)
	if tile == null:
		return 0.0
	return _rest_depth(p - Vector2(coord) * ROOM_SIZE, tile.layout)

func wake(p: Vector2, velocity: Vector2, power: float) -> void:
	impact(p, minf(0.16, power))
	var tile: Tile = tiles.get(room_coord(p))
	if tile == null:
		return
	var local: Vector2 = p - Vector2(tile.coord) * ROOM_SIZE
	var dx: float = ROOM_SIZE / float(tile.n)
	var cx: int = clampi(int((local.x + 16.0) / dx) + 1, 1, tile.n)
	var cz: int = clampi(int((local.y + 16.0) / dx) + 1, 1, tile.n)
	var gain: float = clampf(power * 0.4, 0.0, 0.12)
	for z in range(maxi(1, cz - 1), mini(tile.n + 1, cz + 2)):
		for x in range(maxi(1, cx - 1), mini(tile.n + 1, cx + 2)):
			var i: int = z * tile.stride + x
			if tile.depth[i] > 0.0:
				var weight: float = 1.0 / float(1 + abs(x - cx) + abs(z - cz))
				tile.flow_x[i] = clampf(tile.flow_x[i] + velocity.x * gain * weight, -MAX_FLOW, MAX_FLOW)
				tile.flow_z[i] = clampf(tile.flow_z[i] + velocity.y * gain * weight, -MAX_FLOW, MAX_FLOW)
