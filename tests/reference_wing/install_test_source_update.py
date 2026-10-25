"""Independent synthetic fixtures. Never updates the production project.

Run: python -m unittest discover -s tests/reference_wing -p 'install_test*.py' -v
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "tools/reference_wing_delivery/update_source.py"
SPEC = importlib.util.spec_from_file_location("source_update_under_test", SCRIPT)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class SourceUpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="source update 测试 ")
        self.base = Path(self.tmp.name)
        self.project = self.base / "原项目 有空格"
        self.package = self.base / "更新 包"
        self.project.mkdir()
        self.package.mkdir()
        self.update_id = "synthetic-install-test"
        self.project_bytes = b"config_version=5\n; synthetic fixture only\n"
        (self.project / "project.godot").write_bytes(self.project_bytes)
        self.originals = {
            "scripts/main.gd": b"extends Node\n# BASELINE main\n",
            "scripts/app/world_restart.gd": b"extends Node\n# BASELINE restart\n",
            "scripts/rendering/rt_material_refresh.gd": b"extends Node\n# BASELINE refresh\n",
        }
        self.new_files = {
            "scripts/main.gd": b"extends Node\n# UPDATED main\n",
            "scripts/app/world_restart.gd": b"extends Node\n# UPDATED restart\n",
            "scripts/rendering/rt_material_refresh.gd": b"extends Node\n# UPDATED refresh\n",
            "assets/models/reference_wing/房间 mock.glb": b"fake glb fixture - not a real asset",
            "docs/reference_wing/模拟说明.md": "只用于安装器测试。\n".encode("utf-8"),
        }
        for relative, content in self.originals.items():
            self.write(self.project / relative, content)
        for relative, content in self.new_files.items():
            self.write(self.package / "payload" / relative, content)
        self.write(self.project / "unrelated/user.txt", b"unrelated private work")
        self.manifest = {
            "format": updater.FORMAT,
            "update_id": self.update_id,
            "baseline_commit": updater.BASELINE,
            "anchors": [{"path": "project.godot", "sha256": updater.sha_bytes(self.project_bytes)}],
            "files": [{"path": relative,
                       "old_sha256": updater.sha_bytes(self.originals[relative]) if relative in self.originals else None,
                       "new_sha256": updater.sha_bytes(content)}
                      for relative, content in self.new_files.items()],
        }
        self.save_manifest()

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def write(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def save_manifest(self):
        (self.package / "manifest.json").write_text(json.dumps(self.manifest, ensure_ascii=False), encoding="utf-8")

    def receipt_path(self):
        return self.project / updater.STATE_DIR / self.update_id / "receipt.json"

    def assert_originals(self):
        for relative, content in self.originals.items():
            self.assertEqual((self.project / relative).read_bytes(), content)
        for relative in self.new_files.keys() - self.originals.keys():
            self.assertFalse((self.project / relative).exists(), relative)
        self.assertEqual((self.project / "unrelated/user.txt").read_bytes(), b"unrelated private work")

    def assert_installed(self):
        for relative, content in self.new_files.items():
            self.assertEqual((self.project / relative).read_bytes(), content)

    def cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                              capture_output=True, encoding="utf-8")

    def test_clean_apply_and_rollback_unicode_spaces(self):
        result = updater.apply_update(self.project, self.package)
        self.assertEqual(result["result"], "installed")
        self.assert_installed()
        receipt = updater.load_receipt(self.receipt_path())
        self.assertEqual(receipt["status"], "installed")
        for relative, content in self.originals.items():
            self.assertEqual((self.receipt_path().parent / "originals" / relative).read_bytes(), content)
        result = updater.rollback_update(self.project, self.update_id)
        self.assertEqual(result["result"], "rolled_back")
        self.assert_originals()
        self.assertTrue(self.receipt_path().is_file())

    def test_already_applied_is_noop(self):
        updater.apply_update(self.project, self.package)
        before = {p: (p.stat().st_mtime_ns, p.read_bytes()) for p in self.project.rglob("*") if p.is_file()}
        self.assertEqual(updater.apply_update(self.project, self.package)["result"], "already_applied")
        after = {p: (p.stat().st_mtime_ns, p.read_bytes()) for p in self.project.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_already_applied_without_receipt_does_not_invent_backup(self):
        for relative, content in self.new_files.items():
            self.write(self.project / relative, content)
        result = updater.apply_update(self.project, self.package)
        self.assertEqual(result["result"], "already_applied")
        self.assertIsNone(result["receipt"])
        self.assertFalse((self.project / updater.STATE_DIR).exists())

    def test_modified_main_refused_before_any_write(self):
        self.write(self.project / "scripts/main.gd", b"USER EDIT")
        with self.assertRaisesRegex(updater.UpdateError, "Modified/non-baseline"):
            updater.apply_update(self.project, self.package)
        self.assertEqual((self.project / "scripts/main.gd").read_bytes(), b"USER EDIT")
        self.assertFalse((self.project / updater.STATE_DIR).exists())

    def test_late_bad_payload_refused_before_any_write(self):
        self.write(self.package / "payload/docs/reference_wing/模拟说明.md", b"CORRUPTED")
        with self.assertRaisesRegex(updater.UpdateError, "Payload missing or SHA256 mismatch"):
            updater.apply_update(self.project, self.package)
        self.assert_originals()
        self.assertFalse((self.project / updater.STATE_DIR).exists())

    def test_missing_payload_refused(self):
        (self.package / "payload/scripts/main.gd").unlink()
        with self.assertRaisesRegex(updater.UpdateError, "Payload missing"):
            updater.apply_update(self.project, self.package)
        self.assert_originals()

    def test_new_path_conflict_even_when_some_new_bytes_match(self):
        relative = "assets/models/reference_wing/房间 mock.glb"
        self.write(self.project / relative, self.new_files[relative])
        with self.assertRaisesRegex(updater.UpdateError, "New path already exists"):
            updater.apply_update(self.project, self.package)
        self.assertFalse((self.project / updater.STATE_DIR).exists())

    def test_requires_project_root_and_baseline_anchor(self):
        with self.assertRaisesRegex(updater.UpdateError, "project root"):
            updater.apply_update(self.project / "scripts", self.package)
        (self.project / "project.godot").write_bytes(b"different project")
        with self.assertRaisesRegex(updater.UpdateError, "Baseline anchor mismatch"):
            updater.apply_update(self.project, self.package)
        self.assertFalse((self.project / updater.STATE_DIR).exists())

    def test_path_traversal_absolute_windows_and_excluded_paths(self):
        for path in ["../escape.txt", "/tmp/escape", "a/../b", "a//b", "a/./b", "C:/escape",
                     "a\\b", "a:stream", "CON.txt", "a/NUL", "a/file. ", "a/.godot/cache",
                     "output/file", "references/photo.png", ".env", ".env.local", "secrets/key"]:
            with self.subTest(path=path):
                manifest = copy.deepcopy(self.manifest)
                manifest["files"][0]["path"] = path
                with self.assertRaises(updater.UpdateError):
                    updater.validate_manifest(manifest)

    def test_manifest_rejects_duplicates_case_aliases_and_prefix_collision(self):
        for relative in ["scripts/main.gd", "SCRIPTS/MAIN.GD", "scripts"]:
            manifest = copy.deepcopy(self.manifest)
            manifest["files"].append({"path": relative, "old_sha256": None,
                                      "new_sha256": "a" * 64})
            with self.assertRaises(updater.UpdateError):
                updater.validate_manifest(manifest)

    def test_duplicate_json_keys_rejected(self):
        (self.package / "manifest.json").write_text('{"format": 1, "format": 2}', encoding="utf-8")
        with self.assertRaisesRegex(updater.UpdateError, "Duplicate JSON key"):
            updater.apply_update(self.project, self.package)

    def test_payload_symlink_refused(self):
        payload = self.package / "payload/scripts/main.gd"
        outside = self.base / "outside"
        outside.write_bytes(self.new_files["scripts/main.gd"])
        payload.unlink()
        try:
            payload.symlink_to(outside)
        except (OSError, NotImplementedError):
            self.skipTest("Symlink creation not available")
        with self.assertRaisesRegex(updater.UpdateError, "Symlink/junction"):
            updater.apply_update(self.project, self.package)
        self.assert_originals()

    def test_destination_symlink_refused_without_touching_target(self):
        target = self.base / "outside main"
        target.write_bytes(self.originals["scripts/main.gd"])
        destination = self.project / "scripts/main.gd"
        destination.unlink()
        try:
            destination.symlink_to(target)
        except (OSError, NotImplementedError):
            self.skipTest("Symlink creation not available")
        with self.assertRaisesRegex(updater.UpdateError, "Symlink/junction"):
            updater.apply_update(self.project, self.package)
        self.assertEqual(target.read_bytes(), self.originals["scripts/main.gd"])
        self.assertFalse((self.project / updater.STATE_DIR).exists())

    def test_destination_ancestor_symlink_refused(self):
        outside = self.base / "outside assets"
        outside.mkdir()
        try:
            (self.project / "assets").symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("Symlink creation not available")
        with self.assertRaisesRegex(updater.UpdateError, "Symlink/junction"):
            updater.apply_update(self.project, self.package)
        self.assertEqual(list(outside.iterdir()), [])

    def test_backup_directory_symlink_refused(self):
        outside = self.base / "outside state"
        outside.mkdir()
        try:
            (self.project / updater.STATE_DIR).symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("Symlink creation not available")
        with self.assertRaisesRegex(updater.UpdateError, "Symlink/junction"):
            updater.apply_update(self.project, self.package)
        self.assert_originals()
        self.assertEqual(list(outside.iterdir()), [])

    def test_failed_second_write_automatically_rolls_back(self):
        real_write = updater.atomic_write
        failed = False

        def fail_once(path, **kwargs):
            nonlocal failed
            if Path(path) == self.project / "scripts/app/world_restart.gd" and not failed:
                failed = True
                raise OSError("synthetic disk write failure")
            return real_write(path, **kwargs)

        with patch.object(updater, "atomic_write", side_effect=fail_once):
            with self.assertRaisesRegex(updater.UpdateError, "original source files were restored"):
                updater.apply_update(self.project, self.package)
        self.assert_originals()
        self.assertEqual(updater.load_receipt(self.receipt_path())["status"], "rolled_back")

    def test_failed_apply_and_conflicting_edit_leave_explicit_recoverable_journal(self):
        real_write = updater.atomic_write

        def fail_and_edit(path, **kwargs):
            if Path(path) == self.project / "scripts/app/world_restart.gd":
                (self.project / "scripts/main.gd").write_bytes(b"USER EDIT DURING APPLY")
                raise OSError("synthetic failure plus user edit")
            return real_write(path, **kwargs)

        with patch.object(updater, "atomic_write", side_effect=fail_and_edit):
            with self.assertRaisesRegex(updater.UpdateError, "rollback could not complete"):
                updater.apply_update(self.project, self.package)
        self.assertEqual((self.project / "scripts/main.gd").read_bytes(), b"USER EDIT DURING APPLY")
        self.assertEqual(updater.load_receipt(self.receipt_path())["status"], "applying")
        # A deliberate resolution back to the known installed bytes enables recovery.
        (self.project / "scripts/main.gd").write_bytes(self.new_files["scripts/main.gd"])
        updater.rollback_update(self.project, self.update_id)
        self.assert_originals()

    def test_atomic_replace_failure_preserves_original_and_cleans_temp(self):
        target = self.project / "scripts/main.gd"
        with patch.object(updater.os, "replace", side_effect=OSError("synthetic replace failure")):
            with self.assertRaises(OSError):
                updater.atomic_write(target, data=b"NEW", expected_current=updater.file_hash(target))
        self.assertEqual(target.read_bytes(), self.originals["scripts/main.gd"])
        self.assertEqual(list(target.parent.glob(".poolcore-write-*")), [])

    def test_changed_destination_before_replace_is_preserved(self):
        target = self.project / "scripts/main.gd"
        old_hash = updater.file_hash(target)
        target.write_bytes(b"late edit")
        with self.assertRaisesRegex(updater.UpdateError, "Destination changed"):
            updater.atomic_write(target, data=b"NEW", expected_current=old_hash)
        self.assertEqual(target.read_bytes(), b"late edit")

    def test_real_process_exit_after_replace_recovers_from_durable_receipt(self):
        # os._exit simulates SIGKILL: no Python finally blocks or auto-rollback.
        code = r'''
import importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location("u", sys.argv[1])
u = importlib.util.module_from_spec(spec); spec.loader.exec_module(u)
root, package = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
real = u.atomic_write
def crash(path, **kwargs):
    real(path, **kwargs)
    if pathlib.Path(path) == root / "scripts/main.gd":
        os._exit(87)
u.atomic_write = crash
u.apply_update(root, package)
'''
        proc = subprocess.run([sys.executable, "-c", code, str(SCRIPT), str(self.project), str(self.package)])
        self.assertEqual(proc.returncode, 87)
        self.assertEqual(updater.load_receipt(self.receipt_path())["status"], "applying")
        with self.assertRaisesRegex(updater.UpdateError, "Interrupted update"):
            updater.apply_update(self.project, self.package)
        checked = self.cli("check", self.project, "--package", self.package)
        self.assertEqual(checked.returncode, 2)
        self.assertIn("Interrupted update", checked.stderr)
        result = updater.rollback_update(self.project, self.update_id)
        self.assertEqual(result["result"], "rolled_back")
        self.assert_originals()

    def test_rollback_failure_journal_can_resume(self):
        updater.apply_update(self.project, self.package)
        real_write = updater.atomic_write
        failed = False

        def fail_once(path, **kwargs):
            nonlocal failed
            if Path(path) == self.project / "scripts/app/world_restart.gd" and not failed:
                failed = True
                raise OSError("synthetic restore failure")
            return real_write(path, **kwargs)

        with patch.object(updater, "atomic_write", side_effect=fail_once):
            with self.assertRaisesRegex(OSError, "synthetic restore failure"):
                updater.rollback_update(self.project, self.update_id)
        self.assertEqual(updater.load_receipt(self.receipt_path())["status"], "rollback_failed")
        self.assertEqual(updater.rollback_update(self.project, self.update_id)["result"], "rolled_back")
        self.assert_originals()

    def test_later_user_edit_refuses_whole_rollback(self):
        updater.apply_update(self.project, self.package)
        target = self.project / "scripts/main.gd"
        target.write_bytes(b"USER'S LATER WORK")
        snapshot = {p: p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        with self.assertRaisesRegex(updater.UpdateError, "preserve a later edit"):
            updater.rollback_update(self.project, self.update_id)
        self.assertEqual(snapshot, {p: p.read_bytes() for p in self.project.rglob("*") if p.is_file()})

    def test_later_user_deletion_refuses_rollback(self):
        updater.apply_update(self.project, self.package)
        (self.project / "docs/reference_wing/模拟说明.md").unlink()
        with self.assertRaisesRegex(updater.UpdateError, "preserve a later edit/deletion"):
            updater.rollback_update(self.project, self.update_id)
        self.assertEqual((self.project / "scripts/main.gd").read_bytes(), self.new_files["scripts/main.gd"])

    def test_corrupt_backup_refuses_rollback_before_changes(self):
        updater.apply_update(self.project, self.package)
        backup = self.receipt_path().parent / "originals/scripts/main.gd"
        backup.write_bytes(b"corrupted backup")
        with self.assertRaisesRegex(updater.UpdateError, "Backup missing or SHA256 mismatch"):
            updater.rollback_update(self.project, self.update_id)
        self.assert_installed()

    def test_user_file_in_new_directory_survives_rollback(self):
        updater.apply_update(self.project, self.package)
        keep = self.project / "assets/models/reference_wing/user added.txt"
        keep.write_bytes(b"keep me")
        updater.rollback_update(self.project, self.update_id)
        self.assert_originals()
        self.assertEqual(keep.read_bytes(), b"keep me")

    def test_repeated_rollback_and_reapply(self):
        updater.apply_update(self.project, self.package)
        updater.rollback_update(self.project, self.update_id)
        self.assertEqual(updater.rollback_update(self.project, self.update_id)["result"], "already_rolled_back")
        updater.apply_update(self.project, self.package)
        self.assert_installed()
        updater.rollback_update(self.project, self.update_id)
        self.assert_originals()

    def test_receipt_manifest_tamper_is_refused(self):
        updater.apply_update(self.project, self.package)
        receipt = updater.read_json(self.receipt_path())
        receipt["manifest"]["files"][0]["new_sha256"] = "f" * 64
        self.receipt_path().write_text(json.dumps(receipt), encoding="utf-8")
        with self.assertRaisesRegex(updater.UpdateError, "integrity failure"):
            updater.rollback_update(self.project, self.update_id)
        self.assert_installed()

    def test_cli_check_apply_status_and_packageless_rollback(self):
        result = self.cli("check", self.project, "--package", self.package)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"], "ready")
        self.assertFalse((self.project / updater.STATE_DIR).exists())
        result = self.cli("apply", self.project, "--package", self.package)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.cli("status", self.project, "--update-id", self.update_id)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(x["matches_installed"] for x in json.loads(result.stdout)["files"]))
        result = self.cli("rollback", self.project, "--update-id", self.update_id)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_originals()

    def test_wrong_baseline_and_missing_project_anchor_are_refused(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["baseline_commit"] = "0" * 40
        with self.assertRaisesRegex(updater.UpdateError, "baseline"):
            updater.validate_manifest(manifest)
        manifest = copy.deepcopy(self.manifest)
        manifest["anchors"][0]["path"] = "other.txt"
        with self.assertRaisesRegex(updater.UpdateError, "project.godot"):
            updater.validate_manifest(manifest)

    def test_no_force_flag(self):
        result = self.cli("apply", self.project, "--package", self.package, "--force")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.project / updater.STATE_DIR).exists())

    def test_incomplete_backup_preparation_refuses_check_and_apply(self):
        self.receipt_path().parent.mkdir(parents=True)
        with self.assertRaisesRegex(updater.UpdateError, "no source writes started"):
            updater.apply_update(self.project, self.package)
        checked = self.cli("check", self.project, "--package", self.package)
        self.assertEqual(checked.returncode, 2)
        self.assertIn("no source writes started", checked.stderr)
        self.assert_originals()

    @unittest.skipIf(os.name == "nt", "POSIX file modes only")
    def test_original_file_mode_is_restored(self):
        target = self.project / "scripts/main.gd"
        target.chmod(0o640)
        updater.apply_update(self.project, self.package)
        updater.rollback_update(self.project, self.update_id)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    @unittest.skipIf(os.name == "nt", "POSIX flock process test; Windows uses msvcrt")
    def test_concurrent_installer_is_refused(self):
        state = self.project / updater.STATE_DIR
        state.mkdir()
        import fcntl
        with (state / "installer.lock").open("wb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.cli("apply", self.project, "--package", self.package)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Another installer owns", result.stderr)
        self.assert_originals()


if __name__ == "__main__":
    unittest.main()
