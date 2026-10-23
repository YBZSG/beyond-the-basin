#!/usr/bin/env python3
"""Package a verified source delta; restore to a new folder, never modify the base."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil
import sys
sys.dont_write_bytecode = True
import zipfile
import zlib
from audit_packages import AuditError, no_secrets, require
from stage_release import sha, verify_manifest

RESTORER = '''#!/usr/bin/env python3
"""Restore this recovery into a NEW directory. No engine, export, or installation."""
import argparse, hashlib, json, pathlib, shutil, sys
PIN = {pin!r}
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''): h.update(b)
    return h.hexdigest()
def safe(root,name):
    p=pathlib.PurePosixPath(name)
    if not name or p.is_absolute() or '..' in p.parts or '\\\\' in name or ':' in name:
        raise ValueError('Unsafe recovery path')
    path=root.joinpath(*p.parts)
    if root.is_symlink() or any(q.is_symlink() for q in [path,*path.parents] if q==root or root in q.parents):
        raise ValueError('Symlink in recovery input: '+name)
    return path
def check(root,entries):
    for e in entries:
        p=safe(root,e['path'])
        if not p.is_file() or p.stat().st_size!=e['bytes'] or digest(p)!=e['sha256']:
            raise ValueError('Missing/changed recovery input: '+e['path'])
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args()
try:
    here=pathlib.Path(__file__).resolve().parent
    receipt=here/'RECOVERY-DELTA.json'
    if digest(receipt)!=PIN: raise ValueError('Recovery delta manifest SHA-256 mismatch')
    d=json.loads(receipt.read_text())
    base=a.base.absolute(); out=a.output.absolute()
    if out.exists(): raise ValueError('Output must not exist; preserve the old recovery')
    if base==out or base in out.parents or here==out or here in out.parents:
        raise ValueError('Output must be separate from base and delta')
    check(base,d['base_files']); check(here/'PAYLOAD',d['payload_files'])
    payload={{e['path'] for e in d['payload_files']}}
    out.mkdir(parents=True)
    for e in d['target_files']:
        root=here/'PAYLOAD' if e['path'] in payload else base
        src=safe(root,e['path']); dst=safe(out,e['path'])
        dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
    check(out,d['target_files'])
    expected={{e['path'] for e in d['target_files']}}
    actual={{p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file()}}
    if actual!=expected: raise ValueError('Restored file set differs from target')
    print('RECOVERY RESTORED:',out)
    print('Development checkpoint only. Lighting candidate is quarantined, not accepted.')
    print('Base preserved. Omitted old paths:',len(d['deleted_paths']))
except Exception as exc:
    print('RESTORE FAILED:',exc,file=sys.stderr)
    print('Do not treat a partial output as a working recovery.',file=sys.stderr)
    sys.exit(1)
'''


def entries(root):
    return [{'path':p.relative_to(root).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}
            for p in sorted(root.rglob('*')) if p.is_file()]


def build(base, current, base_archives, base_uploads, out, label, utc, limit=16_000_000,
          reuse_unchanged_terrain=False):
    base,current,out=Path(base).resolve(),Path(current).resolve(),Path(out).resolve()
    require(not out.exists(), 'Use a new recovery output directory')
    require(out != current and current not in out.parents and out != base and base not in out.parents,
            'Recovery output must be separate from source/base')
    require(label and all(c.isalnum() or c in '-_' for c in label),'Invalid recovery label')
    require(utc==datetime.strptime(utc,'%Y-%m-%dT%H:%M:%SZ').strftime('%Y-%m-%dT%H:%M:%SZ'),'Invalid snapshot UTC')
    verify_manifest(base);verify_manifest(current)
    old,new=entries(base),entries(current)
    oldmap={e['path']:e for e in old};newmap={e['path']:e for e in new}
    payload=[e for e in new if oldmap.get(e['path'])!=e or
             (not reuse_unchanged_terrain and e['path'].startswith('assets/cache/source_terrain/'))]
    payload_names={e['path'] for e in payload}
    reused_terrain=[e for e in new if e['path'].startswith('assets/cache/source_terrain/') and e['path'] not in payload_names]
    require(all(oldmap.get(e['path'])==e for e in reused_terrain), 'Reused terrain differs from verified base')
    deleted=sorted(set(oldmap)-set(newmap))
    no_secrets(e['path'] for e in payload)
    archives=json.loads(Path(base_archives).read_text())
    uploads=json.loads(Path(base_uploads).read_text())
    ids={e['file_name']:e['library_file_id'] for e in uploads['results'] if e['status']=='succeeded'}
    baseline=[]
    for item in archives['archives']:
        require(item['filename'] in ids, 'Missing durable base Library ID: '+item['filename'])
        baseline.append({**item,'library_file_id':ids[item['filename']]})
    out.mkdir(parents=True)
    stage=out/'delta-staging';stage.mkdir();(stage/'PAYLOAD').mkdir()
    for e in payload:
        target=stage/'PAYLOAD'/e['path'];target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(current/e['path'],target)
        require(sha(target)==e['sha256'],'Delta copy changed: '+e['path'])
    receipt={'format':1,'kind':'incremental-development-recovery','snapshot_utc':utc,
             'base_snapshot_utc':archives['snapshot_utc'],'base_project_folder':archives['project_folder'],
             'base_archives':baseline,'base_archives_manifest_sha256':sha(Path(base_archives)),
             'base_checkpoint_manifest':archives,
             'base_metadata_library_files':[{'filename':r['file_name'],'library_file_id':r['library_file_id']} for r in uploads['results'] if r['status']=='succeeded' and r['file_name'].endswith('.json')],
             'base_files':old,'target_files':new,'payload_files':payload,'deleted_paths':deleted,
             'delete_policy':'Never delete from the base. Restore constructs a new tree and omits these old paths.',
             'all_current_terrain_payloads_included':not reused_terrain,
             'unchanged_terrain_reused_from_verified_base':reused_terrain,
             'terrain_payload_policy':'changed-only-exact-base-bound' if reuse_unchanged_terrain else 'all-current-terrain',
             'candidate_lighting_accepted':False,
             'scope':'Recovery only, not a final build, graphical acceptance, PCK or APK.',
             'excluded_in_progress':'output/ and *.log; in-progress native A/B is not claimed complete.'}
    (stage/'RECOVERY-DELTA.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    (stage/'Restore-Recovery.py').write_text(RESTORER.format(pin=sha(stage/'RECOVERY-DELTA.json')))
    (stage/'RESTORE.txt').write_text('''增量开发恢复检查点，不是最终发行版，也不是独立完整工程。
1. 先完整还原 RECOVERY-DELTA.json 所指定的基础检查点。若基础本身是增量，须先完成其恢复链。
2. 再把本次所有增量 ZIP 解压到另一个共同目录。不要覆盖基础工程。
3. 使用 Python 3，运行本目录的 Restore-Recovery.py：
   python Restore-Recovery.py --base "基础工程目录" --output "尚不存在的新恢复目录"
程序核对基础文件及增量 SHA-256，只在新目录恢复，不删除或修改基础工程。
RECOVERY-DELTA.json 明确列出基础 ZIP 的 Library ID/散列、完整恢复链、全部新文件和删除差异。
光照候选与原生烘焙仅作为隔离恢复证据保存，不表示图形验收通过。

Fully restore the exact base checkpoint specified in RECOVERY-DELTA.json first.
If it is itself incremental, complete its recorded base recovery chain first.
Extract ALL matching new delta ZIPs together elsewhere. Run the Python command above, choosing a NEW output
folder. The base is verified and preserved; deleted-path records are omission
instructions for the new tree, never destructive actions against your old copy.
Do not open a partial recovery. Final native visual and device acceptance remain
separate. No engine, SDK, signing key, installation or publication is included.
''')
    files=entries(stage); groups={'source-and-evidence':[],'native-bake-candidate':[],'terrain-cache':[]}
    for e in files:
        path=e['path']
        category='terrain-cache' if path.startswith('PAYLOAD/assets/cache/source_terrain/') else 'native-bake-candidate' if path.startswith('PAYLOAD/assets/lighting/') else 'source-and-evidence'
        groups[category].append(e)
    bins=[]
    for category, rows in groups.items():
        batch=[];budget=4096
        for e in rows:
            estimate=len(zlib.compress((stage/e['path']).read_bytes(),9))+len(e['path'].encode())*2+len(label)*2+256
            require(estimate+4096<limit,'One delta file exceeds ZIP bound: '+e['path'])
            if batch and budget+estimate>limit-65536:bins.append((category,batch));batch=[];budget=4096
            batch.append(e);budget+=estimate
        if batch:bins.append((category,batch))
    report=[];seen=set();(out/'archives').mkdir()
    for n,(category,rows) in enumerate(bins,1):
        path=out/'archives'/f'{label}-{n:02d}-{category}.zip'
        with zipfile.ZipFile(path,'x',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
            for e in rows:
                info=zipfile.ZipInfo(label+'/'+e['path'],(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=(0o100755 if (stage/e['path']).stat().st_mode&0o111 else 0o100644)<<16
                z.writestr(info,(stage/e['path']).read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
                require(e['path'] not in seen,'Duplicate delta ZIP path');seen.add(e['path'])
        require(path.stat().st_size<limit,'Delta ZIP exceeds bound')
        with zipfile.ZipFile(path) as z:
            require(z.testzip() is None,'Delta ZIP CRC failure')
            for e in rows:require(hashlib.sha256(z.read(label+'/'+e['path'])).hexdigest()==e['sha256'],'Delta archive entry mismatch')
        report.append({'filename':path.name,'bytes':path.stat().st_size,'sha256':sha(path),'files':len(rows),'category':category})
    require(seen=={e['path'] for e in files},'Delta ZIP union differs from staging')
    verify_manifest(base);verify_manifest(current)
    result={'status':'PASS','kind':receipt['kind'],'snapshot_utc':utc,'project_folder':label,
            'base_archives':baseline,'base_checkpoint_manifest':archives,'target_files':len(new),'payload_files':len(payload),'deleted_paths':deleted,
            'delta_manifest_sha256':sha(stage/'RECOVERY-DELTA.json'),'archives':report,
            'maximum_archive_bytes':limit,'candidate_lighting_accepted':False}
    (out/'INCREMENTAL-ARCHIVES.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('base','current','base-archives','base-uploads','output'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--label',required=True);p.add_argument('--snapshot-utc',required=True)
    p.add_argument('--reuse-unchanged-terrain',action='store_true',
                   help='Keep only byte-identical terrain in the hash-verified base; include every changed terrain file')
    a=p.parse_args()
    try:
        print(json.dumps(build(a.base,a.current,a.base_archives,a.base_uploads,a.output,a.label,a.snapshot_utc,
                               reuse_unchanged_terrain=a.reuse_unchanged_terrain),indent=2));return 0
    except (AuditError,OSError,ValueError,KeyError) as e:
        print('INCREMENTAL_RECOVERY_FAIL:',e,file=sys.stderr);return 1
if __name__=='__main__':sys.exit(main())
