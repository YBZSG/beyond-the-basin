"""Reopen saved editable candidate; validate skin, topology and deformed clips.
Blender CPU only. Does not launch Godot or any GPU renderer.
"""
import bpy,bmesh,json,math,hashlib,struct
from pathlib import Path
from mathutils import Matrix,Quaternion,Vector
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=ROOT/'assets/models/avatar_v2'
bpy.ops.wm.open_mainfile(filepath=str(HERE/'pool_explorer_v2.blend'))
r=bpy.data.objects['ExplorerRig'];s=bpy.context.scene;b=bpy.data.objects['Body_Explorer'];h=bpy.data.objects['Head_Explorer']
expected=json.loads((HERE/'audit/preserved_bone_contract.json').read_text())
manifest=json.loads((OUT/'avatar_v2_manifest.json').read_text())
result={'source_roundtrip':True,'blender':bpy.app.version_string,'bones':len(r.data.bones),'topology':{},'clips':{},'grip_poses':{}}
assert len(r.data.bones)==42
for bone in r.data.bones:
 row=expected[bone.name];assert [list(x) for x in bone.matrix_local]==row['matrix'];assert (bone.parent.name if bone.parent else None)==row['parent']
assert set(a.name for a in bpy.data.actions)==set(manifest['animations'])
assert all(a.use_fake_user for a in bpy.data.actions)
assert any(im.packed_file and 'reference' in im.name for im in bpy.data.images)
for ob in [b,h]:
 assert len([m for m in ob.modifiers if m.type=='ARMATURE' and m.object==r])==1
 for v in ob.data.vertices:
  assert abs(sum(x.weight for x in v.groups)-1)<1e-5;assert len(v.groups)<=4
# Isolate the two actual authored skin arms and assert closed two-component union.
mat_index=next(i for i,m in enumerate(b.data.materials) if m and 'anatomical skin' in m.name)
bm=bmesh.new();bm.from_mesh(b.data)
region=bm.verts.layers.int.get('V2_SurfaceRegion');assert region is not None
remove=[f for f in bm.faces if f.material_index!=mat_index or not all(v[region]==1 for v in f.verts)]
bmesh.ops.delete(bm,geom=remove,context='FACES');bm.verts.ensure_lookup_table()
loose=[v for v in bm.verts if not v.link_faces]
if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
components=[];pending=set(bm.verts)
while pending:
 seed=pending.pop();stack=[seed];comp={seed}
 while stack:
  v=stack.pop()
  for e in v.link_edges:
   other=e.other_vert(v)
   if other in pending:pending.remove(other);comp.add(other);stack.append(other)
 components.append(len(comp))
boundaries=sum(e.is_boundary for e in bm.edges);nonmanifold=sum(not e.is_manifold for e in bm.edges)
result['topology']={'arm_components':sorted(components),'boundary_edges':boundaries,'nonmanifold_edges':nonmanifold}
assert len(components)==2,(components,'Detached new skin surface')
assert boundaries==0 and nonmanifold==0
bm.free()
# New hands may use Hand/Forearm and one single digit branch, never a neighbour.
usedverts=set(v for p in b.data.polygons if p.material_index==mat_index for v in p.vertices if b.data.attributes['V2_SurfaceRegion'].data[v].value==1)
for vi in usedverts:
 fingers=set()
 for g in b.data.vertices[vi].groups:
  name=b.vertex_groups[g.group].name
  for digit in ['Index','Middle','Ring','Little','Thumb']:
   if name.startswith(digit):fingers.add(digit)
 assert len(fingers)<=1,(vi,fingers)
result['topology']['cross_digit_weight_vertices']=0

def bounds():
 dep=bpy.context.evaluated_depsgraph_get();coords=[]
 for ob in [b,h]:
  ev=ob.evaluated_get(dep);me=ev.to_mesh();coords.extend(ob.matrix_world@v.co for v in me.vertices);ev.to_mesh_clear()
 assert all(math.isfinite(c) for p in coords for c in p)
 mn=[min(p[k] for p in coords) for k in range(3)];mx=[max(p[k] for p in coords) for k in range(3)]
 assert max(mx[k]-mn[k] for k in range(3))<3
 return {'min':mn,'max':mx}
for a in bpy.data.actions:
 r.animation_data.action=a;rows=[]
 for frac in [0,.125,.25,.375,.5,.625,.75,.875,1.]:
  s.frame_set(round(a.frame_range[1]*frac));rows.append({'phase':frac,**bounds()})
 result['clips'][a.name]=rows
r.animation_data.action=None
for name,pose in json.loads((OUT/'grip_poses.json').read_text())['poses'].items():
 for pb in r.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 for bone,row in pose.items():r.pose.bones[bone].rotation_quaternion=Quaternion(row['quaternion_wxyz'])
 bpy.context.view_layer.update();result['grip_poses'][name]=bounds()
result['glb_sha256']=manifest['glb_sha256'];result['blend_sha256']=manifest['blend_sha256'];result['passed']=True
(HERE/'audit/source_verification.json').write_text(json.dumps(result,indent=2));print('SOURCE_V2_CHECK_PASSED '+json.dumps({k:v for k,v in result.items() if k not in ['clips','grip_poses']}))
