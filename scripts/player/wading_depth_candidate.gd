extends RefCounted
## Optional authored movement response, NOT a change to the source water solver.
## Call only from the existing in-water speed branch, with stable terrain depth.
## Deep-water eligibility bypasses this curve, even during a swim jump.
## Values are gameplay tuning, not measured human hydrodynamics.
const KNEE_DEPTH_M: float = 0.40
const WAIST_DEPTH_M: float = 1.05
const WAIST_WALK_MPS: float = 1.00
const WAIST_SPRINT_MPS: float = 1.65

static func speed(terrain_depth: float, sprinting: bool, deep_water: bool,
		legacy_wade: float = 1.25, legacy_wade_sprint: float = 2.2) -> float:
	var legacy: float = legacy_wade_sprint if sprinting else legacy_wade
	# Zero/invalid samples cannot accelerate a wet player toward the dry speed.
	# The caller owns the original dry/wet and genuine swimming decisions.
	if deep_water or not is_finite(terrain_depth) or terrain_depth <= KNEE_DEPTH_M:
		return legacy
	var waist: float = WAIST_SPRINT_MPS if sprinting else WAIST_WALK_MPS
	# Never increase a custom controller's lower legacy water speed.
	waist = minf(legacy, waist)
	return lerpf(legacy, waist, smoothstep(KNEE_DEPTH_M, WAIST_DEPTH_M, terrain_depth))
