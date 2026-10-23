"""CPU-only Blender UV/tangent build. Never renders or re-exports a rig.

The frozen GLB remains the authoritative geometry/skin/animation container.
Only shirt/trouser per-corner UV2 and MikkTSpace tangents are appended, with
necessary seam vertex splits. UV0/albedo, all geometry values and animation
accessors stay byte-exact. The .blend is a cloth UV editing source, not a rig
replacement. Coordinates in that editing source are glTF metres, Y-up.

blender -b -t 2 --python tools/blender/avatar_finish/build_avatar_finish_candidate.py
"""
from __future__ import annotations
import sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import bpy
import json
import hashlib
import numpy as np
from avatar_finish_glb import GLB,CLOTH,FROZEN_SHA,uv_metrics
ROOT=HERE.parents[2]
OUT=ROOT/'assets/textures/avatar_finish'
AUDIT=HERE/'audit'
SOURCE=ROOT/'assets/models/avatar_v2/pool_explorer_v2.glb'
DEST=OUT/'avatar_finish_candidate.glb'


def components(vertex_count,triangles):
    parent=np.arange(vertex_count)
    def find(x):
        while parent[x]!=x:
            parent[x]=parent[parent[x]];x=parent[x]
        return x
    for t in triangles:
        a=find(int(t[0]))
        for v in t[1:]:
            b=find(int(v))
            if a!=b:parent[b]=a
    roots=np.array([find(i) for i in range(vertex_count)])
    _,labels=np.unique(roots,return_inverse=True)
    return labels


def add_editing_material(obj, profile):
    material=bpy.data.materials.new(profile+' | editable dry cloth finish')
    material.use_nodes=True;nodes=material.node_tree.nodes;links=material.node_tree.links
    bsdf=nodes.get('Principled BSDF');bsdf.inputs['Specular IOR Level'].default_value=2*(.30 if profile=='shirt_plain' else .50)**2
    original_uv=nodes.new('ShaderNodeUVMap');original_uv.uv_map='UVMap'
    meter_uv=nodes.new('ShaderNodeUVMap');meter_uv.uv_map='FabricMeters'
    scale=nodes.new('ShaderNodeVectorMath');scale.operation='SCALE'
    scale.inputs[3].default_value=1.0/(.0224 if profile=='shirt_plain' else .0256)
    links.new(meter_uv.outputs['UV'],scale.inputs[0])
    old_name='shirt' if profile=='shirt_plain' else 'pants'
    base=nodes.new('ShaderNodeTexImage')
    base.image=bpy.data.images.load(str(ROOT/f'assets/models/avatar_v2/pool_explorer_v2_explorer_{old_name}_weave.png'),check_existing=True)
    base.image.pack();links.new(original_uv.outputs['UV'],base.inputs['Vector']);links.new(base.outputs['Color'],bsdf.inputs['Base Color'])
    for suffix in ['normal','roughness']:
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/f'{profile}_{suffix}.png'),check_existing=True)
        tex.image.colorspace_settings.name='Non-Color';tex.image.pack();links.new(scale.outputs['Vector'],tex.inputs['Vector'])
        if suffix=='normal':
            normal=nodes.new('ShaderNodeNormalMap');normal.uv_map='FabricMeters'
            links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
        else:links.new(tex.outputs['Color'],bsdf.inputs['Roughness'])
    obj.data.materials.append(material)


def unwrap_surface(glb,index,profile):
    primitive=glb.j['meshes'][0]['primitives'][index]
    attrs={k:glb.acc(v) for k,v in primitive['attributes'].items()}
    pos=attrs['POSITION'];norm=attrs['NORMAL'];tri=glb.acc(primitive['indices']).reshape(-1,3).astype(int)
    labels=components(len(pos),tri)
    mesh=bpy.data.meshes.new(profile+'_meter_cloth_mesh')
    mesh.from_pydata(pos.tolist(),[],tri.tolist());mesh.update()
    obj=bpy.data.objects.new(profile+'_UV_editing_source',mesh)
    bpy.context.collection.objects.link(obj)
    obj['source_glb_sha256']=FROZEN_SHA
    obj['coordinate_system']='Exact GLB metres, Y-up. No geometry modification.'
    obj['uv_contract']='UVMap is original albedo; FabricMeters is cloth-only, 1 UV unit = 1 m.'
    mesh.uv_layers.new(name='UVMap')
    original_uv=mesh.uv_layers.active
    for loop in mesh.loops:
        old_uv=attrs['TEXCOORD_0'][loop.vertex_index]
        original_uv.data[loop.index].uv=(old_uv[0],1.0-old_uv[1])
    mesh.uv_layers.new(name='FabricMeters');mesh.uv_layers.active_index=1
    add_editing_material(obj,profile)
    for poly in mesh.polygons:poly.use_smooth=True
    mesh.normals_split_custom_set_from_vertices(norm.tolist())
    centers=np.array([p.center[:] for p in mesh.polygons])
    # Mark garment construction seams on existing edges, no topology/positions
    # are remeshed. Main panels follow front/back side seams. Trousers also use
    # rise/inseams; sleeves are cut at their shoulder attachment.
    face_labels=[];component_centers={};component_axes={}
    for c in np.unique(labels):
        pp=pos[labels==c].astype(float);component_centers[c]=pp.mean(0)
        _,_,vt=np.linalg.svd(pp-pp.mean(0),full_matrices=False)
        component_axes[c]=vt[-1]
    biggest=int(np.bincount(labels).argmax())
    for face,ids in zip(mesh.polygons,tri):
        c=int(labels[ids[0]]);q=np.array(face.center[:]);normal=np.array(face.normal[:])
        if c==biggest:
            side=int(q[2]>=0)
            if index==0:
                part=1 if q[0]>.185 else (2 if q[0]<-.185 else 0)
                cap=3 if q[1]<.982 and abs(normal[1])>.7 else (4 if q[1]>1.445 and normal[1]>.6 else 0)
            else:
                part=int(q[0]>=0)
                cap=3 if q[1]<.105 and normal[1]<-.7 else (4 if q[1]>.98 and normal[1]>.7 else 0)
            face_labels.append((c,part,side,cap))
        else:
            side=int(np.dot(q-component_centers[c],component_axes[c])>=0)
            face_labels.append((c,side))
    edge_faces={}
    for p in mesh.polygons:
        for edge_key in p.edge_keys:edge_faces.setdefault(tuple(sorted(edge_key)),[]).append(p.index)
    seam_count=0
    for e in mesh.edges:
        fs=edge_faces.get(tuple(sorted(e.vertices)),[])
        e.use_seam=len(fs)!=2 or face_labels[fs[0]]!=face_labels[fs[1]]
        seam_count+=int(e.use_seam)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.unwrap(method='ANGLE_BASED',fill_holes=True,correct_aspect=False,use_subsurf_data=False,margin=.001)
    bpy.ops.object.mode_set(mode='OBJECT')
    # Edge-connected charts. Normalize EACH chart by physical surface area,
    # then orient its grain along the panel's long garment direction. No atlas
    # packing rescale is used: these are repeating metrically-scaled UVs.
    parent=list(range(len(mesh.polygons)))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for e in mesh.edges:
        fs=edge_faces.get(tuple(sorted(e.vertices)),[])
        if not e.use_seam and len(fs)==2:
            a,b=map(find,fs)
            if a!=b:parent[b]=a
    charts={}
    for p in mesh.polygons:charts.setdefault(find(p.index),[]).append(p.index)
    uv=mesh.uv_layers['FabricMeters'];chart_info=[]
    for chart_id,faces in enumerate(charts.values()):
        loops=np.array([li for fi in faces for li in mesh.polygons[fi].loop_indices])
        coords=np.array([uv.data[int(li)].uv[:] for li in loops],float)
        pts=np.array([pos[mesh.loops[int(li)].vertex_index] for li in loops],float)
        uv_tris=coords.reshape(-1,3,2)
        e1=uv_tris[:,1]-uv_tris[:,0];e2=uv_tris[:,2]-uv_tris[:,0]
        uarea=float(np.abs(e1[:,0]*e2[:,1]-e1[:,1]*e2[:,0]).sum()/2)
        parea=sum(mesh.polygons[fi].area for fi in faces)
        assert uarea>1e-16 and parea>0,(profile,chart_id,'empty chart')
        coords-=coords.mean(0)
        grain=(pts[:,1]-pts[:,1].mean())@coords
        # When height has little range (caps), align the broad X direction.
        if np.linalg.norm(grain)<1e-8:grain=(pts[:,0]-pts[:,0].mean())@coords
        theta=np.pi/2-np.arctan2(grain[1],grain[0])
        rot=np.array([[np.cos(theta),-np.sin(theta)],[np.sin(theta),np.cos(theta)]])
        coords=coords@rot.T*np.sqrt(parea/uarea)
        coords-=coords.min(0)
        coords+=np.array([(chart_id%4)*1.2,(chart_id//4)*1.3])
        for li,co in zip(loops,coords):uv.data[int(li)].uv=co
        chart_info.append(dict(chart=chart_id,triangles=len(faces),area_m2=parea,normalization_m_per_uv=1.0))
    mesh.update()
    mesh.normals_split_custom_set_from_vertices(norm.tolist())
    mesh.calc_tangents(uvmap='FabricMeters')
    uv=mesh.uv_layers['FabricMeters'] # Reacquire after tangent custom-data allocation.
    # Split only where the authored per-corner UV/tangent tuple requires it.
    # Original attributes are copied by source vertex ID, never recomputed.
    lookup={};old_ids=[];new_uv=[];new_t=[];new_indices=[]
    for loop in mesh.loops:
        uvv=np.array(uv.data[loop.index].uv[:],dtype='<f4')
        # Match Blender's glTF exporter: flip UV V, but NOT tangent handedness.
        # Normal maps remain OpenGL +Y. Positions already are glTF Y-up.
        uvv[1]=1.0-uvv[1]
        tangent=np.array((*loop.tangent[:],loop.bitangent_sign),dtype='<f4')
        # Blender internally quantizes custom normals. Orthogonalize its Mikk
        # tangent to the exact frozen normal, without modifying that normal.
        authoritative_normal=norm[loop.vertex_index].astype(float)
        direction=tangent[:3].astype(float)
        direction-=authoritative_normal*np.dot(authoritative_normal,direction)
        direction/=np.linalg.norm(direction)
        tangent[:3]=direction
        key=(loop.vertex_index,uvv.tobytes(),tangent.tobytes())
        if key not in lookup:
            lookup[key]=len(old_ids);old_ids.append(loop.vertex_index);new_uv.append(uvv);new_t.append(tangent)
        new_indices.append(lookup[key])
    old_ids=np.array(old_ids,dtype=int)
    for name,oldacc in list(primitive['attributes'].items()):
        a=glb.j['accessors'][oldacc]
        primitive['attributes'][name]=glb.append(attrs[name][old_ids],a['type'],a['componentType'],a,with_bounds=name=='POSITION')
    primitive['attributes']['TEXCOORD_1']=glb.append(new_uv,'VEC2')
    primitive['attributes']['TANGENT']=glb.append(new_t,'VEC4')
    primitive['indices']=glb.append(new_indices,'SCALAR',5125)
    # This source-to-output map is validation evidence, not a runtime dependency.
    np.savez_compressed(AUDIT/f'{profile}_vertex_provenance.npz',source_vertex=old_ids)
    return dict(material=glb.j['materials'][primitive['material']]['name'],
                source_vertices=len(pos),candidate_vertices=len(old_ids),
                seam_edges=seam_count,charts=chart_info,
                metric=uv_metrics(glb,primitive,'TEXCOORD_1'))


def main():
    glb=GLB(SOURCE);assert hashlib.sha256(glb.raw).hexdigest()==FROZEN_SHA
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    OUT.mkdir(parents=True,exist_ok=True);AUDIT.mkdir(parents=True,exist_ok=True)
    report=dict(source=SOURCE.relative_to(ROOT).as_posix(),source_sha256=FROZEN_SHA,
                modifications='Cloth-only TEXCOORD_1 + MikkTSpace tangent and seam vertex splits. Original attributes copied exactly.',
                original_uv={},candidate_uv={})
    for index,profile in CLOTH.items():
        report['original_uv'][profile]=uv_metrics(glb,glb.j['meshes'][0]['primitives'][index])
        report['candidate_uv'][profile]=unwrap_surface(glb,index,profile)
    glb.j.setdefault('extras',{})['avatar_finish_candidate']=dict(source_sha256=FROZEN_SHA,cloth_uv='TEXCOORD_1; metres; all other surfaces unchanged')
    glb.save(DEST)
    report['candidate_sha256']=hashlib.sha256(DEST.read_bytes()).hexdigest()
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'avatar_finish_candidate_uv_source.blend'),compress=True)
    (AUDIT/'avatar_finish_candidate_uv_build.json').write_text(json.dumps(report,indent=2)+'\n')
    print('AVATAR_FINISH_CANDIDATE_UV_BUILD '+json.dumps(report,indent=2))

if __name__=='__main__':main()
