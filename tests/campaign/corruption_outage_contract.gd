extends SceneTree
const Corruption = preload("res://scripts/campaign/campaign_corruption.gd")
class ResidentWorld extends Node3D:
	var resident_rooms: Dictionary = {}
class AnimatedFixture extends Node3D:
	func enable_flicker() -> void: pass
	func _process(_delta: float) -> void: pass
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)
func fixture(world: ResidentWorld, coord: Vector2i, energies: Array) -> Array:
	var room := Node3D.new(); world.add_child(room); world.resident_rooms[coord] = room
	var rig := Node3D.new(); rig.name = "NativeLighting"; room.add_child(rig)
	var result := []
	for energy: float in energies:
		var lamp := OmniLight3D.new(); lamp.light_color = Color(0.8,0.7,0.6); lamp.light_energy = energy; rig.add_child(lamp); result.append(lamp)
	return result
func tick(c: RefCounted, world: Node, seconds: float) -> void:
	for frame in range(int(seconds*10)): c.apply(world,1.0,0.1)
func run() -> void:
	var world := ResidentWorld.new(); root.add_child(world)
	var lamps := fixture(world,Vector2i.ZERO,[2.5,1.75])
	lamps[1].name = "SourceExitLight"
	var c := Corruption.new(); tick(c,world,20.0)
	check(lamps[0].light_energy == 0.0, "eligible native lamp actually turns off")
	check(lamps[1].light_energy == 1.75, "exit lamp stays exactly authored")
	var elapsed: float = c._elapsed; var sequence: int = c._outage_sequence
	for frame in range(100): c.apply(world,1.0,0.0)
	check(c._elapsed == elapsed and c._outage_sequence == sequence, "paused clock cannot create extra event")
	check(lamps[0].light_energy == 0.0, "paused dark hold does not advance")
	tick(c,world,8.0)
	check(lamps[0].light_energy > 0.0 and c._outage_sequence == 1, "smooth restore and no repeated fast outage")
	tick(c,world,40.0)
	check(c._outage_sequence == 1, "minimum64second separation")
	c.reset()
	check(lamps[0].light_energy == 2.5 and lamps[0].light_color == Color(0.8,0.7,0.6), "reset exact after outage")
	tick(c,world,20.0); lamps[1].queue_free(); c.apply(world,1.0,0.1)
	check(lamps[0].light_energy > 0.0, "queued backup removal restores in same frame")
	await process_frame; c.apply(world,1.0,0.1)
	check(lamps[0].light_energy > 0.0, "backup free immediately restores selected lamp")
	c.reset(); world.free()
	world = ResidentWorld.new(); root.add_child(world)
	lamps = fixture(world,Vector2i.ZERO,[2.5,1.75]); lamps[1].set_meta("campaign_preserve_light",true)
	tick(c,world,20.0); lamps[1].light_energy = 0.0; c.apply(world,1.0,0.1)
	check(lamps[0].light_energy > 0.0, "backup power loss aborts outage immediately")
	c.reset(); lamps[1].light_energy = 1.75; tick(c,world,20.0); c.apply(world,0.4,0.1)
	check(lamps[0].light_energy > 0.0, "repair below high severity restores dark lamp")
	c.reset(); tick(c,world,20.0); world.resident_rooms[Vector2i.ZERO].queue_free(); world.resident_rooms.clear(); await process_frame; c.apply(world,1.0,0.1)
	check(c._outage == null, "room freed during outage clears weak ownership")
	c.reset(); world.free()
	world = ResidentWorld.new(); root.add_child(world)
	lamps = fixture(world,Vector2i.ZERO,[2.5])
	var other := fixture(world,Vector2i.RIGHT,[2.5])
	tick(c,world,24.0)
	check(lamps[0].light_energy > 0.0 and other[0].light_energy > 0.0 and c._outage_sequence == 0, "different rooms cannot provide redundancy")
	c.reset(); world.free()
	world = ResidentWorld.new(); root.add_child(world)
	lamps = fixture(world,Vector2i.ZERO,[2.5,1.75]); lamps[1].set_meta("campaign_puzzle_light",true)
	tick(c,world,20.0); world.resident_rooms.clear(); c.apply(world,1.0,0.1)
	check(lamps[0].light_energy > 0.0 and lamps[1].light_energy == 1.75, "ownership removal aborts dark hold and protects puzzle light")
	c.reset(); world.free()
	world = ResidentWorld.new(); root.add_child(world)
	lamps = fixture(world,Vector2i.ZERO,[2.5,1.75]); lamps[1].set_meta("campaign_temporary_light",true)
	tick(c,world,24.0)
	check(lamps[0].light_energy > 0.0 and c._outage_sequence == 0, "temporary lens cannot qualify as backup")
	c.reset(); world.free()
	world = ResidentWorld.new(); root.add_child(world)
	lamps = fixture(world,Vector2i.ZERO,[2.5])
	var room: Node3D = world.resident_rooms[Vector2i.ZERO]
	var animated := AnimatedFixture.new(); room.get_node("NativeLighting").add_child(animated); animated.set_process(true)
	var unstable := OmniLight3D.new(); unstable.light_energy = 2.0; animated.add_child(unstable)
	var arrival := OmniLight3D.new(); arrival.light_energy = 2.0; room.add_child(arrival)
	tick(c,world,24.0)
	check(c._outage_sequence == 0 and lamps[0].light_energy > 0.0, "animated and arrival lights never qualify as stable backup")
	c.reset(); c.reduced_effects = true
	tick(c,world,100.0)
	check(lamps[0].light_energy >= 2.5*0.91 and c._outage_sequence == 0, "reduced effects never darkens a fixture")
	c.reset(); world.free()
	print("CAMPAIGN_CORRUPTION_OUTAGE_CONTRACT ", "PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
