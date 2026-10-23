"""Read-only editable-source proof; export copies outside the production assets.

Run with Blender 4.3.2, background mode and at most two threads:
  blender -b -t 2 --disable-autoexec --factory-startup --python \
    tools/blender/formal_source_roundtrip.py -- --output-dir /tmp/formal-roundtrip

This does not run the generator or save any .blend file. It opens each delivered
editable scene and exports it using the generator's exact glTF export options.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ['formal_arch', 'formal_mainhall', 'formal_arcade',
          'formal_sidepool', 'formal_terrace', 'formal_bath']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-dir', type=Path, default=ROOT/'tools/blender/source')
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
output = args.output_dir.resolve()
production = (ROOT/'assets/models/formal').resolve()
if output == production or production in output.parents:
    raise ValueError('Round-trip output must be outside production assets')
output.mkdir(parents=True, exist_ok=True)
rows = []
for asset in ASSETS:
    source = (args.source_dir/(asset+'.blend')).resolve()
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    visible = [obj for obj in meshes if not obj.name.startswith('COLLISION_')]
    proxies = [obj for obj in meshes if obj.name.startswith('COLLISION_')]
    assert bpy.context.scene.unit_settings.system == 'METRIC'
    assert bpy.context.scene.unit_settings.scale_length == 1.0
    assert all('UVMap' in obj.data.uv_layers and 'UV2_Lightmap' in obj.data.uv_layers
               for obj in visible)
    assert all(obj.get('collision_proxy', False) and obj.hide_render for obj in proxies)
    target = output/(asset+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB',
                             export_yup=True, export_apply=True, export_extras=True,
                             export_cameras=False, export_lights=False)
    after = hashlib.sha256(source.read_bytes()).hexdigest()
    assert before == after, 'Editable source was unexpectedly changed: '+asset
    rows.append({'asset': asset, 'source_blend_sha256': before,
                 'source_file_unchanged': True,
                 'exported_glb_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                 'visible_meshes': len(visible), 'collision_meshes': len(proxies),
                 'metric_units': True, 'visible_UV0_and_UV2': True,
                 'hidden_collision_metadata': True,
                 'material_roles': sorted({slot.material.name for obj in meshes
                                           for slot in obj.material_slots if slot.material})})
    print('FORMAL_EDITABLE_ROUNDTRIP', asset, rows[-1]['exported_glb_sha256'])
(output/'source-roundtrip.json').write_text(json.dumps({
    'pass': True, 'blender_version': bpy.app.version_string,
    'generator_executed': False, 'source_blend_files_saved': False,
    'production_assets_written': False, 'assets': rows,
}, indent=2)+'\n')
