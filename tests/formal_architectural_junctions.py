#!/usr/bin/env python3
"""Current architecture acceptance entry point, plus named historical detail audit.
Run normally for the current measured geometry contract.
Use --historical-check only on the pre-refinement checkpoint assets.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
BASELINE_COLLISION_HASH = 'f8a5ec94250a288c0c23f21bbf1ca5ba9641d18b7c4b742e8144567552b59c43'
BASELINE_COUNTS = {'vertices': 97142, 'triangles': 66444, 'visible_meshes': 140, 'collision_meshes': 219, 'bytes': 4463812}
MODIFIED = {'Main_Stair' + str(i) for i in range(4)} | {
    'Main_CopingSide-8.18', 'Main_CopingSide8.18', 'Main_CopingNorth',
    'Main_CopingSouth-5.2', 'Main_CopingSouth5.2'}
ADDED = {'Main_CopingStairNosings', 'Main_CopingArchitecturalCaps'}

class GLB:
    def __init__(self, path):
        self.path = Path(path)
        self.raw = self.path.read_bytes()
        assert self.raw[:4] == b'glTF' and struct.unpack_from('<II', self.raw, 4) == (2, len(self.raw))
        n = struct.unpack_from('<I', self.raw, 12)[0]
        self.doc = json.loads(self.raw[20:20+n])
        offset = 20+n
        size, kind = struct.unpack_from('<II', self.raw, offset)
        assert kind == 0x004e4942
        self.binary = self.raw[offset+8:offset+8+size]
        self.nodes = {n['name']: n for n in self.doc['nodes'] if 'mesh' in n}

    def accessor(self, index):
        a = self.doc['accessors'][index]
        view = self.doc['bufferViews'][a['bufferView']]
        fmt = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}[a['componentType']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        fmt = '<' + fmt*width
        size = struct.calcsize(fmt)
        stride = view.get('byteStride', size)
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        return [struct.unpack_from(fmt, self.binary, start+i*stride) for i in range(a['count'])]

    def primitives(self, name):
        return self.doc['meshes'][self.nodes[name]['mesh']]['primitives']

    def positions(self, name):
        return [v for p in self.primitives(name) for v in self.accessor(p['attributes']['POSITION'])]

    def bounds(self, name):
        vs = self.positions(name)
        return [[min(v[i] for v in vs) for i in range(3)], [max(v[i] for v in vs) for i in range(3)]]

    def node_geometry(self, name):
        n = self.nodes[name]
        return {
            'name': name,
            'transform': {k: n[k] for k in ('matrix', 'translation', 'rotation', 'scale') if k in n},
            'primitives': [{'positions': self.accessor(p['attributes']['POSITION']),
                            'indices': self.accessor(p['indices'])} for p in self.primitives(name)],
        }

    def collision_hash(self):
        data = [self.node_geometry(name) for name in sorted(self.nodes) if name.startswith('COLLISION_')]
        return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

    def counts(self):
        ps = [p for name in self.nodes for p in self.primitives(name)]
        return {'vertices': sum(self.doc['accessors'][p['attributes']['POSITION']]['count'] for p in ps),
                'triangles': sum(self.doc['accessors'][p['indices']]['count']//3 for p in ps),
                'visible_meshes': sum(not n.startswith('COLLISION_') for n in self.nodes),
                'collision_meshes': sum(n.startswith('COLLISION_') for n in self.nodes),
                'bytes': len(self.raw)}


def historical_main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-root', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    current = GLB(ROOT/'assets/models/formal/formal_mainhall.glb')
    assertions = 0
    def check(ok, label):
        nonlocal assertions
        assertions += 1
        if not ok:
            raise AssertionError(label)

    counts = current.counts()
    check(counts['collision_meshes'] == 219, 'All 219 collision proxies retained')
    check(counts['visible_meshes'] == 142, 'Only two added visible mesh batches')
    check(current.collision_hash() == BASELINE_COLLISION_HASH, 'Collision names, transforms, vertices and indices identical to pre-detail baseline')
    check(counts['vertices'] < BASELINE_COUNTS['vertices']*1.17, 'Restrained vertex increase below 17%')
    check(counts['triangles'] < BASELINE_COUNTS['triangles']*1.13, 'Restrained triangle increase below 13%')
    check(not any(n.startswith('COLLISION_') and ('Nosing' in n or 'Caps' in n) for n in current.nodes), 'No decorative collision added')

    normal_count = 0
    for name, node in current.nodes.items():
        visible = not name.startswith('COLLISION_')
        check(not any(k in node for k in ('matrix', 'translation', 'rotation', 'scale')), 'Room-local identity transform: '+name)
        if visible and 'StairRail' not in name:
            check(node.get('extras', {}).get('units') == 'metres', 'Metre geometry metadata: '+name)
        for primitive in current.primitives(name):
            role = current.doc['materials'][primitive['material']]['name']
            check(role.startswith('Formal_'), 'Existing Formal_* material contract: '+name)
            attrs = primitive['attributes']
            if visible:
                check('TEXCOORD_0' in attrs and 'TEXCOORD_1' in attrs, 'Both UV sets retained: '+name)
            for normal in current.accessor(attrs['NORMAL']):
                check(all(math.isfinite(v) for v in normal) and abs(sum(v*v for v in normal)-1)<0.0001, 'Finite unit normal: '+name)
                normal_count += 1

    for name in ADDED:
        check(name in current.nodes, 'Batched detail exists: '+name)
        for primitive in current.primitives(name):
            check(current.doc['materials'][primitive['material']]['name'] == 'Formal_Coping', 'Pale ceramic uses existing coping role: '+name)

    # Flat upper faces retain metre-space UV derivatives, including on the
    # newly cut coping. glTF flips UV V relative to Blender's UV convention.
    metric_uv_samples = 0
    for name in ADDED | {n for n in MODIFIED if n.startswith('Main_Coping')}:
        for primitive in current.primitives(name):
            attrs = primitive['attributes']
            for v, n, uv in zip(current.accessor(attrs['POSITION']), current.accessor(attrs['NORMAL']), current.accessor(attrs['TEXCOORD_0'])):
                if n[1] > .99999:
                    check(abs(uv[0]-v[0])<2e-5 and abs(uv[1]-(1+v[2]))<2e-5, 'Top-face UV0 in metres: '+name)
                    metric_uv_samples += 1
    check(metric_uv_samples > 100, 'Real upper-surface UV0 metre coordinates inspected')

    nosings = current.positions('Main_CopingStairNosings')
    stair_heights = []
    for i, expected in enumerate((.38, .24, .10, -.04)):
        top = current.bounds('COLLISION_Main_Stair'+str(i))[1][1]
        stair_heights.append(top)
        check(abs(top-expected)<1e-7, 'Exact stair collision top '+str(i))
        front = 5.78-i*.42-.21
        part = [v for v in nosings if front-1e-5<=v[2]<=front+.054+1e-5]
        check(bool(part), 'Nosing on actual tread '+str(i))
        check(abs(max(v[1] for v in part)-top)<1e-7, 'Flush, not raised, nosing '+str(i))
        check(abs(min(v[1] for v in part)-(expected-.028))<1e-7, 'Nosing sits in a 28 mm visual seat '+str(i))
        check(abs(max(v[2] for v in part)-min(v[2] for v in part)-.054)<1e-6, '54 mm narrow nosing '+str(i))
        check(abs(max(v[0] for v in part)-min(v[0] for v in part)-4.8)<1e-6, 'Original tread width '+str(i))

    joint_count = 0
    for name in sorted(MODIFIED):
        if not name.startswith('Main_Coping'):
            continue
        node = current.nodes[name]
        check(node['extras']['joint_width_metres'] == .005, '5 mm coping joint '+name)
        along = 2 if 'Side' in name else 0
        across = 0 if along == 2 else 2
        vs = current.positions(name)
        bounds = current.bounds(name)
        centre = (bounds[0][across]+bounds[1][across])/2
        for joint in node['extras']['joint_centres_metres']:
            # Inspect the actual cut vertices, not just descriptive extras.
            at_joint = [v for v in vs if abs(v[along]-joint)<.00151 and abs(v[across]-centre)<.17]
            check(bool(at_joint), 'Physical joint vertices '+name)
            check(abs(max(v[1] for v in at_joint)-.566)<1e-6, 'Actual 4 mm recess '+name)
            joint_count += 1
    check(joint_count == 44, '44 restrained physical coping joints')

    caps = json.loads(current.nodes['Main_CopingArchitecturalCaps']['extras']['cap_pieces_json'])
    check(len(caps) == 17, 'Six wall and eleven existing pier terminations')
    for cap in caps:
        c, s = cap['centre'], cap['size']
        check(abs(s[1]-.036)<1e-9, 'Slim 36 mm cap')
        if 'East' in cap['at']:
            check(abs(c[2])-s[2]/2 >= 4-1e-6, 'Eight metre east portal stays clear')
        if 'South' in cap['at']:
            check(abs(c[0])-s[0]/2 >= 4-1e-6, 'Eight metre south portal stays clear')
        check(abs(c[1]-(1.278 if 'CeramicFoot' in cap['at'] else 1.478))<1e-6, 'Cap at actual ceramic/plaster seam')

    unchanged_files = {}
    unchanged_architecture = None
    before_counts = BASELINE_COUNTS
    if args.baseline_root:
        baseline = GLB(args.baseline_root/'assets/models/formal/formal_mainhall.glb')
        before_counts = baseline.counts()
        check(baseline.collision_hash() == current.collision_hash(), 'Direct before/after collision hash match')
        unchanged_architecture = 0
        check(set(current.nodes)-set(baseline.nodes) == ADDED, 'Exactly the intended new mesh names')
        check(not set(baseline.nodes)-set(current.nodes), 'No previous objects removed')
        for name in baseline.nodes:
            if name in MODIFIED:
                continue
            check(baseline.positions(name) == current.positions(name), 'Unchanged exact vertex positions: '+name)
            for old, new in zip(baseline.primitives(name), current.primitives(name)):
                check(baseline.accessor(old['attributes']['NORMAL']) == current.accessor(new['attributes']['NORMAL']), 'Unchanged authored normals/bevels: '+name)
                check(len(baseline.accessor(old['indices'])) == len(current.accessor(new['indices'])), 'Unchanged triangle count: '+name)
            unchanged_architecture += not name.startswith('COLLISION_')
        for asset in ('formal_arch', 'formal_arcade', 'formal_sidepool'):
            for relative in (f'assets/models/formal/{asset}.glb', f'tools/blender/source/{asset}.blend'):
                data = (ROOT/relative).read_bytes()
                check(data == (args.baseline_root/relative).read_bytes(), 'Byte-identical other room: '+relative)
                unchanged_files[relative] = hashlib.sha256(data).hexdigest()
        relative = 'assets/models/formal/formal_manifest.json'
        check((ROOT/relative).read_bytes() == (args.baseline_root/relative).read_bytes(), 'Unchanged manifest dimensions and water contract')

    result = {
        'pass': True, 'assertions': assertions, 'validation': 'Direct GLB data, no Godot/GPU claim',
        'before': before_counts, 'after': counts,
        'vertex_increase_percent': round((counts['vertices']/before_counts['vertices']-1)*100, 3),
        'triangle_increase_percent': round((counts['triangles']/before_counts['triangles']-1)*100, 3),
        'collision_sha256': current.collision_hash(),
        'mainhall_glb_sha256': hashlib.sha256(current.raw).hexdigest(),
        'exact_stair_collision_tops': stair_heights, 'physical_coping_joints': joint_count,
        'termination_cap_pieces': len(caps), 'unit_normals_checked': normal_count,
        'metric_uv_samples': metric_uv_samples,
        'unchanged_existing_visible_meshes': unchanged_architecture,
        'byte_identical_other_assets': unchanged_files,
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    import sys
    if '--historical-check' in sys.argv:
        sys.argv.remove('--historical-check')
        historical_main()
    else:
        from formal_authored_architecture import main
        main()
