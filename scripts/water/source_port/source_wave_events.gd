class_name SourceWaveEvents
extends RefCounted
## Source-only event bridge from poolcore@66a4543602d9e774db07c2da12ce1d40d522532c:
## InteractiveWater.crestSpray (water-system.ts:422-457), render's environmental
## detail injection (lines541-545), and engine.ts:989 call order. No new splashes.
## All positions are local to the solver's96m domain, including camera focus.

const SOURCE_COMMIT := "66a4543602d9e774db07c2da12ce1d40d522532c"
const PHYS := 384
const PHYS_CELL := 0.25
const HALF := 48.0
const DEFAULT_SETTINGS := {"quality": "High", "simulation": true, "foam": true, "foamStrength": 1.0, "spray": 1.0, "environmentalStrength": 0.08}
const QUALITIES := ["Low", "Medium", "High", "Ultra"]

var crest_clock := 0.0
var crest_scan := 0
var crest_patches := 0
var last_environment := 0.0
var environment_injections := 0
var _solver: SourceWaveSolver
var _settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var _random_source := Callable()

func configure(solver: SourceWaveSolver, settings: Dictionary = {}, random_source: Callable = Callable()) -> void:
	_solver = solver
	_settings = DEFAULT_SETTINGS.duplicate()
	apply_settings(settings)
	_random_source = random_source

## Retain the event clocks and rotating scan when quality replaces the solver,
## matching original InteractiveWater retaining these fields across updateQuality.
func set_solver(solver: SourceWaveSolver) -> void:
	_solver = solver

## Relevant subset of the original sanitizeWaterSettings, retaining original keys.
func apply_settings(values: Dictionary) -> void:
	for name in ["simulation", "foam"]:
		if values.has(name) and values[name] is bool:
			_settings[name] = values[name]
	if values.has("quality") and QUALITIES.has(values.quality):
		_settings.quality = values.quality
	for name in ["foamStrength", "spray", "environmentalStrength"]:
		if values.has(name) and (values[name] is float or values[name] is int) and is_finite(float(values[name])):
			_settings[name] = clampf(float(values[name]), 0.0, 1.0 if name == "environmentalStrength" else 2.0)

func snapshot() -> Dictionary:
	return _settings.duplicate()

func _random() -> float:
	return float(_random_source.call()) if _random_source.is_valid() else randf()

## Original Math.hypot uses JS doubles. Do not route through Godot Vector2.length,
## whose real_t components are float32 in the standard build.
static func crest_power(eta: float, u: float, v: float, divergence: float, depth: float, gravity: float, curvature: float = 1.0) -> float:
	for value in [eta, u, v, divergence, depth, gravity, curvature]:
		if not is_finite(float(value)):
			return 0.0
	if depth <= 0.0 or gravity <= 0.0 or eta < 0.015:
		return 0.0
	var speed := sqrt(u * u + v * v)
	var critical := sqrt(gravity * maxf(depth, 0.05))
	var energy := smoothstep(0.16, 1.44, speed * speed)
	var trapped := smoothstep(1.8, 4.0, -divergence)
	var crest := smoothstep(0.65, 1.25, speed / critical) * smoothstep(0.08, 0.8, curvature)
	return energy * maxf(trapped, crest) * smoothstep(0.015, 0.045, eta)

## Original caller: crest_spray(min(dt,.05)*whitewater_rate, callback, camera_xz).
## Callback(x,z,power,foam). engine.ts forwards power and local flow to
## liquid.crest, ignoring the fourth foam argument; do not invent extra foam.
## Run before liquid.frame, particle update, and solver.step for original order.
func crest_spray(dt: float, emit: Callable, focus: Vector2 = Vector2.ZERO) -> int:
	if _solver == null:
		return 0
	var foam_on: bool = bool(_settings.foam) and float(_settings.foamStrength) > 0.0
	if _settings.quality == "Low" or not _settings.simulation or (not foam_on and float(_settings.spray) <= 0.0) or _solver.settled or _solver.peak < 0.008:
		crest_clock = 0.0
		return 0
	if not is_finite(dt) or dt <= 0.0:
		return 0
	crest_clock += minf(dt, 0.05)
	if crest_clock < 1.0 / 30.0:
		return 0
	var elapsed := minf(crest_clock, 0.1)
	crest_clock = 0.0
	# Production tiers all use the original384² readback. Tiny numerical solver
	# test grids cannot support a64x64 neighboring-cell scan and are not emitters.
	if _solver.physics_size != PHYS or _solver.physics_eta.size() != PHYS * PHYS:
		return 0
	var x0 := clampi(floori((focus.x - 8.0 + HALF) / PHYS_CELL), 1, PHYS - 65)
	var z0 := clampi(floori((focus.y - 8.0 + HALF) / PHYS_CELL), 1, PHYS - 65)
	var eta := _solver.physics_eta
	var cell2 := PHYS_CELL * PHYS_CELL
	var offset := (crest_scan * 1597) % 4096
	crest_scan += 1
	var emitted := 0
	for j in 4096:
		if emitted >= 12:
			break
		var k := (j + offset) % 4096
		var ix := x0 + k % 64
		var iz := z0 + int(k / 64)
		var i := ix + iz * PHYS
		var h := eta[i]
		var w := eta[i - 1]
		var e := eta[i + 1]
		var b := eta[i - PHYS]
		var n := eta[i + PHYS]
		if h < 0.008:
			continue
		var cx := (2.0 * h - w - e) / cell2
		var cz := (2.0 * h - b - n) / cell2
		var along_x := cx >= cz
		var a := w if along_x else b
		var c := e if along_x else n
		if h < a or h < c or maxf(cx, cz) <= 0.035:
			continue
		var curvature := cx + cz
		var u := _solver.physics_u[i]
		var v := _solver.physics_v[i]
		var foam := SourceWaveSolver.crest_foam_power(h, u, v, curvature) if foam_on else 0.0
		var divergence := (_solver.physics_u[i + 1] - _solver.physics_u[i - 1] + _solver.physics_v[i + PHYS] - _solver.physics_v[i - PHYS]) / (2.0 * PHYS_CELL)
		var center_x := -HALF + (ix + 0.5) * PHYS_CELL
		var center_z := -HALF + (iz + 0.5) * PHYS_CELL
		var power := crest_power(h, u, v, divergence, _solver.depth_at(center_x, center_z), 9.81 * _solver.wave_speed, curvature) * float(_settings.spray)
		var rate := maxf(foam, power) * 12.0
		if rate <= 0.0 or _random() > 1.0 - exp(-rate * elapsed):
			continue
		var ridge := clampf(0.5 * (a - c) / (a - 2.0 * h + c), -0.5, 0.5) * PHYS_CELL
		var tangent := (_random() - 0.5) * PHYS_CELL
		var x := center_x + (ridge if along_x else tangent)
		var z := center_z + (tangent if along_x else ridge)
		if _solver.is_land(x, z):
			continue
		if emit.is_valid():
			emit.call(x, z, power, foam)
		emitted += 1
		crest_patches += 1
	return emitted

## This code lives inside original render(), not a separate environmentalDrips
## function. It queues only the detail solver, never SWE impact or MPM particles.
## Supply absolute render time. Run immediately before solver.step(delta).
## Optional callback(x,z,amplitude,radius) is a test/integration seam replacing
## queue_detail_impact, not an additional emission path.
func environmental_drips(time: float, emit_detail: Callable = Callable()) -> bool:
	if _solver == null:
		return false
	if time - last_environment > 2.7 and float(_settings.environmentalStrength) > 0.0:
		last_environment = time
		var x := sin(time * 1.71) * 12.0
		var z := sin(time * 2.39) * 12.0
		if not _solver.is_land(x, z):
			var amplitude := 0.0003 * float(_settings.environmentalStrength)
			if emit_detail.is_valid():
				emit_detail.call(x, z, amplitude, 0.12)
			else:
				_solver.queue_detail_impact(x, z, amplitude, 0.12)
			environment_injections += 1
			return true
	return false

func debug() -> Dictionary:
	return {"crest_clock": crest_clock, "crest_scan": crest_scan, "crest_patches": crest_patches, "last_environment": last_environment, "environment_injections": environment_injections}
