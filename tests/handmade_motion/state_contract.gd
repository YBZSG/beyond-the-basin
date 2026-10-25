extends SceneTree
const Actions=preload("res://scripts/art_pass/character/handmade_action_state.gd")
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: push_error(label);quit(1)
func _initialize()->void:
	var a=Actions.new()
	var s={"epoch":1,"enabled":true,"mode":"ground","throw_phase":"none","release_kind":"none"}
	a.integrate(s,1.0/60.0,0)
	a.integrate(s,1.0/60.0,123)
	check(a.pickup_serial==1,"pickup event")
	for i in 12:a.integrate(s,1.0/60.0,123)
	check(a.sample().pickup_weight>0.5,"authored pickup active")
	check(a.pickup_serial==1,"held object not repeated")
	var age=a.pickup_age;s.enabled=false
	for i in 20:a.integrate(s,.1,123)
	check(is_equal_approx(age,a.pickup_age),"pause freezes clock")
	s.enabled=true;s.throw_phase="charging";a.integrate(s,.016,123)
	check(a.sample().pickup_weight==0,"throw priority")
	s.throw_phase="release";s.release_kind="throw";a.integrate(s,.016,0)
	check(a.setdown_serial==0,"throw not a drop")
	s.throw_phase="none";s.release_kind="none";a.integrate(s,.016,456)
	s.release_kind="drop";s.throw_release_serial=1;s.throw_release_age=0.0;a.integrate(s,.016,0)
	check(a.setdown_serial==1,"drop event")
	a.integrate(s,.12,0);check(a.sample().setdown_weight>.9,"drop authored")
	# Old drop metadata must not fabricate an action when a later prop disappears.
	a.integrate(s,.016,456);a.integrate(s,.016,0)
	check(a.setdown_serial==1,"freed prop ignores stale drop metadata")
	s.epoch=2;a.integrate(s,.016,789)
	check(a.sample().pickup_weight==0 and a.sample().setdown_weight==0,"warp never ghost event")
	check(a.sample().physical_release_delay==0,"no physical release delay")
	# Real controller pause increments epoch, intentionally cancelling gestures.
	s.epoch=3;s.enabled=false;a.integrate(s,.016,789)
	check(a.sample().pickup_weight==0 and a.sample().setdown_weight==0,"real pause epoch cancels gesture")
	s.enabled=true
	# Same physical timeline sampled with coarse/fine dt: event times are elapsed
	# physics time, never one frame per rendered frame or clipped to100ms.
	for hz in [5,15,30,60,120]:
		var b=Actions.new();s.epoch=1;s.mode="wade";s.release_kind="none"
		b.integrate(s,1.0/hz,0);b.integrate(s,1.0/hz,42)
		for i in hz:b.integrate(s,1.0/hz,42)
		check(absf(b.pickup_age-1.0)<.00001,"frame independence "+str(hz))
		check(b.sample().pickup_weight==0,"gesture completed "+str(hz))
	var c=Actions.new();c.integrate(s,.016,0);c.integrate(s,.016,12);s.mode="swim";c.integrate(s,.1,12)
	check(c.sample().pickup_weight==0,"swim keeps original strokes")
	var clock=c.clock;c.integrate(s,NAN,12);check(c.clock==clock,"NaN rejected")
	print("HANDMADE_STATE_PASS checks=",checks);quit()
