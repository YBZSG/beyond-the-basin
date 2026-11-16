extends RefCounted
## Mirror-only plane clipping for the common mapped tile materials in wet rooms.
## Room-local overrides leave the cached materials and other scene shaders intact.
const Receiver = preload("res://scripts/dreamcore/uncanny/hollow_visage_tile_receiver.gd")
const Filtered = preload("res://shaders/dreamcore/dream_tile_filtered.gdshader")
const ALLOWED = ["Annex PBR / tile", "Annex PBR / lime_tile"]
static func apply(room: Node3D, data: Dictionary) -> void:
 if not data.get("water_enabled",false): return
 var clones: Dictionary = {}
 for child: Node in room.get_children():
  if not child is MeshInstance3D or child.mesh == null: continue
  var base := child.material_override as StandardMaterial3D
  if base == null or base.resource_name not in ALLOWED: continue
  if base.emission_enabled or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
  if base.albedo_texture == null or not base.normal_enabled or base.normal_texture == null: continue
  if base.roughness_texture == null or base.metallic_texture != base.roughness_texture or base.ao_texture != base.roughness_texture: continue
  var bounds: AABB = child.transform * child.mesh.get_aabb()
  if bounds.position.y >= .318 and str(data.get("dream_id", "")) != "hanging_hand": continue
  var id := base.get_instance_id()
  if not clones.has(id):
   clones[id] = Receiver._from_standard(base)
   clones[id].shader = Filtered
  child.material_override = clones[id]
