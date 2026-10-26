extends Node
## Deterministic opaque color for water transmission while the main scene uses RT.
## The main depth buffer still owns silhouettes and optical water thickness.
const CaptureEnvironment=preload("res://scripts/water/source_port/source_capture_environment.gd")
const EXCLUDED_LAYERS:=2|4|524288 # Water, splash particles and mirror clip marker.
var viewport:SubViewport
var camera:Camera3D
var source_camera:Camera3D
var environment:Environment
var output:Texture2D
var enabled:=false
var capture_ready:=false
var _pending:=false

func configure(source:Camera3D,source_environment:Environment)->void:
 source_camera=source;environment=source_environment

func set_enabled(value:bool)->void:
 enabled=value
 if not enabled:
  capture_ready=false;_pending=false
  if is_instance_valid(viewport):viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func _create()->void:
 viewport=SubViewport.new();viewport.name="RasterWaterTransmission"
 viewport.disable_3d=false;viewport.use_hdr_2d=true;viewport.use_taa=false
 viewport.msaa_3d=Viewport.MSAA_2X
 viewport.world_3d=source_camera.get_world_3d()
 viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
 add_child(viewport)
 camera=Camera3D.new();camera.current=true
 camera.environment=CaptureEnvironment.create(environment)
 # Avoid a second GI/SSR pipeline. Direct lights, shadows, material textures
 # and the existing receiver caustics remain available in this raster pass.
 camera.environment.sdfgi_enabled=false;camera.environment.ssr_enabled=false
 camera.environment.ssao_enabled=false;camera.environment.ssil_enabled=false
 # An indoor pool floor must not reflect the unoccluded outdoor sky. The water
 # surface already supplies its own room-correct planar reflection above it.
 camera.environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
 viewport.add_child(camera);output=viewport.get_texture()
 RenderingServer.frame_post_draw.connect(_captured)

func update()->void:
 if not enabled or not is_instance_valid(source_camera):return
 if not is_instance_valid(viewport):_create()
 if _pending:return
 var screen:=source_camera.get_viewport().get_visible_rect().size
 var width:=mini(768,maxi(1,int(screen.x)))
 var size:=Vector2i(width,maxi(1,roundi(float(width)*screen.y/maxf(screen.x,1.0))))
 if viewport.size!=size:viewport.size=size
 CaptureEnvironment.synchronize_live(environment,camera.environment)
 camera.global_transform=source_camera.global_transform
 camera.projection=source_camera.projection;camera.fov=source_camera.fov
 camera.size=source_camera.size;camera.frustum_offset=source_camera.frustum_offset
 camera.near=source_camera.near;camera.far=source_camera.far
 camera.keep_aspect=source_camera.keep_aspect
 camera.h_offset=source_camera.h_offset;camera.v_offset=source_camera.v_offset
 camera.cull_mask=source_camera.cull_mask & ~EXCLUDED_LAYERS
 _pending=true;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _captured()->void:
 if _pending:capture_ready=true;_pending=false

func dispose()->void:
 set_enabled(false)
 if RenderingServer.frame_post_draw.is_connected(_captured):RenderingServer.frame_post_draw.disconnect(_captured)
 if is_instance_valid(viewport):viewport.queue_free()
 viewport=null;camera=null;output=null

func _exit_tree()->void:dispose()
