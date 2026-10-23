extends RefCounted
## Integrated, reversible supported-wading pace policy, NOT a water-solver edit.
## Retain the exact original 0.525 m step and 1.05 m Wade cycle. Merely making
## that cycle longer was rejected: the existing clip then skates 24-28 cm.
## Call after the original speed/depth calculation, before intent acceleration.
## The controller still owns collision, distance phase and water-state decisions.
const ANKLE_DEPTH_M: float = 0.15
const KNEE_DEPTH_M: float = 0.50
const SUPPORTED_SPRINT_CAP_MPS: float = 1.75
const SOFT_CEILING_BAND_MPS: float = 0.04

static func supported_speed(original_speed: float, sprinting: bool,
		in_water: bool, grounded: bool, deep_water: bool, swimming: bool,
		terrain_depth: float, legacy_sprint_speed: float = 2.2) -> float:
	if not is_finite(original_speed) or original_speed < 0.0:
		return original_speed
	if not sprinting or not in_water or not grounded or deep_water or swimming:
		return original_speed
	if not is_finite(terrain_depth) or terrain_depth <= ANKLE_DEPTH_M:
		return original_speed
	# Ankle depth keeps prior agency. The 0.15-0.50 m band is gameplay tuning
	# guided by this rig's 0.115 m ankle and 0.500 m knee, not fluid physics.
	var ceiling: float = lerpf(legacy_sprint_speed + SOFT_CEILING_BAND_MPS,
		SUPPORTED_SPRINT_CAP_MPS, smoothstep(ANKLE_DEPTH_M, KNEE_DEPTH_M, terrain_depth))
	# C1 polynomial soft minimum is monotone in both arguments and never
	# accelerates the original response. Starting one band ABOVE legacy speed
	# preserves the ankle edge exactly. Deep-supported sprint is also exact
	# once its original target is at least one band below the 1.75 m/s ceiling.
	var h: float = clampf(0.5 + 0.5 * (ceiling - original_speed) / SOFT_CEILING_BAND_MPS, 0.0, 1.0)
	return lerpf(ceiling, original_speed, h) - SOFT_CEILING_BAND_MPS * h * (1.0 - h)
