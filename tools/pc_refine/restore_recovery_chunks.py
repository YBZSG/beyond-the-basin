#!/usr/bin/env python3
"""Restore only hash-declared oversized files after all recovery ZIPs are extracted."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent
manifest=json.loads((root/'RECOVERY-OVERLAY-MANIFEST.json').read_text())
def safe(name):
 p=Path(name)
 if p.is_absolute() or '..' in p.parts: raise ValueError('Unsafe relative path')
 target=root/p
 if not target.resolve().is_relative_to(root): raise ValueError('Path escapes recovery folder')
 return target
for row in manifest.get('chunked_files',[]):
 target=safe(row['path'])
 if target.exists():
  if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=row['sha256']:raise ValueError('Refusing changed existing target: '+row['path'])
  print('Already exact:',row['path']);continue
 data=bytearray()
 for part in row['parts']:
  payload=safe(part['path']).read_bytes()
  if len(payload)!=part['bytes'] or hashlib.sha256(payload).hexdigest()!=part['sha256']:raise ValueError('Part failed SHA256: '+part['path'])
  data.extend(payload)
 if len(data)!=row['bytes'] or hashlib.sha256(data).hexdigest()!=row['sha256']:raise ValueError('Reconstructed file failed SHA256')
 target.parent.mkdir(parents=True,exist_ok=True)
 with target.open('xb') as output:output.write(data)
 print('Restored:',row['path'])
print('Recovery chunks verified. No installation or network action was performed.')
