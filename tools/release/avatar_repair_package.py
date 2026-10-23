#!/usr/bin/env python3
"""Build an exact-base, byte-copy-only PC repair; never modify the original PCK."""
from pathlib import Path
import hashlib,json,struct,subprocess,os,shutil,sys,zipfile,re
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).parent))
from audit_packages import Pck,require,no_secrets
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT.parent/'delivery/avatar-repair-20261022'
BASE=ROOT.parent/'delivery/pc-expansion-20261022/export-03/PoolCore-PC-Expansion-20261022.pck'
BASESOURCE=ROOT.parent/'delivery/pc-expansion-20261022/build-03'
ENGINE=Path('/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64')
BASEHASH='075b795ec945fa94c82610236590cc5bd1339dafec86c624dafe1c707e7b0f35'
TARGET='PoolCore-PC-Avatar-Repair-20261022.pck'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def digest(b):return hashlib.sha256(b).hexdigest()
def js(p,v):p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
def ranges(p):
 b=p.read_bytes();ver=struct.unpack_from('<I',b,4)[0];base=struct.unpack_from('<Q',b,24)[0];o=struct.unpack_from('<Q',b,32)[0] if ver==3 else 96;n=struct.unpack_from('<I',b,o)[0];o+=4;r={}
 for _ in range(n):
  z=struct.unpack_from('<I',b,o)[0];o+=4;k=b[o:o+z].rstrip(b'\0').decode().removeprefix('res://');o+=z;a,l=struct.unpack_from('<QQ',b,o);o+=36;r[k]=(a+base,l)
 return r

def main():
 OUT.mkdir(exist_ok=True);stage=OUT/'play-staging';stage.mkdir(exist_ok=True)
 require(sha(BASE)==BASEHASH,'Wrong base')
 freeze=json.loads((OUT/'FINAL-FREEZE.json').read_text())
 for p,h in freeze.items():require(sha(ROOT/p)==h,'Freeze changed: '+p)
 pk=Pck(BASE);allfiles=dict(pk.entries)
 changed=[p for p in freeze if p.startswith('scripts/')] + ['assets/models/avatar/avatar_manifest.json']
 imp='assets/models/avatar/pool_explorer.glb.import'
 scene=re.search(r'path="res://([^"]+)"',pk.read(imp).decode()).group(1)
 md5=(ROOT/scene).with_suffix('.md5').read_text()
 require(hashlib.md5((ROOT/'assets/models/avatar/pool_explorer.glb').read_bytes()).hexdigest() in md5,'Imported avatar is stale')
 changed.append(scene)
 records=[]
 for p in changed:
  new=(ROOT/p).read_bytes();old=allfiles.get(p);allfiles[p]=new
  records.append({'path':p,'before_sha256':digest(old) if old is not None else None,'after_sha256':digest(new),'bytes':len(new)})
 packroot=OUT/'packer-project';packroot.mkdir(exist_ok=True);(packroot/'project.godot').write_text('config_version=5\n')
 data=OUT/'packed-resources';data.mkdir(exist_ok=True)
 script='extends SceneTree\nfunc _initialize():\n\tvar p = PCKPacker.new()\n\tassert(p.pck_start('+json.dumps(str(OUT/TARGET))+') == OK)\n'
 for k,v in sorted(allfiles.items()):
  f=data/k;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(v)
  script+='\tassert(p.add_file('+json.dumps('res://'+k)+', '+json.dumps(str(f))+') == OK)\n'
 script+='\tassert(p.flush() == OK)\n\tprint("AVATAR_REPAIR_PACK_OK")\n\tquit()\n';(packroot/'pack.gd').write_text(script)
 env=os.environ.copy();home=OUT/'isolated-home';home.mkdir(exist_ok=True);env['HOME']=str(home)
 for var in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
  q=home/var;q.mkdir(exist_ok=True);env[var]=str(q)
 proc=subprocess.run([str(ENGINE),'--headless','--path',str(packroot),'--script',str(packroot/'pack.gd')],env=env,capture_output=True,text=True,timeout=120)
 (OUT/'pack.log').write_text(proc.stdout+proc.stderr);require(proc.returncode==0 and 'AVATAR_REPAIR_PACK_OK' in proc.stdout,'Native pack build failed')
 target=OUT/TARGET;new=Pck(target);require(set(new.entries)==set(allfiles),'New entries differ')
 for k,v in allfiles.items():require(new.read(k)==v,'Packed bytes differ: '+k)
 br=ranges(BASE);nr=ranges(target);nb=target.read_bytes();payload=bytearray();ops=[];pos=0
 def literal(b):
  if not b:return
  ops.append(['payload',len(payload),len(b)]);payload.extend(b)
 for k,(start,length) in sorted(nr.items(),key=lambda x:x[1][0]):
  require(start>=pos,'Overlapping new pack records');literal(nb[pos:start])
  if k in br and pk.entries[k]==new.entries[k]:ops.append(['base',br[k][0],length])
  else:literal(nb[start:start+length])
  pos=start+length
 literal(nb[pos:]);(stage/'Avatar-Repair.payload').write_bytes(payload)
 manifest={'format':'poolcore-byte-range-delta-v1','base_file':BASE.name,'base_sha256':BASEHASH,'base_bytes':BASE.stat().st_size,'output_file':TARGET,'output_sha256':sha(target),'output_bytes':len(nb),'payload_file':'Avatar-Repair.payload','payload_sha256':digest(payload),'payload_bytes':len(payload),'operations':ops,'runtime_files':records,'unchanged_resources':len(pk.entries)-len([r for r in records if r['before_sha256']]),'tested_engine':'Godot 4.6.3 Linux CPU','windows_executed':False,'gpu_acceptance':'pending separately','baseline_preserved':True,'android_unchanged':True}
 js(stage/'AVATAR-REPAIR-MANIFEST.json',manifest)
 b=BASE.read_bytes();rebuilt=b''.join((b if kind=='base' else payload)[start:start+length] for kind,start,length in ops)
 require(rebuilt==nb,'Python reconstruction failed')
 js(OUT/'BUILD-RESULT.json',{'pck':str(target),'pck_sha256':sha(target),'stage':str(stage),'payload_bytes':len(payload),'changed_resources':records,'freeze':freeze})
 print(json.dumps({'pck':str(target),'sha256':sha(target),'bytes':len(nb),'payload_bytes':len(payload),'resources':len(new.entries)},indent=2))
if __name__=='__main__':main()
