#!/usr/bin/env python3
"""Split a staged editable development checkpoint into independent bounded ZIPs.

Not multipart ZIP volumes: extract every ZIP into the same directory, in any
order. Source paths occur once across archives. No export/import/signing occurs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
# Verification may run from an immutable staged tree; never create local bytecode.
sys.dont_write_bytecode = True
import zipfile
import zlib
from datetime import datetime
from types import SimpleNamespace
from audit_packages import AuditError, no_secrets, require, source_audit
from stage_release import manifest, sha, verify_manifest


def write_delivery_notes(root, kind, snapshot_utc):
    if kind == 'development-checkpoint':
        (root/'CHECKPOINT-STATUS.md').write_text(f'''# Development recovery checkpoint\n\nSnapshot UTC: {snapshot_utc}\n\nThis is an editable development checkpoint, NOT a final PC release, APK, or completed graphical regression. The first native lightmap lab bake contains rejected non-finite radiance, is excluded from PC/APK exports, and is retained only as experimental evidence. Ongoing water-visual checks are not asserted to have passed. It includes the latest copied scripts/assets and all editable Blender sources.\n\nExtract EVERY checkpoint ZIP into the SAME folder; each is a normal independent ZIP, not a multipart volume. No concatenation is needed. Open the shared project folder only after all parts are extracted. The source ZIP alone is not the complete game.\n\nWindows: drag the official Godot 4.6.x / 4.7.x Standard Windows x86_64 executable onto Prepare-Editor.cmd, then allow imports to finish. A single portable .godot/extension_list.cfg bootstrap avoids the known first-discovery headless engine-docs race. Other generated editor caches are deliberately absent.\n\nNative Windows/Android binaries are cross-built and statically audited, not executed on those platforms here. No private signing key, credentials, engine, SDK, toolchain, output, or generated import cache is included. Prior verification files record their own narrower scope and dates.\n''')
        (root/'CHECKPOINT-RESTORE.txt').write_text('开发恢复检查点，不是最终发行版。\n请把本检查点的全部 ZIP 解压到同一个目录。每个都是可独立解压的普通 ZIP，不需要拼接。\n全部解压完成后进入共同的项目目录，Windows 可将官方 Godot 4.6.x / 4.7.x Standard EXE 拖到 Prepare-Editor.cmd。\n包含原始 GDScript、三个平台的原生辅助库、原生源码、构建说明、六个可编辑 Blender 文件和资产。\n不含密钥、SDK、引擎或构建机器的生成缓存。当前仍在进行光照/水体图形回归，请勿视为最终验收。\n')
        return
    (root/'EDITABLE-SOURCE-STATUS.txt').write_text(f'''EDITABLE GAMEPLAY SOURCE PARTS
Snapshot UTC: {snapshot_utc}

This is editable source, not the PC play package or an Android installer.
Extract ALL matching ordinary ZIPs into the SAME folder. They are independent
ZIP archives, not binary multipart volumes; no concatenation is required.
The source ZIP alone is not the complete project.

The optional lighting laboratory is separate. See LAB-RESTORE.txt before
restoring laboratory fixtures or running saved-bake tests. Experimental and
rejected lab data is not gameplay lighting.

Godot 4.6.3 is the tested build baseline. Official 4.6/4.7 Standard Windows
executables may be dragged onto Prepare-Editor.cmd, with an unverified-version
warning for non-baseline builds. First import/cache preparation may take time.

This archive tool verifies bytes and inclusion, not Windows/phone performance
or graphical acceptance. Read the separately supplied release acceptance report.
No private key, engine, SDK, compiler or generated editor cache is included,
except the small portable native-extension registration bootstrap.
''')
    (root/'EDITABLE-SOURCE-RESTORE.txt').write_text('可编辑源工程，不是 PC 游戏包或安卓安装包。\n请将同一标签的全部普通 ZIP 解压到同一个目录，不需要拼接。\n全部解压后，可将官方 Godot 4.6 / 4.7 Standard 的主 EXE 拖到 Prepare-Editor.cmd。\n测试基线为 4.6.3；其他版本允许打开但未验证。\n可选光照实验室另行提供，请先阅读 LAB-RESTORE.txt。\n')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--staged-source',type=Path,required=True)
    p.add_argument('--kind', choices=('development-checkpoint', 'editable-source'), default='development-checkpoint')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--label',required=True,help='Portable project folder label, for example PoolCore-Development-20261021-2048')
    p.add_argument('--snapshot-utc',required=True)
    p.add_argument('--max-bytes',type=int,default=16_000_000)
    args=p.parse_args()
    try:
        root=args.staged_source.resolve(); out=args.output.resolve()
        require(args.snapshot_utc == datetime.strptime(args.snapshot_utc,'%Y-%m-%dT%H:%M:%SZ').strftime('%Y-%m-%dT%H:%M:%SZ'),
                'Snapshot UTC must use YYYY-MM-DDTHH:MM:SSZ')
        require(args.label and all(c.isalnum() or c in '-_' for c in args.label),'Label must be a portable folder name')
        require(not out.exists() or not any(out.iterdir()),'Archive output must be empty')
        require(root != out and root not in out.parents,'Archive output must not be inside staged source')
        require(args.max_bytes >= 1024*1024,'Unreasonably small archive bound')
        out.mkdir(parents=True,exist_ok=True)
        staged = verify_manifest(root)
        if args.kind == 'editable-source':
            require(staged.get('audit', {}).get('source_profile') == 'final', 'Editable-source parts require the final clean source profile')
        report=source_audit(SimpleNamespace(directory=root))
        write_delivery_notes(root, args.kind, args.snapshot_utc)
        report=source_audit(SimpleNamespace(directory=root))
        report['source_profile'] = staged.get('audit', {}).get('source_profile', 'development')
        manifest(root, args.kind, report)
        groups={name:[] for name in ['source','runtime-assets','runtime-models','editable-blender','terrain-cache']}
        for path in sorted(root.rglob('*')):
            if not path.is_file(): continue
            rel=path.relative_to(root).as_posix()
            if rel.startswith('assets/cache/'): group='terrain-cache'
            elif rel.startswith('assets/models/'): group='runtime-models'
            elif rel.startswith('assets/'): group='runtime-assets'
            elif rel.startswith('tools/blender/source/') and path.suffix=='.blend': group='editable-blender'
            else: group='source'
            groups[group].append(path)
        no_secrets(p.relative_to(root).as_posix() for paths in groups.values() for p in paths)
        bins=[]
        # Compression estimate deliberately reserves directory/manifest overhead.
        for group,files in groups.items():
            current=[]; budget=4096
            for path in files:
                estimate=len(zlib.compress(path.read_bytes(),9))+len(path.relative_to(root).as_posix().encode())*2+256
                require(estimate+4096 < args.max_bytes,f'Individual file exceeds independent ZIP bound: {path.relative_to(root)}')
                if current and budget+estimate > args.max_bytes-65536:
                    bins.append((group,current));current=[];budget=4096
                current.append(path);budget+=estimate
            if current: bins.append((group,current))
        reports=[]; seen=set()
        for index,(group,files) in enumerate(bins,1):
            name=f'{args.label}-{index:02d}-{group}.zip'; archive=out/name
            with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
                for path in files:
                    rel=path.relative_to(root).as_posix(); require(rel not in seen,f'Duplicate source path: {rel}');seen.add(rel)
                    info=zipfile.ZipInfo(args.label+'/'+rel,(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
                    info.external_attr=(0o100755 if path.stat().st_mode&0o111 else 0o100644)<<16
                    z.writestr(info,path.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
            require(archive.stat().st_size<=args.max_bytes,f'Actual ZIP exceeds bound: {name}')
            with zipfile.ZipFile(archive) as z:
                require(z.testzip() is None,f'ZIP CRC failure: {name}')
                for path in files:
                    rel=path.relative_to(root).as_posix()
                    require(hashlib.sha256(z.read(args.label+'/'+rel)).hexdigest()==sha(path),f'ZIP/source mismatch: {rel}')
            reports.append({'filename':name,'category':group,'bytes':archive.stat().st_size,'sha256':sha(archive),'files':len(files)})
        expected={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
        require(seen==expected,'Archive union does not exactly reproduce staged source')
        verify_manifest(root)
        result={'status':'PASS','kind':args.kind,'snapshot_utc':args.snapshot_utc,'project_folder':args.label,
                'all_parts_required':True,'independently_extractable':True,'maximum_archive_bytes':args.max_bytes,
                'files':len(seen),'archives':reports,'source_audit':report,
                'verification_limits':['This archive tool performs no PCK/APK export or Windows/phone execution.',
                                       'Source archive integrity is not graphical or performance acceptance.']}
        (out/('CHECKPOINT-ARCHIVES.json' if args.kind == 'development-checkpoint' else 'EDITABLE-SOURCE-ARCHIVES.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps(result,ensure_ascii=False,indent=2))
        return 0
    except (AuditError,OSError,ValueError) as exc:
        print(f'CHECKPOINT_ARCHIVE_FAIL: {exc}',file=sys.stderr);return 1

if __name__=='__main__': sys.exit(main())
