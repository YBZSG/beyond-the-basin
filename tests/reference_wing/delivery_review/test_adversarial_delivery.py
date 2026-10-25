"""Independent SOURCE installer review. Synthetic temp trees only, no Godot/Git/network.

Run from the repository root:
    PYTHONDONTWRITEBYTECODE=1 python -m unittest discover \
        -s tests/reference_wing/delivery_review -p 'test_*.py' -v
"""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools/reference_wing_delivery/update_source.py"
SPEC = importlib.util.spec_from_file_location("independent_source_update", SCRIPT)
u = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(u)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def snapshot(root):
    return {p.relative_to(root).as_posix(): (p.read_bytes(), p.stat().st_mode & 0o777)
            for p in root.rglob("*") if p.is_file() and not p.is_symlink()}


class AdversarialDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="delivery review 测试 ")
        self.root = Path(self.temp.name)
        self.project = self.root / "原项目 & (100%) !"
        self.package = self.root / "更新包 & (100%) !"
        self.project.mkdir()
        self.package.mkdir()
        self.old = {"scripts/a.gd": b"old A\n", "scripts/b.gd": b"old B\n"}
        self.new = {"scripts/a.gd": b"new A\n", "scripts/b.gd": b"new B\n",
                    "assets/room/new file.bin": b"new asset\x00\x01",
                    "docs/安装.md": "测试文档\n".encode()}
        write(self.project / "project.godot", b"config_version=5\n")
        write(self.project / "unrelated/keep.txt", b"private unrelated user work")
        for path, data in self.old.items():
            write(self.project / path, data)
        for path, data in self.new.items():
            write(self.package / "payload" / path, data)
        self.manifest = {"format": u.FORMAT, "update_id": "independent-review",
                         "baseline_commit": u.BASELINE,
                         "anchors": [{"path": "project.godot",
                                      "sha256": u.file_hash(self.project / "project.godot")}],
                         "files": [{"path": p,
                                    "old_sha256": u.sha_bytes(self.old[p]) if p in self.old else None,
                                    "new_sha256": u.sha_bytes(b)} for p, b in self.new.items()]}
        self.save_manifest()
        self.baseline = snapshot(self.project)

    def tearDown(self):
        self.temp.cleanup()

    def save_manifest(self):
        (self.package / "manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def receipt(self):
        return self.project / u.STATE_DIR / self.manifest["update_id"] / "receipt.json"

    def source_snapshot(self):
        return {p: content for p, content in snapshot(self.project).items()
                if not p.startswith(u.STATE_DIR + "/")}

    def test_cli_metacharacters_are_literal_without_shell_interpolation(self):
        # This validates Python's argv route on this host, not cmd.exe behavior.
        for command, expected in (("check", "ready"), ("apply", "installed"),
                                  ("apply", "already_applied"), ("rollback", "rolled_back")):
            result = subprocess.run([sys.executable, str(SCRIPT), command, str(self.project),
                                     "--package", str(self.package)], capture_output=True,
                                    text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["result"], expected)
        self.assertEqual(self.source_snapshot(), self.baseline)

    def test_unused_payload_files_never_escape_the_allowlist(self):
        write(self.package / "payload/unlisted/extra.txt", b"never copy me")
        write(self.package / "payload/.env", b"synthetic fixture, not a secret")
        u.apply_update(self.project, self.package)
        self.assertFalse((self.project / "unlisted").exists())
        self.assertFalse((self.project / ".env").exists())
        u.rollback_update(self.project, self.manifest["update_id"])
        self.assertEqual(self.source_snapshot(), self.baseline)

    def test_non_directory_destination_ancestor_refused_before_writes(self):
        write(self.project / "assets", b"user file occupies directory name")
        before = snapshot(self.project)
        with self.assertRaisesRegex(u.UpdateError, "Non-directory ancestor"):
            u.apply_update(self.project, self.package)
        self.assertEqual(snapshot(self.project), before)

    def test_directory_in_place_of_new_file_refused_before_writes(self):
        (self.project / "assets/room/new file.bin").mkdir(parents=True)
        before = snapshot(self.project)
        with self.assertRaisesRegex(u.UpdateError, "ordinary file"):
            u.apply_update(self.project, self.package)
        self.assertEqual(snapshot(self.project), before)
        self.assertFalse((self.project / u.STATE_DIR).exists())

    def test_dangling_destination_symlink_is_not_treated_as_missing(self):
        (self.project / "assets/room").mkdir(parents=True)
        target = self.root / "missing outside file"
        link = self.project / "assets/room/new file.bin"
        link.symlink_to(target)
        with self.assertRaisesRegex(u.UpdateError, "Symlink/junction"):
            u.apply_update(self.project, self.package)
        self.assertTrue(link.is_symlink())
        self.assertFalse(target.exists())
        self.assertFalse((self.project / u.STATE_DIR).exists())

    def test_canonical_unicode_collisions_and_control_characters_refused(self):
        for first, second in (("docs/é.txt", "docs/é.txt"),
                              ("docs/STRAẞE.txt", "docs/strasse.txt")):
            with self.subTest(first=first):
                manifest = copy.deepcopy(self.manifest)
                for p in (first, second):
                    manifest["files"].append({"path": p, "old_sha256": None,
                                              "new_sha256": "a" * 64})
                with self.assertRaisesRegex(u.UpdateError, "colliding"):
                    u.validate_manifest(manifest)
        for path in ("a/\x00b", "a/\tb", "a/\rb", "a/\nb", "a/COM1.dat", "a/LPT9"):
            with self.subTest(path=path), self.assertRaises(u.UpdateError):
                u.validate_relative(path)

    def test_invalid_manifest_shapes_are_refusals_not_tracebacks(self):
        cases = [[], None, {}, {**self.manifest, "extra": True},
                 {**self.manifest, "files": None}, {**self.manifest, "anchors": []},
                 {**self.manifest, "update_id": "../elsewhere"},
                 {**self.manifest, "files": [None]}]
        for manifest in cases:
            with self.subTest(manifest=manifest), self.assertRaises(u.UpdateError):
                u.validate_manifest(manifest)

    def test_later_manual_reversion_still_refuses_complete_rollback(self):
        u.apply_update(self.project, self.package)
        write(self.project / "scripts/a.gd", self.old["scripts/a.gd"])
        before = snapshot(self.project)
        with self.assertRaisesRegex(u.UpdateError, "later edit/deletion"):
            u.rollback_update(self.project, self.manifest["update_id"])
        self.assertEqual(snapshot(self.project), before)

    def test_same_update_id_with_different_manifest_refuses_without_writes(self):
        u.apply_update(self.project, self.package)
        before = snapshot(self.project)
        path = "docs/additional.md"
        write(self.package / "payload" / path, b"extra")
        self.manifest["files"].append({"path": path, "old_sha256": None,
                                       "new_sha256": u.sha_bytes(b"extra")})
        self.save_manifest()
        with self.assertRaisesRegex(u.UpdateError, "different manifest"):
            u.apply_update(self.project, self.package)
        self.assertEqual(snapshot(self.project), before)

    def test_missing_old_backup_refuses_whole_rollback(self):
        u.apply_update(self.project, self.package)
        (self.receipt().parent / "originals/scripts/a.gd").unlink()
        before = snapshot(self.project)
        with self.assertRaisesRegex(u.UpdateError, "Backup missing"):
            u.rollback_update(self.project, self.manifest["update_id"])
        self.assertEqual(snapshot(self.project), before)

    def test_anchor_edit_after_install_is_preserved_and_blocks_rollback(self):
        u.apply_update(self.project, self.package)
        write(self.project / "project.godot", b"later user project settings")
        before = snapshot(self.project)
        with self.assertRaisesRegex(u.UpdateError, "Baseline anchor mismatch"):
            u.rollback_update(self.project, self.manifest["update_id"])
        self.assertEqual(snapshot(self.project), before)

    def test_invalid_receipt_created_directories_cannot_delete_unrelated_files(self):
        u.apply_update(self.project, self.package)
        receipt = u.read_json(self.receipt())
        receipt["created_directories"].append("unrelated")
        self.receipt().write_text(json.dumps(receipt), encoding="utf-8")
        before = snapshot(self.project)
        with self.assertRaisesRegex(u.UpdateError, "Unrelated directory"):
            u.rollback_update(self.project, self.manifest["update_id"])
        self.assertEqual(snapshot(self.project), before)

    def test_apply_failure_at_every_file_boundary_restores_original_bytes(self):
        for failed_path in self.new:
            with self.subTest(failed_path=failed_path):
                real = u.atomic_write
                fired = False
                def fail_once(path, **kwargs):
                    nonlocal fired
                    if Path(path) == self.project / failed_path and not fired:
                        fired = True
                        raise OSError("independent injected write failure")
                    return real(path, **kwargs)
                with patch.object(u, "atomic_write", side_effect=fail_once):
                    with self.assertRaisesRegex(u.UpdateError, "original source files were restored"):
                        u.apply_update(self.project, self.package)
                self.assertEqual(self.source_snapshot(), self.baseline)
                self.assertEqual(u.load_receipt(self.receipt())["status"], "rolled_back")

    def test_killed_process_after_each_payload_replacement_is_recoverable(self):
        code = '''
import importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location("u", sys.argv[1])
u = importlib.util.module_from_spec(spec); spec.loader.exec_module(u)
root, package, target = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), sys.argv[4]
original = u.atomic_write
def crash_after(path, **kwargs):
    original(path, **kwargs)
    if pathlib.Path(path) == root / target:
        os._exit(91)
u.atomic_write = crash_after
u.apply_update(root, package)
'''
        for path in self.new:
            with self.subTest(path=path):
                process = subprocess.run([sys.executable, "-c", code, str(SCRIPT),
                                          str(self.project), str(self.package), path])
                self.assertEqual(process.returncode, 91)
                self.assertEqual(u.load_receipt(self.receipt())["status"], "applying")
                self.assertEqual(u.rollback_update(self.project, self.manifest["update_id"])["result"],
                                 "rolled_back")
                self.assertEqual(self.source_snapshot(), self.baseline)

    def test_rollback_preserves_unrelated_post_install_user_files_and_empty_dirs(self):
        u.apply_update(self.project, self.package)
        write(self.project / "assets/room/user-added.txt", b"later addition")
        (self.project / "assets/room/user-empty-dir").mkdir()
        u.rollback_update(self.project, self.manifest["update_id"])
        self.assertEqual((self.project / "assets/room/user-added.txt").read_bytes(), b"later addition")
        self.assertTrue((self.project / "assets/room/user-empty-dir").is_dir())
        self.assertFalse((self.project / "assets/room/new file.bin").exists())

    def test_final_exercise_harness_uses_only_a_disposable_copy(self):
        spec = importlib.util.spec_from_file_location("final_review", Path(__file__).with_name("verify_final_package.py"))
        reviewer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reviewer)
        shutil.copyfile(SCRIPT, self.package / "update_source.py")
        before = reviewer.tree(self.project, mtimes=True)
        result = reviewer.exercise(self.package, self.project, self.root / "disposable copy", self.manifest)
        self.assertEqual(result["apply"], "installed")
        self.assertEqual(result["rollback"], "rolled_back")
        self.assertTrue(result["later_edit_preserved"])
        self.assertEqual(reviewer.tree(self.project, mtimes=True), before)

    def test_ui_runner_creates_all_three_isolated_inputs_without_engine_execution(self):
        script = ROOT / "tests/reference_wing/ui_run_contract.py"
        spec = importlib.util.spec_from_file_location("isolated_ui_runner_review", script)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        calls = []
        def inspect_without_engine(arguments, **kwargs):
            fixture = Path(arguments[arguments.index("--path") + 1])
            host = fixture / "tests/reference_wing/ui_host.gd"
            desktop = fixture / "tests/reference_wing/ui_desktop_settings.gd"
            sources = fixture / "tests/reference_wing/ui_sources.json"
            self.assertIn("func _load_settings", host.read_text())
            self.assertIn("func save_settings", desktop.read_text())
            self.assertIsInstance(json.loads(sources.read_text()), dict)
            calls.append(str(fixture))
            return SimpleNamespace(returncode=0, stdout='REFERENCE_UI_CONTRACT {"passed":true}\n')
        with patch.object(runner.subprocess, "run", side_effect=inspect_without_engine), \
                patch.object(sys, "argv", [str(script)]), redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(), 0)
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0], calls[1])
        self.assertFalse(Path(calls[0]).exists())

    def test_generated_fixture_exclusion_is_exact_and_never_applies_to_production(self):
        spec = importlib.util.spec_from_file_location("fixture_review", Path(__file__).with_name("verify_final_package.py"))
        reviewer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reviewer)
        generator = reviewer.UI_FIXTURE_GENERATOR
        write(self.package / "payload" / generator, (ROOT / generator).read_bytes())
        for target in reviewer.UI_GENERATED_INPUTS:
            self.assertIsNotNone(reviewer.generated_fixture_reference(reviewer.UI_FIXTURE_CONSUMER, target, self.package, {generator}))
            self.assertIsNone(reviewer.generated_fixture_reference("scripts/main.gd", target, self.package, {generator}))
        self.assertIsNone(reviewer.generated_fixture_reference(reviewer.UI_FIXTURE_CONSUMER,
                          "tests/reference_wing/other_missing.gd", self.package, {generator}))
        with self.assertRaises(reviewer.u.UpdateError):
            reviewer.generated_fixture_reference(reviewer.UI_FIXTURE_CONSUMER,
                "tests/reference_wing/ui_host.gd", self.package, set())
        write(self.package / "payload" / generator, b"# runner no longer generates these files\n")
        with self.assertRaises(reviewer.u.UpdateError):
            reviewer.generated_fixture_reference(reviewer.UI_FIXTURE_CONSUMER,
                "tests/reference_wing/ui_host.gd", self.package, {generator})


if __name__ == "__main__":
    unittest.main()
