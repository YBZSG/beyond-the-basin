#!/usr/bin/env python3
"""Freeze private build inputs, retaining imports but never export credentials.

This is NOT a distributable source package. It performs no engine invocation,
import, bake, export, signing, key access or upload. Use only after the release
owner has paused writes to the selected project inputs.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from audit_packages import AuditError, no_secrets, require, safe_name
from preflight_release import preflight
from stage_release import manifest, sha, source_paths, verified_copy_set, verify_manifest

METADATA = ('.godot/extension_list.cfg', '.godot/global_script_class_cache.cfg',
            '.godot/uid_cache.bin', '.godot/.gdignore')


def build_paths(root):
    root = Path(root).resolve()
    paths = source_paths(root)
    imported = root / '.godot/imported'
    require(imported.is_dir() and not imported.is_symlink(), 'Completed local imported-resource cache is required')
    for path in imported.rglob('*'):
        require(not path.is_symlink(), f'Imported cache symlink: {path.relative_to(root)}')
        if path.is_file():
            paths.append(path)
    require(any(p.suffix != '.md5' for p in imported.rglob('*') if p.is_file()), 'Imported-resource cache is empty')
    for rel in METADATA:
        path = root / rel
        if path.is_file():
            require(not path.is_symlink(), f'Build metadata symlink: {rel}')
            paths.append(path)
    require(root / METADATA[0] in paths, 'Native extension startup registry is missing')
    require(root / METADATA[1] in paths, 'Imported global script class registry is missing')
    require(root / METADATA[2] in paths, 'Imported resource UID cache is missing')
    paths = sorted(set(paths))
    no_secrets(path.relative_to(root).as_posix() for path in paths)
    return paths


def verify_frozen_inputs(root):
    """Permit new engine cache files, never a changed/missing frozen source/import."""
    root = Path(root).resolve()
    data = json.loads((root / 'BUILD-PACKAGE-MANIFEST.json').read_text())
    require(data.get('kind') == 'private-frozen-build-inputs', 'Not a frozen build-input manifest')
    entries = data['files']
    names = [safe_name(entry['path']) for entry in entries]
    require(len(names) == len(set(names)), 'Duplicate build input in manifest')
    sums = ''.join(entry['sha256'] + '  ' + entry['path'] + '\n' for entry in entries)
    require((root / 'BUILD-SHA256SUMS.txt').read_text() == sums, 'Build checksums differ from manifest')
    source_expected = {name for name in names if not name.startswith('.godot/') and name != 'BUILD-README.txt'}
    source_actual = {path.relative_to(root).as_posix() for path in source_paths(root)}
    require(source_actual == source_expected, 'Frozen source file set changed during build/export')
    checked = []
    for entry in entries:
        name = entry['path']
        if name in METADATA:
            continue  # Editor may update registries without changing source/imported payloads.
        path = root / name
        require(path.is_file() and not path.is_symlink(), f'Frozen input missing or symlinked: {name}')
        require(path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256'], f'Frozen input changed: {name}')
        checked.append(name)
    return {'status': 'PASS', 'files_bound': len(checked), 'source_files': len(source_expected),
            'scope': 'Original source and imported payload bytes remain exact; new engine-generated cache metadata is allowed.',
            'export_or_render_acceptance': False}


def freeze(source, output):
    root, out = Path(source).resolve(), Path(output).resolve()
    require(out != root and root not in out.parents, 'Freeze into a separate workspace-level directory')
    require(not out.exists() or not any(out.iterdir()), 'Build snapshot output must be new or empty')
    require((root / 'project.godot').is_file(), 'Invalid source project')
    report = preflight(root)
    paths = build_paths(root)
    out.mkdir(parents=True, exist_ok=True)
    verified_copy_set(paths, root, out, lambda: build_paths(root))
    # Re-audit copied bytes rather than trusting the earlier live inventory.
    report = preflight(out)
    (out / 'BUILD-README.txt').write_text('''PRIVATE BUILD SNAPSHOT, NOT AN EDITABLE SOURCE DELIVERY ZIP.
This tree deliberately retains generated imported payloads for exact PC/APK
export identity. It omits export credentials, signing keys, editor preferences,
SDKs and toolchains. Do not upload or zip this build tree for the user.

After import/export, run freeze_build_inputs.py verify against this tree.
If a frozen source or imported payload changed, do not patch the old manifest or
silently accept it. Investigate, rebuild/revalidate affected terrain if needed,
and create a newly identified build freeze.

For the final editable delivery, run stage_release.py source --source-profile
final from this tree. That stage strips generated .godot caches except the
portable native-extension startup registry. Stage the optional lab separately.
''')
    report.update({'snapshot_utc': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                   'private_build_cache_retained': True, 'distributable': False})
    manifest(out, 'private-frozen-build-inputs', report, prefix='BUILD-')
    verify_manifest(out, prefix='BUILD-')
    result = verify_frozen_inputs(out)
    result.update({'directory': str(out), 'snapshot_utc': report['snapshot_utc'],
                   'imported_files': sum(path.relative_to(root).as_posix().startswith('.godot/imported/') for path in paths)})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest='action', required=True)
    create = subs.add_parser('create')
    create.add_argument('--source', type=Path, required=True)
    create.add_argument('--output', type=Path, required=True)
    verify = subs.add_parser('verify')
    verify.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = freeze(args.source, args.output) if args.action == 'create' else verify_frozen_inputs(args.source)
        print(json.dumps(result, indent=2))
        return 0
    except (AuditError, OSError, ValueError, KeyError) as exc:
        print(f'BUILD_FREEZE_FAIL: {exc}\nPartial or changed build snapshots are not releases.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
