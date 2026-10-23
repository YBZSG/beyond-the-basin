#!/usr/bin/env python3
"""Create hash-indexed PC-only recovery overlays against immutable repair1."""
from pathlib import Path
import hashlib,json,zipfile,datetime,zlib,sys
root=Path(__file__).resolve().parents[2]
base=root.parent/'poolcore-godot-visual-work'
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M')
out=root.parent/'delivery'/'pc-refine-checkpoints';out.mkdir(parents=True,exist_ok=True)
excluded={'.git','.godot','__pycache__','node_modules','build','.cache'}
rows=[]
for p in sorted(root.rglob('*')):
 if not p.is_file():continue
 rel=p.relative_to(root)
 if any(part in excluded for part in rel.parts) or p.suffix in {'.pyc','.p12','.jks','.keystore','.pem','.key'}:continue
 if rel.parts[0]=='output' and not str(rel).startswith('output/pc-refine/'):continue
 data=p.read_bytes();other=base/rel
 digest=hashlib.sha256(data).hexdigest()
 if other.is_file() and hashlib.sha256(other.read_bytes()).hexdigest()==digest:continue
 rows.append((str(rel),data,digest,len(zlib.compress(data,6))+256))
limit=15*1024*1024; groups=[];current=[];size=0
original_rows=list(rows); chunked=[]; prepared=[]
for rel,data,digest,estimate in rows:
 if estimate<=limit:
  prepared.append((rel,data,digest,estimate));continue
 parts=[]
 for start in range(0,len(data),12*1024*1024):
  payload=data[start:start+12*1024*1024]
  path=f'RECOVERY-CHUNKS/{digest}/{len(parts)+1:03d}.bin'
  part_hash=hashlib.sha256(payload).hexdigest()
  prepared.append((path,payload,part_hash,len(zlib.compress(payload,6))+256))
  parts.append({'path':path,'bytes':len(payload),'sha256':part_hash})
 chunked.append({'path':rel,'bytes':len(data),'sha256':digest,'parts':parts})
rows=prepared
for row in rows:
 if current and size+row[3]>limit:groups.append(current);current=[];size=0
 if row[3]>limit:raise SystemExit('Oversize indivisible recovery file: '+row[0])
 current.append(row);size+=row[3]
if current:groups.append(current)
manifest={'kind':'recovery_overlay_not_release','timestamp_utc':stamp,'base':'immutable delivered eight-hour repair1','base_local_folder':base.name,'android':'unchanged; no new Android build','pending':'PC visual lighting/material and engine-clock candidates remain under validation; the separately delivered splash repair is immutable. Tests alone do not establish visual or release acceptance','sealed_splash_patch_sha256':'9b428af241423991daca86f7d81b213ef2c298e23fd4406c448bb08efb6afb9c','chunked_files':chunked,'files':[{'path':r[0],'bytes':len(r[1]),'sha256':r[2]} for r in original_rows]}
written=[]
for i,g in enumerate(groups,1):
 name=f'PoolCore-PC-Refine-Recovery-{stamp}-{i:02d}-of-{len(groups):02d}.zip';p=out/name
 with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  z.writestr('RECOVERY-OVERLAY-MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2))
  z.writestr('RECOVERY-README.txt','Work-in-progress recovery, not a finished release. Apply all independent overlay ZIPs over the delivered eight-hour repair1 source folder. Paths and hashes are in the manifest. Original baseline and Android remain unchanged. Do not treat unfinished diagnostic candidates as approved defaults. If chunked_files is nonempty, extract ALL archives into that source folder, then run python3 restore_recovery_chunks.py there. It verifies SHA256 and reconstructs only the declared oversized source files, refusing changed existing targets. No install or network.\n')
  if chunked:z.write(root/'tools/pc_refine/restore_recovery_chunks.py','restore_recovery_chunks.py')
  for rel,data,digest,_ in g:z.writestr(rel,data)
 with zipfile.ZipFile(p) as z:
  assert z.testzip() is None
  for rel,data,digest,_ in g:assert hashlib.sha256(z.read(rel)).hexdigest()==digest
 written.append({'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'files':len(g)})
index=out/f'PoolCore-PC-Refine-Recovery-{stamp}-index.json';index.write_text(json.dumps(written,indent=2)+'\n')
print(json.dumps({'index':str(index),'files':written},indent=2))
