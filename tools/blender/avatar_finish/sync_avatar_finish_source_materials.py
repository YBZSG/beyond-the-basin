"""Sync dry PBR authoring nodes only; no geometry, rig or GLB export."""
from pathlib import Path
import bpy
HERE=Path(__file__).resolve().parent
path=HERE/'avatar_finish_candidate_uv_source.blend'
bpy.ops.wm.open_mainfile(filepath=str(path))
for obj in bpy.context.scene.objects:
    if obj.type!='MESH':continue
    shirt=obj.name.startswith('shirt_plain')
    if not shirt and not obj.name.startswith('trousers_twill'):continue
    for material in obj.data.materials:
        bsdf=material.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['IOR'].default_value=1.5
        bsdf.inputs['Specular IOR Level'].default_value=2*(.3 if shirt else .5)**2
bpy.ops.wm.save_as_mainfile(filepath=str(path))
