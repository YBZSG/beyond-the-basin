#!/usr/bin/env python3
"""Compare isolated generator and editable-scene exports without changing assets."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile

sys.dont_write_bytecode = True
from formal_architectural_junctions import GLB

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ['formal_arch', 'formal_mainhall', 'formal_arcade',
          'formal_sidepool', 'formal_terrace', 'formal_bath']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strict_semantics(path):
    """Ignore container packing/exporter labels, not mesh or collision content.

    This intentionally preserves vertex/index order, normals, every UV layer,
    material definitions, node transforms and extras. It is stricter than merely
    comparing an unlabelled set of triangles or rendered appearance.
    """
    glb = GLB(path)
    assert not glb.doc.get('textures') and not glb.doc.get('animations'), 'Unexpected non-static authored content'
    names = [node['name'] for node in glb.doc['nodes']]
    assert len(names) == len(set(names)), 'Ambiguous duplicate scene node names'
    nodes = []
    for node in glb.doc['nodes']:
        record = {key: value for key, value in node.items() if key not in ('mesh', 'children')}
        if 'children' in node:
            record['children'] = [names[index] for index in node['children']]
        if 'mesh' in node:
            mesh = glb.doc['meshes'][node['mesh']]
            record['mesh_metadata'] = {key: value for key, value in mesh.items() if key != 'primitives'}
            record['primitives'] = []
            for primitive in mesh['primitives']:
                values = {key: value for key, value in primitive.items()
                          if key not in ('attributes', 'indices', 'material')}
                values['material'] = glb.doc['materials'][primitive['material']]['name']
                values['indices'] = glb.accessor(primitive['indices'])
                values['attributes'] = {key: glb.accessor(index)
                                        for key, index in primitive['attributes'].items()}
                record['primitives'].append(values)
        nodes.append(record)
    scenes = [{**scene, 'nodes': [names[index] for index in scene.get('nodes', [])]}
              for scene in glb.doc['scenes']]
    value = {'nodes': sorted(nodes, key=lambda node: node['name']), 'scenes': scenes,
             'materials': sorted(glb.doc['materials'], key=lambda material: material['name'])}
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def check_semantic_fallback():
    """Small scratch-only controls ensure metadata cannot mask a mesh change."""
    original = ROOT/'assets/models/formal/formal_arch.glb'
    glb = GLB(original)
    reference = strict_semantics(original)
    json_size = struct.unpack_from('<I', glb.raw, 12)[0]
    result = {}
    with tempfile.TemporaryDirectory(prefix='formal-semantic-controls-') as folder:
        folder = Path(folder)
        document = json.loads(json.dumps(glb.doc))
        document['asset']['generator'] += ' metadata-only-test'
        block = json.dumps(document, separators=(',', ':')).encode()
        block += b' ' * ((-len(block)) % 4)
        remainder = glb.raw[20+json_size:]
        raw = b'glTF'+struct.pack('<II', 2, 20+len(block)+len(remainder))
        raw += struct.pack('<II', len(block), 0x4e4f534a)+block+remainder
        candidate = folder/'metadata.glb'; candidate.write_bytes(raw)
        result['metadata_only_accepted'] = sha(candidate) != sha(original) and strict_semantics(candidate) == reference
        for label, collision, attribute in [('collision_vertex_change_rejected', True, 'POSITION'),
                                            ('UV0_change_rejected', False, 'TEXCOORD_0')]:
            name = next(name for name in glb.nodes if name.startswith('COLLISION_') == collision)
            primitive = glb.primitives(name)[0]
            accessor = glb.doc['accessors'][primitive['attributes'][attribute]]
            view = glb.doc['bufferViews'][accessor['bufferView']]
            offset = 28+json_size+view.get('byteOffset', 0)+accessor.get('byteOffset', 0)
            changed = bytearray(glb.raw)
            value = struct.unpack_from('<f', changed, offset)[0]
            struct.pack_into('<f', changed, offset, value+.01)
            candidate = folder/(label+'.glb'); candidate.write_bytes(changed)
            result[label] = strict_semantics(candidate) != reference
    assert all(result.values()), 'Semantic fallback control failed'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rebuilt-root', type=Path, required=True)
    parser.add_argument('--source-roundtrip-dir', type=Path, required=True)
    parser.add_argument('--report', type=Path,
                        default=ROOT/'docs/verification/formal-fitted-clean-rebuild.json')
    args = parser.parse_args()
    semantic_controls = check_semantic_fallback()
    before = json.loads((args.rebuilt_root/'reports/production-before.json').read_text())
    run_config_path = args.rebuilt_root/'reports/run-config.json'
    run_config = json.loads(run_config_path.read_text()) if run_config_path.is_file() else {}
    editable = json.loads((args.source_roundtrip_dir/'source-roundtrip.json').read_text())
    assert editable['pass'] and not editable['source_blend_files_saved']
    editable_rows = {row['asset']: row for row in editable['assets']}
    assert set(editable_rows) == set(ASSETS)
    rows = []
    for asset in ASSETS:
        live = ROOT/'assets/models/formal'/f'{asset}.glb'
        rebuilt = args.rebuilt_root/'assets/models/formal'/live.name
        roundtrip = args.source_roundtrip_dir/live.name
        hashes = [sha(path) for path in (live, rebuilt, roundtrip)]
        exact_build, exact_source = hashes[0] == hashes[1], hashes[0] == hashes[2]
        semantic_live = None if exact_build and exact_source else strict_semantics(live)
        semantic_build = exact_build or strict_semantics(rebuilt) == semantic_live
        semantic_source = exact_source or strict_semantics(roundtrip) == semantic_live
        assert semantic_build and semantic_source, 'Geometry/material/UV/proxy mismatch: '+asset
        source_blend = ROOT/'tools/blender/source'/f'{asset}.blend'
        assert editable_rows[asset]['source_blend_sha256'] == sha(source_blend)
        assert editable_rows[asset]['exported_glb_sha256'] == hashes[2]
        rows.append({'asset': asset, 'production_sha256': hashes[0],
                     'clean_generator_glb_sha256': hashes[1], 'editable_source_glb_sha256': hashes[2],
                     'clean_generator_GLB_byte_identical': exact_build,
                     'editable_source_GLB_byte_identical': exact_source,
                     'geometry_material_collision_UV_identity': semantic_build and semantic_source,
                     'semantic_evidence': 'Whole GLB bytes identical' if exact_build and exact_source
                                          else 'Strict canonical mesh/material/node comparison',
                     'editable_source_sha256': sha(source_blend),
                     'rebuilt_blend_sha256': sha(args.rebuilt_root/'tools/blender/source'/source_blend.name),
                     'blend_container_byte_identical': source_blend.read_bytes() ==
                         (args.rebuilt_root/'tools/blender/source'/source_blend.name).read_bytes(),
                     'counts': GLB(live).counts(), 'editable_scene_contract': editable_rows[asset]})
    live_manifest = (ROOT/'assets/models/formal/formal_manifest.json').read_bytes()
    new_manifest = (args.rebuilt_root/'assets/models/formal/formal_manifest.json').read_bytes()
    assert json.loads(live_manifest) == json.loads(new_manifest)
    unchanged = {path: sha(ROOT/path) == expected for path, expected in before['sha256'].items()}
    assert all(unchanged.values()), 'A production model, source, builder or catalog changed during verification'
    generator = ROOT/'tools/blender/build_formal.py'
    assert sha(generator) == sha(args.rebuilt_root/'tools/blender/build_formal.py')
    result = {
        'pass': True, 'scope': 'Independent clean Blender rebuild plus direct delivered .blend export round-trip',
        'blender_version': editable['blender_version'], 'cpu_threads': run_config.get('cpu_threads'),
        'thread_count_provenance': run_config.get('provenance', 'Not recorded; comparison does not infer the original launch flags'),
        'GPU_used': False,
        'generator_sha256': sha(generator), 'production_files_unchanged': unchanged,
        'all_six_clean_GLBs_byte_identical': all(row['clean_generator_GLB_byte_identical'] for row in rows),
        'all_six_editable_source_GLBs_byte_identical': all(row['editable_source_GLB_byte_identical'] for row in rows),
        'manifest_byte_identical': live_manifest == new_manifest, 'manifest_semantic_identical': True,
        'manifest_difference': 'JSON serialization differs; all parsed keys and values are identical'
                               if live_manifest != new_manifest else 'None',
        'manifest_top_level_key_order_differs': list(json.loads(live_manifest)) != list(json.loads(new_manifest)),
        'manifest_terminal_newline_differs': live_manifest.endswith(b'\n') != new_manifest.endswith(b'\n'),
        'semantic_fallback_controls': semantic_controls,
        'blend_container_identity_note': 'A .blend container hash is separate from exported geometry identity; both hashes are recorded without requiring native container bytes to match.',
        'assets': rows,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2)+'\n')
    print('FORMAL_FITTED_CLEAN_REBUILD PASS:',
          sum(row['clean_generator_GLB_byte_identical'] for row in rows), 'clean GLBs and',
          sum(row['editable_source_GLB_byte_identical'] for row in rows),
          'editable-source GLBs byte-identical;', len(unchanged), 'production files unchanged')


if __name__ == '__main__':
    main()
