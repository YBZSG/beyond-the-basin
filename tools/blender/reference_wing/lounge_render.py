"""Bounded CPU camera render; run only after the shared render slot is approved."""
import bpy,os,json,time,hashlib
root=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../..'))
out=os.path.join(root,'output/reference_wing/lounge');os.makedirs(out,exist_ok=True)
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=64;s.cycles.use_denoising=False;s.render.threads_mode='FIXED';s.render.threads=4
for ob in s.objects:
 if ob.type=='LIGHT' and ob.name in ['Warm_entrance_bounce','Soft_camera_fill']:ob.hide_render=True
s.render.filepath=os.path.join(out,'reference4_lounge_preview.png');start=time.time();bpy.ops.render.render(write_still=True)
with open(os.path.join(out,'render_report.json'),'w') as f:json.dump({'renderer':'Blender Cycles CPU','samples':s.cycles.samples,'resolution':[s.render.resolution_x,s.render.resolution_y],'elapsed_seconds':time.time()-start,'camera':s.camera.name,'is_godot_runtime_capture':False,'denoising':False,'preview_only_fill_lights_excluded':True,'source_blend_sha256':hashlib.sha256(open(bpy.data.filepath,'rb').read()).hexdigest(),'glb_sha256':hashlib.sha256(open(os.path.join(root,'assets/models/reference_wing/ball_lounge.glb'),'rb').read()).hexdigest()},f,indent=2)
