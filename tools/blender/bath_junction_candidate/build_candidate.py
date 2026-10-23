"""Build a review-only continuous bath plaster wall from the shipped editable scene.

blender -b -t 2 --disable-autoexec --factory-startup --python \
  tools/blender/bath_junction_candidate/build_candidate.py

Only candidate directories are written. Existing collision proxies and unrelated
meshes are loaded, never regenerated. A separate GLB splicer preserves their
original serialized bytes. This file also provides make_continuous_wall() for a
reviewable future production-generator integration.
"""
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
import bmesh

ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT/'assets/models/bath_junction_candidate'
DOC = ROOT/'docs/bath-junction-candidate'
SOURCE = ROOT/'tools/blender/source/formal_bath.blend'
BLEND = ROOT/'tools/blender/bath_junction_candidate/formal_bath_continuous_wall.blend'
TARGETS = {'Bath_Wall', 'Bath_UpperDrum'}


def signature(ob):
    """Exact source-semantic witness; no quantization and no unsafe scene execution."""
    if ob.type != 'MESH':
        return {'type': ob.type, 'matrix': [list(v) for v in ob.matrix_world]}
    me=ob.data
    row={'type':ob.type, 'matrix':[list(v) for v in ob.matrix_world],
         'vertices':[list(v.co) for v in me.vertices],
         'edges':[list(e.vertices) for e in me.edges],
         'faces':[list(p.vertices) for p in me.polygons],
         'smooth':[p.use_smooth for p in me.polygons],
         'normal':[list(n.vector) for n in me.corner_normals],
         'uv':{uv.name:[list(x.uv) for x in uv.data] for uv in me.uv_layers},
         'materials':[m.name for m in me.materials],
         'hide_render':ob.hide_render,
         'extras':dict(ob.items())}
    return hashlib.sha256(json.dumps(row,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def bath_angles():
    """Exact source angular breaks, including deck/stair and portal corners."""
    alpha=math.asin(3.0/8.8)
    special=[alpha,math.tau-alpha,math.pi/2-alpha,math.pi/2+alpha]
    for half,reach in [(1.8,6.0),(1.8,math.sqrt(4.8**2-1.8**2)),(3.0,9.3)]:
        a=math.atan2(reach,half);special.extend([a,math.pi-a])
    special.extend([math.atan2(3,9.3),math.tau-math.atan2(3,9.3)])
    return sorted(set([math.tau*i/96 for i in range(97)]+special))


def make_continuous_wall(material, angles=None):
    """One closed manifold solid; true portals below y=3.2, headers above.

    The y=3.2 rings share vertices and surface edges, but there are no horizontal
    faces except on the actual portal soffits. Only external silhouette corners
    receive the source 8 mm / 3-segment bevel. No decorative seam-covering ring.
    Source Godot coordinates (x,y,z) become Blender (x,-z,y).
    """
    angles=angles or bath_angles()
    count=len(angles)-1
    alpha=math.asin(3.0/8.8)
    opening=[]
    for i in range(count):
        a=(angles[i]+angles[i+1])*.5
        opening.append((math.cos(a)>0 and abs(math.sin(a))<math.sin(alpha)) or
                       (math.sin(a)>0 and abs(math.cos(a))<math.sin(alpha)))
    verts=[]
    for a in angles[:-1]:
        for y in [1.48,3.2,4.6]:
            for r in [8.80,9.16]:
                verts.append((r*math.cos(a),-r*math.sin(a),y))
    def v(i,h,side):return (i%count)*6+h*2+side
    faces=[]
    for i in range(count):
        j=(i+1)%count
        # Shared y=3.2 edges prevent both the former groove and internal caps.
        for h in ([1] if opening[i] else [0,1]):
            faces.extend([(v(i,h,0),v(i,h+1,0),v(j,h+1,0),v(j,h,0)),
                          (v(i,h,1),v(j,h,1),v(j,h+1,1),v(i,h+1,1))])
        faces.append((v(i,2,0),v(i,2,1),v(j,2,1),v(j,2,0)))
        h=1 if opening[i] else 0
        faces.append((v(i,h,0),v(j,h,0),v(j,h,1),v(i,h,1)))
        if not opening[i] and opening[(i-1)%count]:
            faces.append((v(i,0,0),v(i,0,1),v(i,1,1),v(i,1,0)))
        if not opening[i] and opening[j]:
            faces.append((v(j,0,0),v(j,1,0),v(j,1,1),v(j,0,1)))
    me=bpy.data.meshes.new('Bath_Wall_Continuous');me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new('Bath_Wall',me);bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    bm=bmesh.new();bm.from_mesh(me)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.normal_update();bm.to_mesh(me);bm.free();me.update()
    uv=me.uv_layers.new(name='UVMap')
    for f in me.polygons:
        f.use_smooth=abs(f.normal.z)<.1
        # Same world-metre dominant-axis projection as the original generator.
        axis=max(range(3),key=lambda i:abs(f.normal[i]));axes=[i for i in range(3) if i!=axis]
        for li in f.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('External masonry edges only; no y3.2 joint','BEVEL')
    mod.width=.008;mod.segments=3;mod.limit_method='ANGLE';mod.angle_limit=math.radians(30);mod.harden_normals=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=ob.modifiers.new('Preserved planar caps and smooth walls','WEIGHTED_NORMAL');mod.keep_sharp=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    ob['units']='metres';ob['uv0']='1 UV unit = 1 metre; runtime ceramic pitch 0.1m'
    ob['uv2']='packed nonoverlapping smart projection, unbaked'
    ob['construction']='Single watertight plaster shell with lower east/south portals and upper headers; no internal y=3.2 caps or groove'
    ob['junction_candidate']=True
    me.uv_layers.new(name='UV2_Lightmap');me.uv_layers.active_index=1
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15192,island_margin=.006)
    bpy.ops.object.mode_set(mode='OBJECT');me.uv_layers.active_index=0
    ob.select_set(False)
    return ob


def topology(ob):
    bm=bmesh.new();bm.from_mesh(ob.data);bm.normal_update()
    row={'vertices':len(bm.verts),'edges':len(bm.edges),'faces':len(bm.faces),
         'boundary_edges':sum(e.is_boundary for e in bm.edges),
         'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),
         'loose_vertices':sum(not v.link_faces for v in bm.verts),
         'zero_area_faces':sum(f.calc_area()<1e-12 for f in bm.faces),
         'volume_cubic_metres':bm.calc_volume(signed=True)}
    # The only horizontal y=3.2 surfaces must be real headers across portals.
    rows=[]
    for f in bm.faces:
        if all(abs(v.co.z-3.2)<1e-5 for v in f.verts):
            c=f.calc_center_median();x,z=c.x,-c.y
            rows.append({'centroid_godot':[x,c.z,z],'area':f.calc_area(),
                         'inside_actual_portal':(x>0 and abs(z)<3.05) or (z>0 and abs(x)<3.05)})
    row['horizontal_y3_2_faces']=rows
    assert not row['boundary_edges'] and not row['nonmanifold_edges'] and not row['loose_vertices']
    assert not row['zero_area_faces'] and row['volume_cubic_metres']>0
    assert all(x['inside_actual_portal'] for x in rows)
    bm.free();return row


def main():
    DEST.mkdir(parents=True,exist_ok=True);DOC.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    source_sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE),load_ui=False,use_scripts=False)
    before={ob.name:signature(ob) for ob in bpy.context.scene.objects if ob.name not in TARGETS}
    original={name:topology(bpy.data.objects[name]) for name in []}
    material=bpy.data.objects['Bath_Wall'].data.materials[0]
    for name in TARGETS:bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
    wall=make_continuous_wall(material)
    # Retain the old drum node name only as a nonrendering reference, no mesh.
    marker=bpy.data.objects.new('Bath_UpperDrum',None);bpy.context.collection.objects.link(marker)
    marker['construction']='Geometry unified into Bath_Wall; all original COLLISION_Bath_UpperDrum_* proxies preserved'
    after={ob.name:signature(ob) for ob in bpy.context.scene.objects if ob.name not in TARGETS}
    assert before==after,'Unrelated editable-source objects changed'
    report={'pass':True,'blender_version':bpy.app.version_string,'source_blend_sha256':source_sha,
            'unrelated_source_objects_exact':len(before),'collision_source_objects_exact':sum(n.startswith('COLLISION_') for n in before),
            'topology':topology(wall),'object_semantic_sha256':before,
            'new_wall_semantic_sha256':signature(wall)}
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.export_scene.gltf(filepath=str(DEST/'formal_bath_full_source_export.glb'),export_format='GLB',export_yup=True,
                             export_apply=True,export_extras=True,export_cameras=False,export_lights=False)
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_sha
    (DOC/'blend-geometry-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('CANDIDATE_SOURCE_PASS',json.dumps({k:v for k,v in report.items() if k not in ['object_semantic_sha256','topology']}))
    print('CANDIDATE_TOPOLOGY',json.dumps({k:v for k,v in report['topology'].items() if k!='horizontal_y3_2_faces'}))

if __name__=='__main__':main()
