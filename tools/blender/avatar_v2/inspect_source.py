import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[3]
bpy.ops.wm.open_mainfile(filepath=str(P/'tools/blender/avatar/pool_explorer.blend'))
r=bpy.data.objects['ExplorerRig'];b=bpy.data.objects['Body_Explorer']
out={'bones':{},'materials':{},'actions':{}}
for bone in r.data.bones:out['bones'][bone.name]={'head':list(bone.head_local),'tail':list(bone.tail_local),'parent':bone.parent.name if bone.parent else None,'matrix':[list(row) for row in bone.matrix_local]}
b.data.calc_loop_triangles()
for slot in b.material_slots:
 idx=slot.slot_index;verts=set(v for p in b.data.polygons if p.material_index==idx for v in p.vertices)
 out['materials'][slot.material.name]={'slot':idx,'vertices':len(verts),'triangles':sum(t.material_index==idx for t in b.data.loop_triangles),'min':[min(b.data.vertices[v].co[k] for v in verts) for k in range(3)],'max':[max(b.data.vertices[v].co[k] for v in verts) for k in range(3)]}
for a in bpy.data.actions:out['actions'][a.name]={'range':list(a.frame_range),'channels':len(a.fcurves)}
(P/'tools/blender/avatar_v2/audit/source_contract.json').write_text(json.dumps(out,indent=2))
print(json.dumps(out,indent=2))
