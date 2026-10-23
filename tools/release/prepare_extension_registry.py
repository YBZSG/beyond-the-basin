#!/usr/bin/env python3
"""Pre-register the known optional helper before a fresh Godot editor scan.

Workaround for the Godot headless first-discovery documentation shutdown race.
Only .godot/extension_list.cfg changes. Existing entries are preserved. No
native binary, source script, import cache, credential, or security setting changes.
"""
import argparse
import json
from pathlib import Path
import sys
from audit_packages import AuditError, DESCRIPTOR, require


def prepare(project):
    root = Path(project).resolve()
    require((root/'project.godot').is_file(), 'Project root does not contain project.godot')
    require((root/DESCRIPTOR).is_file(), 'Known source-water extension descriptor is missing')
    folder = root/'.godot'
    require(not folder.is_symlink(), 'Refusing symlinked .godot directory')
    folder.mkdir(exist_ok=True)
    path = folder/'extension_list.cfg'
    require(not path.is_symlink(), 'Refusing symlinked extension registry')
    entry = 'res://' + DESCRIPTOR
    current = path.read_text(encoding='utf-8-sig') if path.exists() else ''
    existing = [line.strip() for line in current.splitlines() if line.strip()]
    if entry in existing:
        return {'status':'PASS','added':False,'existing_entries_preserved':len(existing),'portable_path':entry}
    updated = current.rstrip('\r\n') + ('\n' if current.strip() else '') + entry + '\n'
    temporary = path.with_suffix('.cfg.tmp')
    require(not temporary.is_symlink(), 'Refusing symlinked registry temporary file')
    temporary.write_text(updated,encoding='utf-8')
    temporary.replace(path)
    return {'status':'PASS','added':True,'existing_entries_preserved':len(existing),'portable_path':entry}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project',type=Path,required=True)
    args=p.parse_args()
    try:
        print(json.dumps(prepare(args.project)))
        return 0
    except (AuditError,OSError,ValueError) as exc:
        print(f'EXTENSION_REGISTRY_FAIL: {exc}',file=sys.stderr)
        return 1

if __name__=='__main__':
    sys.exit(main())
