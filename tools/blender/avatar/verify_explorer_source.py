"""Round-trip verification of the editable source, skin and original actions."""
import bpy, json, math
from pathlib import Path
P=Path(__file__).resolve().parents[3]
bpy.ops.wm.open_mainfile(filepath=str(P/'tools/blender/avatar/pool_explorer.blend'))
rig=bpy.data.objects['ExplorerRig'];scene=bpy.context.scene
required=['Idle','Walk','Run','Hold','Wade','Swim','Climb']
assert all(n in bpy.data.actions for n in required),'Native .blend lost an action'
assert all(bpy.data.actions[n].use_fake_user for n in required)
assert len(rig.data.bones)==42
assert all(b.parent is not None for b in rig.data.bones if b.name!='Root')
assert any(im.packed_file and 'reference' in im.name for im in bpy.data.images)
result={'source_roundtrip':'passed','blender':bpy.app.version_string,'actions':required,'bone_count':42,'skin':{},'deformed_bounds':{}}
for n in ['Body_Explorer','Head_Explorer']:
 o=bpy.data.objects[n];assert len([m for m in o.modifiers if m.type=='ARMATURE' and m.object==rig])==1
 sums=[sum(g.weight for g in v.groups) for v in o.data.vertices]
 assert min(sums)>.99 and max(sums)<1.01,(min(sums),max(sums))
 result['skin'][n]={'vertices':len(sums),'min_weight_sum':min(sums),'max_weight_sum':max(sums),'multiple_influence_vertices':sum(len(v.groups)>1 for v in o.data.vertices)}
for name in required:
 action=bpy.data.actions[name];rig.animation_data.action=action
 bounds=[]
 for frac in [0,.125,.25,.375,.5,.625,.75,.875,1]:
  scene.frame_set(round(action.frame_range[0]+frac*(action.frame_range[1]-action.frame_range[0])))
  deps=bpy.context.evaluated_depsgraph_get()
  coords=[]
  for n in ['Body_Explorer','Head_Explorer']:
   o=bpy.data.objects[n].evaluated_get(deps);me=o.to_mesh();coords += [o.matrix_world@v.co for v in me.vertices];o.to_mesh_clear()
  assert all(math.isfinite(c) for v in coords for c in v)
  mn=[min(v[k] for v in coords) for k in range(3)];mx=[max(v[k] for v in coords) for k in range(3)]
  bounds.append({'phase':frac,'min':mn,'max':mx})
 result['deformed_bounds'][name]=bounds
out=P/'assets/models/avatar/avatar_source_verification.json';out.write_text(json.dumps(result,indent=2));print('AVATAR_SOURCE_ROUNDTRIP '+json.dumps(result))
