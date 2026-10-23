extends RefCounted
## Opt-in PC preview only. ResourceLoader supports exported resource remaps;
## raw source hashes belong to the build gate, never exported runtime reads.
const FLAG := "--pc-mainhall-lightmap-preview"
const VISUAL := "res://scenes/lighting_lab/runtime_mainhall_candidate.tscn"
const DATA := "res://assets/lighting/runtime_mainhall_candidate/native_indirect.lmbake"
const SOURCE := "res://assets/models/formal/formal_mainhall.glb"
const HDR := "res://assets/lighting/runtime_mainhall_candidate/indirect_00.exr"
const SOURCE_SHA256 := "3d4089cf0fb3a265765f923d445369a4c086727b782bbbba58c3569c61564bf1"
const PROBE_SHA256 := "c467cbcaa7011fc5946d71b3fde541c545fc519db8275ba1215eb29f5626581c"
const BUILD_SHA256 := {
	VISUAL: "e78182701bb135fb350895f4409a2e9fa242cfa94835bb3a12ca47a73ce45583",
	DATA: "57d7fdc37f152eb046dfd673dd4e76878e6258ca89a55f502defdcc32a604b18",
	SOURCE: SOURCE_SHA256,
	HDR: "8aabb748f20fad0d36fadee1d8288aded72ac9660cdd2687806a43a7618c1f95",
}
const USER_DATA_SHA256 := "865922ee4a525c62d193bf936f82662a3271acfe2a9631cbe282c20564bff88c"
const NATIVE_STORAGE_SHA256 := "7129ed0d2a59a7574da3f4e58ffe6e392fa3e4b3baa1699eb344699ba8e02e46"
const PHYSICAL_SKY_ENERGY := 3.98049270761935
const SCOPE := "EXPERIMENTAL: mainhall-only native bake; SDFGI off. Other 4 rooms retain direct/ambient light, NOT equivalent indirect lighting."

static func desktop_allowed(args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	return not (OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in args)

static func requested(args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	return desktop_allowed(args) and FLAG in args

static func failure(reason: String) -> Dictionary:
	return {"pass":false, "installed":false, "reason":reason, "scope":SCOPE}

static func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

static func environment_errors(environment: Environment, sun: DirectionalLight3D) -> Array[String]:
	var errors: Array[String] = []
	if environment == null or environment.sky == null or not environment.sky.sky_material is PhysicalSkyMaterial:
		errors.append("Energy-matched PhysicalSky is missing")
	elif absf(environment.sky.sky_material.energy_multiplier - PHYSICAL_SKY_ENERGY) > .00001:
		errors.append("PhysicalSky energy differs from the native bake")
	if environment != null and (environment.sdfgi_enabled or absf(environment.ambient_light_energy - .18) > .00001 or absf(environment.tonemap_exposure - 3.2) > .00001):
		errors.append("Mainhall GI/exposure/ambient rig is not settled")
	if sun == null or sun.light_bake_mode != Light3D.BAKE_DYNAMIC:
		errors.append("Realtime-direct formal sun is missing")
	elif absf(sun.light_energy - 1.45) > .00001 or absf(sun.light_indirect_energy - .8) > .00001 or not sun.light_color.is_equal_approx(Color("fff9ee")):
		errors.append("Formal source sun differs from the native bake")
	if sun != null:
		var ray := Basis.from_euler(Vector3(deg_to_rad(-62.0),deg_to_rad(-28.0),0)).z.normalized()
		if sun.global_basis.z.normalized().distance_to(ray) > .000002:
			errors.append("Formal source sun direction differs")
	return errors

static func prepare_candidate(room: Node3D, library: RefCounted) -> Dictionary:
	# Every return before commit leaves the original scene untouched. A candidate
	# is caller-owned only on success and must be freed if not committed.
	if room == null or library == null or not library.has_method("get_material"):
		return failure("Original room/live material library missing")
	var old := room.get_node_or_null("FormalAuthoredArchitecture") as Node3D
	var collision := room.get_node_or_null("ArchitectureCollision") as StaticBody3D
	if old == null or collision == null or collision.get_child_count() != 254:
		return failure("Expected original architecture and 254 collision shapes")
	if not room.find_children("*","LightmapGI",true,false).is_empty():
		return failure("Existing lightmap ownership is ambiguous")
	if not ResourceLoader.exists(VISUAL,"PackedScene") or not ResourceLoader.exists(DATA,"LightmapGIData"):
		return failure("Native preview resources are absent from this build")
	var packed := ResourceLoader.load(VISUAL,"PackedScene") as PackedScene
	if packed == null: return failure("Native preview scene could not load")
	var candidate := packed.instantiate() as Node3D
	if candidate == null: return failure("Native preview scene could not instantiate")
	var visual := candidate.get_node_or_null("FormalAuthoredArchitecture") as Node3D
	var lightmap := candidate.get_node_or_null("Bake_Mainhall_Indirect") as LightmapGI
	var errors: Array[String] = []
	if candidate.get_meta("formal_bake_source_glb_sha256", "") != SOURCE_SHA256 or not candidate.get_meta("formal_bake_requires_live_material_binding", false):
		errors.append("Native preview provenance metadata differs")
	if visual == null or lightmap == null or lightmap.light_data == null:
		errors.append("Native preview architecture/lightmap data missing")
	for forbidden: String in ["CollisionObject3D","Light3D","Camera3D","WorldEnvironment"]:
		if not candidate.find_children("*",forbidden,true,false).is_empty():
			errors.append("Native visual artifact may not own physics, a lighting rig or cameras")
	if not errors.is_empty(): candidate.free(); return failure(str(errors))
	errors.append_array(resource_data_errors(lightmap.light_data))
	var counts := [0,0,0,0,0]
	for mesh: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
		counts[0] += 1
		if mesh.mesh == null: errors.append("Missing native mesh"); continue
		if mesh.gi_mode == GeometryInstance3D.GI_MODE_STATIC: counts[1] += 1
		elif mesh.gi_mode == GeometryInstance3D.GI_MODE_DYNAMIC: counts[2] += 1
		elif mesh.get_meta("source_transmissive",false): counts[3] += 1
		var original := old.get_node_or_null(visual.get_path_to(mesh)) as MeshInstance3D
		var roles: PackedStringArray = mesh.get_meta("formal_live_material_roles",PackedStringArray())
		if original == null or original.mesh == null or roles.size() != mesh.mesh.get_surface_count():
			errors.append("Missing original receiver or explicit surface role: " + str(mesh.name)); continue
		if not mesh.transform.is_equal_approx(original.transform) or not mesh.mesh.get_aabb().is_equal_approx(original.mesh.get_aabb()):
			errors.append("Original receiver transform/bounds differ: " + str(mesh.name))
		for index in roles.size():
			var material: Material = library.get_material(roles[index])
			if material == null or index >= original.mesh.get_surface_count() or original.get_active_material(index) != material:
				errors.append("Live material role differs: " + str(mesh.name)); continue
			mesh.set_surface_override_material(index,material)
			counts[4] += 1
	if counts != [223,147,65,11,223]: errors.append("Expected 223 surfaces / 147 static / 65 dynamic / 11 glazing")
	if not errors.is_empty(): candidate.free(); return failure(str(errors))
	return {"pass":true,"candidate":candidate,"visual":visual,"lightmap":lightmap,"counts":counts,"scope":SCOPE}

static func resource_data_errors(data: LightmapGIData) -> Array[String]:
	var errors: Array[String] = []
	if data == null: errors.append("Missing native bake resource"); return errors
	if data.get_user_count() != 147 or _hash(data.get("user_data")) != USER_DATA_SHA256:
		errors.append("Native receiver paths/UV rectangles/atlas slices differ")
	if not data.is_using_spherical_harmonics() or not data.get_shadowmask_textures().is_empty():
		errors.append("Expected directional indirect-only native bake")
	var textures := data.get_lightmap_textures()
	if textures.size() != 1 or textures[0] == null:
		errors.append("Missing native HDR array")
	elif [textures[0].get_width(),textures[0].get_height(),textures[0].get_layers(),textures[0].get_format()] != [256,256,48,Image.FORMAT_RGBH]:
		errors.append("Native HDR array dimensions/half-float format differ")
	return errors

static func _stored_lightmap_state(data: LightmapGIData) -> Dictionary:
	var state := {}
	for property: Dictionary in data.get_property_list():
		var key := str(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
		if key.begins_with("resource_") or key in ["script","lightmap_textures","light_texture","shadowmask_textures"]: continue
		state[key] = data.get(key)
	return state

static func native_data_errors(lightmap: LightmapGI) -> Array[String]:
	var errors: Array[String] = []
	var data := lightmap.light_data
	if data == null: errors.append("Missing native bake"); return errors
	# These getters require the real RenderingDevice. Dummy/headless is never
	# accepted as proof that a bake works, even when the PackedScene loads.
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 6 or version.patch != 3 or RenderingServer.get_current_rendering_method() != "forward_plus":
		errors.append("This preview is validated only for Godot 4.6.3 Forward+")
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		errors.append("Native bake needs a Forward+ rendering device; headless is validation only")
		return errors
	if data.get_user_count() != 147 or not data.is_using_spherical_harmonics():
		errors.append("Native 147-user directional bake is unavailable")
	if _hash(_stored_lightmap_state(data)) != NATIVE_STORAGE_SHA256: errors.append("Native stored bake state differs")
	var probes: Dictionary = data.get("probe_data")
	if probes.get("sh",PackedColorArray()).size() != 1692 or _hash(probes) != PROBE_SHA256:
		errors.append("Native probe coefficients differ from the tested bake")
	var seen := {}
	for index in data.get_user_count():
		var path := data.get_user_path(index)
		var receiver := lightmap.get_node_or_null(path) as MeshInstance3D
		if receiver == null or receiver.gi_mode != GeometryInstance3D.GI_MODE_STATIC or seen.has(path):
			errors.append("Unresolved/duplicate native receiver path")
		seen[path] = true
	return errors

static func install(room: Node3D, library: RefCounted, environment: Environment, sun: DirectionalLight3D) -> Dictionary:
	if room == null or room.get_meta("coord",Vector2i.ZERO) != Vector2i(-1,-1):
		return failure("Only the formal mainhall is eligible")
	var errors := environment_errors(environment,sun)
	if not errors.is_empty(): return failure(str(errors))
	var prepared := prepare_candidate(room,library)
	if not prepared.pass: return prepared
	var candidate: Node3D = prepared.candidate
	var visual: Node3D = prepared.visual
	var lightmap: LightmapGI = prepared.lightmap
	errors = native_data_errors(lightmap)
	if not errors.is_empty(): candidate.free(); return failure(str(errors))
	var old := room.get_node("FormalAuthoredArchitecture") as Node3D
	var collision := room.get_node("ArchitectureCollision") as StaticBody3D
	var shapes := collision.get_children()
	var collision_id := collision.get_instance_id()
	var sibling := old.get_index()
	_clear_owners(visual); _clear_owners(lightmap)
	candidate.remove_child(visual); candidate.remove_child(lightmap)
	# Atomic: no await, no first draw with half-installed visuals, no collider swap.
	room.remove_child(old); room.add_child(visual); room.move_child(visual,sibling); room.add_child(lightmap)
	for index in lightmap.light_data.get_user_count():
		if not lightmap.has_node(lightmap.light_data.get_user_path(index)): errors.append("Moved native receiver path failed")
	if collision.get_instance_id() != collision_id or collision.get_children() != shapes:
		errors.append("Original collider identity changed")
	if not errors.is_empty():
		room.remove_child(visual); room.remove_child(lightmap); room.add_child(old); room.move_child(old,sibling)
		visual.free(); lightmap.free(); candidate.free()
		return failure(str(errors) + "; original visual restored")
	old.free(); candidate.free()
	room.set_meta("pc_mainhall_lightmap_preview_installed",true)
	return {"pass":true,"installed":true,"surfaces":223,"native_users":147,"collider_shapes":254,
		"collider_id":collision_id,"probe_sha256":PROBE_SHA256,"build_visual_sha256":BUILD_SHA256[VISUAL],"scope":SCOPE}

static func _clear_owners(node: Node) -> void:
	node.owner = null
	for child: Node in node.get_children(): _clear_owners(child)
