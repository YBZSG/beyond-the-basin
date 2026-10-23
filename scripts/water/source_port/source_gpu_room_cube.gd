extends TextureCubemapRD
## The consumer-visible resource owns the immutable original RD cube, not the
## probe/cache. Eviction, invalidation and probe disposal only drop references.
## A material retaining this texture keeps every required RID alive.
var _lease: RefCounted

func retain_payload(value: RefCounted) -> void:
	assert(_lease == null)
	_lease = value

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _lease != null:
		# Match the validated wrapper-detach-before-original-release order.
		# The lease callback retains only itself, never this dying Resource.
		texture_rd_rid = RID()
		RenderingServer.call_on_render_thread(_lease.release)
		_lease = null
