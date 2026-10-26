class_name SourcePlanarReflection
extends Node
## Port of Three Water.js mirror camera / render target into a Godot SubViewport.
## Godot Camera3D has no arbitrary projection setter; the original oblique clip
## plane is implemented as the SAME world-space plane in receiver shaders.
## Clip marker is camera-only, never a geometry render layer. Water is excluded.
const CaptureEnvironment=preload("res://scripts/water/source_port/source_capture_environment.gd")
const MARKER:=524288
const AVATAR_BODY_LAYER:=65536 # Layer17, never captured by the static room cube.
const AVATAR_HEAD_LAYER:=131072 # Layer18, excluded only from the main first-person camera.
var viewport:SubViewport
var mirror:Camera3D
var source_camera:Camera3D
var output:Texture2D
var texture_matrix:=Projection.IDENTITY
var capture_msaa:int=Viewport.MSAA_4X
var resolution:=768
var requested_resolution:=768
var rt_budget:=false
var _raster_msaa:int=Viewport.MSAA_4X
var interval:=0
var capture_ready:=false
var enabled:=true
var _age:=1000
var _pending:=false
var _last_camera_transform:=Transform3D.IDENTITY
var _last_projection:=Projection.IDENTITY
var captures:=0
var _pending_matrix:=Projection.IDENTITY
var _environment:Environment
func configure(camera:Camera3D, environment:Environment)->void:
 source_camera=camera
 source_camera.cull_mask=source_camera.cull_mask & ~MARKER
 _environment=environment
 if viewport:return
 viewport=SubViewport.new();viewport.name="OriginalWaterMirror";viewport.size=Vector2i(resolution,resolution);viewport.disable_3d=false;viewport.use_hdr_2d=true;viewport.use_taa=false;viewport.transparent_bg=false;viewport.world_3d=camera.get_world_3d();viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;viewport.msaa_3d=capture_msaa;add_child(viewport)
 mirror=Camera3D.new();mirror.cull_mask=1|AVATAR_BODY_LAYER|AVATAR_HEAD_LAYER|MARKER;mirror.current=true;viewport.add_child(mirror)
 # Capture linear HDR. Main viewport applies AgX/exposure once at composition.
 var capture_env:Environment=CaptureEnvironment.create(environment)
 mirror.environment=capture_env
 output=viewport.get_texture()
 RenderingServer.frame_post_draw.connect(_captured)
func set_quality(size_value:int, refresh:int=0)->void:
 requested_resolution=size_value
 resolution=mini(size_value,1024) if rt_budget else size_value
 interval=maxi(0,refresh);_age=1000
 if viewport:viewport.size=Vector2i(resolution,resolution)
func set_rt_budget(active:bool)->void:
 if rt_budget==active:return
 if active:_raster_msaa=capture_msaa
 rt_budget=active
 capture_msaa=Viewport.MSAA_2X if active else _raster_msaa
 if is_instance_valid(viewport):viewport.msaa_3d=capture_msaa
 set_quality(requested_resolution,interval)
func refresh_lighting()->void:
 if mirror and _environment:
  if CaptureEnvironment.synchronize(_environment,mirror.environment):_age=1000
func update()->void:
 if not enabled or not is_instance_valid(source_camera) or not is_instance_valid(viewport):return
 if _pending:return
 # Environment setters do not emit Resource.changed. Keep the small live mood
 # set current through its source tween; reuse one capture Environment/Sky.
 if CaptureEnvironment.synchronize_live(_environment,mirror.environment):_age=1000
 var camera_transform:=source_camera.global_transform
 var current_projection:=source_camera.get_camera_projection()
 var moved:=not camera_transform.is_equal_approx(_last_camera_transform) or current_projection!=_last_projection
 _age+=1
 # An old reflected eye cannot represent a moving viewer. Refresh-rate controls
 # only throttle a stationary camera; motion always gets a matched current pair.
 if not moved and _age<=interval:return
 _age=0
 _last_camera_transform=camera_transform;_last_projection=current_projection
 var eye:=camera_transform.origin
 if eye.y<.32:return
 var reflected_eye:=Vector3(eye.x,.64-eye.y,eye.z)
 var forward:Vector3=-camera_transform.basis.z
 var up:Vector3=camera_transform.basis.y
 forward.y=-forward.y;up.y=-up.y
 mirror.global_position=reflected_eye
 mirror.look_at(reflected_eye+forward,up)
 mirror.near=source_camera.near;mirror.far=source_camera.far;mirror.fov=source_camera.fov;mirror.keep_aspect=source_camera.keep_aspect
 # Match source aspect while rendering square: original copies camera projection.
 # Godot uses frustum size/offset to preserve full vertical and horizontal FOV.
 var screen_size:=source_camera.get_viewport().get_visible_rect().size
 var aspect:float=screen_size.x/maxf(1.0,screen_size.y)
 mirror.projection=Camera3D.PROJECTION_FRUSTUM
 mirror.size=2.0*mirror.near*tan(deg_to_rad(source_camera.fov)*.5)
 # A square viewport projection cannot encode a non-square aspect through size.
 # Use matching-aspect capture dimensions instead; original math is unchanged.
 viewport.size=Vector2i(resolution,maxi(1,roundi(float(resolution)/aspect)))
 mirror.projection=Camera3D.PROJECTION_PERSPECTIVE
 # Godot viewport textures are top-left-origin, unlike Three/WebGL render targets.
 var bias:=Projection(Vector4(.5,0,0,0),Vector4(0,-.5,0,0),Vector4(0,0,1,0),Vector4(.5,.5,0,1))
 _pending_matrix=bias*mirror.get_camera_projection()*Projection(mirror.global_transform.affine_inverse())
 # Godot draws child viewports before the parent. Publish the transform for
 # THIS texture update before the main water material binds it, not post-draw.
 texture_matrix=_pending_matrix
 _pending=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
func _captured()->void:
 if _pending:
  capture_ready=true;_pending=false;captures+=1
func dispose()->void:
 enabled=false
 if RenderingServer.frame_post_draw.is_connected(_captured):RenderingServer.frame_post_draw.disconnect(_captured)
 if is_instance_valid(viewport):viewport.queue_free()
 viewport=null;mirror=null;capture_ready=false;output=null
func _exit_tree()->void:dispose()
