#!/usr/bin/env python3
"""Offline, fail-closed Godot 4.6 PCK/APK/source release audit. No execution/signing.

PCK format: Godot 4.6.3 core/io/file_access_pack.cpp (formats 2 and 3).
This audits full, unencrypted standalone PCKs, not sparse bundles or patch packs.
"""
from __future__ import annotations
import argparse
import configparser
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import sys
import zipfile

DESCRIPTOR = 'native/source_water/source_water.gdextension'
ENTRY = 'source_water_library_init'
TARGETS = {'windows': 'windows.x86_64', 'linux': 'linux.x86_64', 'android': 'android.arm64'}
SECRET_SUFFIXES = ('.keystore', '.jks', '.p12', '.pfx', '.pem', '.key')
RAW_SUFFIXES = ('.glslinc', '.vert', '.frag', '.rg16f', '.compute', '.gdshader', '.gdshaderinc')
EXPERIMENTAL_EXPORT_PREFIXES = ('scenes/lighting_lab/', 'assets/lighting/')
# Final-release decision, 2026-10-22: native finite-data proofs did not establish
# full-game art acceptance. Any future promotion needs a new explicit release
# policy/acceptance gate, not merely files appearing at these prepared paths.
UNACCEPTED_BAKE_DESTINATIONS = ('assets/lighting_runtime', 'scenes/formal_baked',
                               'scripts/rendering/formal_baked_lighting.gd')
NON_RUNTIME_EXPORT_PREFIXES = ('output/', 'tools/', 'tests/', 'docs/', 'source_provenance/',
                               'terrain-cache-history/', 'native/source_water/build/')
FORMAL_ASSETS = ('formal_arcade', 'formal_arch', 'formal_bath', 'formal_mainhall',
                'formal_sidepool', 'formal_terrace')
QUIET_ASSETS = ('quiet-wing-changing-gallery', 'quiet-wing-oculus-court',
               'quiet-wing-prop-kit', 'quiet-wing-vaulted-lap-hall')

class AuditError(RuntimeError):
    pass

def require(ok, message):
    if not ok:
        raise AuditError(message)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def safe_name(name):
    require('\\' not in name and not name.startswith('/'), f'Unsafe archive path: {name}')
    require(not any(p in ('..', '.', '') for p in name.split('/')), f'Unsafe archive path: {name}')
    require(not re.match(r'^[A-Za-z]:', name), f'Absolute archive path: {name}')
    return name

def no_secrets(names):
    for name in names:
        lower = name.lower()
        require(not lower.endswith(SECRET_SUFFIXES), f'Private signing/credential material: {name}')
        require(not any(p in ('.git', '.aws', '.ssh', '.env') for p in lower.split('/')), f'Private directory: {name}')
        require(not PurePosixPath(lower).name.startswith('.env.'), f'Environment file: {name}')
        require('export_credentials.cfg' not in lower, f'Export credentials: {name}')

def descriptor_libraries(data):
    c = configparser.ConfigParser(interpolation=None)
    c.read_string(data.decode('utf-8-sig'))
    require(c.get('configuration', 'entry_symbol', fallback='').strip('"') == ENTRY, 'Unexpected native entry symbol')
    result = {}
    for platform, key in TARGETS.items():
        value = c.get('libraries', key, fallback='').strip('"')
        require(value.startswith('res://'), f'Missing/absolute native descriptor target: {key}')
        result[platform] = safe_name(value[6:])
    return result

class Pck:
    """Bounded parser with entry MD5 verification; never extracts archive paths."""
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        self.entries = {}
        require(len(self.data) >= 100, 'Truncated PCK header')
        magic, version, major, minor, patch, flags = struct.unpack_from('<6I', self.data)
        require(magic == 0x43504447, 'Not a standalone Godot PCK')
        require(version in (2, 3), f'Unsupported PCK format: {version}')
        require(flags & ~2 == 0, f'Encrypted/sparse/unknown PCK flags: {flags}')
        self.engine = f'{major}.{minor}.{patch}'
        self.format = version
        base = struct.unpack_from('<Q', self.data, 24)[0]
        offset = struct.unpack_from('<Q', self.data, 32)[0] if version == 3 else 96
        require(offset + 4 <= len(self.data), 'PCK directory offset outside file')
        count = struct.unpack_from('<I', self.data, offset)[0]
        offset += 4
        require(count <= (len(self.data) - offset) // 40, 'Implausible PCK entry count')
        for _ in range(count):
            require(offset + 4 <= len(self.data), 'Truncated PCK path size')
            size = struct.unpack_from('<I', self.data, offset)[0]
            offset += 4
            require(0 < size <= 65536 and offset + size + 36 <= len(self.data), 'Invalid/truncated PCK entry')
            raw = self.data[offset:offset + size]
            name = raw.rstrip(b'\0').decode('utf-8')
            require(b'\0' not in raw.rstrip(b'\0'), 'Embedded null in PCK path')
            if name.startswith('res://'):
                name = name[6:]
            safe_name(name)
            require(name not in self.entries, f'Duplicate PCK path: {name}')
            offset += size
            start, length = struct.unpack_from('<QQ', self.data, offset)
            md5 = self.data[offset + 16:offset + 32]
            entry_flags = struct.unpack_from('<I', self.data, offset + 32)[0]
            offset += 36
            require(entry_flags == 0, f'Encrypted/removed/delta entry: {name}')
            start += base
            require(start <= len(self.data) and length <= len(self.data) - start, f'Entry outside PCK: {name}')
            data = self.data[start:start + length]
            require(hashlib.md5(data).digest() == md5, f'PCK integrity mismatch: {name}')
            self.entries[name] = data
        no_secrets(self.entries)
    def read(self, name):
        require(name in self.entries, f'Missing PCK resource: {name}')
        return self.entries[name]

def check_native_bytes(data, platform):
    if platform == 'windows':
        require(len(data) > 256 and data[:2] == b'MZ', 'Native Windows library is not PE')
        pe = struct.unpack_from('<I', data, 60)[0]
        require(pe + 24 + 128 <= len(data) and data[pe:pe+4] == b'PE\0\0', 'Invalid PE header')
        require(struct.unpack_from('<H', data, pe + 4)[0] == 0x8664, 'Wrong Windows DLL architecture')
        optional = pe + 24
        require(struct.unpack_from('<H', data, optional)[0] == 0x20B, 'Expected PE32+')
        require(struct.unpack_from('<II', data, optional + 120) == (0, 0), 'Unexpected native DLL import dependency')
    else:
        require(len(data) >= 64 and data[:6] == b'\x7fELF\x02\x01', 'Native library is not little-endian ELF64')
        machine = 183 if platform == 'android' else 62
        require(struct.unpack_from('<H', data, 18)[0] == machine, f'Wrong {platform} ELF architecture')
        phoff = struct.unpack_from('<Q', data, 32)[0]
        phsize, phnum = struct.unpack_from('<HH', data, 54)
        require(phsize == 56 and phoff + phsize * phnum <= len(data), 'Invalid ELF program header')
        loads = []
        for i in range(phnum):
            typ, flags, off, _, _, fsize, _, align = struct.unpack_from('<II6Q', data, phoff + i * phsize)
            if typ == 1:
                loads.append(align)
            if typ == 2:
                require(off + fsize <= len(data) and fsize % 16 == 0, 'Invalid ELF dynamic segment')
                for pos in range(off, off + fsize, 16):
                    tag, _ = struct.unpack_from('<qQ', data, pos)
                    require(tag != 1, 'Unexpected native ELF NEEDED dependency')
            if typ == 0x6474e551:
                require(not (flags & 1), 'Executable ELF stack')
        require(loads, 'ELF has no LOAD segments')
        if platform == 'android':
            require(all(a >= 16384 for a in loads), 'Android helper lacks 16 KiB ELF alignment')
    require(ENTRY.encode() in data, 'Native entry symbol absent')
    return {'bytes': len(data), 'sha256': digest(data), 'platform': platform, 'runtime_executed': False}

def check_registration(read):
    require(read('project.binary').startswith(b'ECFG'), 'Missing/invalid exported project settings')
    descriptor = read(DESCRIPTOR)
    entries = read('.godot/extension_list.cfg').decode('utf-8').splitlines()
    require('res://' + DESCRIPTOR in entries, 'Native descriptor not startup-registered; run editor import before export')
    return descriptor_libraries(descriptor), descriptor

def check_bake_quarantine(root=None, names=()):
    for name in names:
        require(not any(name == blocked or name.startswith(blocked + '/') or
                        name.startswith(blocked + '.remap') for blocked in UNACCEPTED_BAKE_DESTINATIONS),
                'Unaccepted full-game bake must not enter final runtime: ' + name)
    if root is not None:
        for name in UNACCEPTED_BAKE_DESTINATIONS:
            require(not (Path(root) / name).exists(),
                    'Unaccepted bake production destination must remain absent: ' + name)
    return {'baked_gi_quarantined': True, 'production_bake_accepted': False}


def check_export_exclusions(names, root=None):
    """Reject quarantined non-finite lightmap study, including imported payloads."""
    names = set(names)
    quarantine = check_bake_quarantine(root, names)
    require(not any(name.startswith(EXPERIMENTAL_EXPORT_PREFIXES) for name in names),
            'Experimental lighting lab must not be included in playable exports')
    require(not any(name.startswith(NON_RUNTIME_EXPORT_PREFIXES) for name in names),
            'Non-runtime source, historical terrain, or test artifact leaked into playable export')
    imported_checked = 0
    if root is not None:
        for path in (Path(root) / 'assets/lighting').rglob('*.import'):
            for target in re.findall(r'"res://([^"\n]+)"', path.read_text()):
                if target.startswith('.godot/imported/'):
                    imported_checked += 1
                    require(target not in names, f'Experimental lightmap imported payload leaked into export: {target}')
    return {**quarantine, 'experimental_lightmap_excluded': True, 'non_runtime_exports_excluded': True,
            'excluded_import_paths_checked': imported_checked}

def check_export_policy(root):
    config = configparser.ConfigParser(interpolation=None)
    config.read(Path(root) / 'export_presets.cfg')
    for section in config.sections():
        for key, value in config.items(section):
            if any(token in key for token in ('password', 'keystore/', 'codesign/identity')):
                require(not value.strip('"').strip(), f'Non-portable signing/credential setting in {section}: {key}')
    checked = []
    for section in config.sections():
        if not re.fullmatch(r'preset\.\d+', section):
            continue
        platform = config.get(section, 'platform', fallback='').strip('"')
        if platform not in ('Windows Desktop', 'Android'):
            continue
        require(config.getint(section, 'script_export_mode', fallback=-1) == 0,
                f'{platform} must preserve raw GDScript for cache signatures')
        include = config.get(section, 'include_filter', fallback='').strip('"').split(',')
        exclude = config.get(section, 'exclude_filter', fallback='').strip('"').split(',')
        require('*.terrain' in include, f'{platform} must include prepared terrain files')
        for suffix in ('.glslinc', '.vert', '.frag', '.rg16f', '.compute'):
            if any((Path(root) / 'shaders').rglob('*' + suffix)):
                require('*' + suffix in include, f'{platform} must include raw shader *{suffix}')
        require(all(prefix + '*' in exclude for prefix in EXPERIMENTAL_EXPORT_PREFIXES),
                f'{platform} must exclude the rejected experimental lighting study')
        require('terrain-cache-history/*' in exclude,
                f'{platform} must exclude obsolete terrain-cache-history files')
        checked.append(platform)
    require(set(checked) == {'Windows Desktop', 'Android'}, 'PC/Android source export presets are missing')
    return checked

def check_editable_assets(root):
    """Presence/header gate, not a geometry, texture, or GPU-quality claim."""
    root = Path(root)
    required = ['tools/blender/build_formal.py', 'tools/blender/export_formal_floorplan.py',
                'assets/models/formal/formal_manifest.json', 'scripts/world/room_catalog.gd',
                'scripts/world/source_wfc.gd', 'scripts/world/formal_rooms.gd',
                'scripts/rendering/desktop_quality_panel.gd', 'scripts/mobile/pool_mobile_quality.gd',
                'scripts/audio/pool_audio.gd', 'scripts/water/source_water_runtime.gd',
                'scripts/water/source_port/source_wave_solver.gd',
                'shaders/source_water/swe_height.glsl', 'shaders/source_water/caustic_photons.vert']
    blends = [f'tools/blender/source/{name}.blend' for name in FORMAL_ASSETS]
    models = [f'assets/models/formal/{name}.glb' for name in FORMAL_ASSETS]
    models += [f'assets/models/{name}.glb' for name in QUIET_ASSETS]
    required += blends + models
    for rel in required:
        require((root / rel).is_file(), f'Editable/runtime dependency missing: {rel}')
        require((root / rel).stat().st_size > 0, f'Editable/runtime dependency empty: {rel}')
    for rel in blends:
        with (root / rel).open('rb') as stream:
            require(stream.read(7) == b'BLENDER', f'Editable Blender header invalid: {rel}')
    for rel in models:
        with (root / rel).open('rb') as stream:
            header = stream.read(12)
        require(len(header) == 12 and struct.unpack('<3I', header) ==
                (0x46546c67, 2, (root / rel).stat().st_size), f'Runtime GLB header/length invalid: {rel}')
    return {'editable_blender_files': blends, 'runtime_glb_files': models,
            'generators_and_runtime_dependencies_checked': len(required),
            'scope': 'Presence and binary headers only; no fresh geometry or GPU validation.'}

def check_runtime_imports(read, root):
    """Follow actual exported remaps for runtime assets, not just raw source paths."""
    root = Path(root)
    checked = []
    paths = []
    for folder in ('assets', 'scripts/mobile', 'shaders'):
        paths.extend(path for path in (root / folder).rglob('*.import')
                     if not path.relative_to(root).as_posix().startswith(EXPERIMENTAL_EXPORT_PREFIXES))
    for path in sorted(paths):
        rel = path.relative_to(root).as_posix()
        exported = read(rel).decode('utf-8').rstrip('\0')
        targets = re.findall(r'^path(?:\.[^=\n]+)?="res://([^"\n]+)"', exported, re.M)
        require(targets, f'Exported runtime import has no payload target: {rel}')
        for target in targets:
            safe_name(target)
            payload = read(target)
            require(payload, f'Empty exported runtime import payload: {target}')
            original = root / target
            require(original.is_file(), f'Frozen imported payload absent: {target}; finish import before export')
            require(payload == original.read_bytes(), f'Exported runtime import differs from frozen payload: {target}')
        checked.append({'asset': rel.removesuffix('.import'), 'payloads': targets})
    require(checked, 'No runtime imports were checked')
    return checked

def runtime_dependencies(root):
    """Static literal coverage only; dynamically constructed resource paths need runtime gates."""
    root = Path(root)
    references = {}
    for folder in ('scripts', 'shaders', 'scenes', 'assets'):
        for path in (root / folder).rglob('*'):
            if path.suffix not in {'.gd', '.gdshader', '.gdshaderinc', '.tscn', '.tres'}:
                continue
            if path.relative_to(root).as_posix().startswith(EXPERIMENTAL_EXPORT_PREFIXES):
                continue
            for rel in re.findall(r"[\"']res://([^\"'\n]+)[\"']", path.read_text()):
                if any(token in rel for token in ('%', '*')) or not PurePosixPath(rel).suffix:
                    continue
                if rel.startswith('output/'):
                    continue  # QA screenshot destinations, not input dependencies.
                safe_name(rel)
                require(not rel.startswith(EXPERIMENTAL_EXPORT_PREFIXES + NON_RUNTIME_EXPORT_PREFIXES),
                        f'Runtime depends on an excluded resource: {path.relative_to(root)} -> {rel}')
                require((root / rel).is_file(), f'Runtime literal dependency missing: {path.relative_to(root)} -> {rel}')
                references.setdefault(rel, []).append(path.relative_to(root).as_posix())
    return references


def check_runtime_dependencies(read, root):
    verified = []
    for name in sorted(runtime_dependencies(root)):
        try:
            payload = read(name)
        except AuditError:
            payload = None
        if payload is not None:
            require(payload, f'Runtime literal resource is empty: {name}')
            verified.append({'resource': name, 'exported': [name]})
            continue
        targets = None
        for suffix in ('.remap', '.import'):
            try:
                remap = read(name + suffix).decode('utf-8').rstrip('\0')
            except AuditError:
                continue
            targets = re.findall(r'^path(?:\.[^=\n]+)?="res://([^"\n]+)"', remap, re.M)
            require(targets, f'Runtime literal remap is invalid: {name + suffix}')
            for target in targets:
                safe_name(target)
                require(read(target), f'Runtime literal remap payload is empty: {target}')
            break
        require(targets is not None, f'Runtime literal resource absent from export: {name}')
        verified.append({'resource': name, 'exported': targets})
    return verified


def check_source_resources(read, root):
    # Exported text resources may be rewritten to binary resources with remaps.
    config = (root / 'project.godot').read_text()
    main = re.search(r'^run/main_scene="(res://[^"]+)"', config, re.M)
    require(main is not None, 'Source main scene must use an explicit res:// path')
    name = main.group(1)[6:]
    try:
        scene = read(name)
    except AuditError:
        remap = read(name + '.remap').decode('utf-8')
        target = re.search(r'^path="(res://[^"]+)"', remap, re.M)
        require(target is not None, 'Main-scene remap is missing its target')
        scene = read(safe_name(target.group(1)[6:]))
    require(scene, 'Exported main scene is empty')
    verified = []
    for path in sorted((root / 'shaders').rglob('*')):
        if path.is_file() and path.suffix in RAW_SUFFIXES:
            name = path.relative_to(root).as_posix()
            require(read(name) == path.read_bytes(), f'Raw source shader differs: {name}')
            verified.append(name)
    # The final release deliberately exports source scripts. Cache keys hash their
    # exact text; bytecode-only exports cannot establish the same identity.
    for path in sorted((root / 'scripts').rglob('*.gd')):
        name = path.relative_to(root).as_posix()
        require(read(name) == path.read_bytes(), f'Exported GDScript differs/missing: {name}; use script_export_mode=0')
    for path in sorted((root / 'assets' / 'cache').rglob('*.terrain')):
        name = path.relative_to(root).as_posix()
        require(read(name) == path.read_bytes(), f'Prepared terrain asset differs/missing: {name}; include *.terrain')
        verified.append(name)
    return verified

def pck_audit(args):
    pck = Pck(args.pck)
    libraries, descriptor = check_registration(pck.read)
    path = Path(args.package_root) / libraries[args.platform]
    require(path.is_file(), f'External native library missing: {libraries[args.platform]}; --export-pack does not copy it')
    native = check_native_bytes(path.read_bytes(), args.platform)
    require(libraries[args.platform] not in pck.entries, 'Native shared library should be external, not a raw PCK asset')
    result = {'kind': 'pck', 'file': pck.path.name, 'bytes': len(pck.data), 'sha256': digest(pck.data),
              'pck_format': pck.format, 'godot_export_version': pck.engine, 'entry_count': len(pck.entries),
              'all_entry_md5_verified': True, 'startup_extension_registered': True,
              'external_library': libraries[args.platform], 'native': native}
    result.update(check_export_exclusions(pck.entries, args.source))
    if args.source:
        root = Path(args.source)
        require(descriptor == (root / DESCRIPTOR).read_bytes(), 'PCK descriptor differs from frozen source')
        require(path.read_bytes() == (root / libraries[args.platform]).read_bytes(), 'Staged native library differs from source')
        result['raw_source_assets_verified'] = check_source_resources(pck.read, root)
        result['runtime_imports_verified'] = check_runtime_imports(pck.read, root)
        result['runtime_literal_dependencies_verified'] = check_runtime_dependencies(pck.read, root)
    if args.launcher:
        data = Path(args.launcher).read_bytes()
        launcher = data.decode('utf-8-sig')
        require('DisableDelayedExpansion' in launcher, 'Launcher must preserve ! in paths')
        require('--path "%ROOT%\\."' in launcher and '--main-pack "%PACK%"' in launcher, 'Launcher lacks explicit package-root binding')
        require('--log-file "%GODOTLOG%"' in launcher and 'pause' in launcher.lower(), 'Launcher diagnostic/pause behavior missing')
        require(b'\r\n' in data, 'Windows CMD must use CRLF')
        result['launcher_static_audit'] = True
        result['windows_cmd_executed'] = False
    return result

def run_tool(tool, *args):
    proc = subprocess.run([str(tool), *map(str, args)], capture_output=True, text=True)
    require(proc.returncode == 0, f'{Path(tool).name} failed: {proc.stdout}\n{proc.stderr}')
    return proc.stdout, proc.stderr

def verify_apk_signer_report(output, expected_sha256=None):
    """Verify public signing identity only; never opens a keystore/private key."""
    require('v2): true' in output and 'v3): true' in output, 'Expected APK v2/v3 signatures')
    certificates = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})$', output, re.M | re.I)
    require(len(certificates) == 1 and re.search(r'^Number of signers: 1$', output, re.M),
            'Expected exactly one APK signing certificate')
    actual = certificates[0].lower()
    if expected_sha256 is not None:
        require(re.fullmatch(r'[0-9a-fA-F]{64}', expected_sha256), 'Expected signer must be a 64-character SHA-256 digest')
        require(actual == expected_sha256.lower(), 'APK signing certificate differs from the approved baseline')
    return actual


def apk_audit(args):
    expected_signer = getattr(args, 'expected_signer_sha256', None)
    require(not expected_signer or args.require_signature, '--expected-signer-sha256 requires --require-signature')
    apk = Path(args.apk)
    data = apk.read_bytes()
    with zipfile.ZipFile(apk) as z:
        names = z.namelist()
        require(len(names) == len(set(names)), 'Duplicate APK ZIP entries')
        for name in names:
            safe_name(name.rstrip('/'))
        no_secrets(names)
        require(z.testzip() is None, 'APK CRC failure')
        def read(name):
            entry = 'assets/' + name
            require(entry in names, f'Missing APK asset: {entry}')
            return z.read(entry)
        libraries, descriptor = check_registration(read)
        lib = 'lib/arm64-v8a/' + PurePosixPath(libraries['android']).name
        require(lib in names, f'APK native ARM64 helper missing: {lib}')
        require(not any(n.startswith('assets/') and n.endswith(('.so', '.dll')) for n in names), 'Native library incorrectly stored as raw asset')
        abis = sorted({n.split('/')[1] for n in names if n.startswith('lib/') and n.endswith('.so')})
        require(abis == ['arm64-v8a'], f'Unexpected APK ABIs: {abis}')
        require('lib/arm64-v8a/libgodot_android.so' in names, 'Android Godot runtime missing')
        native = check_native_bytes(z.read(lib), 'android')
        result = {'kind': 'apk', 'file': apk.name, 'bytes': len(data), 'sha256': digest(data), 'zip_crc_verified': True,
                  'abis': abis, 'startup_extension_registered': True, 'native_library_entry': lib,
                  'native': native, 'phone_install_or_execution_tested': False}
        result.update(check_export_exclusions((name[7:] for name in names if name.startswith('assets/')), args.source))
        if args.source:
            root = Path(args.source)
            require(descriptor == (root / DESCRIPTOR).read_bytes(), 'APK descriptor differs from frozen source')
            require(z.read(lib) == (root / libraries['android']).read_bytes(), 'APK native helper differs from source')
            result['raw_source_assets_verified'] = check_source_resources(read, root)
            result['runtime_imports_verified'] = check_runtime_imports(read, root)
            result['runtime_literal_dependencies_verified'] = check_runtime_dependencies(read, root)
    if args.build_tools:
        build = Path(args.build_tools)
        manifest, warnings = run_tool(build / 'aapt2', 'dump', 'badging', apk)
        xml, xml_warnings = run_tool(build / 'aapt2', 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml')
        require("native-code: 'arm64-v8a'" in manifest, 'Manifest ABI missing')
        require('application-debuggable' in manifest, 'Expected test/debug APK manifest')
        require(re.search(r'extractNativeLibs.*=true', xml), 'Expected template extraction-based native library loading')
        require('assets/native/' not in xml, 'Unexpected native metadata')
        permissions = [line for line in manifest.splitlines() if line.startswith('uses-permission')]
        require(not permissions, f'Unexpected APK permissions: {permissions}')
        if args.package_id:
            require(f"package: name='{args.package_id}'" in manifest, 'Unexpected Android package ID')
        alignment, _ = run_tool(build / 'zipalign', '-c', '-P', '16', '-v', '4', apk)
        require('Verification successful' in alignment, 'APK ZIP alignment failed')
        result.update({'manifest_extract_native_libs': True, 'zipalign_16k_check': True, 'debuggable_test_build': True,
                       'permissions': permissions, 'manifest': manifest.splitlines(),
                       'warnings': (warnings + xml_warnings).strip()})
        if args.require_signature:
            signature, sig_warnings = run_tool(build / 'apksigner', 'verify', '--verbose', '--print-certs', apk)
            signer = verify_apk_signer_report(signature, expected_signer)
            result['signing_certificate_sha256'] = signer
            result['approved_baseline_signer_matched'] = expected_signer is not None
            result['signature_v2_v3_verified'] = True
            result['signature_warnings'] = sig_warnings.strip()
    else:
        require(not args.require_signature, '--require-signature requires --build-tools')
        result['manifest_and_signature_checked'] = False
    return result

def check_native_source_identity(root, libraries=None):
    root = Path(root)
    if libraries is None:
        libraries = descriptor_libraries((root / DESCRIPTOR).read_bytes())
    atomic_path = root / 'native/source_water/verification/atomic_build.json'
    require(atomic_path.is_file(), 'Frozen native atomic-build verification is missing')
    atomic = json.loads(atomic_path.read_text())
    for rel in libraries.values():
        require(digest((root / rel).read_bytes()) == atomic['targets'][PurePosixPath(rel).name],
                f'Native binary differs from verified atomic build: {rel}')
    for rel, expected in atomic['cross_target_audit']['source_sha256'].items():
        name = safe_name(rel)
        require(digest((root / 'native/source_water' / name).read_bytes()) == expected,
                f'Native source differs from verified atomic build: {name}')
    # Follow local quoted includes as well as the historical fixed list so a
    # newly integrated helper cannot silently omit a required C header/binding.
    native_root = (root / 'native/source_water').resolve()
    pending = [native_root / 'source_water.c']
    native_includes = set()
    while pending:
        source = pending.pop()
        rel = source.relative_to(native_root).as_posix()
        if rel in native_includes:
            continue
        native_includes.add(rel)
        require(source.is_file(), f'Native local source dependency missing: {rel}')
        for included in re.findall(r'^\s*#\s*include\s*"([^"\n]+)"', source.read_text(), re.M):
            target = (source.parent / safe_name(included)).resolve()
            require(native_root.resolve() in target.parents, f'Native include escapes source bundle: {included}')
            pending.append(target)
    require(native_includes <= set(atomic['cross_target_audit']['source_sha256']),
            'Native included source is not bound by the atomic-build manifest')
    return sorted(native_includes)


def source_audit(args):
    root = Path(args.directory)
    files = sorted(p for p in root.rglob('*') if p.is_file())
    names = [p.relative_to(root).as_posix() for p in files]
    no_secrets(names)
    require(not any(p.is_symlink() for p in root.rglob('*')), 'Source package contains symlinks')
    require((root / 'project.godot').is_file(), 'Source project.godot missing')
    export_policy = check_export_policy(root)
    libraries = descriptor_libraries((root / DESCRIPTOR).read_bytes())
    registry = root / '.godot/extension_list.cfg'
    require(registry.is_file(), 'Portable source native startup registry is missing')
    require(registry.read_text().splitlines() == ['res://' + DESCRIPTOR], 'Source startup registry is not the single expected portable res:// path')
    require(sorted(p.relative_to(root / '.godot').as_posix() for p in (root / '.godot').rglob('*') if p.is_file()) == ['extension_list.cfg'], 'Source ships generated editor cache beyond portable registry')
    editor = root / 'Prepare-Editor.cmd'
    require(editor.is_file(), 'Source editor preparation launcher missing')
    editor_data = editor.read_bytes()
    editor_text = editor_data.decode('ascii')
    require('DisableDelayedExpansion' in editor_text and '--editor --path "%ROOT%\\."' in editor_text, 'Editor launcher path handling is not portable')
    require('res://' + DESCRIPTOR in editor_text and b'\r\n' in editor_data, 'Editor launcher lacks native bootstrap/CRLF')
    native = {}
    for platform, rel in libraries.items():
        require((root / rel).is_file(), f'Source native dependency missing: {rel}')
        native[platform] = check_native_bytes((root / rel).read_bytes(), platform)
    for name in ('native/source_water/LICENSE', 'native/source_water/THIRD_PARTY_NOTICES.md',
                 'native/source_water/README.md', 'native/source_water/source_water.c',
                 'native/source_water/readback_core.h', 'native/source_water/occlusion_core.h',
                 'native/source_water/vendor/gdextension_interface.h', 'native/source_water/build.sh',
                 'native/source_water/acquire_toolchain.py', 'native/source_water/toolchain-packages.json'):
        require((root / name).is_file(), f'Native source/build/license file missing: {name}')
    native_includes = check_native_source_identity(root, libraries)
    solver = (root / 'scripts/water/source_port/source_wave_solver.gd').read_text()
    require('ClassDB.class_exists' in solver and 'SourceWaterReadback' in solver, 'Optional native class availability guard missing')
    assets = check_editable_assets(root)
    return {'kind': 'source', 'files': len(files), 'bytes': sum(p.stat().st_size for p in files), 'editable_assets': assets,
            'native_targets': native, 'private_signing_material': False, 'native_class_guard_present': True, 'portable_startup_registry': True,
            'editor_launcher_static_audit': True, 'windows_editor_executed': False,
            'native_atomic_build_hashes_verified': True, 'native_local_includes_verified': sorted(native_includes),
            'source_text_terrain_export_presets_verified': export_policy}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--report', type=Path, help='Write JSON on success (outside the package is recommended)')
    sub = p.add_subparsers(dest='kind', required=True)
    q = sub.add_parser('pck')
    q.add_argument('pck', type=Path)
    q.add_argument('--platform', required=True, choices=('windows', 'linux'))
    q.add_argument('--package-root', required=True, type=Path)
    q.add_argument('--source', type=Path)
    q.add_argument('--launcher', type=Path)
    q = sub.add_parser('apk')
    q.add_argument('apk', type=Path)
    q.add_argument('--source', type=Path)
    q.add_argument('--build-tools', type=Path)
    q.add_argument('--package-id', default='org.poolcore.beyondthebasin')
    q.add_argument('--require-signature', action='store_true')
    q.add_argument('--expected-signer-sha256', help='Public SHA-256 fingerprint from the approved earlier test APK; never a private key')
    q = sub.add_parser('source')
    q.add_argument('directory', type=Path)
    args = p.parse_args()
    try:
        result = {'pck': pck_audit, 'apk': apk_audit, 'source': source_audit}[args.kind](args)
        result['status'] = 'PASS'
        encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(encoded)
        print(encoded, end='')
        return 0
    except (AuditError, OSError, ValueError, struct.error, zipfile.BadZipFile, KeyError) as exc:
        print(f'PACKAGE_AUDIT_FAIL: {exc}', file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
