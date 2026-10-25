extends SceneTree
## Actual production nodes and actual source-water methods, dummy renderer only.
const Lighting = preload("res://scripts/reference_wing/reference_lighting.gd")
const OriginalLighting = preload("res://scripts/rendering/pool_lighting.gd")
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const Water = preload("res://scripts/reference_wing/reference_scene_water_runtime.gd")
const OriginalWater = preload("res://scripts/water/source_water_runtime.gd")

class LightCollector extends CompositorEffect:
	var entries: Array = []
	func set_lights(value: Array) -> void: entries = value.duplicate(true)

class CollectionWater extends Water:
	## Only suppress unrelated GPU publication/terrain scheduling. add_room and
	## both original/new light collection bodies remain actual production code.
	func _apply_surface(_material: ShaderMaterial) -> void: pass
	func _invalidate_terrain(_changed_coord: Variant = null) -> void: pass
	func _refresh_surface_visibility() -> void: pass

var errors: Array[String] = []
var checks := 0
var room_reports: Array = []
var host: Node3D
var camera: Camera3D

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: errors.append(message)

func _initialize() -> void: run.call_deferred()

func make_room(layout: Dictionary) -> Node3D:
	var room := Node3D.new()
	room.position = Vector3(layout.coord.x * 32.0, 0, layout.coord.y * 32.0)
	room.set_meta("coord", layout.coord)
	room.set_meta("layout", layout)
	host.add_child(room)
	return room

func lights(room: Node3D) -> Array[Light3D]:
	var result: Array[Light3D] = []
	for node in room.find_children("*", "Light3D", true, false): result.append(node)
	return result

func snapshot(room: Node3D) -> Array:
	var result: Array = []
	for lamp: Light3D in lights(room):
		result.append([lamp.get_class(), lamp.position, lamp.basis, lamp.light_color, lamp.light_energy,
			lamp.light_indirect_energy, lamp.light_size, lamp.light_specular, lamp.shadow_enabled,
			lamp.omni_range if lamp is OmniLight3D else lamp.spot_range])
	return result

func serializable_binding(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.position = [value.position.x, value.position.y, value.position.z]
	result.direction = [value.direction.x, value.direction.y, value.direction.z]
	result.color = [value.color.r, value.color.g, value.color.b]
	return result

func run() -> void:
	check(DisplayServer.get_name() == "headless" and RenderingServer.get_rendering_device() == null, "Requires headless dummy renderer")
	host = Node3D.new(); root.add_child(host)
	camera = Camera3D.new(); host.add_child(camera)
	var manager := Lighting.new()
	var original := OriginalLighting.new()
	for raw_color in [[.003,.2,.78], [.78,.92,.88], [1.0,.3,.07]]:
		var linear_source := {"name": "ColorContract", "position": [0,3,0], "type": "omni", "color": raw_color, "color_space": "linear"}
		var linear_binding := Lighting.binding(linear_source)
		var expected_linear := Color(raw_color[0],raw_color[1],raw_color[2])
		check(linear_binding.color.srgb_to_linear().is_equal_approx(expected_linear), "Native color preserves authored Blender linear radiance")
		linear_source.color_space = "srgb"
		check(Lighting.binding(linear_source).color.is_equal_approx(expected_linear), "Unconverted explicit sRGB contract preserved")
	var rooms: Array[Node3D] = []
	var total := 0
	for index in Catalog.COORDS.size():
		var layout := Catalog.room_layout(Catalog.COORDS[index], 42)
		var photon_fixtures: Array = layout.fixtures.duplicate(true)
		var room := make_room(layout); rooms.append(room)
		manager.add_room_lights(room, layout.variant)
		check(layout.fixtures == photon_fixtures, layout.reference_id + ": photon source fixture inputs are not rewritten")
		var native := lights(room)
		check(native.size() == layout.fixtures.size(), layout.reference_id + ": exactly one native light per fixture")
		check(native.size() <= 17, layout.reference_id + ": no rectangular multi-light fanout")
		manager.add_room_lights(room, layout.variant)
		check(lights(room).size() == native.size(), layout.reference_id + ": idempotent attachment")
		var shape_counts := {"spot": 0, "omni": 0}
		var bindings: Array = []
		for slot in native.size():
			var lamp: Light3D = native[slot]
			var spec := Lighting.binding(layout.fixtures[slot])
			bindings.append(serializable_binding(spec))
			shape_counts[spec.type] += 1
			check(lamp is SpotLight3D if spec.type == "spot" else lamp is OmniLight3D, layout.reference_id + ": native type")
			check(lamp.position.is_equal_approx(spec.position), layout.reference_id + ": authored local center")
			check(lamp.global_position.is_equal_approx(room.position + spec.position), layout.reference_id + ": room offset applied once")
			check(is_equal_approx(lamp.light_energy, spec.energy), layout.reference_id + ": native energy")
			check(lamp.light_color.is_equal_approx(spec.color), layout.reference_id + ": native color")
			var authored: Dictionary = layout.fixtures[slot].reference_light
			if authored.get("color_space", "srgb") == "linear":
				var raw: Array = authored.color
				check(lamp.light_color.srgb_to_linear().is_equal_approx(Color(raw[0], raw[1], raw[2])), layout.reference_id + ": actual native/light-water decode preserves author linear color")
			check(is_equal_approx(lamp.light_size, spec.radius), layout.reference_id + ": emitter radius")
			check(lamp.basis.is_finite() and is_equal_approx(lamp.basis.determinant(), 1.0), layout.reference_id + ": nondegenerate rotation")
			check(lamp.get_meta("source_shadow_managed", false), layout.reference_id + ": quality-managed source")
			check(not lamp.visible and not lamp.shadow_enabled, layout.reference_id + ": unselected fixtures never flash")
			if lamp is SpotLight3D:
				check((-lamp.basis.z).is_equal_approx(spec.direction), layout.reference_id + ": -Z cone direction")
				check(is_equal_approx(lamp.spot_range, spec.range), layout.reference_id + ": spot range")
				check(is_equal_approx(lamp.spot_angle, spec.spot_angle), layout.reference_id + ": half-angle, not diameter")
				check(is_equal_approx(lamp.spot_angle_attenuation, spec.spot_attenuation), layout.reference_id + ": cone attenuation")
		room_reports.append({"id": layout.reference_id, "fixtures": native.size(), "native_shapes": shape_counts, "bindings": bindings})
		total += native.size()
	check(manager._source_lights.is_empty(), "Reference spots must not enter Omni-only inherited list")
	for index in rooms.size():
		var layout: Dictionary = rooms[index].get_meta("layout")
		camera.position = rooms[index].position + layout.spawn_local + Vector3.UP * 1.6
		manager.update_active_room(layout.coord, layout)
		manager.update_source_view(camera)
		var stats := manager.reference_lighting_stats()
		check(stats.visible <= 27 and stats.shadowed <= 4, "Combined reference visibility/shadow cap")
		for lamp in lights(rooms[index]): check(lamp.visible, "Current room retains every bounded fixture")
		var shadow_before: Array = []
		for lamp in lights(rooms[index]): shadow_before.append(lamp.shadow_enabled)
		camera.rotate_y(PI)
		manager.update_source_view(camera)
		var shadow_after: Array = []
		for lamp in lights(rooms[index]): shadow_after.append(lamp.shadow_enabled)
		check(shadow_after == shadow_before, "Camera reversal does not pop active-room shadow selection")
		camera.rotate_y(-PI)
		for lamp in lights(rooms[index]): lamp.set_meta("source_shadows_allowed", false)
		manager.update_source_view(camera)
		for lamp in lights(rooms[index]): check(not lamp.shadow_enabled, "Desktop/mobile shadow-off respected")
		for lamp in lights(rooms[index]): lamp.set_meta("source_shadows_allowed", true)
		manager.update_source_view(camera)
		check(manager.reference_lighting_stats().shadowed <= 4, "Shadow restore remains capped")
		var first: Light3D = lights(rooms[index])[0]
		first.set_meta("reference_authored_shadow", false)
		manager.update_source_view(camera)
		check(not first.shadow_enabled, "Authored no-shadow fixture remains unshadowed")
		first.set_meta("reference_authored_shadow", true)
	var legacy_layout := {"coord": Vector2i.ZERO, "variant": 0, "fixtures": [{"geometry": "authored_wall", "position": Vector3(1,3,2), "color": Color(.8,.9,1), "power": 12.0, "range": 7.0}]}
	var legacy := make_room(legacy_layout)
	var baseline := make_room(legacy_layout)
	manager.add_room_lights(legacy, 0); original.add_room_lights(baseline, 0)
	check(snapshot(legacy) == snapshot(baseline), "Legacy actual nodes exactly match base manager")
	manager.update_active_room(Vector2i.ZERO, legacy_layout)
	original.update_active_room(Vector2i.ZERO, legacy_layout)
	manager.update_source_view(camera); original.update_source_view(camera)
	check(snapshot(legacy) == snapshot(baseline), "Legacy manager behavior restored after reference mode")
	check(manager.reference_lighting_stats().visible == 0, "Leaving reference disables retained reference rigs")
	var formal_layout := {"coord": Vector2i(-1,-1), "formal": true, "ceiling": 4.8}
	var formal := make_room(formal_layout); var formal_base := make_room(formal_layout)
	manager.add_formal_lights(formal, formal_layout); original.add_formal_lights(formal_base, formal_layout)
	check(snapshot(formal) == snapshot(formal_base), "Formal actual nodes exactly match inherited path")
	formal.free(); formal_base.free(); baseline.free()
	var current: Dictionary = rooms[3].get_meta("layout")
	manager.update_active_room(current.coord, current)
	manager.update_source_view(camera)
	check(not lights(legacy)[0].visible and not lights(legacy)[0].shadow_enabled, "Entering reference retires inherited source budget")
	legacy.free()
	var collection_water := CollectionWater.new()
	collection_water._configured = true
	collection_water.add_room(rooms[3], current.coord, current)
	check(collection_water._room_light_refs[current.coord].size() == lights(rooms[3]).size(), "Actual add_room replaces Omni-only cache with native Spot/Omni refs")
	check(not collection_water.solver.is_ready and collection_water._reference_depth_thread == null, "Collection test never configures solver or starts a worker")
	collection_water.remove_room(current.coord)
	check(not collection_water._room_light_refs.has(current.coord), "Inherited room removal clears new light refs")
	collection_water.free()
	# Exercise the actual new water override against the untouched source method.
	var water := Water.new(); var source_water := OriginalWater.new()
	var collector := LightCollector.new(); var source_collector := LightCollector.new()
	water._liquid_surface = collector; source_water._liquid_surface = source_collector
	water._camera = camera; source_water._camera = camera
	water.domain_origin = Vector2(32,-64); source_water.domain_origin = water.domain_origin
	water._layouts = {current.coord: current}; source_water._layouts = water._layouts
	check(water._effective_lamps(current.coord) == source_water._effective_lamps(current.coord), "Reference photon inputs preserve the actual original source selection")
	check(water._effective_lamps(current.coord).size() == 2, "Original two-effective-photon-lamp limit is explicit, not expanded")
	var omni_room := Node3D.new(); host.add_child(omni_room)
	var refs: Array[WeakRef] = []
	for index in 32:
		var lamp := OmniLight3D.new(); omni_room.add_child(lamp)
		lamp.position = Vector3(32 + index * .2, 2.5, -64 + index * .5)
		lamp.light_energy = .1 + index * .03; lamp.light_color = Color(.62,.83,.91)
		lamp.omni_range = 4 + index * .1; lamp.shadow_enabled = index < 4
		lamp.set_meta("source_power_per_energy", 1.0/.07); lamp.set_meta("source_shadow_managed", true)
		lamp.set_meta("source_shadow_priority", index < 3)
		refs.append(weakref(lamp))
	water._room_light_refs = {current.coord: refs}; source_water._room_light_refs = water._room_light_refs
	water._set_liquid_lights(); source_water._set_liquid_lights()
	check(collector.entries == source_collector.entries, "All original Omni liquid inputs numerically identical")
	check(collector.entries.size() == 27, "Liquid/droplet source cap remains 27")
	var native_refs: Array[WeakRef] = []
	var active_native: Array[Light3D] = lights(rooms[3])
	for lamp in active_native: lamp.visible = true; native_refs.append(weakref(lamp))
	water._room_light_refs = {current.coord: native_refs}
	water._set_liquid_lights()
	check(collector.entries.size() == active_native.size(), "Spot fixtures remain in liquid/droplet inputs")
	for index in active_native.size():
		var lamp: Light3D = active_native[index]
		var entry: Dictionary = collector.entries[index]
		check(entry.position.is_equal_approx(lamp.global_position - Vector3(32,0,-64)), "Liquid source transform rebases exactly once")
		check(is_equal_approx(entry.intensity, lamp.light_energy / .07), "Liquid intensity preserves source conversion")
		check(is_equal_approx(entry.range, lamp.spot_range if lamp is SpotLight3D else lamp.omni_range), "Liquid accepts correct shape range")
		check(entry.color.is_equal_approx(lamp.light_color.srgb_to_linear()), "Liquid color conversion remains identical")
	active_native[0].visible = false; water._set_liquid_lights()
	check(collector.entries.size() == active_native.size() - 1, "Hidden source is removed from liquid input")
	active_native[0].free(); water._set_liquid_lights()
	check(collector.entries.size() == active_native.size() - 1, "Freed source weakref is harmless")
	water._liquid_surface = null; source_water._liquid_surface = null
	water.free(); source_water.free(); omni_room.free()
	rooms[0].hide(); manager.update_source_view(camera)
	for lamp in lights(rooms[0]): check(not lamp.visible and not lamp.shadow_enabled, "Hidden retired room releases budget")
	for room in rooms: room.free()
	manager.update_source_view(camera)
	check(manager.reference_lighting_stats().tracked == 0, "Freed reference weakrefs pruned")
	check(manager._source_lights.is_empty(), "Freed legacy weakrefs pruned")
	check(manager._room_roots.is_empty(), "Freed rig weakrefs pruned even without crossing another room")
	var rebuilt := make_room(Catalog.room_layout(Vector2i.ZERO, 43))
	manager.add_room_lights(rebuilt, 20)
	manager.update_active_room(Vector2i.ZERO, rebuilt.get_meta("layout")); manager.update_source_view(camera)
	check(manager.reference_lighting_stats().tracked == lights(rebuilt).size(), "Regeneration attaches no stale lights")
	rebuilt.free(); host.free()
	print("REFERENCE_LIGHTING_CONTRACT ", JSON.stringify({"passed": errors.is_empty(), "checks": checks,
		"errors": errors, "rooms": room_reports, "native_fixture_total": total, "gpu_run": false,
		"scope": "Actual production light nodes, transforms, manager lifecycle, and source/new water point input parity. No pixels, shader execution or NVIDIA acceptance."}))
	quit(0 if errors.is_empty() else 1)
