#!/usr/bin/env python3
"""Offline release-policy regressions; never freezes/exports the actual project."""
import hashlib
import json
from pathlib import Path
import random
import tempfile
import unittest
from unittest import mock
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pc_expansion_release as p


class ExpansionReleasePolicy(unittest.TestCase):
    def test_preview_is_exact_not_directory_wide(self):
        for name in p.PREVIEW_PINS:
            self.assertTrue(p.runtime_allowed(name,{}),name)
        for name in ('assets/lighting/runtime_mainhall_candidate/unreviewed.exr',
                     'assets/lighting/runtime_mainhall_candidate/new.lmbake',
                     'assets/lighting/final_mainhall/native_indirect.lmbake',
                     'scenes/lighting_lab/final_mainhall_native.tscn',
                     'scenes/lighting_lab/new.tscn','docs/secret.json',
                     'tests/sample.gd','assets/cache/source_terrain/obsolete.terrain'):
            self.assertFalse(p.runtime_allowed(name,{}),name)
        self.assertTrue(p.runtime_allowed(p.PREVIEW_SCENE+'.remap',{}))

    def test_source_dependency_groups(self):
        names=list(p.PREVIEW_PINS)+list(p.EXTRA_REQUIRED)
        names += ['assets/models/expansion/'+n+'.glb' for n in p.ROOMS+p.PROPS]
        names += ['tools/blender/expansion/source/'+n+'.blend' for n in p.ROOMS+p.PROPS]
        names += ['native/source_water/source_water.c','native/source_water/vendor/gdextension_interface.h',
                  'assets/models/avatar/pool_explorer_explorer_shirt_weave.png',
                  'shaders/source_water/swe_height.glsl','scripts/main.gd']
        for name in names:self.assertEqual(p.classify(name,{})[0],'core',name)

    def test_caches_credentials_diagnostics_excluded(self):
        for name in ('.godot/imported/a.scn','.git/config','.aws/credentials','tools/.env.local',
                     'tools/export_credentials.cfg','assets/key.pem','assets/sign.jks',
                     'native/source_water/build/a.o','tools/blender/avatar/qa_project/project.godot',
                     'tools/blender/avatar/delivery/checkpoint.zip','docs/verification/run.log',
                     'docs/verification/raw-frame-rgba16f.bin',
                     'tests/fixtures/lab/cpu_state/cache/fontconfig/font.cache',
                     'assets/lighting/formal_mainhall/study_indirect.exr',
                     'assets/lighting/formal_mainhall/study_indirect.exr.import',
                     'assets/lighting/final_mainhall/native_indirect.lmbake',
                     'tools/blender/source/formal_mainhall.blend1'):
            self.assertEqual(p.classify(name,{})[0],'exclude',name)

    def test_optional_qa_not_relabelled_as_acceptance(self):
        for name in ('docs/verification/pc-refine/result.json',
                     'tools/blender/avatar/previews/explorer_preview_rest.png',
                     'scenes/lighting_lab/final_mainhall_native.tscn'):
            self.assertEqual(p.classify(name,{})[0],'optional',name)

    def test_launcher_name_and_no_restricted_switches(self):
        for preview in (False,True):
            raw=p.expansion_launcher(preview)
            self.assertIn(p.PACK_NAME.encode(),raw)
            self.assertNotIn(p.previous.PACK_NAME.encode(),raw)
            self.assertIn(p.PACK_NAME[:-4].encode()+b'.exe',raw)
            self.assertEqual(p.previous.audit_launcher(raw,preview)['static_contract'],'PASS')

    def test_glb_header_and_truncated_json_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/'invalid.glb';f.write_bytes(b'not a glb')
            with self.assertRaises(p.AuditError):p.glb_json(f)

    def test_regular_input_rejects_traversal_and_symlink(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);(root/'file').write_text('x');(root/'link').symlink_to(root/'file')
            for name in ('../escape','link'):
                with self.assertRaises(p.AuditError):p.regular(root,name)

    def test_existing_report_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/'report.json';f.write_text('existing')
            with self.assertRaises(p.AuditError):p.write_json(f,{'changed':True})
            self.assertEqual(f.read_text(),'existing')

    def test_copy_detects_changed_input(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'in';root.mkdir();out=Path(td)/'out';out.mkdir()
            (root/'file').write_text('new')
            with self.assertRaises(p.AuditError):p.copy_rows(root,out,[{'path':'file','bytes':3,'sha256':hashlib.sha256(b'old').hexdigest()}])
            self.assertFalse((out/'file').exists())

    def test_changed_inventory_refused(self):
        with mock.patch.object(p,'inventory',return_value={'included_identity_sha256':'new'}):
            with self.assertRaises(p.AuditError):p.check_inventory(Path('.'),{'content_secret_scan':True,'included_identity_sha256':'old'})

    def test_windows_credential_policy_refused(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);(root/'export_presets.cfg').write_text('[preset.0.options]\nkeystore/password="secret"\n')
            with self.assertRaises(p.AuditError):p.export_policy(root,{},set())

    def test_accepted_preview_tamper_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);(root/'preview.exr').write_bytes(b'changed')
            pins={'preview.exr':hashlib.sha256(b'accepted').hexdigest()}
            with mock.patch.object(p.previous,'current_cache',return_value={}), mock.patch.object(p,'PREVIEW_PINS',pins):
                with self.assertRaisesRegex(p.AuditError,'Accepted preview source hash changed'):
                    p.preflight(root,False)

    def test_secret_content_pattern_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/'apparently-safe.txt';f.write_text('gh'+'p_'+'a'*36)
            with self.assertRaisesRegex(p.AuditError,'Potential github-token'):
                p.previous.scanned(f)

    def test_transport_shipped_reconstruction(self):
        # Actual shipped reconstruction script runs on small deterministic data.
        with tempfile.TemporaryDirectory(prefix='expansion release tests ') as td:
            root=Path(td);stage=root/'stage';stage.mkdir()
            (stage/'sample.bin').write_bytes(random.Random(1227).randbytes(700_000))
            canonical=root/'PoolCore-Expansion-Selftest.zip'
            p.previous.archive_tree(stage,canonical)
            result=p.previous.transport(canonical,root/'parts','PoolCore-Expansion-Selftest','source',256_000)
            self.assertTrue(result['python_roundtrip_unicode_spaces_bang_path'])
            self.assertTrue(result['tampered_chunk_rejected'])
            self.assertTrue(result['different_existing_output_preserved'])
            self.assertFalse(result['windows_cmd_powershell_executed'])
            self.assertGreater(len(result['archives']),1)
            self.assertTrue(all(r['bytes']<16_000_000 for r in result['archives']))


if __name__=='__main__':unittest.main(verbosity=2)
