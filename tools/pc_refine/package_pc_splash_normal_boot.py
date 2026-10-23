#!/usr/bin/env python3
"""Add verified compact terrain reconstruction and normal sibling-PCK boot."""
from pathlib import Path
import sys,os,json,hashlib,base64,struct,shutil,subprocess
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).parent));import package_pc_splash_repair as p

def pack(engine,root,output,files,label):
 work=root/(label+'-packer');work.mkdir(exist_ok=True);(work/'project.godot').write_text('config_version=5\n')
 text='extends SceneTree\nfunc _initialize() -> void:\n\tvar p := PCKPacker.new()\n\tif p.pck_start('+json.dumps(str(output))+') != OK: quit(70); return\n'
 for name,path in files:
  text+='\tif p.add_file('+json.dumps('res://'+name)+','+json.dumps(str(path))+') != OK: quit(71); return\n'
 text+='\tif p.flush() != OK: quit(72); return\n\tprint("PACK_OK")\n\tquit(0)\n';(work/'pack.gd').write_text(text)
 r=subprocess.run([str(engine),'--headless','--path',str(work),'--script',str(work/'pack.gd')],env=p.env_for(root/'packing-user'),capture_output=True,text=True,timeout=120)
 (root/(label+'-pack.log')).write_text(r.stdout+r.stderr);p.require(r.returncode==0 and 'PACK_OK' in r.stdout,'Pack failed '+label)

def augment(out,baseline,proof,engine,template):
 result=json.loads((out/'BUILD-RESULT.json').read_text());stage=Path(result['stage']);host=Path(result['host'])
 eq=json.loads((proof/'retained/CACHE-EQUIVALENCE.json').read_text());p.require(eq['pass'] and len(eq['files'])==16,'Equivalence proof required')
 recipe={'kind':'verified-lossless-cache-header-delta','physical_payloads_freshly_regenerated_and_byte_compared':True,'historical_timing_preserved':True,'files':[]}
 for row in sorted(eq['files'],key=lambda x:x['new_path']):
  old=baseline/'source-staging/assets/cache/source_terrain'/row['old_path'];new=proof/'retained'/Path(row['new_path']).name
  oldbytes=old.read_bytes();newbytes=new.read_bytes();a=19+struct.unpack_from('<I',oldbytes,15)[0];b=19+struct.unpack_from('<I',newbytes,15)[0]
  p.require(oldbytes[a:]==newbytes[b:],'Stored payload is not byte-identical')
  p.require(p.sha(new)==row['retained_sha256'] and p.sha(old)==row['baseline_sha256'],'Equivalence source bytes changed')
  recipe['files'].append({'old_path':'assets/cache/source_terrain/'+row['old_path'],'new_path':row['new_path'],'before_sha256':p.sha(old),'after_sha256':p.sha(new),'old_prefix_bytes':a,'new_prefix_base64':base64.b64encode(newbytes[:b]).decode(),'bytes':len(newbytes)})
 support=out/'bootstrap-inputs';support.mkdir(exist_ok=True)
 p.write_json(support/'pc_splash_cache_recipe.json',recipe)
 cachepack=out/'expected-exact-terrain.pck'
 pack(engine,out,cachepack,[(r['new_path'],proof/'retained'/Path(r['new_path']).name) for r in recipe['files']],'cache')
 for row in recipe['files']:p.require(p.sha_bytes(p.Pck(cachepack).read(row['new_path']))==row['after_sha256'],'Cache pack bytes mismatch')
 bootstrap=(stage/'PC-Splash-Bootstrap.gd').read_text().replace('@CACHE_PACK_SHA256@',p.sha(cachepack)).replace('@CACHE_RECIPE_SHA256@',p.sha(support/'pc_splash_cache_recipe.json'))
 p.require('@CACHE_' not in bootstrap,'Unexpanded cache pins')
 (support/'pc_splash_bootstrap.gd').write_text(bootstrap)
 (stage/'PC-Splash-Bootstrap.gd').write_text(bootstrap)
 shutil.copyfile(p.TOOLS/'package_pc_splash_cache_reconstruct.gd',support/'pc_splash_cache_reconstruct.gd')
 config=(baseline/'source-staging/project.godot').read_text().replace('run/main_scene="res://scenes/main.tscn"','run/main_scene="res://pc_splash_bootstrap.tscn"')
 (support/'project.godot').write_text(config)
 (support/'pc_splash_bootstrap.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://pc_splash_bootstrap.gd" id="1"]\n[node name="PCSplatBootstrap" type="Node"]\nscript = ExtResource("1")\n')
 original=p.Pck(baseline/'pc-staging/PoolCore-Source-Water.pck')
 metadata=['.godot/extension_list.cfg','.godot/global_script_class_cache.cfg','.godot/uid_cache.bin','native/source_water/source_water.gdextension']
 for name in metadata:
  target=support/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(original.read(name))
 names=['project.godot','pc_splash_bootstrap.gd','pc_splash_bootstrap.tscn','pc_splash_cache_recipe.json','pc_splash_cache_reconstruct.gd']+metadata
 runner=stage/'PoolCore-PC-Splash-Launcher.pck';pack(engine,out,runner,[(n,support/n) for n in names],'bootstrap')
 shutil.copyfile(runner,host/runner.name);shutil.copy2(template,host/'PoolCore-PC-Splash-Launcher');(host/'PoolCore-PC-Splash-Launcher').chmod(0o755)
 shutil.copyfile(support/'pc_splash_cache_recipe.json',stage/'Source-Patch/CACHE-RECONSTRUCTION.json')
 shutil.copyfile(support/'pc_splash_cache_reconstruct.gd',stage/'Source-Patch/cache_reconstruct.gd')
 shutil.copyfile(proof/'retained/CACHE-EQUIVALENCE.json',stage/'CACHE-EQUIVALENCE.json')
 # Replace external-script launcher invocation with normal sibling pack boot.
 s=(stage/'Launch-PoolCore-Splash-Repair.cmd').read_text()
 s=s.replace('set "BOOTSTRAP=%ROOT%\\PC-Splash-Bootstrap.gd"','set "BOOTSTRAP=%ROOT%\\PoolCore-PC-Splash-Launcher.pck"\nset "RUNEXE=%ROOT%\\PoolCore-PC-Splash-Launcher.exe"')
 s=s.replace('>>"%REPORT%" echo Baseline and overlay SHA-256 pins verified.', 'certutil -hashfile "%BOOTSTRAP%" SHA256 >"%HASHLOG%" 2>&1\nif errorlevel 1 goto hash_failed\nfindstr /I /X /C:"'+p.sha(runner)+'" "%HASHLOG%" >nul\nif errorlevel 1 goto wrong_patch\n>>"%REPORT%" echo Baseline, overlay and bootstrap SHA-256 pins verified.')
 s=s.replace(':version_ready\n', ':version_ready\nrem A normal sibling PCK works with the official restricted release template.\nrem Copy locally, byte-for-byte; never download or modify an existing engine.\nif /I "%ENGINE%"=="%RUNEXE%" goto engine_copy_ready\nif exist "%RUNEXE%" goto verify_engine_copy\necho Preparing a byte-identical local copy of the selected engine...\ncopy /b "%ENGINE%" "%RUNEXE%" >nul\nif errorlevel 1 goto engine_copy_failed\n:verify_engine_copy\nfc /b "%ENGINE%" "%RUNEXE%" >nul 2>&1\nif errorlevel 1 goto engine_copy_failed\n:engine_copy_ready\n')
 s=s.replace('"%ENGINE%" --path "%ROOT%\\." --main-pack "%PACK%" --rendering-method forward_plus --verbose --log-file "%GODOTLOG%" --script "%BOOTSTRAP%" -- "--pc-splash-root=%ROOT%\\."','"%RUNEXE%" --rendering-method forward_plus --verbose --log-file "%GODOTLOG%" -- "--pc-splash-root=%ROOT%\\."')
 s=s.replace('rem Explicit --path also makes external native dependencies work with a separate engine.\nrem The final \\. avoids a quoted argument ending in a Windows backslash.','rem No --path, --main-pack or --script: official 4.6.3 release templates refuse them.\nrem RUNEXE discovers the identically named sibling bootstrap PCK normally.')
 s=s.replace('Missing the repair PCK or PC-Splash-Bootstrap.gd','Missing the repair PCK or bootstrap PCK')
 s=s.replace('\n:missing_patch','\n:engine_copy_failed\necho Cannot create or verify the separate local engine copy. The game was not started.\necho If PoolCore-PC-Splash-Launcher.exe already exists, keep it for inspection and select the same original engine.\necho The original game EXE and PCK were not changed. No download or security change was attempted.\npause\npopd\nexit /b 12\n\n:missing_patch')
 # A renamed console wrapper is not a portable standalone executable.
 s=s.replace('for %%G in ("%ENGINE%") do set "ENGINE_EXT=%%~xG"','for %%G in ("%ENGINE%") do set "ENGINE_EXT=%%~xG"\nfor %%G in ("%ENGINE%") do set "ENGINE_BYTES=%%~zG"\nif %ENGINE_BYTES% LSS 10000000 goto console_wrapper')
 s=s.replace('\n:engine_copy_failed','\n:console_wrapper\necho Select the full Godot EXE, not its small _console wrapper.\necho The bundled PoolCore-Source-Water.exe is preferred.\npause\npopd\nexit /b 13\n\n:engine_copy_failed')
 (stage/'Launch-PoolCore-Splash-Repair.cmd').write_bytes(s.replace('\r\n','\n').replace('\n','\r\n').encode())
 manifest=json.loads((stage/'PC-SPLASH-MANIFEST.json').read_text())
 manifest.update({'boot_method':'Normal sibling bootstrap PCK; launcher locally copies existing official EXE byte-for-byte. No path/script CLI overrides.', 'bootstrap_pck_sha256':p.sha(runner),'cache_pack_sha256':p.sha(cachepack),'cache_recipe_sha256':p.sha(support/'pc_splash_cache_recipe.json'),'cache_policy':'Freshly regenerated physical payloads were byte-compared to original, with only timing_ms excluded; complete original stored payload bytes and historical timing retained with recomputed current algorithm headers. Deterministic reconstruction is SHA-256 checked before use.','local_disk_cost':'About 31.5 MB permanent exact cache PCK; about 31.5 MB temporary reconstruction files, deleted after successful cache-pack validation; one local byte-identical engine copy (~105 MB for the bundled Windows engine).','cache_files':recipe['files']})
 p.write_json(stage/'PC-SPLASH-MANIFEST.json',manifest)
 result.update({'bootstrap_pck_sha256':p.sha(runner),'cache_pack_sha256':p.sha(cachepack),'native_command':[str(host/'PoolCore-PC-Splash-Launcher'),'--rendering-method','forward_plus','--','--pc-splash-root='+str(host),'--qa','--qa-room=arrival','--qa-impact','--qa-frames=16','--qa-wait-ready','--qa-ready-timeout=400'],'normal_cpu_command':[str(host/'PoolCore-PC-Splash-Launcher'),'--headless','--','--pc-splash-root='+str(host),'--pc-splash-verify-only']})
 p.write_json(out/'BUILD-RESULT.json',result);print(json.dumps(result,indent=2))
if __name__=='__main__':
 import argparse
 a=argparse.ArgumentParser();a.add_argument('--output',type=Path,required=True);a.add_argument('--baseline',type=Path,required=True);a.add_argument('--proof',type=Path,required=True);a.add_argument('--engine',type=Path,default=Path('/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64'));a.add_argument('--template',type=Path,required=True);v=a.parse_args();augment(v.output.resolve(),v.baseline.resolve(),v.proof.resolve(),v.engine.resolve(),v.template.resolve())
