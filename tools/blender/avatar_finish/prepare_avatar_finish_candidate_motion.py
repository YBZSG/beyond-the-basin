"""CPU-only motion staging, preserving the accepted static fixture and caches.

This intentionally requires the owner's existing native stage. It will not create
a cold replacement, guess DISPLAY, launch an engine, or rewrite runtime inputs.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ACCEPTED = HERE / 'audit/native-20261022T201118Z'
FIXTURE = 'tests/avatar_finish_candidate_motion.gd'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def settings(path: Path, section: str) -> dict[str, str]:
    current = ''
    result = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line.startswith('[') and line.endswith(']'):
            current = line[1:-1]
        elif current == section and '=' in line and not line.startswith((';', '#')):
            key, value = line.split('=', 1)
            result[key.strip()] = value.strip()
    return result


def prepare(stage: Path) -> dict:
    receipt = json.loads((ACCEPTED / 'completed_exit_receipt.json').read_text())
    review = json.loads((ACCEPTED / 'avatar_finish_candidate_visual_review.json').read_text())
    manifest = json.loads((ACCEPTED / 'stage_manifest.json').read_text())
    if not receipt.get('passed') or not review.get('verdict', '').startswith('accept for isolated dry'):
        raise RuntimeError('The fixed static evidence is not an accepted dry candidate.')
    if not (stage / 'project.godot').is_file() or not (stage / '.godot/imported').is_dir():
        raise RuntimeError(f'Existing accepted native stage/cache required at {stage}; no cold stage created.')
    changed = []
    staged = {}
    for relative, expected in manifest['copied_files'].items():
        source = ROOT / relative
        if not source.is_file() or sha(source) != expected:
            changed.append('current source: ' + relative)
        dest = stage / relative
        if not dest.is_file():
            changed.append('missing staged input: ' + relative)
        elif relative.endswith('.import'):
            # Godot rewrites remap metadata and may append default keys. Preserve
            # that cache metadata; require every authored data-map parameter.
            required = settings(source, 'params')
            actual = settings(dest, 'params')
            if any(actual.get(key) != value for key, value in required.items()):
                changed.append('staged import parameters: ' + relative)
            staged[relative] = sha(dest)
        elif sha(dest) != expected:
            changed.append('staged source: ' + relative)
        else:
            staged[relative] = expected
    candidate_import = 'assets/textures/avatar_finish/avatar_finish_candidate.glb.import'
    required = settings(ROOT / candidate_import, 'params')
    actual = settings(stage / candidate_import, 'params')
    if any(actual.get(key) != value for key, value in required.items()):
        changed.append('staged candidate scene import parameters')
    project = stage / 'project.godot'
    if settings(project, 'rendering').get('renderer/rendering_method') != '"forward_plus"':
        changed.append('staged renderer is not accepted Forward+')
    if changed:
        raise RuntimeError('Refusing drift from accepted static inputs: ' + '; '.join(changed))
    # Preserve static pixels, source fixtures and all shader/import caches. An
    # ignore marker prevents an editor scan from importing old captured PNGs.
    static_captures = stage / 'captures'
    if static_captures.is_dir():
        (static_captures / '.gdignore').touch(exist_ok=True)
    destination = stage / FIXTURE
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / FIXTURE, destination)
    caches = {}
    for relative in ('.godot/imported', '.godot/shader_cache', 'xdg-cache'):
        path = stage / relative
        files = [p for p in path.rglob('*') if p.is_file()] if path.is_dir() else []
        caches[relative] = {'exists': path.is_dir(), 'files': len(files), 'bytes': sum(p.stat().st_size for p in files)}
    return {
        'stage': str(stage), 'accepted_static_evidence': str(ACCEPTED.relative_to(ROOT)),
        'accepted_manifest_sha256': sha(ACCEPTED / 'stage_manifest.json'),
        'accepted_static_inputs_unchanged': True, 'copied_files': {FIXTURE: sha(destination)},
        'preserved_staged_input_hashes': staged, 'project_sha256': sha(project),
        'candidate_import_sha256': sha(stage / candidate_import),
        'cache_inventory_before_engine': caches, 'cache_hit_claim': False,
        'ran_engine': False, 'production_changed': False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, default=Path('/tmp/avatar_finish_candidate_stage'))
    args = parser.parse_args()
    try:
        result = prepare(args.stage.resolve())
    except Exception as error:
        print(json.dumps({'passed': False, 'ran_engine': False, 'error': str(error)}, indent=2))
        return 1
    print(json.dumps({'passed': True, **result}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
