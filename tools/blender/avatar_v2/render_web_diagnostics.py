"""Isolate which finger tracks cause the carry-web fold; CPU-only audit."""
from pathlib import Path
here=Path(__file__).resolve().parent
exec((here/'render_audit.py').read_text().split("for candidate,path in ")[0])
s,r,c=setup(HERE/'pool_explorer_v2.blend')
W=r.data.bones['Hand_L'].head_local;K=r.data.bones['Middle1_L'].head_local;L=(K-W).normalized();D=Vector((1,0,0));D=(D-L*D.dot(L)).normalized();R=D.cross(L).normalized();center=W+L*.075
original=bpy.data.objects['Body_Explorer'];arm=original.copy();arm.data=original.data.copy();s.collection.objects.link(arm)
bm=bmesh.new();bm.from_mesh(arm.data);bmesh.ops.delete(bm,geom=[v for v in bm.verts if not(v.co.x>.27 and v.co.z<1.18)],context='VERTS');bm.to_mesh(arm.data);bm.free();original.hide_render=True;bpy.data.objects['Head_Explorer'].hide_render=True
library=json.loads((ROOT/'assets/models/avatar_v2/grip_poses.json').read_text())
for name,disabled in [('thumb_static',['Thumb1','Thumb2']),('thumb_root_static',['Thumb1']),('index_static',['Index1','Index2']),('index_root_static',['Index1'])]:
 for p in r.pose.bones:p.matrix_basis=Matrix.Identity(4)
 for bone,row in library['poses']['carry_large'].items():
  if any(bone.startswith(x) for x in disabled):continue
  r.pose.bones[bone].rotation_quaternion=Quaternion(row['quaternion_wxyz'])
 bpy.context.view_layer.update()
 shoot(s,c,'diagnostic_'+name,center+D*.65+R*.45,center,.265)
