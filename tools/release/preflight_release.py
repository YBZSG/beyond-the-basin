#!/usr/bin/env python3
"""Read-only release inclusion preflight. No snapshot, engine, export or signing.

This can run while work continues, but its result is only a momentary inventory.
Run frozen staging/audits later to establish the actual delivered byte identity.
"""
import argparse
import json
from pathlib import Path
import re
import sys
# Verification may run from an immutable staged tree; never create local bytecode.
sys.dont_write_bytecode = True
from audit_packages import (AuditError, check_editable_assets, check_export_policy,
                            check_native_bytes, descriptor_libraries, require, runtime_dependencies, check_native_source_identity, check_bake_quarantine)
from stage_release import LAB_PREFIXES, REJECTED_LAB_PAYLOADS, source_paths


resource_dependencies = runtime_dependencies

def preflight(root):
    root = Path(root).resolve()
    require((root / 'project.godot').is_file(), 'Invalid source root')
    policy = check_export_policy(root)
    quarantine = check_bake_quarantine(root)
    assets = check_editable_assets(root)
    dependencies = resource_dependencies(root)
    libraries = descriptor_libraries((root / 'native/source_water/source_water.gdextension').read_bytes())
    native = {platform: check_native_bytes((root / rel).read_bytes(), platform) for platform, rel in libraries.items()}
    profiles = {}
    for profile in ('development', 'final'):
        paths = source_paths(root, profile)
        profiles[profile] = {'files': len(paths), 'uncompressed_bytes': sum(p.stat().st_size for p in paths),
                             'runtime_terrain_files': sum(p.suffix == '.terrain' for p in paths)}
    historical = list((root / 'terrain-cache-history').rglob('*.terrain'))
    return {'status': 'PASS', 'scope': 'Read-only momentary inclusion preflight, not a frozen package or graphical pass.',
            'source_export_policies': policy, 'lighting_policy': quarantine, 'editable_assets': assets, 'native_targets': native,
            'native_atomic_source_dependencies': check_native_source_identity(root, libraries),
            'runtime_literal_dependencies': sorted(dependencies), 'source_profiles': profiles,
            'excluded_historical_terrain': {'files': len(historical), 'bytes': sum(p.stat().st_size for p in historical)},
            'optional_lab_prefixes': list(LAB_PREFIXES), 'rejected_lab_payloads': sorted(REJECTED_LAB_PAYLOADS),
            'verification_limits': ['No engine execution, import, cache rebake, export, APK signing or upload.',
                                    'No Windows, Android device or GPU performance validation.',
                                    'Static literal paths cannot establish dynamically constructed dependency coverage.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('.'))
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        result = preflight(args.source)
        text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(text)
        print(text, end='')
        return 0
    except (AuditError, OSError, ValueError) as exc:
        print(f'RELEASE_PREFLIGHT_FAIL: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
