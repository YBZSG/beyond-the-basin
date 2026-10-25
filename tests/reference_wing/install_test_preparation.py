"""Preparation helper uses mocked Git objects, never the changing production assets."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[2] / "tools/reference_wing_delivery"
sys.path.insert(0, str(TOOLS))
import update_source
import prepare_source_update


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="source prepare 测试 ")
        self.base = Path(self.tmp.name)
        self.project = self.base / "mock project"
        self.project.mkdir()
        (self.project / "project.godot").write_bytes(b"baseline project")
        (self.project / "scripts").mkdir()
        (self.project / "scripts/main.gd").write_bytes(b"new main")
        (self.project / "assets").mkdir()
        (self.project / "assets/new.bin").write_bytes(b"new asset")
        (self.project / "docs/reference_wing").mkdir(parents=True)
        (self.project / "docs/reference_wing/INSTALL-源码更新.md").write_bytes(b"mock source update instructions")
        self.allowlist = self.base / "allowlist.txt"
        self.allowlist.write_text("scripts/main.gd\nassets/new.bin\n", encoding="utf-8")
        self.output = self.base / "package output"
        self.git_patch = patch.object(prepare_source_update, "git", side_effect=self.fake_git)
        self.git_patch.start()

    def tearDown(self):
        self.git_patch.stop()
        self.tmp.cleanup()

    @staticmethod
    def fake_git(root, *args, check=True):
        spec = args[-1]
        content = None
        if spec.endswith(":project.godot"):
            content = b"baseline project"
        elif spec.endswith(":scripts/main.gd"):
            content = b"original main"
        elif spec.endswith("^{commit}"):
            content = b""
        if content is None and check:
            raise update_source.UpdateError("mock Git object missing")
        return SimpleNamespace(returncode=0 if content is not None else 128,
                               stdout=content or b"", stderr=b"")

    def test_explicit_allowlist_builds_one_cumulative_manifest(self):
        result = prepare_source_update.prepare(self.project, self.allowlist, self.output, "synthetic-prep")
        self.assertFalse(result["archived"])
        self.assertFalse(result["uploaded"])
        _, manifest = update_source.load_package(self.output)
        self.assertEqual(manifest["baseline_commit"], update_source.BASELINE)
        self.assertEqual([item["path"] for item in manifest["files"]], ["scripts/main.gd", "assets/new.bin"])
        self.assertEqual(manifest["files"][0]["old_sha256"], update_source.sha_bytes(b"original main"))
        self.assertIsNone(manifest["files"][1]["old_sha256"])
        self.assertTrue((self.output / "README-SOURCE-UPDATE.md").is_file())
        self.assertTrue((self.output / "APPLY_SOURCE_UPDATE.cmd").is_file())

    def test_output_directory_cannot_be_overwritten(self):
        self.output.mkdir()
        with self.assertRaisesRegex(update_source.UpdateError, "will not overwrite"):
            prepare_source_update.prepare(self.project, self.allowlist, self.output, "synthetic-prep")
        self.assertEqual(list(self.output.iterdir()), [])

    def test_no_recursive_directories_or_excluded_cache(self):
        for line in ("assets\n", "assets/*\n", ".godot/imported/cache.bin\n", "output/old.zip\n"):
            self.allowlist.write_text(line, encoding="utf-8")
            with self.assertRaises(update_source.UpdateError):
                prepare_source_update.prepare(self.project, self.allowlist, self.output, "synthetic-prep")
            self.assertFalse(self.output.exists())

    def test_changing_source_during_stage_is_detected(self):
        real_write = update_source.atomic_write

        def change_before_copy(path, **kwargs):
            if Path(path).name == "main.gd":
                (self.project / "scripts/main.gd").write_bytes(b"changed mid-build")
            return real_write(path, **kwargs)

        with patch.object(update_source, "atomic_write", side_effect=change_before_copy):
            with self.assertRaisesRegex(update_source.UpdateError, "Source changed during copy"):
                prepare_source_update.prepare(self.project, self.allowlist, self.output, "synthetic-prep")
        self.assertFalse((self.output / "manifest.json").exists())

    def test_no_op_source_entry_is_refused(self):
        (self.project / "scripts/main.gd").write_bytes(b"original main")
        with self.assertRaisesRegex(update_source.UpdateError, "unchanged baseline file"):
            prepare_source_update.prepare(self.project, self.allowlist, self.output, "synthetic-prep")
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
