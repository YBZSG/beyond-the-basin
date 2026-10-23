#!/usr/bin/env python3
"""Stage source or portable Windows release from a frozen project/PCK.

Never exports the live project, signs an APK, copies credentials, or publishes.
Uses empty output directories so stale files cannot survive from earlier builds.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys
# Verification may run from an immutable staged tree; never create local bytecode.
sys.dont_write_bytecode = True
import zipfile
from types import SimpleNamespace
from audit_packages import AuditError, descriptor_libraries, no_secrets, pck_audit, require, safe_name, source_audit

TOP_DIRS = {'assets', 'docs', 'native', 'scenes', 'scripts', 'shaders', 'source_provenance',
            'tests', 'tools', 'feature_profiles', 'script_templates', 'text_editor_themes'}
ROOT_FILES = {'project.godot', 'export_presets.cfg', 'default_bus_layout.tres', '.gitignore',
              'README.md', 'CREDITS.md', 'CHECKPOINT-STATUS.md'}
IGNORE_DIRS = {'.git', '.godot', '.cache', '__pycache__', 'node_modules', 'output', '.aws', '.ssh', '.codex', '.agents',
               'xdg-cache', 'xdg-config', 'xdg-data', 'shader_cache', 'mesa_shader_cache', 'mesa_shader_cache_db'}
IGNORE_SUFFIXES = {'.pyc', '.pyo', '.log', '.tmp', '.blend1', '.blend2', '.blend@', '.bphys', '.keystore', '.jks', '.p12', '.pfx', '.pem', '.key'}
LAB_PREFIXES = ('assets/lighting/', 'scenes/lighting_lab/')
# Official 4.6.3 bounded-entry acquisition receipt, retained in docs/verification/release.
WINDOWS_RELEASE_SHA256 = '91724f15024a3a545e28ccd83134403d31ce2323a38e51c95e4dfa282f732ab6'
REJECTED_LAB_PAYLOADS = {
    'assets/lighting/formal_mainhall/study_indirect.exr',
    'assets/lighting/formal_mainhall/study_indirect.exr.import',
    'assets/lighting/formal_mainhall/study_indirect.lmbake',
}


def generated_fixture_path(parts):
    """Keep test harnesses/goldens, not repeated generated run workspaces."""
    if parts[:2] != ('tests', 'fixtures'):
        return False
    if any(part in ('build', 'parse-cache', 'parse-data') for part in parts[3:]):
        return True
    for index, part in enumerate(parts):
        if index > 2 and parts[index - 1] == 'audit' and re.fullmatch(r'run-\d{8}T\d{6}Z-[A-Za-z0-9_-]+', part):
            # Small top-level result/input manifests retain provenance. Repeated
            # snapshots, instrumented binaries and user/cache trees do not.
            return not (len(parts) == index + 2 and Path(parts[-1]).suffix in {'.json', '.md', '.txt'})
    return False


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def source_paths(root, profile='development'):
    result = []
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        parts = rel.parts
        if any(part in IGNORE_DIRS or part.lower().startswith('blendcache_') for part in parts):
            continue
        if re.search(r'\.blend\d+$', path.name, flags=re.IGNORECASE):
            continue
        if parts[:3] == ('native', 'source_water', 'build'):
            continue
        if generated_fixture_path(parts):
            continue
        if parts[0] not in TOP_DIRS and rel.as_posix() not in ROOT_FILES:
            continue
        if path.suffix.lower() in IGNORE_SUFFIXES or path.name == 'export_credentials.cfg' or path.name.startswith('.env'):
            continue
        if profile == 'final' and (rel.as_posix().startswith(LAB_PREFIXES) or rel.as_posix() == 'CHECKPOINT-STATUS.md'):
            continue
        require(not path.is_symlink(), f'Refusing source symlink: {rel}')
        if path.is_file():
            result.append(path)
    no_secrets(p.relative_to(root).as_posix() for p in result)
    return result


def verified_copy_set(paths, root, out, enumerate_again):
    hashes = {path: sha(path) for path in paths}
    for path in paths:
        copy(path, out, path.relative_to(root))
    require(paths == enumerate_again(), 'Source file set changed during staging; freeze and retry in a fresh directory')
    require(all(sha(path) == value for path, value in hashes.items()), 'Source changed during staging; freeze and retry in a fresh directory')
    require(all(sha(out / path.relative_to(root)) == value for path, value in hashes.items()), 'Staged source hash mismatch')


def copy(source, root, rel):
    target = root / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def manifest(root, kind, report, prefix=''):
    manifest_name, sums_name = prefix + 'PACKAGE-MANIFEST.json', prefix + 'SHA256SUMS.txt'
    files = sorted(p for p in root.rglob('*') if p.is_file() and p.relative_to(root).as_posix() not in (manifest_name, sums_name))
    entries = [{'path': p.relative_to(root).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in files]
    data = {'format': 1, 'kind': kind, 'files': entries, 'audit': report,
            'verification_limits': ['No Windows executable or Android device execution is asserted by static package audits.']}
    (root / manifest_name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    (root / sums_name).write_text(''.join(e['sha256'] + '  ' + e['path'] + '\n' for e in entries))


def verify_manifest(root, prefix=''):
    """Verify the exact staged file set, including manifest/checksum consistency."""
    root = Path(root)
    manifest_name, sums_name = prefix + 'PACKAGE-MANIFEST.json', prefix + 'SHA256SUMS.txt'
    data = json.loads((root / manifest_name).read_text())
    entries = data['files']
    expected = {safe_name(entry['path']) for entry in entries}
    require(len(entries) == len(expected), 'Staged manifest has duplicate paths')
    actual = {path.relative_to(root).as_posix() for path in root.rglob('*') if path.is_file()}
    require(actual == expected | {manifest_name, sums_name}, 'Staged file set differs from package manifest')
    for entry in entries:
        path = root / entry['path']
        require(not path.is_symlink(), f'Staged manifest symlink: {entry["path"]}')
        require(path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256'],
                f'Staged bytes differ from package manifest: {entry["path"]}')
    expected_sums = ''.join(entry['sha256'] + '  ' + entry['path'] + '\n' for entry in entries)
    require((root / sums_name).read_text() == expected_sums, 'Staged checksums differ from package manifest')
    return data


def archive(root, destination):
    require(not destination.exists(), f'Refusing to replace existing archive: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in sorted(root.rglob('*')):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(root).as_posix(), (2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o100755 if path.stat().st_mode & 0o111 else 0o100644) << 16
                z.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(destination) as z:
        require(z.testzip() is None, 'Created ZIP has a CRC failure')
    return {'file': destination.name, 'bytes': destination.stat().st_size, 'sha256': sha(destination)}


def stage_windows_executable(executable, template, out):
    """Add an unmodified official release-template EXE, without running Windows."""
    executable, template = Path(executable), Path(template)
    require(template.name == 'windows_release_x86_64.exe',
            'Use the official windows_release_x86_64.exe template, not an editor or console wrapper')
    for path in (executable, template):
        require(path.is_file() and not path.is_symlink(), f'Missing or symlinked Windows executable: {path}')
    data = template.read_bytes()
    require(len(data) > 256 and data[:2] == b'MZ', 'Windows release template is not PE')
    pe = struct.unpack_from('<I', data, 60)[0]
    require(pe + 24 + 128 <= len(data) and data[pe:pe + 4] == b'PE\0\0', 'Invalid Windows template PE header')
    require(struct.unpack_from('<H', data, pe + 4)[0] == 0x8664, 'Wrong Windows EXE architecture')
    flags = struct.unpack_from('<H', data, pe + 22)[0]
    require(flags & 2 and not flags & 0x2000, 'Windows template is not an executable main image')
    require(struct.unpack_from('<H', data, pe + 24)[0] == 0x20b, 'Expected PE32+ Windows template')
    require(sha(template) == WINDOWS_RELEASE_SHA256, 'Official 4.6.3 Windows template SHA-256 pin mismatch')
    require(sha(executable) == sha(template),
            'Exported Windows EXE differs from the official template; embedded PCK/resource modification is not allowed')
    target = Path(out) / 'PoolCore-Source-Water.exe'
    copy(executable, Path(out), target.name)
    require(sha(target) == sha(template), 'Staged Windows executable bytes changed')
    return {'filename': target.name, 'bytes': target.stat().st_size, 'sha256': sha(target),
            'template_filename': template.name, 'template_bytes_identical': True,
            'architecture': 'x86_64', 'embedded_pck': False, 'windows_executed': False,
            'official_release': '4.6.3-stable', 'official_acquisition_sha256_pin_matched': True}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('kind', choices=('windows', 'source', 'lab'))
    p.add_argument('--source', type=Path, required=True, help='Frozen source tree (read-only to this tool)')
    p.add_argument('--output', type=Path, required=True, help='New or empty package directory')
    p.add_argument('--pck', type=Path, help='Actual final PCK for Windows package')
    p.add_argument('--zip', type=Path, help='Optional new archive; never overwrites')
    p.add_argument('--windows-exe', type=Path, help='Optional actual self-contained Windows export EXE')
    p.add_argument('--windows-template', type=Path, help='Official matching windows_release_x86_64.exe, required with --windows-exe')
    p.add_argument('--source-profile', choices=('development', 'final'), default='development',
                   help='Final separates optional lighting studies from the editable gameplay source')
    args = p.parse_args()
    try:
        require(bool(args.windows_exe) == bool(args.windows_template), '--windows-exe and --windows-template must be paired')
        require(not args.windows_exe or args.kind == 'windows', 'Windows EXE is only valid for windows staging')
        root = args.source.resolve()
        out = args.output.resolve()
        require((root / 'project.godot').is_file(), 'Invalid source project')
        require(out != root and root not in out.parents, 'Stage outside the source project, not inside it')
        require(not out.exists() or not any(out.iterdir()), 'Output must be empty; refuse stale package contents')
        if args.zip:
            require(not args.zip.exists(), 'ZIP already exists; choose a new destination')
            require(out not in args.zip.resolve().parents, 'ZIP destination must be outside staging directory')
        out.mkdir(parents=True, exist_ok=True)
        if args.kind == 'source':
            paths = source_paths(root, args.source_profile)
            verified_copy_set(paths, root, out, lambda: source_paths(root, args.source_profile))
            # Portable startup registry only; never copy editor caches from the build host.
            (out / '.godot').mkdir(exist_ok=True)
            (out / '.godot/extension_list.cfg').write_text('res://native/source_water/source_water.gdextension\n')
            copy(Path(__file__).resolve().parent / 'Prepare-Editor.cmd', out, 'Prepare-Editor.cmd')
            if args.source_profile == 'final':
                copy(Path(__file__).resolve().parent / 'LAB-RESTORE.txt', out, 'LAB-RESTORE.txt')
            report = source_audit(SimpleNamespace(directory=out))
            report['source_profile'] = args.source_profile
            report['optional_lab_assets_separated'] = args.source_profile == 'final'
            (out / 'SOURCE-OPEN.txt').write_text('''这是可编辑的 Godot 4.6.3 源工程，不是已安装的游戏。
请先把同一检查点的全部 ZIP 解压到同一目录。Windows 可把官方 Godot 4.6.x / 4.7.x Standard 的完整主 EXE 拖到 Prepare-Editor.cmd，并等待首次资源导入完成。
小型 _console.exe 只是包装器，需要同目录、名称匹配的主 EXE；若只复制一个引擎文件或想任意重命名，请使用完整主 EXE。
保留原始 GDScript、六个 Blender 源模型、原生 C 源码/构建说明，以及 Windows x64、Linux x64、Android arm64 辅助库。不包含引擎、SDK、编译器或签名密钥。
几何、材质、灯光、算法或导入结果改变后，旧缓存会被安全拒绝；发行前须按 tools/release/README.md 重新构建并验证缓存。

This is the editable Godot 4.6.3 project, not an installed game.\nOn Windows, drag the official Godot 4.6.x / 4.7.x Standard main EXE onto Prepare-Editor.cmd, then let the first import finish.
Other supported desktops can open project.godot normally; the shipped startup registry is portable.\nOnly .godot/extension_list.cfg is shipped: it pre-registers the optional helper and avoids the known headless first-discovery engine documentation race.
Prepare-Editor.cmd restores that one known res:// entry if .godot was removed, without replacing other extension entries.\nDo not launch a fresh unimported source tree directly and mistake the fallback for a native-helper test.\nAll three supported native binaries and their licenses are included. No signing key, engine, SDK, or compiler is included.\nSource scripts remain editable. See tools/release/README.md for verified export/package instructions.\nOn other target platforms remove/omit the unsupported .gdextension from that platform export; the solver retains GDScript fallback.\n''')
        elif args.kind == 'lab':
            def lab_paths():
                return [path for path in source_paths(root) if
                        path.relative_to(root).as_posix().startswith(LAB_PREFIXES) and
                        path.relative_to(root).as_posix() not in REJECTED_LAB_PAYLOADS]
            paths = lab_paths()
            require(paths, 'No optional lighting laboratory sources found')
            verified_copy_set(paths, root, out, lab_paths)
            copy(Path(__file__).resolve().parent / 'LAB-RESTORE.txt', out, 'LAB-RESTORE.txt')
            report = {'kind': 'optional-lighting-lab', 'runtime_integrated': False,
                      'source_files_and_small_fixtures': len(paths),
                      'rejected_payloads_excluded': sorted(REJECTED_LAB_PAYLOADS),
                      'validation_limits': ['Laboratory-only. Read each fixture report; presence is not validation.',
                                            'The original full-hall rejected bake requires deliberate regeneration.']}
        else:
            require(args.pck and args.pck.is_file(), '--pck must point to the completed frozen-source export')
            libraries = descriptor_libraries((root / 'native/source_water/source_water.gdextension').read_bytes())
            copy(args.pck, out, 'PoolCore-Source-Water.pck')
            copy(root / libraries['windows'], out, libraries['windows'])
            for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md', 'README.md'):
                rel = 'native/source_water/' + name
                copy(root / rel, out, rel)
            # Ship the small, editable helper implementation/build recipe next
            # to its binary, never a compiler, SDK or build intermediates.
            native_root = root / 'native/source_water'
            native_sources = [path for path in native_root.rglob('*') if path.is_file() and
                              path.suffix in {'.c', '.h', '.inc'} and
                              'build' not in path.relative_to(native_root).parts]
            for path in native_sources:
                copy(path, out, path.relative_to(root))
            for name in ('build.sh', 'acquire_toolchain.py', 'toolchain-packages.json', 'verification/atomic_build.json'):
                rel = 'native/source_water/' + name
                copy(root / rel, out, rel)
            release = Path(__file__).resolve().parent
            for name in ('Launch-PoolCore.cmd', 'README-RUN.txt'):
                copy(release / name, out, name)
            copy(root / 'CREDITS.md', out, 'CREDITS.md')
            # Preserve existing licensing evidence without bundling source toolchains.
            for folder in ('docs/licenses',):
                for path in (root / folder).rglob('*'):
                    if path.is_file():
                        copy(path, out, path.relative_to(root))
            for rel in ('docs/SOURCE_LIQUID_LICENSES.md', 'docs/audit/source-caustics-third-party-license.txt',
                        'assets/textures/NOTICE.md', 'source_provenance/beyond-the-basin-66a4543/ATTRIBUTIONS.md',
                        'source_provenance/beyond-the-basin-66a4543/THIRD_PARTY_THREE_LICENSE.txt'):
                if (root / rel).is_file():
                    copy(root / rel, out, rel)
            report = pck_audit(SimpleNamespace(pck=out/'PoolCore-Source-Water.pck', platform='windows',
                              package_root=out, source=root, launcher=out/'Launch-PoolCore.cmd'))
            report['engine_bundled'] = bool(args.windows_exe)
            if args.windows_exe:
                report['windows_executable'] = stage_windows_executable(args.windows_exe, args.windows_template, out)
                for name in ('GODOT_LICENSE.txt', 'GODOT_THIRD_PARTY_COPYRIGHT.txt'):
                    require((out / 'docs/licenses' / name).is_file(), f'Bundled Godot license missing: {name}')
        no_secrets(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file())
        manifest(out, args.kind, report, prefix='LAB-' if args.kind == 'lab' else '')
        verify_manifest(out, prefix='LAB-' if args.kind == 'lab' else '')
        result = {'status': 'PASS', 'kind': args.kind, 'directory': str(out), 'audit': report}
        if args.zip:
            result['archive'] = archive(out, args.zip.resolve())
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (AuditError, OSError, ValueError) as exc:
        print(f'PACKAGE_STAGE_FAIL: {exc}\nPartial output is NOT a release. Correct the issue and use a fresh staging directory.', file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
