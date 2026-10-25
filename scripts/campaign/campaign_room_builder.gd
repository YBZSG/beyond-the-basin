extends "res://scripts/world/room_builder.gd"
## Ceiling closure must query the actual campaign neighbour, not another catalog.
var campaign_world: Node3D
func _adjacent_layout(coord: Vector2i) -> Dictionary:
	if campaign_world != null and coord in campaign_world.finite_coords:
		return campaign_world.get_layout(coord)
	return {"ceiling":float(layout.ceiling)}

func build_interior()->void:
	super.build_interior()
	for bounds:AABB in layout.get("campaign_backing_solids",[]):layout.solids.append(bounds)
	room.set_meta("layout",layout)
