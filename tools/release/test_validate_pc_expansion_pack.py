#!/usr/bin/env python3
"""Offline origin-isolation regressions; no freeze/export/GPU execution."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import validate_pc_expansion_pack as v

class PackValidationIsolation(unittest.TestCase):
    def host(self, root):
        p=root/v.release.PACK_NAME;p.write_bytes(b'fixture, not executable')
        m={'host_root':str(root),'pack_path':str(p),'pck_sha256':v.SHA(p),'source_inventory_sha256':'fixture','files':v.payload_rows(root)}
        (root/v.MANIFEST).write_text(json.dumps(m));return m
    def test_origin_adapter_preserves_original_body(self):
        source='extends SceneTree\nfunc _run()->void:\n\tprint("real native body")\n'
        adapted=v.adapt_native(source)
        self.assertTrue(adapted.endswith('\tprint("real native body")\n'))
        self.assertIn('report["pack_origin"]',adapted)
        self.assertNotIn('--qa',adapted)
        with self.assertRaises(v.AuditError):v.adapt_native('changed entrypoint')
    def test_host_rejects_active_runtime_fallback(self):
        for name in v.ABSENT_ROOTS:
            with tempfile.TemporaryDirectory() as td:
                root=Path(td);self.host(root);(root/name).mkdir()
                with self.assertRaises(v.AuditError):v.verify(root)
    def test_host_rejects_unlisted_or_changed_inputs(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);self.host(root);v.verify(root)
            (root/'unlisted.gd').write_text('fallback')
            with self.assertRaises(v.AuditError):v.verify(root)
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);self.host(root);(root/v.release.PACK_NAME).write_bytes(b'changed')
            with self.assertRaises(v.AuditError):v.verify(root)
    def test_symlink_even_in_state_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);self.host(root);(root/'state').mkdir();(root/'state/link').symlink_to(root/v.release.PACK_NAME)
            with self.assertRaises(v.AuditError):v.verify(root)
    def test_only_evidence_and_state_may_grow(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);self.host(root)
            for name in ('state/fresh/data','evidence/run.json'):
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('diagnostic')
            v.verify(root)
    def test_commands_bind_exact_pack_and_external_helpers(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);self.host(root)
            for kind in ('original','formal','expanded','observe','wet-pool'):
                m,cmd,env,state,prefix=v.configuration(root,sys.executable,kind,'unique')
                self.assertEqual(cmd[cmd.index('--path')+1],str(root))
                self.assertEqual(cmd[cmd.index('--main-pack')+1],str(root/v.release.PACK_NAME))
                self.assertTrue(cmd[cmd.index('--script')+1].startswith(str(root)))
                self.assertTrue(env['HOME'].startswith(str(root/'state')))
                self.assertNotIn('--pc-local-wet-finish',cmd)
                self.assertEqual('--headless' in cmd,kind in ('original','formal','expanded'))
            with self.assertRaises(v.AuditError):v.run(root,sys.executable,'wet-pool','unique')
    def test_warm_cache_requires_terminal_matching_launch(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);state=root/'old-state';(state/'cache').mkdir(parents=True)
            (state/'cache/shader.cache').write_bytes(b'compiled-cache')
            memory=root/'prior-memory.json';launch=root/'prior-launch.json'
            cmd=['godot','res://tests/pc_expanded_native.gd']
            terminal={'finished':True,'returncode':0,'command':cmd}
            memory.write_text(json.dumps(terminal));launch.write_text(json.dumps({'state':str(state),'environment':{'XDG_CACHE_HOME':str(state/'cache')},'command':cmd}))
            proof=v.warm_cache_proof(state,memory)
            self.assertFalse(proof['preferences_copied']);self.assertEqual(len(proof['files']),1)
            terminal['finished']=False;memory.write_text(json.dumps(terminal))
            with self.assertRaises(v.AuditError):v.warm_cache_proof(state,memory)
    def test_missing_freeze_fails_before_copy(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            with self.assertRaises((v.AuditError,OSError)):v.prepare(root,root/'missing.pck',root/'must-not-exist')
            self.assertFalse((root/'must-not-exist').exists())

if __name__=='__main__':unittest.main(verbosity=2)
