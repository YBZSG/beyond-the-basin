"""A separate, reproducible near-wall material camera; never a player spawn."""
import bpy,math
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
NAME='DIAGNOSTIC_RightWall_10cm_Grid'
def p(v):return(v[0],-v[2],v[1])
def g(v):return(v[0],v[2],-v[1])
def add_diagnostic_camera():
 scene=bpy.context.scene;reference=scene.camera;oldres=(scene.render.resolution_x,scene.render.resolution_y)
 eye=Vector((2.3,7.0,4.0));fixture='CeilingStrip_R0_02_Lens';ob=bpy.data.objects[fixture];vs=[Vector(g(ob.matrix_world@v.co)) for v in ob.data.vertices]
 source=Vector(((min(v.x for v in vs)+max(v.x for v in vs))/2,min(v.y for v in vs),(min(v.z for v in vs)+max(v.z for v in vs))/2))
 virtual=Vector((5.8-source.x,source.y,source.z));t=(2.9-eye.x)/(virtual.x-eye.x);target=eye+(virtual-eye)*t
 cam=bpy.data.objects.get(NAME)
 if cam is None:
  data=bpy.data.cameras.new(NAME);cam=bpy.data.objects.new(NAME,data);scene.collection.objects.link(cam)
 cam.location=p(eye);cam.rotation_euler=(Vector(p(target))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='PERSP';cam.data.sensor_fit='VERTICAL';cam.data.sensor_height=24;cam.data.sensor_width=36;cam.data.lens=24/(2*math.tan(math.radians(40)/2))
 scene.render.resolution_x=640;scene.render.resolution_y=640;scene.camera=cam;bpy.context.view_layer.update()
 frame=cam.data.view_frame(scene=scene);v=[math.atan2(q.y,-q.z) for q in frame];h=[math.atan2(q.x,-q.z) for q in frame]
 def px(q):
  c=world_to_camera_view(scene,cam,Vector(p(q)));return[c.x*640,(1-c.y)*640]
 centre_px=px(target);assert max(abs(v-320) for v in centre_px)<.01,('Diagnostic target is not centred',centre_px)
 tile=[px((2.9,target.y+dy,target.z+dz)) for dy,dz in [(-.05,-.05),(-.05,.05),(.05,.05),(.05,-.05)]]
 dist=lambda a,b:sum((a[i]-b[i])**2 for i in [0,1])**.5
 view={'id':'stair_right_wall_10cm_grid','camera_name':NAME,'diagnostic_only':True,'not_a_spawn':True,'from':list(eye),'toward':list(target),'fov_degrees':math.degrees(max(v)-min(v)),'fov_axis':'vertical','horizontal_fov_degrees':math.degrees(max(h)-min(h)),'reference_resolution':[640,640],'reference_pixel_aspect':[1,1],'lens_mm':cam.data.lens,'sensor_fit':'VERTICAL','source_fixture':fixture,'actual_lens_emitting_face_center':list(source),'mirrored_source_center':list(virtual),'target_method':'Analytic reflection of actual lens centre across right wall x=2.9, intersected by the eye-to-virtual-source ray. No guessed highlight target.','target_projected_px':centre_px,'projection_matrix_updated_and_center_checked':True,'wall_tile_pitch_metres':.1,'meter_scale_note':'Each ceramic grid cell is 0.10 m; ten cells span 1 m. Wall geometry, lights, material and exposure are unchanged.','wall_tile_at_target_projected_px':{'corners':tile,'along_corridor':dist(tile[0],tile[1]),'vertical':dist(tile[1],tile[2])},'optional_filter_enabled':False,'native_godot_validation':False}
 cam['diagnostic_contract']=str(view);scene.camera=reference;scene.render.resolution_x,scene.render.resolution_y=oldres
 return cam,view
