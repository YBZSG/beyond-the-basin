class_name PoolSourceWFC
extends RefCounted
## Deterministic source wfc.ts AC-3 solver. Order of propagation and RNG draws matters.
const SIZE := 12
const CELL := 2.2
const BITS := [1, 2, 4]
const ALLOW := {1: 7, 2: 1, 4: 5}
const TILE := {1: "E", 2: "P", 4: "S"}

static func doorway_cells(size: int = SIZE) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var ring: Array[int] = [0, 1, size - 2, size - 1]
	for j in ring:
		for i in size:
			if absf((i - (size - 1) / 2.0) * CELL) <= 4.4: cells.append(Vector2i(i, j))
	for i in ring:
		for j in size:
			if absf((j - (size - 1) / 2.0) * CELL) <= 4.4: cells.append(Vector2i(i, j))
	return cells

static func collapse_interior(rng: RefCounted, size: int = SIZE, pillar_boost: float = 1.0) -> Array:
	for attempt in 8:
		var grid: Array = _solve(rng, size, pillar_boost)
		if not grid.is_empty(): return grid
	var empty: Array = []
	for y in size:
		var row: Array = []
		row.resize(size)
		row.fill("E")
		empty.append(row)
	return empty

static func _pop(m: int) -> int:
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1)

static func _propagate(domains: PackedInt32Array, from: int, size: int) -> bool:
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var allowed: int = 0
		for bit in BITS:
			if domains[i] & bit: allowed |= ALLOW[bit]
		var x: int = i % size
		var y: int = i / size
		var neighbours: Array[int] = []
		if x > 0: neighbours.append(i - 1)
		if x < size - 1: neighbours.append(i + 1)
		if y > 0: neighbours.append(i - size)
		if y < size - 1: neighbours.append(i + size)
		for nb in neighbours:
			var next_domain: int = domains[nb] & allowed
			if next_domain == domains[nb]: continue
			if next_domain == 0: return false
			domains[nb] = next_domain
			queue.append(nb)
	return true

static func _solve(rng: RefCounted, size: int, pillar_boost: float) -> Array:
	var n: int = size * size
	var domains := PackedInt32Array()
	domains.resize(n)
	domains.fill(7)
	var assigned := PackedInt32Array()
	assigned.resize(n)
	var weights := {1: 6.0, 2: pillar_boost, 4: 2.6}
	var doors := doorway_cells(size)
	for door in doors:
		var index: int = door.y * size + door.x
		domains[index] = 1
		assigned[index] = 1
		if not _propagate(domains, index, size): return []
	var remaining: int = n - doors.size()
	while remaining > 0:
		var best: int = 4
		var ties: Array[int] = []
		for i in n:
			if assigned[i]: continue
			var count: int = _pop(domains[i])
			if count < best:
				best = count
				ties.clear()
			if count == best: ties.append(i)
		if ties.is_empty(): return []
		var index: int = ties[int(floor(rng.next() * ties.size()))]
		var bit: int = domains[index]
		if _pop(bit) > 1:
			var total: float = 0.0
			for b in BITS:
				if bit & b: total += weights[b]
			var r: float = rng.next() * total
			bit = 0
			for b in BITS:
				if not (domains[index] & b): continue
				bit = b
				r -= weights[b]
				if r <= 0.0: break
		domains[index] = bit
		assigned[index] = bit
		if not _propagate(domains, index, size): return []
		remaining -= 1
	var grid: Array = []
	for y in size:
		var row: Array = []
		for x in size: row.append(TILE[assigned[y * size + x]])
		grid.append(row)
	return grid
