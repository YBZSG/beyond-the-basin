"""Read-only reopen proof: source mesh/binds/old actions exact, authored keys editable."""
import bpy,hashlib,json,struct
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]

def digest(values):return hashlib.sha256(json.dumps(values,separators=(',',':')).encode()).hexdigest()
def capture(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));r=next(o for o in bpy.data.objects if o.type=='ARMATURE')
 meshes={}
 for o in bpy.data.objects:
  if o.type!='MESH':continue
  m=o.data
  meshes[o.name]=digest(dict(vertices=[list(v.co) for v in m.vertices],polygons=[list(p.vertices) for p in m.polygons],
   groups=[[(g.group,g.weight) for g in v.groups] for v in m.vertices],uv={u.name:[list(v.uv) for v in u.data] for u in m.uv_layers},
   materials=[v.name if v else None for v in m.materials],material_ids=[p.material_index for p in m.polygons]))
 bones=digest({b.name:[b.parent.name if b.parent else None,[list(x) for x in b.matrix_local]] for b in r.data.bones})
 actions={a.name:digest([(f.data_path,f.array_index,[(list(k.co),k.interpolation,list(k.handle_left),list(k.handle_right)) for k in f.keyframe_points]) for f in a.fcurves]) for a in bpy.data.actions}
 return dict(meshes=meshes,bones=bones,actions=actions)
base=capture(ROOT/'tools/blender/water_hands/pool_explorer_water_hands.blend')
final=capture(HERE/'explorer_water_motion.blend')
assert base['meshes']==final['meshes'],'Saved mesh/UV/skin/material data changed'
assert base['bones']==final['bones'],'Saved rest rig changed'
preserved=['Idle','Walk','Run','Hold','Climb']
assert all(base['actions'][n]==final['actions'][n] for n in preserved)
new=['Wade','Swim','SwimIdle','JumpRise','JumpAir','Land','ThrowCharge','ThrowRelease','ThrowRecover']
assert all(n in final['actions'] for n in new)
release=bpy.data.actions['ThrowRelease'];assert release.pose_markers['RELEASE'].frame==0
result=dict(passed=True,mesh_uv_skin_material_hashes=final['meshes'],rest_rig_hash=final['bones'],preserved_actions_exact=preserved,
 authored_actions=new,action_count=len(final['actions']),release_marker_frame=0,editable_fcurve_counts={n:len(bpy.data.actions[n].fcurves) for n in new})
(HERE/'saved_source_validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
