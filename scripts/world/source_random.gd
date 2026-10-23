class_name PoolSourceRandom
extends RefCounted
## Bit-exact port of world.ts randomFor, including Javascript's uint32 operations.
var state: int

func _init(x: int = 0, z: int = 0, seed_value: int = 0) -> void:
	state = (imul(x, 73856093) ^ imul(z, 19349663) ^ seed_value) & 0xffffffff

static func imul(a: int, b: int) -> int:
	# Split into 16-bit products to avoid signed int64 overflow at full uint32 range.
	var al: int = a & 0xffff
	var bl: int = b & 0xffff
	return (al * bl + ((((a >> 16) & 0xffff) * bl + al * ((b >> 16) & 0xffff)) << 16)) & 0xffffffff

func next() -> float:
	state = (state + 0x6d2b79f5) & 0xffffffff
	var t: int = imul(state ^ (state >> 15), 1 | state)
	t = (t ^ ((t + imul(t ^ (t >> 7), 61 | t)) & 0xffffffff)) & 0xffffffff
	return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0
