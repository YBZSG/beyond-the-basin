extends SceneTree
## Isolated CPU-only GLTFDocument import. No editor filesystem scan or .import
## sidecars, no extracted textures, no touched source or shared .godot cache.
const LOOPS: Array[String] = ["Idle", "Walk", "Run", "Hold", "Climb", "Wade", "Swim", "SwimIdle", "JumpAir"]
const EXPECTED: Array[String] = ["Idle", "Walk", "Run", "Hold", "Climb", "Wade", "Swim", "SwimIdle", "JumpRise", "JumpAir", "Land", "ThrowCharge", "ThrowRelease", "ThrowRecover"]
var report: Dictionary = {"engine": Engine.get_version_info().string, "gpu_used": false, "textures_extracted": false, "animations": {}, "meshes": [], "errors": []}
var skeleton: Skeleton3D
var player: AnimationPlayer

func _initialize() -> void:
 var args: PackedStringArray = OS.get_cmdline_user_args()
 if args.size() != 3:
  push_error("Expected absolute input.glb output.scn report.json paths")
  quit(2)
  return
 var document := GLTFDocument.new()
 var state := GLTFState.new()
 state.create_animations = true
 state.use_named_skin_binds = true
 state.handle_binary_image = 3 # Embed uncompressed image data in saved scene.
 var error: Error = document.append_from_file(args[0], state)
 if error != OK:
  push_error("GLTFDocument append failed: " + str(error))
  quit(3)
  return
 var node: Node = document.generate_scene(state, 120.0, false, false)
 if node == null:
  push_error("GLTFDocument returned no scene")
  quit(4)
  return
 _inspect(node)
 if skeleton == null or player == null:
  report.errors.append("Missing skeleton or animation player")
 else:
  report.bone_count = skeleton.get_bone_count()
  report.bones = []
  for index: int in skeleton.get_bone_count(): report.bones.append(skeleton.get_bone_name(index))
  if report.bone_count != 54: report.errors.append("Expected revised 54-bone rig")
  for expected: String in EXPECTED:
   var found: String = ""
   for key: String in player.get_animation_list():
    if key.get_slice("/", key.get_slice_count("/") - 1) == expected: found = key
   if found.is_empty():
    report.errors.append("Missing clip: " + expected)
    continue
   var animation: Animation = player.get_animation(found)
   animation.loop_mode = Animation.LOOP_LINEAR if expected in LOOPS else Animation.LOOP_NONE
   if expected == "ThrowRelease":
    animation.add_marker("RELEASE", 0.0)
    animation.set_meta("release_seconds", 0.0)
    animation.set_meta("physics_authority", "Immediate controller launch; animation does not delay or reattach")
   var tracks: Array[String] = []
   for track: int in animation.get_track_count():
    var path: String = String(animation.track_get_path(track))
    tracks.append(path)
    if expected.begins_with("Throw") and (path.ends_with(":Hips") or path.ends_with(":Root") or path.contains(":UpperLeg") or path.contains(":LowerLeg") or path.contains(":Foot") or path.contains(":Toe")):
     report.errors.append("Throw contains lower-body/root track: " + path)
   report.animations[expected] = {"length": animation.length, "loop": animation.loop_mode == Animation.LOOP_LINEAR, "track_count": animation.get_track_count(), "tracks": tracks}
 var packed := PackedScene.new()
 error = packed.pack(node)
 if error == OK: error = ResourceSaver.save(packed, args[1], ResourceSaver.FLAG_COMPRESS)
 if error != OK: report.errors.append("PackedScene save failed: " + str(error))
 else:
  report.output = args[1]
  report.output_bytes = FileAccess.get_file_as_bytes(args[1]).size()
  report.dependencies = Array(ResourceLoader.get_dependencies(args[1]))
  if not report.dependencies.is_empty(): report.errors.append("Unexpected external dependency in self-contained scene")
  var reloaded: PackedScene = ResourceLoader.load(args[1], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
  if reloaded == null: report.errors.append("Saved scene reload failed")
  else:
   var instance: Node = reloaded.instantiate()
   report.reload_instantiated = instance != null
   if instance != null: instance.free()
 report.passed = report.errors.is_empty()
 FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
 print("WATER_MOTION_SCENE ", JSON.stringify({"passed": report.passed, "bone_count": report.get("bone_count", 0), "output_bytes": report.get("output_bytes", 0), "errors": report.errors}))
 node.free()
 quit(0 if report.passed else 5)

func _inspect(node: Node) -> void:
 if node is Skeleton3D: skeleton = node as Skeleton3D
 if node is AnimationPlayer: player = node as AnimationPlayer
 if node is MeshInstance3D:
  var mesh_node := node as MeshInstance3D
  if mesh_node.mesh != null:
   for surface: int in mesh_node.mesh.get_surface_count():
    var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
    var material: Material = mesh_node.mesh.surface_get_material(surface)
    var name: String = material.resource_name if material != null else ""
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var uv0: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
    var skin: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
    var entry: Dictionary = {"mesh": mesh_node.name, "material": name, "vertices": vertices.size(), "uv0_count": uv0.size(), "skin_indices_count": skin.size()}
    if name in ["Explorer | warm ivory woven shirt", "Explorer | charcoal cotton trousers"]:
     var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
     var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
     entry.uv2_count = uv2.size()
     entry.tangent_count = tangents.size()
     var max_u: float = -INF
     var min_v: float = INF
     for uv: Vector2 in uv2:
      max_u = maxf(max_u, uv.x)
      min_v = minf(min_v, uv.y)
     entry.uv2_max_u = max_u
     entry.uv2_min_v = min_v
     if uv2.size() != vertices.size() or tangents.size() != vertices.size() * 4 or max_u <= 3.5 or max_u >= 4.2 or min_v >= -4.0 or min_v <= -10.0:
      report.errors.append("Cloth metre-UV2/tangent contract failed: " + name)
    report.meshes.append(entry)
 for child: Node in node.get_children(): _inspect(child)
