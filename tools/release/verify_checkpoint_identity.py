#!/usr/bin/env python3
"""Bind a staged checkpoint to completed CPU cache reports without running Godot.

Checks Godot's serialized-string source identities, exact five-room/three-quality
coverage, all early teleports, terrain file hashes, snapshot headers and staged
manifest integrity. It never invents a new engine/GPU/phone validation result.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
# Verification may run from an immutable staged tree; never create local bytecode.
sys.dont_write_bytecode = True
from audit_packages import AuditError, require, safe_name
from stage_release import sha, verify_manifest
from validate_frozen_release import authored_catalog, check_cache_report


def source_string_signature(data):
    data.decode('utf-8')  # Refuse undecodable source rather than silently repair.
    # Godot 4 Variant::STRING serialization: type, UTF-8 count and 4-byte padding.
    encoded = struct.pack('<II', 4, len(data)) + data + b'\0' * (-len(data) % 4)
    return hashlib.sha256(encoded).hexdigest()


def resource_path(root, value):
    require(value.startswith('res://'), f'Cache report path is not a portable resource: {value}')
    path = root / safe_name(value[6:])
    require(path.is_file() and not path.is_symlink(), f'Cache report resource missing: {value}')
    return path


def terrain_header(path, key, algorithm):
    data = Path(path).read_bytes()
    magic = b'POOL_TERRAIN_2\n'
    require(data.startswith(magic) and len(data) > len(magic) + 4, f'Invalid terrain container: {path.name}')
    length = struct.unpack_from('<I', data, len(magic))[0]
    require(2 <= length <= 65536 and len(magic) + 4 + length < len(data), f'Invalid terrain header bounds: {path.name}')
    header = json.loads(data[len(magic) + 4:len(magic) + 4 + length])
    stored = data[len(magic) + 4 + length:]
    require(header.get('schema') == 2 and header.get('codec') == 'zstd', f'Unexpected terrain schema/codec: {path.name}')
    require(header.get('key') == key and header.get('algorithm') == algorithm, f'Terrain identity differs: {path.name}')
    require(header.get('stored_bytes') == len(stored) and hashlib.sha256(stored).hexdigest() == header.get('stored_sha256'),
            f'Stored terrain integrity differs: {path.name}')
    require(isinstance(header.get('bytes'), int) and 0 < header['bytes'] <= 256 * 1024 * 1024,
            f'Uncompressed terrain bounds invalid: {path.name}')
    return header


def verify(root, reports):
    root = Path(root).resolve()
    verify_manifest(root)
    coords, sizes = authored_catalog(root), [384, 768, 1152]
    expected_early = {f'({x}, {y})' for x, y in coords}
    observed, baseline, checked_files, case_reports = set(), None, set(), []
    for report_path in reports:
        report = json.loads(Path(report_path).read_text())
        check_cache_report(report, 250821, sizes, coords)
        early = report.get('early_room')
        if early is not None:
            require(early in expected_early and early not in observed, 'Unexpected/duplicate early-room report')
            observed.add(early)
        if baseline is None:
            baseline = report
        else:
            for field in ('algorithm', 'source_signatures', 'snapshot'):
                require(report[field] == baseline[field], f'Cache reports differ in {field}')
        for rel, expected in report['source_signatures'].items():
            path = resource_path(root, rel)
            require(source_string_signature(path.read_bytes()) == expected, f'Staged source differs from validated loaded script: {rel}')
        for entry in report['terrain']:
            path = resource_path(root, entry['path'])
            require(sha(path) == entry['sha256'], f'Staged terrain differs from CPU-validated bytes: {entry["path"]}')
            terrain_header(path, entry['key'], report['algorithm'])
            checked_files.add(path.relative_to(root).as_posix())
        snapshot = report['snapshot']
        path = resource_path(root, snapshot['expected_path'])
        header = terrain_header(path, snapshot['expected_key'], snapshot['algorithm'])
        checked_files.add(path.relative_to(root).as_posix())
        case_reports.append({'report': Path(report_path).name, 'early_room': early,
                             'valid_terrain_hits': len(report['terrain'])})
    require(observed == expected_early, 'All five early-room CPU reports are required')
    actual_files = {path.relative_to(root).as_posix() for path in (root / 'assets/cache').rglob('*.terrain')}
    require(actual_files == checked_files, 'Staged cache contains extra stale files or misses validated files')
    snapshot_path = resource_path(root, baseline['snapshot']['expected_path'])
    verify_manifest(root)
    return {'status': 'PASS', 'source_signature_files_verified': len(baseline['source_signatures']),
            'terrain_files': len(checked_files), 'terrain_bytes': sum((root / rel).stat().st_size for rel in checked_files),
            'all_early_room_reports': case_reports, 'algorithm': baseline['algorithm'],
            'raw_snapshot_container_sha256': sha(snapshot_path), 'raw_snapshot_uncompressed_sha256': header['sha256'],
            'scope': 'CPU saved-file/hash binding to earlier completed reports only; no new engine/import/GPU validation.',
            'uncompressed_terrain_revalidated_here': False, 'windows_or_phone_executed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged-source', type=Path, required=True)
    parser.add_argument('--cache-reports', nargs='+', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify(args.staged_source, args.cache_reports)
        require(args.staged_source.resolve() not in args.report.resolve().parents,
                'Identity report must stay outside the already-manifested staged source')
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
        return 0
    except (AuditError, OSError, ValueError, KeyError, struct.error) as exc:
        print(f'CHECKPOINT_IDENTITY_FAIL: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
