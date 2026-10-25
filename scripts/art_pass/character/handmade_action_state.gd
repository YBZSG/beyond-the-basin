extends RefCounted
## Physics-tick visual event ages. Never moves an object or delays its release.
const PICKUP_DURATION := 29.0 / 60.0
const SETDOWN_DURATION := 28.0 / 60.0
var epoch := -1
var held_id := 0
var pickup_age := 99.0
var setdown_age := 99.0
var clock := 0.0
var pickup_serial := 0
var setdown_serial := 0
var last_release_serial := 0
var enabled := true
var mode := "ground"
var throw_phase := "none"

func integrate(sample: Dictionary, delta: float, next_held_id: int) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var next_epoch := int(sample.get("epoch",0))
	if epoch != next_epoch:
		epoch=next_epoch;held_id=next_held_id;pickup_age=99.0;setdown_age=99.0
		last_release_serial=int(sample.get("throw_release_serial",0))
		return # A restore/warp with an object is not a fresh pickup.
	enabled=bool(sample.get("enabled",true))
	mode=str(sample.get("mode","ground"))
	throw_phase=str(sample.get("throw_phase","none"))
	if not enabled: return
	var release_serial := int(sample.get("throw_release_serial",0))
	var fresh_release := release_serial>last_release_serial
	last_release_serial=maxi(last_release_serial,release_serial)
	clock+=delta
	pickup_age=minf(99.0,pickup_age+delta)
	setdown_age=minf(99.0,setdown_age+delta)
	if next_held_id!=held_id:
		if next_held_id!=0:
			pickup_age=0.0;setdown_age=99.0;pickup_serial+=1
		elif held_id!=0:
			pickup_age=99.0
			# Only a drop, not a throw/cancel/warp. Throw remains original pipeline.
			if fresh_release and str(sample.get("release_kind","none"))=="drop" and float(sample.get("throw_release_age",-1.0))>=0.0:
				setdown_age=0.0;setdown_serial+=1
		held_id=next_held_id
	if throw_phase in ["charging","release","recover"]:
		pickup_age=99.0;setdown_age=99.0

func sample() -> Dictionary:
	var allowed := mode in ["ground","wade"] and throw_phase=="none"
	# Ease in, reach, then yield to the actual prop contact. Maximum 0.8 keeps
	# underlying motion alive. In-place rotation tracks cannot move the feet.
	var pickup := 0.8*smoothstep(0.0,0.10,pickup_age)*(1.0-smoothstep(0.28,PICKUP_DURATION,pickup_age)) if held_id!=0 and pickup_age<PICKUP_DURATION and allowed else 0.0
	var put_down := smoothstep(0.0,0.065,setdown_age)*(1.0-smoothstep(0.28,SETDOWN_DURATION,setdown_age)) if held_id==0 and setdown_age<SETDOWN_DURATION and allowed else 0.0
	return {"pickup_time":minf(pickup_age,PICKUP_DURATION),"pickup_weight":pickup,
		"setdown_time":minf(setdown_age,SETDOWN_DURATION),"setdown_weight":put_down,
		"pickup_serial":pickup_serial,"setdown_serial":setdown_serial,"clock":clock,
		"epoch":epoch,"physics_clock":true,"physical_release_delay":0.0}
