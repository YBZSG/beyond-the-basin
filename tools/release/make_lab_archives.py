#!/usr/bin/env python3
"""Bounded ordinary ZIPs for a separately staged optional laboratory.

No export, engine, signing, installation or publication. Extract every matching
part into the editable project root. These are not binary-split ZIP volumes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
import zipfile
import zlib
from audit_packages import AuditError, no_secrets, require
from stage_release import LAB_PREFIXES, REJECTED_LAB_PAYLOADS, sha, verify_manifest


def make_lab_parts(root, out, label, limit=16_000_000):
    root, out = Path(root).resolve(), Path(out).resolve()
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]+', label), 'Use a portable label')
    require(limit >= 1_000_000, 'Unreasonably small archive bound')
    require(out != root and root not in out.parents, 'Output must be outside staged laboratory')
    require(not out.exists(), 'Refusing to replace an existing output')
    receipt = verify_manifest(root, prefix='LAB-')
    require(receipt['kind'] == 'lab' and receipt['audit'].get('runtime_integrated') is False,
            'Input must be a separately staged, unintegrated optional laboratory')
    files = sorted(p for p in root.rglob('*') if p.is_file())
    paths = [p.relative_to(root).as_posix() for p in files]
    no_secrets(paths)
    for name in paths:
        require(name.startswith(LAB_PREFIXES) or name in
                {'LAB-RESTORE.txt', 'LAB-PACKAGE-MANIFEST.json', 'LAB-SHA256SUMS.txt'},
                'Unexpected non-laboratory path: ' + name)
        require(name not in REJECTED_LAB_PAYLOADS, 'Rejected large bake retained: ' + name)
    bins, batch, budget = [], [], 4096
    for path, name in zip(files, paths):
        estimate = len(zlib.compress(path.read_bytes(), 9)) + len(name.encode()) * 2 + 256
        require(estimate + 4096 < limit, 'Individual lab file exceeds ZIP bound: ' + name)
        if batch and budget + estimate > limit - 65536:
            bins.append(batch); batch, budget = [], 4096
        batch.append(path); budget += estimate
    if batch:
        bins.append(batch)
    out.mkdir(parents=True)
    reports, seen = [], set()
    for index, batch in enumerate(bins, 1):
        target = out / f'{label}-Part{index:02d}-of-{len(bins):02d}.zip'
        with zipfile.ZipFile(target, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in batch:
                name = path.relative_to(root).as_posix()
                require(name not in seen, 'Duplicate lab archive path'); seen.add(name)
                info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        require(target.stat().st_size < limit, 'Lab ZIP exceeds attachment bound')
        with zipfile.ZipFile(target) as archive:
            require(archive.testzip() is None, 'Lab ZIP CRC failure')
            for path in batch:
                require(hashlib.sha256(archive.read(path.relative_to(root).as_posix())).hexdigest() == sha(path),
                        'Lab archive content mismatch')
        reports.append({'filename': target.name, 'bytes': target.stat().st_size,
                        'sha256': sha(target), 'files': len(batch)})
    require(seen == set(paths), 'Lab archive union differs from staging')
    verify_manifest(root, prefix='LAB-')
    result = {'status': 'PASS', 'kind': 'optional-lighting-lab', 'runtime_integrated': False,
              'all_parts_required': True, 'independently_extractable': True,
              'extract_into': 'Editable source project root, beside project.godot',
              'files': len(files), 'maximum_archive_bytes': limit, 'archives': reports,
              'scope': 'Fixture/source preservation only. No lighting acceptance or playable export.'}
    (out / 'OPTIONAL-LAB-ARCHIVES.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged-lab', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(make_lab_parts(args.staged_lab, args.output, args.label), indent=2))
        return 0
    except (AuditError, OSError, ValueError) as exc:
        print('LAB_ARCHIVE_FAIL:', exc, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
