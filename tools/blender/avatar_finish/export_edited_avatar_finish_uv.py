"""Export ONLY edited FabricMeters UVs from the saved UV-source .blend.

blender -b -t 2 --python tools/blender/avatar_finish/export_edited_avatar_finish_uv.py

Writes avatar_finish_candidate_edited.glb, never overwrites the frozen V2 or the
reviewed dry candidate. Any geometry/topology/object-transform edit is rejected.
All skin, clips, normals and original UV0 come from the immutable source GLB.
"""
from pathlib import Path
import sys,json,hashlib
HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(HERE))
import bpy,numpy as np
from avatar_finish_glb import GLB,CLOTH,FROZEN_SHA,uv_metrics
ROOT=HERE.parents[2]
source=GLB(ROOT/'assets/models/avatar_v2/pool_explorer_v2.glb')
assert hashlib.sha256(source.raw).hexdigest()==FROZEN_SHA
bpy.ops.wm.open_mainfile(filepath=str(HERE/'avatar_finish_candidate_uv_source.blend'))
report={}
for index,profile in CLOTH.items():
    primitive=source.j['meshes'][0]['primitives'][index]
    attrs={name:source.acc(accessor) for name,accessor in primitive['attributes'].items()}
    triangles=source.acc(primitive['indices']).reshape(-1,3)
    obj=bpy.data.objects[profile+'_UV_editing_source'];mesh=obj.data
    assert np.array_equal(np.array([v.co[:] for v in mesh.vertices],dtype='<f4'),attrs['POSITION']),profile+' geometry was edited'
    assert np.array_equal(np.array([p.vertices[:] for p in mesh.polygons]),triangles),profile+' topology was edited'
    assert np.allclose(np.array(obj.matrix_world),np.eye(4),atol=1e-12),profile+' object transform was edited'
    assert not obj.modifiers,profile+' has a modifier'
    for p in mesh.polygons:p.use_smooth=True
    mesh.normals_split_custom_set_from_vertices(attrs['NORMAL'].tolist())
    mesh.calc_tangents(uvmap='FabricMeters');uv=mesh.uv_layers['FabricMeters']
    lookup={};old_ids=[];uvs=[];tangents=[];indices=[]
    for loop in mesh.loops:
        co=np.array(uv.data[loop.index].uv[:],dtype='<f4');co[1]=1.0-co[1]
        tangent=np.array((*loop.tangent[:],loop.bitangent_sign),dtype='<f4')
        normal=attrs['NORMAL'][loop.vertex_index].astype(float);direction=tangent[:3].astype(float)
        direction-=normal*np.dot(normal,direction);direction/=np.linalg.norm(direction);tangent[:3]=direction
        key=(loop.vertex_index,co.tobytes(),tangent.tobytes())
        if key not in lookup:
            lookup[key]=len(old_ids);old_ids.append(loop.vertex_index);uvs.append(co);tangents.append(tangent)
        indices.append(lookup[key])
    for name,accessor in list(primitive['attributes'].items()):
        a=source.j['accessors'][accessor]
        primitive['attributes'][name]=source.append(attrs[name][old_ids],a['type'],a['componentType'],a,with_bounds=name=='POSITION')
    primitive['attributes']['TEXCOORD_1']=source.append(uvs,'VEC2')
    primitive['attributes']['TANGENT']=source.append(tangents,'VEC4')
    primitive['indices']=source.append(indices,'SCALAR',5125)
    metric=uv_metrics(source,primitive,'TEXCOORD_1')
    assert metric['degenerate_uv_triangles']==0,(profile,'degenerate UV')
    assert metric['area_anisotropy_over_3']<.0001,(profile,'UV stretch exceeds candidate bound')
    for axis in ['m_per_u_p05_p50_p95','m_per_v_p05_p50_p95']:
        assert .8<metric[axis][0] and metric[axis][2]<1.25,(profile,'metre scale exceeds candidate bound')
    report[profile]=metric
source.j.setdefault('extras',{})['avatar_finish_candidate']=dict(source_sha256=FROZEN_SHA,cloth_uv='Edited FabricMeters; TEXCOORD_1 metres; exact frozen geometry and original UV0')
out=HERE/'audit/avatar_finish_candidate_edited.glb';source.save(out)
report.update(output=str(out.relative_to(ROOT)),sha256=hashlib.sha256(out.read_bytes()).hexdigest(),source_blend_sha256=hashlib.sha256((HERE/'avatar_finish_candidate_uv_source.blend').read_bytes()).hexdigest())
(HERE/'audit/avatar_finish_candidate_edited_export.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
