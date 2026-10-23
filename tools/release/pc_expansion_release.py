#!/usr/bin/env python3
"""PC expansion-only release policy. Offline; never exports, runs Godot or uploads.

Preflight is safe on live inputs. Freeze/staging must be deliberately requested
by the release owner after writes stop. Historical release helpers are unchanged.
"""
from __future__ import annotations
import argparse
import configparser
from datetime import datetime, timezone
from fnmatch import fnmatchcase
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / 'pc_refine'))
from audit_packages import (AuditError, Pck, DESCRIPTOR, RAW_SUFFIXES, require, safe_name,
    no_secrets, descriptor_libraries, check_native_bytes, check_native_source_identity,
    check_editable_assets, check_bake_quarantine, check_registration)
from stage_release import sha, manifest, verify_manifest, stage_windows_executable
import package_pc_visual_milestone as previous

PACK_NAME = 'PoolCore-PC-Expansion-20261022.pck'
DOC = 'docs/PC-EXPANSION-RELEASE.md'
USER_GUIDE = 'docs/PC-EXPANSION-USER-GUIDE.md'
ROOMS = ('shower_changing', 'low_arched_bath', 'skylight_gallery', 'service_transition')
PROPS = ('facility_bench', 'facility_shower', 'facility_drain', 'facility_rail',
         'facility_portal', 'facility_wayfinding', 'facility_service_door')
CLIPS = {'Idle', 'Walk', 'Run', 'Hold', 'Wade', 'Swim', 'Climb'}
PREVIEW_SCENE = previous.PREVIEW_SCENE
PREVIEW_PREFIX = previous.PREVIEW_PREFIX
# Exact bytes from delivered immutable pc-visual-milestone-20261022/build-project-01.
# This is an opt-in preview exception, NOT broad final-lighting acceptance.
PREVIEW_PINS = {
    PREVIEW_PREFIX+'asset_stage_manifest.json': 'be39b8c3a345301d72393f788129c247cd5feef93ca06f120e5ebf29ae959fc1',
    PREVIEW_PREFIX+'indirect_00.exr': '8aabb748f20fad0d36fadee1d8288aded72ac9660cdd2687806a43a7618c1f95',
    PREVIEW_PREFIX+'indirect_00.exr.import': 'f4bd323f9ee2f049e6df5495cb0d6346333863d09cd8abceffab4b5937e06b32',
    PREVIEW_PREFIX+'native_indirect.lmbake': '57d7fdc37f152eb046dfd673dd4e76878e6258ca89a55f502defdcc32a604b18',
    PREVIEW_SCENE: 'e78182701bb135fb350895f4409a2e9fa242cfa94835bb3a12ca47a73ce45583',
}
PREVIEW_IMPORT_PINS = {'.godot/imported/indirect_00.exr-5ee7f9ca0e789286f591be67b6adca8b.ctexarray':
                       '4db3ef9ac45ef660fa102accab779fce5f5ebc613a98d62930c664da8af086d0'}
BUILD_META = ('.godot/extension_list.cfg', '.godot/global_script_class_cache.cfg', '.godot/uid_cache.bin', '.godot/.gdignore')
TEXT_RES = {'.gd', '.gdshader', '.gdshaderinc', '.tscn', '.tres', '.glsl', '.glslinc'}
EXTRA_REQUIRED = (
    'scripts/world/expanded_room_catalog.gd', 'scripts/world/expanded_room_builder.gd',
    'scripts/world/expanded_facility_model.gd', 'scripts/player/pool_avatar.gd',
    'shaders/avatar_body.gdshader', 'tools/blender/expansion/build_expansion.py',
    'tools/blender/avatar/build_explorer.py', 'tools/blender/avatar/pool_explorer.blend',
    'tools/blender/avatar/reference_prompt.txt',
    'assets/models/avatar/explorer_reference_ai.png',
    'assets/models/expansion/reference/poolcore_ai_architecture_reference.png',
    'assets/models/avatar/avatar_manifest.json', 'assets/models/expansion/manifest.json',
    'native/source_water/build.sh', 'native/source_water/acquire_toolchain.py',
    'native/source_water/toolchain-packages.json', 'native/source_water/LICENSE',
    'native/source_water/THIRD_PARTY_NOTICES.md', 'native/source_water/README.md', DOC, USER_GUIDE)
LIMITS = [
    'Static package/byte evidence is not a native GPU, Windows CMD, animation-quality or performance pass.',
    'Android is paused; existing source/binaries are preserved, no APK/export/signing changes are made.',
    'The accepted byte-pinned mainhall bake is session-only opt-in preview, not whole-game lighting acceptance.',
    'Native source and actual exported-PCK evidence must be reported separately and bind their exact tested inputs.',
    'Content scan covers named high-confidence secret patterns, not every possible credential.',
]


def write_json(path, data):
    path = Path(path)
    require(not path.exists(), 'Refusing existing report/output: '+str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def regular(root, name):
    safe_name(name)
    p = root/name
    require(p.is_file() and not p.is_symlink(), 'Missing/non-regular input: '+name)
    require(root.resolve() in p.resolve().parents, 'Input escapes project: '+name)
    return p


def glb_json(path):
    data = path.read_bytes()
    require(len(data) >= 20 and struct.unpack_from('<III', data) == (0x46546C67, 2, len(data)), 'Invalid GLB2: '+path.name)
    size, kind = struct.unpack_from('<II', data, 12)
    require(kind == 0x4E4F534A and 20+size <= len(data), 'Invalid GLB JSON chunk: '+path.name)
    return json.loads(data[20:20+size].decode().rstrip('\0 '))


def import_targets(data):
    return re.findall(r'^path(?:\.[^=\n]+)?="res://([^"\n]+)"', data.decode('utf-8').rstrip('\0'), re.M)


def expected_assets(root):
    legacy = check_editable_assets(root)
    records = json.loads(regular(root, 'assets/models/expansion/manifest.json').read_text())
    require(set(records) == set(ROOMS+PROPS), 'Expansion manifest must contain exactly four rooms and seven props')
    runtime, editable = set(), set(EXTRA_REQUIRED)
    for file, constant, expected in (('scripts/world/expanded_room_catalog.gd', 'MODULES', ROOMS), ('scripts/world/expanded_facility_model.gd', 'NAMES', PROPS)):
        match = re.search(r'const '+constant+r'\s*:?=\s*\[([^\]]+)\]', regular(root, file).read_text())
        require(match is not None and tuple(re.findall(r'"([^"]+)"', match.group(1))) == expected, 'Dynamic asset catalog changed: '+file)
    for name in ROOMS+PROPS:
        g = 'assets/models/expansion/'+name+'.glb'
        b = 'tools/blender/expansion/source/'+name+'.blend'
        require(records[name]['glb'] == g and records[name]['source_blend'] == b, 'Unexpected model/source mapping: '+name)
        glb_json(regular(root, g)); runtime.add(g); editable.add(b)
    avatar = 'assets/models/avatar/pool_explorer.glb'
    data = glb_json(regular(root, avatar)); runtime.add(avatar)
    require(data.get('skins') and any('skin' in n for n in data.get('nodes', [])), 'Avatar is not actually skinned')
    names = {a.get('name') for a in data.get('animations', [])}
    require(CLIPS <= names, 'Avatar GLB lacks authored clips: '+str(sorted(CLIPS-names)))
    require(any('JOINTS_0' in p.get('attributes', {}) and 'WEIGHTS_0' in p.get('attributes', {})
                for m in data.get('meshes', []) for p in m['primitives']), 'Avatar has no weighted mesh attributes')
    images = []
    for row in data.get('images', []):
        uri = row.get('uri')
        if uri:
            require(not uri.startswith(('data:', 'http:', 'https:')), 'External/encoded avatar image must be audited explicitly')
            name = 'assets/models/avatar/'+safe_name(uri)
            regular(root, name); runtime.add(name); images.append(name)
        else:
            require('bufferView' in row, 'Avatar image has no embedded or local payload')
    # Imported GLB embedded-image material maps are also actual source dependencies.
    for path in (root/'assets/models/avatar').glob('*.png'):
        if 'reference' not in path.name:
            runtime.add(path.relative_to(root).as_posix())
    runtime.update(('scripts/player/pool_avatar.gd', 'shaders/avatar_body.gdshader'))
    runtime.update(legacy['runtime_glb_files'])
    for name in editable:
        p = regular(root, name)
        if p.suffix == '.blend':
            with p.open('rb') as f: require(f.read(7) == b'BLENDER', 'Invalid editable Blender source: '+name)
    for name in runtime: regular(root, name)
    return {'runtime': sorted(runtime), 'editable': sorted(editable), 'rooms': list(ROOMS), 'props': list(PROPS),
            'avatar_clips': sorted(CLIPS), 'avatar_embedded_images': sum('bufferView' in i for i in data.get('images', [])),
            'avatar_external_images': images, 'legacy_assets': legacy, 'geometry_or_native_render_acceptance': False}


def runtime_allowed(name, cache):
    if not previous.runtime_name_allowed(name, cache): return False
    if name.startswith('assets/lighting/'):
        return name in PREVIEW_PINS or name.removesuffix('.remap') in PREVIEW_PINS
    return True


def export_policy(root, cache, needed):
    c = configparser.ConfigParser(interpolation=None); c.read(root/'export_presets.cfg')
    for section in c.sections():
        for key, value in c.items(section):
            if any(token in key for token in ('password', 'keystore/', 'codesign/identity')):
                require(not value.strip('"').strip(), 'Signing credential setting: '+section+'/'+key)
    sections = [s for s in c.sections() if re.fullmatch(r'preset\.\d+', s) and c.get(s, 'platform', fallback='').strip('"') == 'Windows Desktop']
    require(len(sections) == 1, 'Exactly one Windows preset is required')
    s = sections[0]
    require(c.get(s, 'export_filter').strip('"') == 'all_resources', 'Expected all_resources Windows policy')
    require(c.getint(s, 'script_export_mode') == 0, 'Raw GDScript export is required')
    include = c.get(s, 'include_filter').strip('"').split(',')
    exclude = c.get(s, 'exclude_filter').strip('"').split(',')
    for ext in ('.terrain', '.glslinc', '.vert', '.frag', '.rg16f', '.compute'):
        if ext == '.terrain' or any((root/'shaders').rglob('*'+ext)):
            require('*'+ext in include, 'Windows raw include missing: *'+ext)
    for prefix in ('output/', 'tools/', 'tests/', 'docs/', 'source_provenance/', 'terrain-cache-history/'):
        require(prefix+'*' in exclude, 'Non-runtime Windows exclusion missing: '+prefix)
    def excluded(n): return any(fnmatchcase(n, pattern) for pattern in exclude)
    for name in needed | set(cache) | {PREVIEW_SCENE, PREVIEW_PREFIX+'indirect_00.exr', PREVIEW_PREFIX+'native_indirect.lmbake'}:
        require(not excluded(name), 'Windows excludes a required runtime resource: '+name)
    for folder in ('assets/lighting', 'scenes/lighting_lab', 'assets/textures/pc_formal_plaster_candidate', 'shaders/pc_gpu_cube'):
        for p in (root/folder).rglob('*'):
            if p.is_file() and not runtime_allowed(p.relative_to(root).as_posix(), cache):
                require(excluded(p.relative_to(root).as_posix()), 'Rejected candidate not excluded by Windows preset: '+str(p.relative_to(root)))
    for p in (root/'assets/cache').rglob('*.terrain'):
        n = p.relative_to(root).as_posix()
        require(n in cache or excluded(n), 'Obsolete terrain not excluded: '+n)
    require(c.getboolean(s+'.options', 'binary_format/embed_pck', fallback=True) is False, 'Expected external PCK')
    require(c.getboolean(s+'.options', 'codesign/enable', fallback=True) is False, 'This helper does not sign Windows exports')
    return {'windows_preset': s, 'raw_scripts': True, 'only_explicit_preview_bake_allowed': True, 'android_untouched': True}


def dependencies(root, cache, assets):
    refs = {name: ['explicit dynamic-model/material contract'] for name in assets['runtime']}
    refs['scenes/main.tscn'] = ['project main scene']
    for folder in ('scripts', 'shaders', 'scenes', 'assets'):
        for path in (root/folder).rglob('*'):
            name = path.relative_to(root).as_posix()
            if path.suffix not in TEXT_RES or not runtime_allowed(name, cache): continue
            for ref in re.findall(r'''["']res://([^"'\n]+)["']''', path.read_text()):
                if any(t in ref for t in ('%', '*')) or not Path(ref).suffix or ref.startswith('output/'): continue
                safe_name(ref)
                require(runtime_allowed(ref, cache), 'Runtime references excluded resource: '+name+' -> '+ref)
                regular(root, ref); refs.setdefault(ref, []).append(name)
    # Dynamic compute shader lookup and all included production shader sources.
    for p in (root/'shaders').rglob('*'):
        n = p.relative_to(root).as_posix()
        if p.is_file() and p.suffix in set(RAW_SUFFIXES)|{'.glsl'} and runtime_allowed(n, cache): refs.setdefault(n, ['production shader inventory'])
    main = regular(root, 'scripts/main.gd').read_text()
    require(re.search(r'const SPAWN_MODES\s*:?=\s*\["original",\s*"formal",\s*"expanded"\]', main), 'Expected original/formal/expanded mode contract missing')
    for label in ('原仓库场景 / ORIGINAL', '重做主池厅 / FORMAL HALL', '扩展随机地图 / EXPANDED', '显示角色身体 / PLAYER BODY', '重建种子世界'):
        require(label in main, 'Expected menu resource missing: '+label)
    return refs


def classify(name, cache):
    p = Path(name)
    if name.startswith('tests/fixtures/') and ('cache' in p.parts or 'fontconfig' in p.parts or 'cpu_state' in p.parts):
        return 'exclude', 'generated test-run user/editor/font caches'
    if name.startswith(('docs/verification/', 'docs/audit/')) and p.suffix.lower() in {'.bin', '.raw', '.exr', '.hdr', '.npy', '.npz'}:
        return 'exclude', 'repeated raw diagnostic/HDR buffers; concise reports and screenshots remain optional'
    if name.startswith(('tools/blender/avatar/qa_project/', 'tools/blender/avatar/delivery/')):
        return 'exclude', 'duplicate transient avatar QA project or historical delivery'
    if p.suffix.lower() == '.log': return 'exclude', 'repeated raw diagnostics; concise evidence remains optional'
    if name.startswith(('assets/lighting/', 'scenes/lighting_lab/')) and name not in PREVIEW_PINS:
        if p.suffix.lower() in {'.exr', '.hdr', '.lmbake'} or (p.suffix == '.import' and Path(p.stem).suffix in {'.exr', '.hdr'}):
            return 'exclude', 'obsolete/rejected generated HDR bake; regenerate from retained laboratory sources'
    group, reason = previous.classify(name, cache)
    if name.startswith('docs/verification/pc-refine/fine-water'):
        group, reason = 'optional', 'historical or pending evidence, not current acceptance'
    if name.startswith('tools/blender/avatar/previews/') or (name.startswith('tools/blender/avatar/') and p.suffix == '.json'):
        group, reason = 'optional', 'authoring/QA evidence, not a runtime dependency'
    return group, reason


def inventory(root, scan=True):
    root = Path(root).resolve(); cache = previous.current_cache(root)
    files, excluded = [], []
    for folder, dirs, names in os.walk(root, followlinks=False):
        folder = Path(folder); kept = []
        for name in sorted(dirs):
            p = folder/name; rel = p.relative_to(root).as_posix()
            if name.lower() in previous.PRIVATE_DIRS or name.lower().startswith('blendcache_') or rel in ('tools/blender/avatar/qa_project', 'tools/blender/avatar/delivery'):
                excluded.append({'path': rel+'/', 'reason': 'private/generated/duplicate subtree; not traversed'})
            else:
                require(not p.is_symlink(), 'Source directory symlink: '+rel); kept.append(name)
        dirs[:] = kept
        for name in sorted(names):
            p = folder/name; rel = p.relative_to(root).as_posix(); group, reason = classify(rel, cache)
            if group == 'exclude': excluded.append({'path': rel, 'reason': reason}); continue
            regular(root, rel); no_secrets([rel])
            if scan: previous.scanned(p)
            files.append({'path': rel, 'group': group, 'bytes': p.stat().st_size, 'sha256': sha(p), 'reason': reason})
    files.sort(key=lambda x:x['path']); excluded.sort(key=lambda x:x['path'])
    identity = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return {'format': 1, 'kind': 'pc-expansion-source-inventory', 'status': 'INVENTORY_ONLY_NOT_FROZEN',
        'included_identity_sha256': identity, 'content_secret_scan': scan, 'files': files, 'excluded': excluded,
        'groups': {g: {'files': sum(r['group']==g for r in files), 'bytes': sum(r['bytes'] for r in files if r['group']==g)} for g in ('core','optional')}, 'verification_limits': LIMITS}


def preflight(root, scan=True):
    root = Path(root).resolve(); cache = previous.current_cache(root)
    for name, pin in PREVIEW_PINS.items(): require(sha(regular(root, name)) == pin, 'Accepted preview source hash changed: '+name)
    preview_import = 'absent_source_can_be_reimported'
    for name, pin in PREVIEW_IMPORT_PINS.items():
        if (root/name).exists(): require(sha(regular(root, name)) == pin, 'Accepted preview imported hash changed: '+name); preview_import = 'exact_delivered_bytes'
    check_bake_quarantine(root)
    assets = expected_assets(root); refs = dependencies(root, cache, assets)
    policy = export_policy(root, cache, set(refs))
    libraries = descriptor_libraries(regular(root, DESCRIPTOR).read_bytes())
    native = {target: check_native_bytes(regular(root,name).read_bytes(), target) for target,name in libraries.items()}
    includes = check_native_source_identity(root, libraries)
    solver = regular(root,'scripts/water/source_port/source_wave_solver.gd').read_text()
    for token in ('ClassDB.class_exists("SourceWaterReadback")', '--no-native-water-readback', 'Standard-engine fallback'):
        require(token in solver, 'Native fallback contract missing: '+token)
    inv = inventory(root, scan)
    core = {r['path'] for r in inv['files'] if r['group']=='core'}
    required = set(refs)|set(assets['editable'])|set(cache)|set(PREVIEW_PINS)|{DESCRIPTOR}|set(libraries.values())
    require(required <= core, 'Editable core omits actual dependencies: '+str(sorted(required-core)))
    return {'status':'PASS', 'scope':'Read-only static PC expansion inclusion preflight; not a freeze or graphical pass',
        'source_inventory':inv, 'runtime_dependencies':refs, 'assets':assets, 'windows_policy':policy,
        'accepted_preview_source_hashes':PREVIEW_PINS, 'accepted_preview_import_status':preview_import,
        'native_targets':native, 'native_source_includes':includes, 'fallback_static_guard':True,
        'required_core_paths':sorted(required), 'native_evidence_status':'SEPARATE_ACTUAL_PCK_STATUS_REQUIRED',
        'verification_limits':LIMITS}


def copy_rows(root, out, rows):
    for row in rows:
        p=regular(root,row['path']); require(sha(p)==row['sha256'], 'Input changed before copy: '+row['path'])
        target=out/row['path']; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,target)
        require(sha(target)==row['sha256']==sha(p), 'Input changed during copy: '+row['path'])


def check_inventory(root, expected):
    actual=inventory(root,False)
    require(expected['content_secret_scan'] is True, 'Original full secret scan is required')
    require(actual['included_identity_sha256']==expected['included_identity_sha256'], 'Source set/bytes changed; create a new identified freeze, never patch a manifest')


def freeze(root,out):
    root=Path(root).resolve(); out=Path(out).resolve()
    require(root!=out and root not in out.parents, 'Freeze outside the live project')
    report=preflight(root); inv=report['source_inventory']; previous.new_dir(out)
    copy_rows(root,out,inv['files'])
    private=[]
    imported=root/'.godot/imported'; require(imported.is_dir() and not imported.is_symlink(),'Completed import cache required')
    for p in sorted(imported.rglob('*')):
        require(not p.is_symlink(),'Imported symlink refused')
        if p.is_file(): private.append({'path':p.relative_to(root).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
    for name in BUILD_META:
        if (root/name).is_file(): private.append({'path':name,'bytes':(root/name).stat().st_size,'sha256':sha(root/name)})
    require(set(BUILD_META[:3]) <= {r['path'] for r in private},'Native/script/UID startup registries required')
    copy_rows(root,out,private); check_inventory(root,inv); preflight(out,False)
    write_json(out/'EXPANSION-FROZEN-INVENTORY.json',inv)
    write_json(out/'EXPANSION-PRIVATE-IMPORTS.json',{'files':private,'distributable':False})
    (out/'PRIVATE-BUILD-NOT-FOR-DELIVERY.txt').write_text('PRIVATE BUILD INPUTS. Never deliver this tree or its .godot cache. Use stage-source.\n')
    manifest(out,'private-pc-expansion-build-not-distributable',{'preflight':'PASS','utc':datetime.now(timezone.utc).isoformat(),'verification_limits':LIMITS},prefix='EXPANSION-BUILD-')
    verify_manifest(out,prefix='EXPANSION-BUILD-')
    return {'status':'PASS','directory':str(out),'source_inventory_sha256':inv['included_identity_sha256'],'private_import_files':len(private),'distributable':False}


def verify_frozen(root):
    root=Path(root).resolve()
    build=json.loads(regular(root,'EXPANSION-BUILD-PACKAGE-MANIFEST.json').read_text())
    require(build.get('kind')=='private-pc-expansion-build-not-distributable','Wrong frozen build manifest kind')
    rows=build['files']; names=[safe_name(r['path']) for r in rows]
    require(len(names)==len(set(names)),'Duplicate frozen build manifest paths')
    require(regular(root,'EXPANSION-BUILD-SHA256SUMS.txt').read_text()==''.join(r['sha256']+'  '+r['path']+'\n' for r in rows),'Frozen build checksums differ from manifest')
    bound={r['path']:r for r in rows}
    for name in ('EXPANSION-FROZEN-INVENTORY.json','EXPANSION-PRIVATE-IMPORTS.json'):
        require(name in bound and sha(regular(root,name))==bound[name]['sha256'],'Frozen inventory metadata changed: '+name)
    inv=json.loads((root/'EXPANSION-FROZEN-INVENTORY.json').read_text())
    check_inventory(root,inv)
    private=json.loads((root/'EXPANSION-PRIVATE-IMPORTS.json').read_text())['files']
    for row in inv['files']+private:
        require(row['path'] in bound and all(bound[row['path']][k]==row[k] for k in ('bytes','sha256')),'Inventory differs from bound build manifest: '+row['path'])
    for row in private:
        if row['path'] in BUILD_META: continue # Engine may rebuild registries, not source/import payloads.
        p=regular(root,row['path']);require(p.stat().st_size==row['bytes'] and sha(p)==row['sha256'],'Frozen imported payload changed: '+row['path'])
    return inv


def source_stage(root,out,optional=False):
    root=Path(root).resolve();out=Path(out).resolve(); inv=verify_frozen(root)
    require(root!=out and root not in out.parents,'Stage outside frozen project')
    previous.new_dir(out); groups=['core','optional'] if optional else ['core']; result={}
    for group in groups:
        target=out/('PoolCore-Expansion-Editable' if group=='core' else 'PoolCore-Expansion-Optional-QA');target.mkdir()
        rows=[r for r in inv['files'] if r['group']==group];copy_rows(root,target,rows)
        if group=='core':
            shutil.copy2(root/'tools/release/Prepare-Editor.cmd',target/'Prepare-Editor.cmd')
            shutil.copy2(root/USER_GUIDE,target/'START-HERE-PC.md')
            (target/'SOURCE-OPEN.txt').write_text('这是完整可编辑源工程，不是独立游戏。使用 Godot 4.6.3 Standard，首次打开须导入资源。\nWindows 将完整主 EXE 拖到 Prepare-Editor.cmd。不要使用小型 _console.exe 包装器。\n不含生成的 .godot 缓存、引擎、签名密钥或 SDK。原生源码、构建脚本、许可证、Blender 源与参考图均在本包。\n实验主厅烘焙为可选预览，不代表全部场景照明验收。Android 暂停。\n',encoding='utf-8-sig')
            audit=preflight(target,False)
            result['editable_required_dependencies_checked']=len(audit['required_core_paths'])
        else:
            (target/'OPTIONAL-QA-RESTORE.txt').write_text('可选历史实验与简要 QA，不是游戏或当前验收证据。仅在需要时合并到匹配源工程。\n旧巨大 HDR/EXR 烘焙、重复运行目录、原始日志和缓存不在包内；保留生成脚本用于有意重建。\n',encoding='utf-8-sig')
        manifest(target,'pc-expansion-editable-'+group,{'source_inventory_sha256':inv['included_identity_sha256'],'native_evidence_status':'SEPARATE_ACTUAL_PCK_STATUS_REQUIRED','verification_limits':LIMITS})
        verify_manifest(target);result[group]={'directory':str(target),'files':len(rows),'bytes':sum(r['bytes'] for r in rows)}
    verify_frozen(root);write_json(out/'SOURCE-INCLUSION-INVENTORY.json',inv)
    return {'status':'PASS',**result,'verification_limits':LIMITS}


def audit_pck(root,pack,package):
    root=Path(root).resolve();pack=Path(pack).resolve();package=Path(package).resolve();verify_frozen(root)
    report=preflight(root,False);cache=previous.current_cache(root);pck=Pck(pack)
    require(pck.engine=='4.6.3','Expected tested Godot 4.6.3 export')
    libraries,descriptor=check_registration(pck.read)
    require(descriptor==regular(root,DESCRIPTOR).read_bytes(),'Exported native descriptor differs')
    dll=regular(package,libraries['windows']);require(dll.read_bytes()==regular(root,libraries['windows']).read_bytes(),'External Windows DLL differs')
    require(libraries['windows'] not in pck.entries,'DLL must remain external beside PCK')
    check_bake_quarantine(root,pck.entries)
    for name in pck.entries: require(runtime_allowed(name,cache),'Forbidden runtime export: '+name)
    # Reject imported payloads belonging to every excluded candidate, not just filenames in PCK.
    runtime_imports = [p for folder in ('assets', 'scripts', 'shaders', 'scenes') for p in (root/folder).rglob('*.import')]
    for p in runtime_imports:
        rel=p.relative_to(root).as_posix()
        if not runtime_allowed(rel,cache):
            for target in import_targets(p.read_bytes()): require(target not in pck.entries,'Hidden rejected import leaked: '+target)
    imports=[];mapped=set()
    for name,data in pck.entries.items():
        if not name.endswith(('.import','.remap')): continue
        targets=import_targets(data);require(targets,'Empty export remap: '+name)
        for target in targets:
            safe_name(target);original=regular(root,target)
            require(pck.read(target)==original.read_bytes(),'Exported remap payload differs from frozen import: '+target);mapped.add(target)
        imports.append({'resource':name,'targets':targets})
    for name in pck.entries:
        if name.startswith('.godot/imported/'):require(name in mapped,'Unreferenced imported payload in PCK: '+name)
    refs=set(report['runtime_dependencies'])|set(cache)|{PREVIEW_SCENE,PREVIEW_PREFIX+'native_indirect.lmbake',PREVIEW_PREFIX+'indirect_00.exr'}
    verified=[]
    for name in sorted(refs):
        options=[n for n in (name,name+'.import',name+'.remap') if n in pck.entries]
        require(options,'Required runtime dependency absent from PCK: '+name)
        if name in pck.entries:require(pck.read(name)==regular(root,name).read_bytes(),'Raw resource differs: '+name)
        verified.append({'resource':name,'exported':options})
    # All current runtime scripts and raw shader helpers must remain byte-exact.
    for row in report['source_inventory']['files']:
        name=row['path'];p=Path(name)
        if row['group']!='core' or not runtime_allowed(name,cache): continue
        if ((name.startswith('scripts/') and p.suffix=='.gd') or (name.startswith('shaders/') and p.suffix in RAW_SUFFIXES)):
            require(pck.read(name)==regular(root,name).read_bytes(),'Raw production source absent/changed: '+name)
        if p.suffix=='.import' and name.startswith(('assets/','shaders/','scripts/mobile/','scenes/')):
            # Cover dynamically selected SFX, texture maps, native resources and
            # every currently imported core model, not only literal GDScript paths.
            require(name in pck.entries,'Core runtime import absent from PCK: '+name)
    for name,pin in PREVIEW_IMPORT_PINS.items():require(hashlib.sha256(pck.read(name)).hexdigest()==pin,'Accepted preview payload hash mismatch')
    return {'status':'PASS','pck_sha256':sha(pack),'bytes':pack.stat().st_size,'entries':len(pck.entries),'all_entry_md5_verified':True,
        'runtime_dependencies':verified,'imports':imports,'external_windows_native':check_native_bytes(dll.read_bytes(),'windows'),
        'accepted_preview_pins':PREVIEW_PINS,'source_inventory_sha256':report['source_inventory']['included_identity_sha256'],'verification_limits':LIMITS}


def expansion_launcher(preview=False):
    raw=previous.launcher(preview).replace(previous.PACK_NAME.encode(),PACK_NAME.encode()).replace(previous.PACK_NAME[:-4].encode(),PACK_NAME[:-4].encode())
    previous.audit_launcher(raw,preview);return raw


def play_stage(root,pack,out,receipt,exe=None,template=None):
    root=Path(root).resolve();out=Path(out).resolve();pack=Path(pack).resolve();verify_frozen(root)
    require(root!=out and root not in out.parents,'Stage outside frozen project')
    previous.scanned(Path(receipt));status=json.loads(Path(receipt).read_text())
    inv=json.loads((root/'EXPANSION-FROZEN-INVENTORY.json').read_text())
    require(status.get('pck_sha256')==sha(pack),'Evidence receipt must bind exact PCK')
    require(status.get('source_inventory_sha256')==inv['included_identity_sha256'],'Evidence receipt must bind exact frozen source inventory')
    require(status.get('export_exit_code')==0 and status.get('cpu_pck_pass') is True,'Successful export and actual-PCK CPU evidence required')
    require(status.get('gpu_pck_status') in {'pass','partial','blocked','not_run','fail'},'Explicit actual-PCK native GPU status required')
    require(status.get('windows_execution_status') in {'pass','partial','blocked','not_run','fail'},'Explicit Windows execution status required')
    require(status['gpu_pck_status']!='fail' and status['windows_execution_status']!='fail','A known failed runtime cannot be staged as a play package; diagnose first')
    require(bool(exe)==bool(template),'Pair --windows-exe and --windows-template')
    previous.new_dir(out);shutil.copy2(pack,out/PACK_NAME)
    for row in inv['files']:
        n=row['path'];p=Path(n)
        keep=n.startswith('native/source_water/') and '/build/' not in n and ('/bin/' not in n or p.name=='source_water.windows.x86_64.dll')
        keep=keep or n.startswith('docs/licenses/') or n in {'CREDITS.md','docs/SOURCE_LIQUID_LICENSES.md','docs/audit/source-caustics-third-party-license.txt','assets/textures/NOTICE.md','source_provenance/beyond-the-basin-66a4543/ATTRIBUTIONS.md','source_provenance/beyond-the-basin-66a4543/THIRD_PARTY_THREE_LICENSE.txt',DOC,USER_GUIDE}
        if keep:copy_rows(root,out,[row])
    shutil.copy2(root/USER_GUIDE,out/'START-HERE-PC.md');shutil.copy2(receipt,out/'PC-EXPANSION-STATUS.json')
    (out/'Launch-PoolCore.cmd').write_bytes(expansion_launcher())
    (out/'Launch-Experimental-Mainhall.cmd').write_bytes(expansion_launcher(True))
    engine={'included':False,'standalone':False,'requires':'Official Godot 4.6.3 Standard Windows x64 full main EXE'}
    if exe:
        engine=stage_windows_executable(exe,template,out)
        (out/'PoolCore-Source-Water.exe').rename(out/(PACK_NAME[:-4]+'.exe'));engine.update({'filename':PACK_NAME[:-4]+'.exe','included':True,'standalone':True})
    audit=audit_pck(root,out/PACK_NAME,out);audit.update({'engine':engine,'gpu_pck_status':status['gpu_pck_status'],'windows_execution_status':status['windows_execution_status'],'evidence_receipt_sha256':sha(Path(receipt))})
    write_json(out/'PC-STATIC-PACKAGE-AUDIT.json',audit);manifest(out,'pc-expansion-play-preview',audit);verify_manifest(out);verify_frozen(root)
    return audit


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='action',required=True)
    for name in ('preflight','inventory','freeze','verify-freeze','stage-source','audit-pck','stage-play'):
        s=sub.add_parser(name);s.add_argument('--source',type=Path,required=True);s.add_argument('--report',type=Path)
        if name in ('freeze','stage-source','stage-play'):s.add_argument('--output',type=Path,required=True)
        if name=='freeze':s.add_argument('--writes-paused',action='store_true',required=True,help='Release owner explicitly stopped writes; never use against active development')
        if name=='stage-source':s.add_argument('--with-optional-qa',action='store_true')
        if name in ('audit-pck','stage-play'):s.add_argument('--pck',type=Path,required=True)
        if name=='audit-pck':s.add_argument('--package-root',type=Path,required=True)
        if name=='stage-play':
            s.add_argument('--receipt',type=Path,required=True);s.add_argument('--windows-exe',type=Path);s.add_argument('--windows-template',type=Path)
    s=sub.add_parser('archive');s.add_argument('--directory',type=Path,required=True);s.add_argument('--zip',type=Path,required=True)
    s=sub.add_parser('transport');s.add_argument('--zip',type=Path,required=True);s.add_argument('--output',type=Path,required=True);s.add_argument('--label',required=True);s.add_argument('--kind',choices=('play','source','optional'),required=True);s.add_argument('--part-bytes',type=int,default=14_000_000)
    args=p.parse_args()
    try:
        if args.action=='preflight':r=preflight(args.source)
        elif args.action=='inventory':r=inventory(args.source)
        elif args.action=='freeze':r=freeze(args.source,args.output)
        elif args.action=='verify-freeze':i=verify_frozen(args.source);r={'status':'PASS','source_inventory_sha256':i['included_identity_sha256']}
        elif args.action=='stage-source':r=source_stage(args.source,args.output,args.with_optional_qa)
        elif args.action=='audit-pck':r=audit_pck(args.source,args.pck,args.package_root)
        elif args.action=='stage-play':r=play_stage(args.source,args.pck,args.output,args.receipt,args.windows_exe,args.windows_template)
        elif args.action=='archive':verify_manifest(args.directory);r=previous.archive_tree(args.directory,args.zip)
        else:
            require(256_000<=args.part_bytes<=15_000_000,'Choose 256 KB–15 MB chunks, leaving delivery ZIP overhead')
            r=previous.transport(args.zip,args.output,args.label,args.kind,args.part_bytes)
        if getattr(args,'report',None):write_json(args.report,r)
        print(json.dumps(r,ensure_ascii=False,indent=2));return 0
    except (AuditError,OSError,ValueError,KeyError,struct.error) as e:
        print('PC_EXPANSION_RELEASE_FAIL: '+str(e)+'\nAny partial staging directory is NOT a release.',file=sys.stderr);return 1

if __name__=='__main__':sys.exit(main())
