#!/usr/bin/env python3
"""Build a tiny exact-baseline PC overlay only after its runtime owner freezes it.

No imports/exports of the active project, graphics, downloads, signing, installation,
Android writes, or baseline writes. PCKPacker runs in a new minimal CPU-only project.
The final archive is withheld until the separate native GPU acceptance is supplied.
"""
from __future__ import annotations
import argparse, datetime, hashlib, json, os, re, shutil, subprocess, sys, zipfile
from pathlib import Path
sys.dont_write_bytecode = True
TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS.parent/'release'))
from audit_packages import Pck, require, no_secrets
BASE_SHA='4e7410955bdd01110993917e1fe45a286092339ce725c85bda3c2505925f3210'
FILES=(
 'scripts/water/source_port/source_liquid_mpm.gd',
 'scripts/water/source_port/source_liquid_surface.gd',
 'scripts/water/source_port/source_whitewater_particles.gd',
 'scripts/water/source_water_runtime.gd',
 'scripts/water/source_port/source_mpm_prewarm.gd',
)
EXCLUDED=('scripts/main.gd','scripts/rendering/pool_lighting.gd',
 'scripts/rendering/pool_materials.gd','shaders/ceramic_world.gdshader')
PATCH='PoolCore-PC-Splash-Repair.pck'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def write_json(p,v): Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def env_for(root):
 e=os.environ.copy()
 for var,folder in [('HOME','home'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
  q=root/folder;q.mkdir(parents=True,exist_ok=True);e[var]=str(q)
 return e

def inventory(source, baseline):
 pck=baseline/'pc-staging/PoolCore-Source-Water.pck'
 require(sha(pck)==BASE_SHA,'Delivered baseline PCK differs from the pinned release')
 pk=Pck(pck); require(pk.engine=='4.6.3','Unexpected baseline engine')
 root=baseline/'source-staging'
 rows=[]
 for rel in FILES:
  p=source/rel;require(p.is_file() and not p.is_symlink(),'Missing or symlinked runtime: '+rel)
  old=(root/rel).read_bytes() if (root/rel).is_file() else None
  if old is not None:
   require(pk.read(rel)==old,'Source/PCK baseline mismatch: '+rel)
  else: require(rel not in pk.entries,'New helper unexpectedly exists in baseline')
  require(rel+'.remap' not in pk.entries,'Raw script unexpectedly remapped: '+rel)
  new=p.read_bytes()
  require(new!=old,'Approved runtime file is unchanged: '+rel)
  rows.append({'path':rel,'before_sha256':sha_bytes(old) if old is not None else None,
               'after_sha256':sha_bytes(new),'bytes':len(new),'operation':'replace' if old is not None else 'add'})
 # Original solver GLSL and all scene source stay baseline-exact in this overlay.
 no_secrets(FILES)
 return pk,rows

def plan(source,baseline,out):
 pk,rows=inventory(source,baseline)
 v={'kind':'pc-splash-patch-build-plan','baseline_pck_sha256':BASE_SHA,
    'raw_script_remaps':False,'baseline_main_scene':'res://scenes/main.tscn',
    'approved_runtime_paths':list(FILES),'current_inventory_not_a_freeze':rows,
    'explicitly_excluded_experimental_runtime':list(EXCLUDED),
    'baseline_native_windows_dll_sha256':sha(baseline/'pc-staging/native/source_water/bin/source_water.windows.x86_64.dll'),
    'baseline_official_windows_exe_sha256':sha(baseline/'pc-staging/PoolCore-Source-Water.exe'),
    'android':'untouched','original_solver_glsl':'not patched',
    'dependencies':'Existing repair1 PC installation with exact PCK, original native tree and official Godot 4.6.3 executable.',
    'required_gates':['Explicit runtime freeze','Official PCKPacker CPU build','PCK directory/hash audit','External bootstrap positive/negative CPU tests','Exact final overlay native GPU main-scene smoke','Archive hash/CRC/restore audit'],
    'primary_references':['https://docs.godotengine.org/en/4.6/tutorials/export/exporting_pcks.html','https://docs.godotengine.org/en/4.6/classes/class_pckpacker.html']}
 write_json(out,v);return v

def build(source,baseline,engine,out):
 require(not out.exists(),'Refusing to replace an existing build output')
 pk,rows=inventory(source,baseline)
 out.mkdir(parents=True); stage=out/'patch-staging';stage.mkdir()
 snapshot=out/'frozen-runtime';snapshot.mkdir()
 for row in rows:
  p=snapshot/row['path'];p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/row['path'],p)
  require(sha(p)==row['after_sha256'],'Runtime changed during snapshot: '+row['path'])
 # Closure: static resource dependencies of the selected scripts must be supplied
 # either by this exact overlay or the original exported resources/remaps.
 dependencies=set()
 for rel in FILES:
  text=(snapshot/rel).read_text()
  for path in re.findall(r'(?:preload|load)\(\s*["\']res://([^"\']+)["\']\s*\)',text):
   require(path in FILES or path in pk.entries or path+'.remap' in pk.entries or path+'.import' in pk.entries,'Missing static patch dependency: '+path)
   dependencies.add(path)
 # No changed original GLSL is allowed in the candidate source selected for release.
 for rel,data in pk.entries.items():
  if rel.startswith('shaders/source_water/') and rel.endswith(('.glsl','.glslinc','.vert','.frag','.compute')):
   require((source/rel).is_file() and (source/rel).read_bytes()==data,'Original solver shader changed: '+rel)
 pack_project=out/'packer-project';pack_project.mkdir();(pack_project/'project.godot').write_text('config_version=5\n')
 pack_script='extends SceneTree\nfunc _initialize() -> void:\n\tvar packer := PCKPacker.new()\n'
 pack_script+='\tvar result := packer.pck_start('+json.dumps(str(stage/PATCH))+')\n\tif result != OK: quit(40); return\n'
 for rel in FILES:
  pack_script+='\tresult = packer.add_file('+json.dumps('res://'+rel)+', '+json.dumps(str(snapshot/rel))+')\n\tif result != OK: quit(41); return\n'
 pack_script+='\tresult = packer.flush()\n\tif result != OK: quit(42); return\n\tprint("PC_SPLASH_PACK_CREATED")\n\tquit(0)\n'
 (pack_project/'pack.gd').write_text(pack_script)
 proc=subprocess.run([str(engine),'--headless','--path',str(pack_project),'--script',str(pack_project/'pack.gd')],env=env_for(out/'packer-user'),capture_output=True,text=True,timeout=120)
 (out/'pack.log').write_text(proc.stdout+proc.stderr)
 require(proc.returncode==0 and 'PC_SPLASH_PACK_CREATED' in proc.stdout,'PCKPacker failed; see pack.log')
 patch=Pck(stage/PATCH);require(set(patch.entries)==set(FILES),'Unexpected overlay contents')
 for row in rows: require(sha_bytes(patch.read(row['path']))==row['after_sha256'],'Packed bytes differ: '+row['path'])
 patch_sha=sha(stage/PATCH)
 placeholders={'@BASELINE_SHA256@':BASE_SHA,'@OVERLAY_SHA256@':patch_sha,
  '@PATCH_FILES@':json.dumps({'res://'+r['path']:r['after_sha256'] for r in rows},ensure_ascii=False)}
 for template,name in [('package_pc_splash_bootstrap.gd.in','PC-Splash-Bootstrap.gd'),('package_pc_splash_launcher.cmd.in','Launch-PoolCore-Splash-Repair.cmd')]:
  text=(TOOLS/template).read_text()
  for key,val in placeholders.items():text=text.replace(key,val)
  require('@BASELINE_' not in text and '@OVERLAY_' not in text,'Unexpanded template')
  if name.endswith('.cmd'):text=text.replace('\r\n','\n').replace('\n','\r\n')
  (stage/name).write_bytes(text.encode('utf-8'))
 source_patch=stage/'Source-Patch';source_patch.mkdir()
 for row in rows:
  p=source_patch/row['path'];p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(snapshot/row['path'],p)
 source_manifest={'kind':'full-source-files-overlay-not-complete-project','baseline':'20261022 repair1 final editable source',
  'baseline_source_manifest_sha256':sha(baseline/'source-staging/PACKAGE-MANIFEST.json'),
  'baseline_project_godot_sha256':sha(baseline/'source-staging/project.godot'),
  'files':rows,'not_included':'Unchanged project, assets, native binaries/source/licenses and optional lab remain in the original full editable release.'}
 write_json(source_patch/'SOURCE-PATCH-MANIFEST.json',source_manifest)
 (source_patch/'SOURCE-PATCH-README.txt').write_text('这是完整 .gd 源文件补丁，不是独立工程，也不是只有差异的 diff。\n先保留原版源码备份，再将此目录内 scripts 文件夹合并到 20261022 repair1 的完整源码根目录（project.godot 所在目录）。\n仅替换清单中的 4 个旧脚本，新增 1 个预热辅助脚本。其余模型、贴图、场景、原始求解器着色器、原生库及许可证全部沿用原完整源码。\n源码补丁清单包含精确的替换前/后 SHA-256。自改过的源码请先比较，勿盲目覆盖。\n使用原有 Prepare-Editor.cmd 和 Godot 4.6.3 打开工程。这个文件夹单独不能运行。\n旧 PACKAGE-MANIFEST.json 描述原版，新增 SOURCE-PATCH-MANIFEST.json 描述这五处覆盖，二者不要混称为同一快照。\n',encoding='utf-8')
 manifest={'kind':'exact-baseline-pc-splash-runtime-overlay','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
   'engine':'Godot 4.6.3 Standard','baseline_pck':{'filename':'PoolCore-Source-Water.pck','sha256':BASE_SHA,'bytes':(baseline/'pc-staging/PoolCore-Source-Water.pck').stat().st_size},
   'overlay_pck':{'filename':PATCH,'sha256':patch_sha,'bytes':(stage/PATCH).stat().st_size},
   'runtime_files':rows,'static_dependencies':sorted(dependencies),'unchanged_solver_shaders':True,
   'excluded_experiments':list(EXCLUDED),'android_untouched':True,'baseline_unchanged':True,
   'native_helper':'Keep the original native/source_water tree, DLL, source, build instructions and licenses.',
   'windows_execution':False,'windows_launcher':'Static audit only; no Windows runtime is available here.',
   'native_gpu_acceptance':'pending; archive withheld until accepted','cpu_gate':'pending'}
 write_json(stage/'PC-SPLASH-MANIFEST.json',manifest)
 # A disposable host, not the user payload: baseline plus exact patch and a Linux helper.
 host=out/'graphical-host';host.mkdir()
 shutil.copyfile(baseline/'pc-staging/PoolCore-Source-Water.pck',host/'PoolCore-Source-Water.pck')
 for name in [PATCH,'PC-Splash-Bootstrap.gd']:shutil.copyfile(stage/name,host/name)
 helper=host/'native/source_water/bin/libsource_water.linux.x86_64.so';helper.parent.mkdir(parents=True)
 shutil.copyfile(baseline/'source-staging/native/source_water/bin/libsource_water.linux.x86_64.so',helper)
 for row in rows:require(sha(source/row['path'])==row['after_sha256'],'Active runtime changed after freeze: '+row['path'])
 result={'stage':str(stage),'host':str(host),'baseline_pck_sha256':BASE_SHA,'overlay_pck_sha256':patch_sha,'files':rows,
  'cpu_command':[str(engine),'--headless','--path',str(host),'--main-pack',str(host/'PoolCore-Source-Water.pck'),'--script',str(host/'PC-Splash-Bootstrap.gd'),'--','--pc-splash-root='+str(host),'--pc-splash-verify-only']}
 write_json(out/'BUILD-RESULT.json',result);return result

def cpu_gate(engine,out):
 result=json.loads((out/'BUILD-RESULT.json').read_text());host=Path(result['host']);user=out/'cpu-user';env=env_for(user)
 runs=[]
 def run(label,args,code,needle):
  proc=subprocess.run(args,env=env,capture_output=True,text=True,timeout=120)
  log=proc.stdout+proc.stderr;(out/(label+'.log')).write_text(log)
  require(proc.returncode==code and needle in log,'Bootstrap gate failed: '+label)
  runs.append({'name':label,'exit_code':proc.returncode,'expected_exit':code,'passed':True})
 command=result['cpu_command'];command[0]=str(engine)
 run('cpu-bootstrap-positive',command,0,'PC_SPLASH_REPAIR_VERIFY_ONLY_OK')
 # Root differs while --main-pack remains the genuine baseline. The loader must refuse.
 wrong=out/'wrong-root';wrong.mkdir(exist_ok=True);(wrong/'PoolCore-Source-Water.pck').write_bytes(b'wrong baseline')
 bad=command[:];bad[bad.index('--')+1]='--pc-splash-root='+str(wrong)
 run('cpu-bootstrap-wrong-baseline',bad,22,'PC_SPLASH_REPAIR_REFUSED')
 # Exact baseline with a tampered overlay must fail before mounting any patched script.
 badroot=out/'tampered-root';badroot.mkdir(exist_ok=True)
 shutil.copyfile(host/'PoolCore-Source-Water.pck',badroot/'PoolCore-Source-Water.pck');(badroot/PATCH).write_bytes(b'bad overlay')
 bad=command[:];bad[bad.index('--')+1]='--pc-splash-root='+str(badroot)
 run('cpu-bootstrap-tampered-overlay',bad,23,'PC_SPLASH_REPAIR_REFUSED')
 # Relocation with Chinese, whitespace and exclamation mark, same external engine.
 relocated=out/'中文 PC splash !';relocated.mkdir(exist_ok=True)
 for name in ['PoolCore-Source-Water.pck',PATCH,'PC-Splash-Bootstrap.gd']:shutil.copyfile(host/name,relocated/name)
 shutil.copytree(host/'native',relocated/'native',dirs_exist_ok=True)
 cmd=[str(engine),'--headless','--path',str(relocated),'--main-pack',str(relocated/'PoolCore-Source-Water.pck'),'--script',str(relocated/'PC-Splash-Bootstrap.gd'),'--','--pc-splash-root='+str(relocated),'--pc-splash-verify-only']
 run('cpu-bootstrap-chinese-spaces-bang',cmd,0,'PC_SPLASH_REPAIR_VERIFY_ONLY_OK')
 launcher=(Path(result['stage'])/'Launch-PoolCore-Splash-Repair.cmd').read_bytes();s=launcher.decode()
 require(b'\n' not in launcher.replace(b'\r\n',b''),'Launcher must have CRLF')
 require('DisableDelayedExpansion' in s,'Launcher expands exclamation marks')
 require(s.index('set "ENGINE=%~f1"')<s.index('pushd'),'Dragged engine resolution occurs too late')
 require('--script "%BOOTSTRAP%" -- "--pc-splash-root=%ROOT%\\."' in s,'Incorrect bootstrap CLI')
 require(s.index('certutil -hashfile')<s.index('"%ENGINE%" --headless --version'),'Baseline hash check must precede Godot')
 require('ExecutionPolicy' not in s and 'powershell' not in s.lower() and 'http://' not in s and 'https://' not in s,'Launcher must not download or bypass execution policy')
 # Every label reference must resolve to a unique label, preventing silent GOTO fallthrough.
 labels=re.findall(r'^:([a-z_]+)\s*$',s,re.M);refs=re.findall(r'\bgoto ([a-z_]+)',s,re.I)
 require(len(labels)==len(set(labels)) and set(x.lower() for x in refs)<=set(labels),'Broken launcher label')
 report={'passed':True,'tests':runs,'windows_cmd_static_audit':True,'windows_executed':False,'gpu_executed':False}
 write_json(out/'CPU-GATE.json',report)
 manifest_path=Path(result['stage'])/'PC-SPLASH-MANIFEST.json';manifest=json.loads(manifest_path.read_text());manifest['cpu_gate']='passed: exact raw overlay, loaded source identity, unchanged main scene parse, hash refusal, path relocation';write_json(manifest_path,manifest)
 return report

def finalize(out,evidence):
 result=json.loads((out/'BUILD-RESULT.json').read_text());stage=Path(result['stage'])
 require(json.loads((out/'CPU-GATE.json').read_text())['passed'],'CPU gate must pass first')
 require(evidence.is_file(),'Native acceptance evidence is required')
 acceptance=json.loads(evidence.read_text());require(acceptance.get('accepted') is True,'Native acceptance must explicitly say accepted=true')
 require(acceptance.get('overlay_pck_sha256')==result['overlay_pck_sha256'],'Native acceptance must bind exact patch hash')
 require(acceptance.get('bootstrap_pck_sha256')==result['bootstrap_pck_sha256'],'Native acceptance must bind exact normal bootstrap hash')
 require(acceptance.get('cache_pack_sha256')==result['cache_pack_sha256'],'Native acceptance must bind exact cache pack hash')
 require(sha(stage/PATCH)==result['overlay_pck_sha256'],'Overlay changed after validation')
 require(sha(stage/'PoolCore-PC-Splash-Launcher.pck')==result['bootstrap_pck_sha256'],'Bootstrap changed after validation')
 require(sha(Path(result['host'])/'PoolCore-Source-Water.pck')==BASE_SHA,'Baseline changed after validation')
 for row in result['files']:require(sha(stage/'Source-Patch'/row['path'])==row['after_sha256'],'Source patch changed after validation')
 shutil.copyfile(evidence,stage/'NATIVE-ACCEPTANCE.json');shutil.copyfile(out/'CPU-GATE.json',stage/'CPU-GATE.json')
 manifest=json.loads((stage/'PC-SPLASH-MANIFEST.json').read_text());manifest['native_gpu_acceptance']='See NATIVE-ACCEPTANCE.json, bound to the exact overlay SHA-256';write_json(stage/'PC-SPLASH-MANIFEST.json',manifest)
 readme='''PoolCore PC 水花更新 | 2026-10-22

这是小型增量补丁，不是独立游戏。已下载过 20261022 repair1 完整 PC 版的用户，无需重下 7 个 PC 包和 6 个源码包。
1. 先关闭游戏。将本 ZIP 的内容解压到原 PC 游戏目录，与 PoolCore-Source-Water.pck、PoolCore-Source-Water.exe 及 native 文件夹放在同一层。
2. 双击 Launch-PoolCore-Splash-Repair.cmd。以后也从这个新入口启动更新版。
3. 若自行使用官方 Godot，请把完整的 Godot 4.6.3 Standard Windows x86_64 EXE 拖到新 CMD 上。原完整 PC 版已包含对应引擎，不需安装或联网。

脚本会先检查原 PCK、补丁 PCK 和引导 PCK 的精确 SHA-256。不匹配就停止，不会覆盖原文件、改安全设置、下载安装或上传日志。其他 Godot 版本会被拒绝。
路径可包含空格；CMD 禁用了延迟变量展开，避免 ! 被吞掉。中文/空格/! 路径经过 Linux 资源加载验证；Windows CMD 只做了静态审计，未在真实 Windows/GPU 上执行。
启动失败或退出后控制台会保留，日志写在当前目录。日志可能包含本地路径及显卡信息，请检查后再分享。

启动器会在本机创建约 105 MB 的引擎副本，字节完全相同，不会重新下载。正常通过同名引导 PCK 启动，不依赖正式导出引擎不支持的 --script 等覆盖参数。
首次运行会从已核对的原缓存重新组合约 31 MB 的精确缓存包，随后复用。使用原附带引擎时，需要约 170 MB 可用空间供副本、缓存及临时文件使用；若选用完整编辑器 EXE，按该 EXE 的实际大小再加约 64 MB 预留。全部 15 个地形缓存和 1 个房间快照均先重新构建并验证物理数据相同，只保留原来的历史 timing_ms 计时元数据，再按新代码生成正确指纹。不是未经验证的改标签，也不会重新烘焙可选大资产。

恢复原版：关闭游戏，直接运行原 PoolCore-Source-Water.exe 即可。原版 PCK、native 原生库、源码/许可证、存档设置和 Android 交付均未替换。
补丁只替换水花相关的 4 个运行时脚本并新增 1 个预热辅助脚本，原始求解器 GLSL、场景、材质和未验收的灯光实验均不混入。
具体验证范围及限制见 PC-SPLASH-MANIFEST.json、CPU-GATE.json 和 NATIVE-ACCEPTANCE.json。局部调度及软件 Vulkan 验证不代表你的整机帧率保证。
本次通过的是官方 Linux 发布模板、正常 Medium 预设（GI 关闭）的整合功能验证：原 25 房间、地形/反射就绪、实际水花、截图和退出均完成。但软件 Vulkan 的 16 帧平均耗时约 1.528 秒、p95 约 7.369 秒，首次水花仍明显过载，不能称为实时性能通过。退出时仍出现 7 个 Texture RID 清理警告，原始日志已保留。
High 档的云端软件 Vulkan 图形测试进入原房间并通过预热后，在完整 25 房间地形准备期间约 211 秒、进程内存约 3.87 GiB 时收到 SIGKILL 而终止，原因未确认。因此这次未完成 High 档验收，也未在真实 Windows 显卡上执行，不能据此保证 High 档帧率或稳定性。另一次 Medium 水/阴影加 QA 强制开启 SDFGI 的运行在约 199 秒、4.42 GiB RSS 时也收到 SIGKILL；原因未确认，它不是正常 Medium 预设的验证。

Source-Patch 内有上述 5 个完整可编辑 .gd 文件、精确替换前/后清单、完整源代码应用工具和缓存重建清单，必须配合已有完整 repair1 源码工程，不能单独当工程打开。仅玩游戏时无需操作该文件夹。
开发者请先关闭编辑器，阅读 Source-Patch/SOURCE-PATCH-README.txt 并运行其中的 Apply-Source-Patch.cmd。必须使用完整的官方 Godot 4.6.3 Standard 编辑器，不是游戏 EXE。不应仅复制这 5 个 .gd 文件，否则缓存指纹会不匹配。工具先验证原文件与依赖并备份，再安装全部脚本和精确缓存。
'''
 (stage/'开始使用-PC水花更新.txt').write_text(readme,encoding='utf-8')
 files=sorted(p for p in stage.rglob('*') if p.is_file());no_secrets(p.relative_to(stage).as_posix() for p in files)
 for p in files:require(not p.is_symlink(),'Symlink in payload')
 entries=[{'path':p.relative_to(stage).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in files]
 write_json(stage/'PATCH-PACKAGE-MANIFEST.json',{'files':entries,'runtime_base':BASE_SHA,'kind':'small-pc-overlay-with-full-source-patch'})
 archive=out/'PoolCore-PC-Splash-Repair-20261022.zip';require(not archive.exists(),'Archive already exists')
 with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for p in sorted(stage.rglob('*')):
   if p.is_file():
    info=zipfile.ZipInfo(p.relative_to(stage).as_posix(),(2026,10,22,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,p.read_bytes())
 with zipfile.ZipFile(archive) as z:
  require(z.testzip() is None,'Archive CRC failed');require(len(z.namelist())==len(set(z.namelist())),'Duplicate archive entries')
  for row in entries:require(sha_bytes(z.read(row['path']))==row['sha256'],'Archive hash mismatch')
 require(archive.stat().st_size<16000000,'Small patch unexpectedly exceeds upload bound')
 receipt={'archive':str(archive),'bytes':archive.stat().st_size,'sha256':sha(archive),'files':len(entries)+1,'baseline_pck_sha256':BASE_SHA,'overlay_pck_sha256':result['overlay_pck_sha256'],'original_baseline_untouched':True,'windows_executed':False}
 write_json(out/'DELIVERY-RECEIPT.json',receipt);return receipt

def main():
 a=argparse.ArgumentParser();a.add_argument('mode',choices=['plan','build','cpu-gate','finalize'])
 a.add_argument('--source',type=Path);a.add_argument('--baseline',type=Path);a.add_argument('--engine',type=Path,default=Path('/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64'))
 a.add_argument('--output',type=Path,required=True);a.add_argument('--runtime-frozen',action='store_true');a.add_argument('--acceptance',type=Path)
 args=a.parse_args();out=args.output.resolve()
 if args.mode in ['plan','build']:
  require(args.source and args.baseline,'--source and --baseline are required');source=args.source.resolve();baseline=args.baseline.resolve()
  if args.mode=='plan':r=plan(source,baseline,out)
  else:require(args.runtime_frozen,'Owner must explicitly freeze runtime before build');r=build(source,baseline,args.engine.resolve(),out)
 elif args.mode=='cpu-gate':r=cpu_gate(args.engine.resolve(),out)
 else:require(args.acceptance,'--acceptance required');r=finalize(out,args.acceptance.resolve())
 print(json.dumps(r,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
