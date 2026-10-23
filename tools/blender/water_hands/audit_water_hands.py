"""Bounded CPU-only posed skin audit and small hand-only renders. No scene render."""
import bpy,bmesh,json,math,os
from pathlib import Path
import numpy as np
from mathutils import Vector,Matrix,Quaternion
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=ROOT/'assets/water_hands'
bpy.ops.wm.open_mainfile(filepath=str(HERE/'pool_explorer_water_hands.blend'))
rig=bpy.data.objects['ExplorerRig'];rig.animation_data.action=None
for tr in rig.animation_data.nla_tracks:tr.mute=True
for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
SIDE=os.environ.get('HAND_AUDIT_SIDE','L');RENDER=os.environ.get('HAND_AUDIT_RENDER','1')=='1'
contract=json.loads((OUT/'hand_pose_contract.json').read_text());body=bpy.data.objects['Body_Explorer'];scene=bpy.context.scene
for o in list(bpy.data.objects):
 if o!=body and o!=rig:bpy.data.objects.remove(o,do_unlink=True)
# Isolate LEFT original hand surface without altering saved source.
bm=bmesh.new();bm.from_mesh(body.data);bm.verts.ensure_lookup_table();slots={i for i,m in enumerate(body.data.materials) if 'anatomical skin' in m.name}
bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index not in slots or f.calc_center_median().x*(1 if SIDE=='L' else -1)<0],context='FACES')
loose=[v for v in bm.verts if not v.link_faces]
if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
bm.to_mesh(body.data);bm.free();body.data.update()
rest=np.array([v.co[:] for v in body.data.vertices]);edges=np.array([e.vertices[:] for e in body.data.edges]);edge_len=np.linalg.norm(rest[edges[:,0]]-rest[edges[:,1]],axis=1);valid=edge_len>1e-6
W=np.array(contract['hand_geometry'][SIDE]['wrist']);L=np.array(contract['hand_geometry'][SIDE]['long_axis']);D=np.array(contract['hand_geometry'][SIDE]['dorsal_axis']);R=np.array(contract['hand_geometry'][SIDE]['radial_axis']);local=(rest-W)@np.stack([R,L,D],axis=1)
tri=np.array([p.vertices[:] for p in body.data.polygons]);rest_area=np.linalg.norm(np.cross(rest[tri[:,1]]-rest[tri[:,0]],rest[tri[:,2]]-rest[tri[:,0]]),axis=1)/2;facegood=rest_area>1e-10
thumbweb=(local[:,0]>.015)&(local[:,0]<.04)&(local[:,1]>.025)&(local[:,1]<.075)
webedges=thumbweb[edges].all(1)&valid
results={}
def set_pose(name,wrist_degrees=0,support=True):
 for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
 for bone,data in contract['poses'][name].items():
  pb=rig.pose.bones[bone];pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion(data['quaternion_wxyz'])
 if wrist_degrees:
  b=rig.data.bones['Hand_'+SIDE];axis=(Vector(L).cross(-Vector(D))).normalized();ax=b.matrix_local.to_3x3().inverted()@axis;q=Quaternion(ax,math.radians(wrist_degrees));rig.pose.bones['Hand_'+SIDE].rotation_quaternion=q
  if support:rig.pose.bones['WristSupport_'+SIDE].rotation_quaternion=Quaternion().slerp(q,.5)
 bpy.context.view_layer.update()
def coords():
 deps=bpy.context.evaluated_depsgraph_get();e=body.evaluated_get(deps);mesh=e.to_mesh();co=np.array([v.co[:] for v in mesh.vertices]);e.to_mesh_clear();return co
for name in ['neutral','relaxed','carry','release','swim']:
 set_pose(name);co=coords();ratios=np.linalg.norm(co[edges[:,0]]-co[edges[:,1]],axis=1)[valid]/edge_len[valid];areas=np.linalg.norm(np.cross(co[tri[:,1]]-co[tri[:,0]],co[tri[:,2]]-co[tri[:,0]]),axis=1)/2
 results[name]={'finite':bool(np.isfinite(co).all()),'edge_length_ratio_p01_p50_p99':np.quantile(ratios,[.01,.5,.99]).tolist(),'edge_length_ratio_min_max':[float(ratios.min()),float(ratios.max())],'triangle_area_ratio_p01_p50_p99':np.quantile(areas[facegood]/rest_area[facegood],[.01,.5,.99]).tolist(),'thumb_web_edge_ratio_p01_p99':np.quantile(np.linalg.norm(co[edges[:,0]]-co[edges[:,1]],axis=1)[webedges]/edge_len[webedges],[.01,.99]).tolist(),'max_vertex_displacement_m':float(np.linalg.norm(co-rest,axis=1).max())}
 assert results[name]['finite'] and results[name]['edge_length_ratio_min_max'][0]>.35,(name,'collapsed skin')
# Test real wrist support rather than merely counting extra bones. Mid-wrist band
# covariance measures cross-sectional area independent of global wrist rotation.
band=(local[:,1]>-.010)&(local[:,1]<.004)
def area_metric(co):
 p=co[band];sv=np.linalg.svd(p-p.mean(0),compute_uv=False);return float(sv[0]*sv[1])
base_area=area_metric(rest)
for angle in [45,70]:
 set_pose('carry',angle,True);correct=coords();set_pose('carry',angle,False);inert=coords()
 results['wrist_'+str(angle)]={'weighted_support_area_ratio':area_metric(correct)/base_area,'inert_support_area_ratio':area_metric(inert)/base_area,'support_motion_max_m':float(np.linalg.norm(correct-inert,axis=1).max()),'support_radians':math.radians(angle)*.5}
 assert results['wrist_'+str(angle)]['support_motion_max_m']>.005
(HERE/('posed_skin_audit'+('' if SIDE=='L' else '_R')+'.json')).write_text(json.dumps(results,indent=2)+'\n');print('POSE_AUDIT '+json.dumps(results))
if not RENDER:raise SystemExit(0)
# Small isolated hand images on CPU, never GPU or full scene.
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16;scene.cycles.use_denoising=False;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=340;scene.render.resolution_y=440;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.15,.17,.18,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
scene.view_settings.view_transform='AgX'
center=Vector(W)+Vector(L)*.068
camdata=bpy.data.cameras.new('Hand audit camera');cam=bpy.data.objects.new('Hand audit camera',camdata);scene.collection.objects.link(cam);scene.camera=cam;camdata.type='ORTHO';camdata.ortho_scale=.275
for label,delta,energy,size in [('key',-Vector(D)*.4+Vector(R)*.35-Vector(L)*.2,8,.35),('fill',Vector(D)*.2-Vector(R)*.3,4,.3)]:
 data=bpy.data.lights.new(label,'AREA');o=bpy.data.objects.new(label,data);scene.collection.objects.link(o);o.location=center+delta;o.rotation_euler=(center-o.location).to_track_quat('-Z','Y').to_euler();data.energy=energy;data.shape='DISK';data.size=size
for pose,view,wrist in [('neutral','palm',0),('relaxed','palm',0),('carry','palm',0),('release','palm',0),('swim','palm',0),('carry','wrist',45),('relaxed','back',0)]:
 set_pose(pose,wrist)
 offset=(-Vector(D)*.6+Vector(R)*.12) if view!='back' else (Vector(D)*.6+Vector(R)*.08)
 if view=='wrist':offset=-Vector(D)*.38+Vector(R)*.5
 cam.location=center+offset;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(HERE/(pose+'_'+view+'.png'));bpy.ops.render.render(write_still=True)
print('HAND_CPU_RENDERS_COMPLETE')
