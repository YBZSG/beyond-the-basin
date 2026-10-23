#!/usr/bin/env python3
"""Standard-library CPU tests. No Godot process, GPU, key access, or export."""
import hashlib
import copy
from pathlib import Path
import struct
import tempfile
import unittest
import subprocess
import sys
# Verification may run from an immutable staged tree; never create local bytecode.
sys.dont_write_bytecode = True
import json
from audit_packages import AuditError, Pck, descriptor_libraries, no_secrets, check_native_bytes, check_export_exclusions, check_export_policy, check_runtime_imports, check_editable_assets, verify_apk_signer_report, runtime_dependencies, check_runtime_dependencies
from stage_release import source_paths, archive, manifest, verify_manifest, stage_windows_executable
from prepare_extension_registry import prepare
from validate_frozen_release import authored_catalog, check_cache_report, stage_process_bound_validator
from make_binary_parts import make_parts
from verify_checkpoint_identity import source_string_signature, terrain_header
from freeze_build_inputs import build_paths, freeze, verify_frozen_inputs
from unittest.mock import patch
from make_checkpoint_archives import write_delivery_notes
from make_incremental_recovery import build as make_incremental
from make_lab_archives import make_lab_parts
from audit_packages import check_bake_quarantine
from acquire_windows_templates import acquire, ASSET, URL, ENTRIES


def pck_bytes(version=3, entries=None):
    if entries is None:
        entries = [('res://file.txt', b'contents')]
    base = 112 if version == 3 else 96 + 4 + sum(40 + len(n.encode()) for n, _ in entries)
    data = b''.join(d for _, d in entries)
    directory = struct.pack('<I', len(entries))
    start = 0
    for name, content in entries:
        raw = name.encode()
        directory += struct.pack('<I', len(raw)) + raw + struct.pack('<QQ', start, len(content))
        directory += hashlib.md5(content).digest() + struct.pack('<I', 0)
        start += len(content)
    header = struct.pack('<6IQ', 0x43504447, version, 4, 6, 3, 2, base)
    if version == 3:
        return header + struct.pack('<Q', base + len(data)) + b'\0' * 72 + data + directory
    return header + b'\0' * 64 + directory + data


class ReleaseToolsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='poolcore-release-test-')
        self.root = Path(self.temp.name)
    def tearDown(self):
        self.temp.cleanup()
    def parse(self, data):
        p = self.root / 'test.pck'; p.write_bytes(data)
        return Pck(p)
    def test_pck_v3_md5(self):
        p = self.parse(pck_bytes())
        self.assertEqual(p.read('file.txt'), b'contents')
        self.assertEqual(p.engine, '4.6.3')
    def test_pck_v2_md5(self):
        self.assertEqual(self.parse(pck_bytes(2)).read('file.txt'), b'contents')
    def test_duplicate_paths(self):
        with self.assertRaisesRegex(AuditError, 'Duplicate'):
            self.parse(pck_bytes(entries=[('file', b'a'), ('file', b'b')]))
    def test_traversal(self):
        with self.assertRaisesRegex(AuditError, 'Unsafe'):
            self.parse(pck_bytes(entries=[('../private', b'a')]))
    def test_corrupt_content(self):
        data = bytearray(pck_bytes()); data[112] ^= 1
        with self.assertRaisesRegex(AuditError, 'integrity'):
            self.parse(data)
    def test_truncated_directory(self):
        with self.assertRaises(AuditError):
            self.parse(pck_bytes()[:-1])
    def test_encrypted_flag(self):
        data = bytearray(pck_bytes()); struct.pack_into('<I', data, 20, 3)
        with self.assertRaisesRegex(AuditError, 'flags'):
            self.parse(data)
    def test_sparse_flag(self):
        data = bytearray(pck_bytes()); struct.pack_into('<I', data, 20, 6)
        with self.assertRaisesRegex(AuditError, 'flags'):
            self.parse(data)
    def test_directory_out_of_bounds(self):
        data = bytearray(pck_bytes()); struct.pack_into('<Q', data, 32, 2**63)
        with self.assertRaisesRegex(AuditError, 'directory offset'):
            self.parse(data)
    def test_secrets_rejected(self):
        for name in ['x/debug.keystore', 'export_credentials.cfg', '.env', '.env.local', '.ssh/key', 'x/private.pem']:
            with self.subTest(name=name), self.assertRaises(AuditError):
                no_secrets([name])
    def test_source_filter(self):
        files = ['project.godot', 'scripts/main.gd', 'native/source_water/build/helper.obj',
                 'native/source_water/bin/helper.dll', 'output/android/private.keystore',
                 '.godot/editor/state.cfg', 'tools/__pycache__/thing.pyc', 'tools/thing.py',
                 'export_credentials.cfg', 'docs/.env.local']
        for name in files:
            p = self.root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('x')
        selected = {p.relative_to(self.root).as_posix() for p in source_paths(self.root)}
        self.assertEqual(selected, {'project.godot', 'scripts/main.gd', 'native/source_water/bin/helper.dll', 'tools/thing.py'})
    def test_blender_generated_backups_and_physics_cache_excluded(self):
        kept=['assets/models/source/room.blend','tools/models/generate_room.py',
              'assets/models/source/.gdignore']
        skipped=['assets/models/source/room.blend1','assets/models/source/room.blend3',
                 'assets/models/source/room.BLEND99','assets/models/source/room.blend@',
                 'assets/models/source/blendcache_room/cache.bphys',
                 'assets/models/source/blendcache_room/simulation.bin',
                 'assets/models/source/cache.bphys']
        for name in kept+skipped:
            path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('fixture')
        for profile in ('development','final'):
            self.assertEqual({p.relative_to(self.root).as_posix() for p in source_paths(self.root,profile)},set(kept))
    def test_generated_fixture_workspaces_excluded(self):
        kept = ['tests/fixtures/particle_gate_audit/audit/run_audit.py',
                'tests/fixtures/particle_gate_audit/audit/summary.json',
                'tests/fixtures/particle_gate_audit/audit/run-20261021T213530Z-abcd/result.json',
                'tests/fixtures/particle_gate_audit/extension_api.json',
                'tests/fixtures/source_incoming_masks_real.maskfixture',
                'assets/cache/source_terrain/prepared.terrain']
        skipped = ['tests/fixtures/particle_gate_audit/audit/run-20261021T213530Z-abcd/snapshot/extension_api.json',
                   'tests/fixtures/particle_gate_audit/build/object.o',
                   'tests/fixtures/source_capture_sampling_audit/parse-cache/fontconfig/cache',
                   'terrain-cache-history/old.terrain']
        for name in kept + skipped:
            p = self.root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('x')
        self.assertEqual({p.relative_to(self.root).as_posix() for p in source_paths(self.root)},set(kept))
    def test_final_source_separates_optional_lab(self):
        for name in ['scenes/main.tscn','scenes/lighting_lab/tiny.tscn','assets/lighting/tiny.exr','tools/lighting/prepare.gd']:
            p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('x')
        self.assertEqual({p.relative_to(self.root).as_posix() for p in source_paths(self.root,'final')},
                         {'scenes/main.tscn','tools/lighting/prepare.gd'})
    def test_source_symlink_rejected(self):
        p = self.root / 'scripts'; p.mkdir(); (p/'leak.gd').symlink_to('/etc/passwd')
        with self.assertRaisesRegex(AuditError, 'symlink'):
            source_paths(self.root)
    def test_reproducible_zip(self):
        root = self.root/'payload'; root.mkdir(); (root/'中文 space !.txt').write_text('data')
        a = archive(root, self.root/'first.zip'); b = archive(root, self.root/'second.zip')
        self.assertEqual(a['sha256'], b['sha256'])
        with self.assertRaisesRegex(AuditError, 'replace'):
            archive(root, self.root/'first.zip')
    def test_real_native_binaries(self):
        root = Path(__file__).resolve().parents[2]
        libraries = descriptor_libraries((root/'native/source_water/source_water.gdextension').read_bytes())
        for platform, rel in libraries.items():
            with self.subTest(platform=platform):
                self.assertEqual(check_native_bytes((root/rel).read_bytes(), platform)['platform'], platform)
    def test_official_windows_range_acquisition_offline_fixture(self):
        import io, zipfile
        from unittest.mock import patch
        index=self.root/'index.tpz'
        with zipfile.ZipFile(index,'w',compression=zipfile.ZIP_DEFLATED) as z:
            for name in ENTRIES:
                z.writestr('templates/'+name,b'MZ'+name.encode()*40)
        data=index.read_bytes()
        metadata={'tag_name':'4.6.3-stable','assets':[{'name':ASSET,'id':123,'size':len(data),
                 'browser_download_url':URL,'digest':'sha256:'+hashlib.sha256(data).hexdigest()}]}
        evidence=self.root/'receipt.json';output=self.root/'templates'
        def ranged(start,end,total):
            self.assertEqual(total,len(data))
            return data[start:end+1],'release-assets.githubusercontent.com'
        with patch('acquire_windows_templates.urllib.request.urlopen',return_value=io.BytesIO(json.dumps(metadata).encode())), \
             patch('acquire_windows_templates.fetch_range',side_effect=ranged):
            report=acquire(index,output,evidence)
        self.assertFalse(report['full_archive_digest_verified'])
        self.assertFalse(report['windows_execution'])
        for entry in report['downloaded_entries']:
            path=output/Path(entry['archive_path']).name
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),entry['sha256'])
        with self.assertRaisesRegex(AuditError,'already exists'):
            acquire(index,output,evidence)

    def test_self_contained_windows_template_identity(self):
        data=bytearray(1024);data[:2]=b'MZ';struct.pack_into('<I',data,60,128)
        data[128:132]=b'PE\0\0';struct.pack_into('<H',data,132,0x8664)
        struct.pack_into('<H',data,150,2);struct.pack_into('<H',data,152,0x20b)
        template=self.root/'windows_release_x86_64.exe';template.write_bytes(data)
        exe=self.root/'Exported game.exe';exe.write_bytes(data)
        out=self.root/'中文 game !';out.mkdir()
        with patch('stage_release.WINDOWS_RELEASE_SHA256',hashlib.sha256(data).hexdigest()):
            report=stage_windows_executable(exe,template,out)
        self.assertTrue(report['template_bytes_identical'])
        self.assertFalse(report['windows_executed'])
        self.assertEqual((out/'PoolCore-Source-Water.exe').read_bytes(),data)
        exe.write_bytes(data+b'appended pack')
        with patch('stage_release.WINDOWS_RELEASE_SHA256',hashlib.sha256(data).hexdigest()):
            with self.assertRaisesRegex(AuditError,'differs'):
                stage_windows_executable(exe,template,out)
        with self.assertRaisesRegex(AuditError,'pin mismatch'):
            stage_windows_executable(exe,template,out)
    def test_self_contained_windows_wrong_arch_or_wrapper_rejected(self):
        data=bytearray(1024);data[:2]=b'MZ';struct.pack_into('<I',data,60,128)
        data[128:132]=b'PE\0\0';struct.pack_into('<H',data,132,0xaa64)
        template=self.root/'windows_release_x86_64.exe';template.write_bytes(data)
        exe=self.root/'game.exe';exe.write_bytes(data)
        with self.assertRaisesRegex(AuditError,'architecture'):
            stage_windows_executable(exe,template,self.root)
        wrapper=self.root/'windows_release_x86_64_console.exe';wrapper.write_bytes(data)
        with self.assertRaisesRegex(AuditError,'console wrapper'):
            stage_windows_executable(exe,wrapper,self.root)
    def test_launcher_quoting_contract(self):
        text = (Path(__file__).parent/'Launch-PoolCore.cmd').read_text()
        self.assertLess(text.index('set "ENGINE=%~f1"'), text.index('pushd'))
        self.assertIn('DisableDelayedExpansion', text)
        self.assertLess(text.index('if defined ENGINE goto check_engine'),text.index('if exist "%ROOT%\\PoolCore-Source-Water.exe"'))
        self.assertLess(text.index('if exist "%ROOT%\\PoolCore-Source-Water.exe"'),text.index('if exist "%ROOT%\\Godot_v4.6.3-stable_win64.exe"'))
        self.assertIn('--path "%ROOT%\\." --main-pack "%PACK%"', text)
        self.assertIn('findstr /R /B /C:"4[.][67][.]"', text)
        self.assertIn('compatibility is unverified', text)
        self.assertIn('matching names', text)
        self.assertIn('"%ROOT%\\*.exe"', text)
        for name in ('Launch-PoolCore.cmd','Prepare-Editor.cmd'):
            data=(Path(__file__).parent/name).read_bytes()
            self.assertNotIn(b'\n',data.replace(b'\r\n',b''))
            self.assertIn(b'4[.][67][.]',data)
    def registry_fixture(self):
        (self.root/'project.godot').write_text('config_version=5\n')
        descriptor=self.root/'native/source_water/source_water.gdextension'
        descriptor.parent.mkdir(parents=True); descriptor.write_text('[configuration]\n')
    def test_registry_preseed_and_idempotence(self):
        self.registry_fixture()
        self.assertTrue(prepare(self.root)['added'])
        expected=b'res://native/source_water/source_water.gdextension\n'
        path=self.root/'.godot/extension_list.cfg'
        self.assertEqual(path.read_bytes(),expected)
        self.assertFalse(prepare(self.root)['added'])
        self.assertEqual(path.read_bytes(),expected)
    def test_registry_preserves_existing_entries_without_final_newline(self):
        self.registry_fixture(); (self.root/'.godot').mkdir()
        path=self.root/'.godot/extension_list.cfg'
        path.write_text('res://other/addon.gdextension')
        self.assertEqual(prepare(self.root)['existing_entries_preserved'],1)
        self.assertEqual(path.read_text().splitlines(),['res://other/addon.gdextension','res://native/source_water/source_water.gdextension'])
    def test_registry_rejects_symlinked_directory(self):
        self.registry_fixture(); (self.root/'.godot').symlink_to('/tmp',target_is_directory=True)
        with self.assertRaisesRegex(AuditError,'symlinked'):
            prepare(self.root)
    def test_manifest_regeneration_does_not_self_hash(self):
        (self.root/'file.txt').write_text('x')
        (self.root/'nested').mkdir(); (self.root/'nested/SHA256SUMS.txt').write_text('nested source data')
        manifest(self.root,'fixture',{}); first=(self.root/'PACKAGE-MANIFEST.json').read_bytes()
        manifest(self.root,'fixture',{})
        self.assertEqual((self.root/'PACKAGE-MANIFEST.json').read_bytes(),first)
        self.assertIn('nested/SHA256SUMS.txt',first.decode())
        self.assertEqual(verify_manifest(self.root)['kind'],'fixture')
    def test_manifest_rejects_changed_or_extra_files(self):
        target=self.root/'data.txt';target.write_text('old')
        manifest(self.root,'fixture',{})
        target.write_text('new')
        with self.assertRaisesRegex(AuditError,'bytes differ'):
            verify_manifest(self.root)
        target.write_text('old');(self.root/'unexpected.txt').write_text('extra')
        with self.assertRaisesRegex(AuditError,'file set differs'):
            verify_manifest(self.root)
    def test_lab_manifest_cannot_overwrite_source_manifest(self):
        (self.root/'LAB-RESTORE.txt').write_text('lab')
        manifest(self.root,'optional-lab',{},prefix='LAB-')
        self.assertFalse((self.root/'PACKAGE-MANIFEST.json').exists())
        self.assertEqual(verify_manifest(self.root,prefix='LAB-')['kind'],'optional-lab')
    def binary_parts_fixture(self):
        folder=self.root/'Chinese 中文 space !';folder.mkdir()
        apk=folder/'PoolCore-Test.apk';apk.write_bytes(bytes(range(256))*2500)
        output=folder/'delivery'
        report=make_parts(apk,output,'PoolCore-Test',part_bytes=256000,maximum_zip_bytes=1000000)
        return apk,output,report
    def test_binary_parts_rebuild_and_idempotence(self):
        apk,output,report=self.binary_parts_fixture()
        root=output/'rebuild-files';script=root/'Rebuild-APK.py'
        proc=subprocess.run([sys.executable,script],capture_output=True,text=True)
        self.assertEqual(proc.returncode,0,proc.stderr)
        self.assertEqual((root/apk.name).read_bytes(),apk.read_bytes())
        self.assertEqual(len(report['archives']),3)
        proc=subprocess.run([sys.executable,script],capture_output=True,text=True)
        self.assertEqual(proc.returncode,0,proc.stderr)
        self.assertIn('Existing file verified',proc.stdout)
        cmd=(root/'Rebuild-APK.cmd').read_bytes()
        self.assertIn(b'DisableDelayedExpansion',cmd)
        self.assertIn(b'set "POOLCORE_REBUILD_BASE=%~dp0"',cmd)
        self.assertNotIn(b'ExecutionPolicy',cmd)
        self.assertNotIn(b'EncodedCommand',cmd)
    def test_binary_reconstruction_cmd_policy_and_path_data(self):
        source=self.root/'PoolCore-PC.zip';source.write_bytes(b'fixture'*50000)
        result=make_parts(source,self.root/'parts','PoolCore-Policy',part_bytes=256000)
        command=(self.root/'parts/rebuild-files/Rebuild-PC-Package.cmd').read_text()
        self.assertIn('set "POOLCORE_REBUILD_BASE=%~dp0"',command)
        self.assertIn('DisableDelayedExpansion',command)
        self.assertIn('powershell.exe -NoProfile -Command "',command)
        self.assertIn('$Base=$env:POOLCORE_REBUILD_BASE',command)
        self.assertNotIn('-File ',command)
        self.assertNotIn('ExecutionPolicy',command)
        self.assertNotIn('Invoke-Expression',command)
        self.assertNotIn('EncodedCommand',command)
        self.assertNotIn('Start-Process',command)
        self.assertIn('[System.IO.File]::Move($Temporary,$Target)',command)
        self.assertIn('Refusing overwrite',command)
        self.assertLess(len(command.encode('ascii')),8000)
        self.assertFalse(result['windows_cmd_executed'])

    def test_binary_parts_fail_closed(self):
        apk,output,report=self.binary_parts_fixture()
        root=output/'rebuild-files';script=root/'Rebuild-APK.py'
        part=root/report['input']['parts'][0]['file'];original=part.read_bytes();part.write_bytes(b'broken')
        proc=subprocess.run([sys.executable,script],capture_output=True,text=True)
        self.assertNotEqual(proc.returncode,0)
        self.assertFalse((root/apk.name).exists())
        self.assertFalse(list(root.glob('*.partial')))
        part.write_bytes(original);(root/apk.name).write_bytes(b'different')
        proc=subprocess.run([sys.executable,script],capture_output=True,text=True)
        self.assertNotEqual(proc.returncode,0)
        self.assertEqual((root/apk.name).read_bytes(),b'different')
    def test_binary_parts_manifest_tampering_rejected(self):
        apk,output,report=self.binary_parts_fixture()
        root=output/'rebuild-files';manifest=root/'PoolCore-Test-BINARY-PARTS.json'
        data=json.loads(manifest.read_text());data['file']='../outside.apk';manifest.write_text(json.dumps(data))
        proc=subprocess.run([sys.executable,root/'Rebuild-APK.py'],capture_output=True,text=True)
        self.assertNotEqual(proc.returncode,0)
        self.assertIn('Manifest mismatch',proc.stderr)
        self.assertFalse((output/'outside.apk').exists())
    def test_experimental_lighting_prefix_rejected(self):
        for name in ['scenes/lighting_lab/study.tscn.remap','assets/lighting/bad.exr.import']:
            with self.subTest(name=name), self.assertRaisesRegex(AuditError,'Experimental'):
                check_export_exclusions([name])
        self.assertTrue(check_export_exclusions(['scenes/main.tscn'])['experimental_lightmap_excluded'])
    def test_experimental_import_payload_rejected(self):
        folder=self.root/'assets/lighting'; folder.mkdir(parents=True)
        (folder/'study.exr.import').write_text('[remap]\npath="res://.godot/imported/study.hash.ctex"\n')
        with self.assertRaisesRegex(AuditError,'payload leaked'):
            check_export_exclusions(['.godot/imported/study.hash.ctex'],self.root)
        self.assertEqual(check_export_exclusions([],self.root)['excluded_import_paths_checked'],1)
    def test_non_runtime_export_leaks_rejected(self):
        for name in ['terrain-cache-history/old.terrain','tests/fixture.gd','tools/blender/build_formal.py',
                     'native/source_water/build/test.o']:
            with self.subTest(name=name), self.assertRaisesRegex(AuditError,'Non-runtime'):
                check_export_exclusions([name])
    def test_runtime_import_payloads(self):
        p=self.root/'assets/models/formal.glb.import';p.parent.mkdir(parents=True)
        p.write_text('[remap]\npath="res://.godot/imported/model.scn"\n')
        payload=self.root/'.godot/imported/model.scn';payload.parent.mkdir(parents=True);payload.write_bytes(b'model')
        entries={'assets/models/formal.glb.import':p.read_bytes()+b'\0','.godot/imported/model.scn':b'model'}
        def read(name):
            if name not in entries: raise AuditError('Missing resource '+name)
            return entries[name]
        self.assertEqual(len(check_runtime_imports(read,self.root)),1)
        entries['.godot/imported/model.scn']=b'wrong'
        with self.assertRaisesRegex(AuditError,'differs'):
            check_runtime_imports(read,self.root)
        del entries['.godot/imported/model.scn']
        with self.assertRaisesRegex(AuditError,'Missing resource'):
            check_runtime_imports(read,self.root)
    def test_production_lightmap_imports_not_lab_imports(self):
        for folder in ('assets/lightmaps', 'assets/lighting'):
            path=self.root/folder/'room.exr.import';path.parent.mkdir(parents=True)
            path.write_text('[remap]\npath="res://.godot/imported/room.ctex"\n')
        payload=self.root/'.godot/imported/room.ctex';payload.parent.mkdir(parents=True);payload.write_bytes(b'validated fixture')
        entries={'assets/lightmaps/room.exr.import':(self.root/'assets/lightmaps/room.exr.import').read_bytes(),
                 '.godot/imported/room.ctex':payload.read_bytes()}
        def read(name):
            if name not in entries: raise AuditError('Missing '+name)
            return entries[name]
        result=check_runtime_imports(read,self.root)
        self.assertEqual(len(result),1)
        self.assertEqual(result[0]['asset'],'assets/lightmaps/room.exr')

    def test_runtime_literal_dependency_export_remaps(self):
        script=self.root/'scripts/test.gd';script.parent.mkdir();script.write_text('const Scene = preload("res://scenes/room.tscn")\n')
        scene=self.root/'scenes/room.tscn';scene.parent.mkdir();scene.write_text('[gd_scene]\n')
        entries={'scenes/room.tscn.remap':b'[remap]\npath="res://.godot/exported/room.scn"\n',
                 '.godot/exported/room.scn':b'scene payload'}
        def read(name):
            if name not in entries: raise AuditError('Missing '+name)
            return entries[name]
        self.assertEqual(check_runtime_dependencies(read,self.root)[0]['exported'],['.godot/exported/room.scn'])
        del entries['.godot/exported/room.scn']
        with self.assertRaisesRegex(AuditError,'Missing'):
            check_runtime_dependencies(read,self.root)
        script.write_text('const Lab = preload("res://scenes/lighting_lab/study.tscn")\n')
        with self.assertRaisesRegex(AuditError,'excluded resource'):
            runtime_dependencies(self.root)

    def test_generated_graphics_caches_excluded_from_source(self):
        for rel in ('docs/audit/native/xdg-cache/mesa_shader_cache_db/cache',
                    'docs/audit/native/xdg-data/godot/app_userdata/Test/shader_cache/binary',
                    'docs/audit/native/xdg-config/editor_settings.tres',
                    'docs/audit/native/shader_cache/compiled.cache',
                    'docs/audit/native/result.json', 'tools/cache/bake_formal_terrain.gd',
                    'assets/cache/terrain/room.terrain'):
            path=self.root/rel;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'fixture')
        actual={p.relative_to(self.root).as_posix() for p in source_paths(self.root)}
        self.assertEqual(actual,{'docs/audit/native/result.json','tools/cache/bake_formal_terrain.gd',
                                 'assets/cache/terrain/room.terrain'})

    def build_freeze_fixture(self):
        root=self.root/'project'
        for rel in ('project.godot','scripts/runtime.gd','assets/cache/room.terrain',
                    '.godot/extension_list.cfg','.godot/global_script_class_cache.cfg',
                    '.godot/uid_cache.bin','.godot/imported/model.scn',
                    '.godot/imported/model.md5','.godot/export_credentials.cfg',
                    '.godot/editor/private-preferences.cfg'):
            p=root/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'fixture')
        return root

    def test_private_build_freeze_omits_credentials_and_preferences(self):
        from unittest.mock import patch
        root=self.build_freeze_fixture();out=self.root/'private-build'
        paths={p.relative_to(root).as_posix() for p in build_paths(root)}
        self.assertNotIn('.godot/export_credentials.cfg',paths)
        self.assertNotIn('.godot/editor/private-preferences.cfg',paths)
        self.assertIn('.godot/imported/model.scn',paths)
        with patch('freeze_build_inputs.preflight',return_value={'status':'PASS'}):
            result=freeze(root,out)
        self.assertEqual(result['status'],'PASS')
        (out/'.godot/uid_cache.bin').write_bytes(b'new generated registry')
        extra=out/'.godot/editor/generated.cfg';extra.parent.mkdir();extra.write_bytes(b'generated')
        self.assertEqual(verify_frozen_inputs(out)['status'],'PASS')
        (out/'scripts/runtime.gd').write_bytes(b'changed')
        with self.assertRaisesRegex(AuditError,'Frozen input changed'):
            verify_frozen_inputs(out)

    def test_private_build_freeze_rejects_changed_import_and_source_set(self):
        from unittest.mock import patch
        root=self.build_freeze_fixture();out=self.root/'private-build'
        with patch('freeze_build_inputs.preflight',return_value={'status':'PASS'}):
            freeze(root,out)
        (out/'.godot/imported/model.scn').write_bytes(b'changed')
        with self.assertRaisesRegex(AuditError,'Frozen input changed'):
            verify_frozen_inputs(out)
        (out/'.godot/imported/model.scn').write_bytes(b'fixture')
        (out/'scripts/new.gd').write_bytes(b'new runtime source')
        with self.assertRaisesRegex(AuditError,'file set changed'):
            verify_frozen_inputs(out)

    def test_final_source_status_is_not_old_recovery_status(self):
        (self.root/'project.godot').write_text('project')
        (self.root/'CHECKPOINT-STATUS.md').write_text('stale recovery description')
        selected={p.name for p in source_paths(self.root, 'final')}
        self.assertNotIn('CHECKPOINT-STATUS.md',selected)
        final=self.root/'clean-final';final.mkdir()
        write_delivery_notes(final,'editable-source','2026-10-22T02:00:00Z')
        self.assertFalse((final/'CHECKPOINT-STATUS.md').exists())
        self.assertTrue((final/'EDITABLE-SOURCE-RESTORE.txt').is_file())
        self.assertIn('not Windows/phone performance',(final/'EDITABLE-SOURCE-STATUS.txt').read_text())

    def test_current_editable_asset_contract(self):
        report=check_editable_assets(Path(__file__).resolve().parents[2])
        self.assertEqual(len(report['editable_blender_files']),6)
        self.assertEqual(len(report['runtime_glb_files']),10)
    def test_current_export_source_identity_policy(self):
        root=Path(__file__).resolve().parents[2]
        self.assertEqual(set(check_export_policy(root)),{'Windows Desktop','Android'})
    def test_new_compute_shader_requires_explicit_filter(self):
        root=Path(__file__).resolve().parents[2]
        (self.root/'export_presets.cfg').write_text((root/'export_presets.cfg').read_text().replace('*.compute,','').replace(',*.compute',''))
        shader=self.root/'shaders/new_kernel.compute';shader.parent.mkdir();shader.write_text('kernel')
        with self.assertRaisesRegex(AuditError,'raw shader'):
            check_export_policy(self.root)
    def test_serialized_source_string_signature(self):
        raw='中文 source\n'.encode()
        expected=hashlib.sha256(struct.pack('<II',4,len(raw))+raw+b'\0'*(-len(raw)%4)).hexdigest()
        self.assertEqual(source_string_signature(raw),expected)
        with self.assertRaises(UnicodeDecodeError):
            source_string_signature(b'\xff')
    def test_terrain_container_identity_and_stored_integrity(self):
        stored=b'stored fixture, intentionally not decompressed by this test'
        header={'schema':2,'codec':'zstd','key':'key','algorithm':'algorithm','bytes':200,
                'stored_bytes':len(stored),'stored_sha256':hashlib.sha256(stored).hexdigest(),'sha256':'a'*64}
        encoded=json.dumps(header).encode();prefix=b'POOL_TERRAIN_2\n'+struct.pack('<I',len(encoded))+encoded
        path=self.root/'test.terrain';path.write_bytes(prefix+stored)
        self.assertEqual(terrain_header(path,'key','algorithm'),header)
        with self.assertRaisesRegex(AuditError,'identity'):
            terrain_header(path,'wrong','algorithm')
        path.write_bytes(prefix+stored+b'changed')
        with self.assertRaisesRegex(AuditError,'integrity'):
            terrain_header(path,'key','algorithm')
    def cache_fixture(self):
        coordinates=[(-1,-1),(0,-1),(-1,0),(0,-2),(-1,-2)]
        coords=[f'({x}, {y})' for x,y in coordinates]
        sizes=[384,768,1152]
        result={'pass':True,'seed':250821,'errors':[],'sizes':sizes,'main_pack':'',
                'snapshot':{'exists':True,'reason':'','coords':coords},'publication_order':coords,
                'source_signatures':{'res://scripts/example.gd':'a'*64},
                'terrain':[{'coord':coord,'size':size,'key':f'{coord}:{size}','valid':True,'sha256':'b'*64}
                           for coord in coords for size in sizes]}
        return result,sizes,coordinates
    def test_frozen_cache_complete_coverage(self):
        result,sizes,coordinates=self.cache_fixture()
        self.assertEqual(len(check_cache_report(result,250821,sizes,coordinates)),15)
        self.assertEqual(authored_catalog(Path(__file__).resolve().parents[2]),coordinates)
    def test_process_bound_validator_adapter_preserves_original(self):
        original = self.root / 'original.gd'
        content = 'before\n\tvar arguments := OS.get_cmdline_args()\nafter\n'
        original.write_text(content)
        adapted = stage_process_bound_validator(original, self.root)
        self.assertEqual(original.read_text(), content)
        self.assertIn('/proc/self/cmdline', adapted.read_text())
        self.assertIn('if value == "--": break', adapted.read_text())
        self.assertTrue(adapted.read_text().startswith('before\n'))
        self.assertTrue(adapted.read_text().endswith('after\n'))
        with self.assertRaisesRegex(AuditError, 'replace existing'):
            stage_process_bound_validator(original, self.root)
    def test_process_bound_validator_adapter_fails_closed(self):
        original = self.root / 'original.gd'; original.write_text('unknown validator')
        with self.assertRaisesRegex(AuditError, 'no longer matches'):
            stage_process_bound_validator(original, self.root)
    def test_android_archive_has_distinct_safe_rebuilder(self):
        source = self.root / 'Android-Test.zip'; source.write_bytes(b'fixture archive bytes' * 20000)
        out = self.root / 'android-transport'
        result = make_parts(source, out, 'Android-Test', artifact_kind='android-archive')
        self.assertEqual(result['rebuild_script'], 'Rebuild-Android-Package')
        self.assertEqual(result['input']['artifact_kind'], 'android-archive')
        readme = (out / 'rebuild-files/Android-Test-RESTORE.txt').read_text(encoding='utf-8-sig')
        self.assertIn('complete ANDROID ZIP', readme)
        self.assertNotIn('Launch-PoolCore.cmd', readme)
    def test_binary_parts_kind_extension_mismatch_rejected(self):
        source = self.root / 'Android-Test.apk'; source.write_bytes(b'apk fixture')
        with self.assertRaisesRegex(AuditError, 'kind differs'):
            make_parts(source, self.root / 'wrong-kind', 'Wrong-Kind', artifact_kind='pc-archive')
    def test_frozen_cache_incomplete_and_duplicate_rejected(self):
        good,sizes,coordinates=self.cache_fixture()
        for entries in [good['terrain'][:-1],good['terrain'][:-1]+[good['terrain'][0]]]:
            result=copy.deepcopy(good);result['terrain']=entries
            with self.assertRaisesRegex(AuditError,'Incomplete or duplicate'):
                check_cache_report(result,250821,sizes,coordinates)
    def test_frozen_cache_publication_order_rejected(self):
        result,sizes,coordinates=self.cache_fixture()
        result['publication_order']=list(reversed(result['publication_order']))
        with self.assertRaisesRegex(AuditError,'publication order'):
            check_cache_report(result,250821,sizes,coordinates)
    def test_apk_public_signer_identity_gate(self):
        fingerprint = 'b3' * 32
        report = ('Verified using v2 scheme (APK Signature Scheme v2): true\n'
                  'Verified using v3 scheme (APK Signature Scheme v3): true\n'
                  'Number of signers: 1\nSigner #1 certificate SHA-256 digest: ' + fingerprint + '\n')
        self.assertEqual(verify_apk_signer_report(report, fingerprint.upper()), fingerprint)
        with self.assertRaisesRegex(AuditError, 'differs from the approved baseline'):
            verify_apk_signer_report(report, 'c4' * 32)
        with self.assertRaisesRegex(AuditError, 'exactly one'):
            verify_apk_signer_report(report.replace('Number of signers: 1', 'Number of signers: 2'))
        with self.assertRaisesRegex(AuditError, 'v2/v3'):
            verify_apk_signer_report(report.replace('v3): true', 'v3): false'))
        with self.assertRaisesRegex(AuditError, '64-character'):
            verify_apk_signer_report(report, 'not-a-fingerprint')

    def test_incremental_restore_preserves_base_and_rejects_tampering(self):
        base=self.root/'base';current=self.root/'current';base.mkdir();current.mkdir()
        for root,files in [(base,{'same':'stable','change':'old','deleted':'old'}),
                           (current,{'same':'stable','change':'new','added':'new'})]:
            for name,value in files.items():(root/name).write_text(value)
            manifest(root,'fixture',{})
        archives=self.root/'archives.json';uploads=self.root/'uploads.json'
        archives.write_text(json.dumps({'snapshot_utc':'2026-10-21T22:38:38Z',
            'project_folder':'base','archives':[{'filename':'base.zip','sha256':'fixture'}]}))
        uploads.write_text(json.dumps({'results':[{'file_name':'base.zip','library_file_id':'libfile_fixture','status':'succeeded'}]}))
        out=self.root/'delta'
        report=make_incremental(base,current,archives,uploads,out,'Delta-Fixture','2026-10-21T23:59:49Z')
        self.assertIn('deleted',report['deleted_paths'])
        script=out/'delta-staging/Restore-Recovery.py';restored=self.root/'中文 restored !'
        run=subprocess.run([sys.executable,'-B',str(script),'--base',str(base),'--output',str(restored)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr);verify_manifest(restored)
        self.assertTrue((base/'deleted').exists());self.assertFalse((restored/'deleted').exists())
        (out/'delta-staging/PAYLOAD/change').write_text('tamper')
        bad=self.root/'bad'
        run=subprocess.run([sys.executable,'-B',str(script),'--base',str(base),'--output',str(bad)],capture_output=True,text=True)
        self.assertNotEqual(run.returncode,0);self.assertFalse(bad.exists())

    def test_cli_helpers_do_not_write_into_immutable_tree(self):
        import shutil
        fixture = self.root / 'immutable-tools'
        fixture.mkdir()
        for path in Path(__file__).parent.glob('*.py'):
            shutil.copy2(path, fixture / path.name)
        for name in ('stage_release.py', 'preflight_release.py', 'verify_checkpoint_identity.py',
                     'validate_frozen_release.py', 'make_checkpoint_archives.py', 'make_binary_parts.py', 'freeze_build_inputs.py', 'acquire_windows_templates.py', 'make_incremental_recovery.py', 'make_lab_archives.py'):
            result = subprocess.run([sys.executable, str(fixture / name), '--help'],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(list(fixture.rglob('__pycache__')))

    def test_incremental_unchanged_terrain_is_bound_to_base(self):
        base=self.root/'base'; current=self.root/'current'
        for root,changed in ((base,b'old'),(current,b'new')):
            cache=root/'assets/cache/source_terrain'; cache.mkdir(parents=True)
            (cache/'same.terrain').write_bytes(b'byte-identical terrain')
            (cache/'changed.terrain').write_bytes(changed)
            manifest(root,'fixture',{})
        archives=self.root/'archives.json'; uploads=self.root/'uploads.json'
        archives.write_text(json.dumps({'snapshot_utc':'2026-10-22T00:43:51Z','project_folder':'base',
                                        'archives':[{'filename':'base.zip','sha256':'fixture'}]}))
        uploads.write_text(json.dumps({'results':[{'file_name':'base.zip','library_file_id':'libfile_fixture','status':'succeeded'}]}))
        out=self.root/'delta'
        make_incremental(base,current,archives,uploads,out,'Delta-Fixture','2026-10-22T01:18:00Z',reuse_unchanged_terrain=True)
        receipt=json.loads((out/'delta-staging/RECOVERY-DELTA.json').read_text())
        self.assertEqual([e['path'] for e in receipt['unchanged_terrain_reused_from_verified_base']],
                         ['assets/cache/source_terrain/same.terrain'])
        self.assertFalse(receipt['all_current_terrain_payloads_included'])
        self.assertTrue((out/'delta-staging/PAYLOAD/assets/cache/source_terrain/changed.terrain').is_file())
        restored=self.root/'restored'
        run=subprocess.run([sys.executable,'-B',str(out/'delta-staging/Restore-Recovery.py'),
                            '--base',str(base),'--output',str(restored)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr);verify_manifest(restored)

    def test_optional_lab_parts_restore_without_binary_reconstruction(self):
        import random, zipfile
        lab = self.root / 'lab'; lab.mkdir()
        data = random.Random(11)
        for name in ('a.exr', 'b.exr'):
            p = lab / 'assets/lighting/tiny_diagnostic' / name
            p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(data.randbytes(700_000))
        (lab / 'LAB-RESTORE.txt').write_text('Laboratory only, no graphical acceptance.')
        manifest(lab, 'lab', {'runtime_integrated': False}, prefix='LAB-')
        out = self.root / 'lab-parts'
        report = make_lab_parts(lab, out, 'Optional-Lab-Fixture', limit=1_000_000)
        self.assertEqual(len(report['archives']), 2)
        restored = self.root / '中文 restored lab !'
        for item in report['archives']:
            self.assertLess(item['bytes'], 1_000_000)
            with zipfile.ZipFile(out / item['filename']) as z: z.extractall(restored)
        verify_manifest(restored, prefix='LAB-')
        with self.assertRaisesRegex(AuditError, 'existing output'):
            make_lab_parts(lab, out, 'Optional-Lab-Fixture')

    def test_optional_lab_rejects_gameplay_and_rejected_bakes(self):
        for name in ('project.godot', 'assets/lighting/formal_mainhall/study_indirect.exr'):
            with self.subTest(name=name):
                lab = self.root / ('case' + str(len(list(self.root.iterdir())))); lab.mkdir()
                p = lab / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('x')
                manifest(lab, 'lab', {'runtime_integrated': False}, prefix='LAB-')
                with self.assertRaises(AuditError):
                    make_lab_parts(lab, self.root / 'invalid-out', 'Optional-Lab-Fixture')

    def test_unaccepted_production_bake_destinations_fail_closed(self):
        for name in ('assets/lighting_runtime/mainhall/indirect_00.exr',
                     'scenes/formal_baked/mainhall.tscn.remap',
                     'scripts/rendering/formal_baked_lighting.gd'):
            with self.subTest(name=name), self.assertRaisesRegex(AuditError, 'Unaccepted'):
                check_export_exclusions([name])
        self.assertFalse(check_bake_quarantine(self.root)['production_bake_accepted'])
        (self.root / 'assets/lighting_runtime').mkdir(parents=True)
        with self.assertRaisesRegex(AuditError, 'remain absent'):
            check_bake_quarantine(self.root)

    def test_frozen_cache_wrong_pack_rejected(self):
        result,sizes,coordinates=self.cache_fixture();result['main_pack']=str(self.root/'wrong.pck')
        with self.assertRaisesRegex(AuditError,'actual isolated PCK'):
            check_cache_report(result,250821,sizes,coordinates,self.root/'actual-release.pck')


if __name__ == '__main__':
    unittest.main(verbosity=2)
