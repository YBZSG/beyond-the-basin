#!/usr/bin/env python3
"""Reproduce formal assets in scratch space without writing production models.

Blender 4.3.2 is the verified baseline. Only Python's standard library is needed
outside Blender. --compare-existing repeats just the cheap comparison of an
already completed scratch run, including its pre-run production hash snapshot.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ['formal_arch', 'formal_mainhall', 'formal_arcade',
          'formal_sidepool', 'formal_terrace', 'formal_bath']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-root', type=Path)
    parser.add_argument('--blender', default='blender')
    parser.add_argument('--threads', type=int, choices=(1, 2), default=2)
    parser.add_argument('--compare-existing', action='store_true')
    parser.add_argument('--report', type=Path,
                        default=ROOT/'docs/verification/formal-fitted-clean-rebuild.json')
    args = parser.parse_args()
    if args.compare_existing and args.work_root is None:
        parser.error('--compare-existing requires the original --work-root')
    work = args.work_root.resolve() if args.work_root else Path(tempfile.mkdtemp(prefix='formal-delivery-'))
    if work == ROOT or ROOT in work.parents:
        parser.error('--work-root must be outside the production project')
    if not args.compare_existing:
        if work.exists() and any(work.iterdir()):
            parser.error('--work-root must be empty for a fresh run')
        (work/'tools/blender').mkdir(parents=True, exist_ok=True)
        (work/'reports').mkdir(exist_ok=True)
        shutil.copy2(ROOT/'tools/blender/build_formal.py', work/'tools/blender/build_formal.py')
        relative = [f'assets/models/formal/{name}.glb' for name in ASSETS]
        relative += [f'tools/blender/source/{name}.blend' for name in ASSETS]
        relative += ['assets/models/formal/formal_manifest.json', 'tools/blender/build_formal.py',
                     'scripts/world/formal_rooms.gd', 'scripts/world/formal_room_builder.gd']
        snapshot = {'production_root': str(ROOT), 'sha256': {
            name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in relative}}
        (work/'reports/production-before.json').write_text(json.dumps(snapshot, indent=2)+'\n')
        environment = dict(os.environ, OMP_NUM_THREADS=str(args.threads),
                           OPENBLAS_NUM_THREADS=str(args.threads), PYTHONDONTWRITEBYTECODE='1')
        prefix = [args.blender, '-b', '-t', str(args.threads), '--disable-autoexec', '--factory-startup']
        jobs = [('clean-build.log', prefix+['--python', str(work/'tools/blender/build_formal.py')]),
                ('editable-roundtrip.log', prefix+['--python', str(ROOT/'tools/blender/formal_source_roundtrip.py'),
                                                   '--', '--output-dir', str(work/'editable-roundtrip')])]
        (work/'reports/run-config.json').write_text(json.dumps({
            'cpu_threads': args.threads, 'commands': [command for _, command in jobs],
            'provenance': 'Recorded by the scratch verification runner before execution',
        }, indent=2)+'\n')
        for log, command in jobs:
            print('Running:', ' '.join(command), flush=True)
            with (work/'reports'/log).open('w') as stream:
                subprocess.run(command, cwd=ROOT, env=environment, stdout=stream,
                               stderr=subprocess.STDOUT, check=True)
    else:
        if not (work/'reports/production-before.json').is_file():
            parser.error('Existing run lacks its original production hash snapshot')
    subprocess.run([sys.executable, '-B', str(ROOT/'tests/formal_clean_rebuild_compare.py'),
                    '--rebuilt-root', str(work), '--source-roundtrip-dir', str(work/'editable-roundtrip'),
                    '--report', str(args.report.resolve())], cwd=ROOT, check=True)
    print('Verified scratch outputs retained at:', work)


if __name__ == '__main__':
    main()
