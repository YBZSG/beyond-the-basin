"""Compact wrapper safety tests. Tiny synthetic fixtures only; no production assets."""
import copy
import importlib.util
import io
import json
import lzma
import os
from pathlib import Path
import shutil
import subprocess
import struct
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / "tools/reference_wing_delivery"
sys.path.insert(0, str(TOOLS))
import compact_source_update as compact
import build_compact_source_update as builder
import update_source as core


def snapshot(root):
    return {p.relative_to(root).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns)
            for p in root.rglob("*") if p.is_file() and not p.is_symlink()}


class CompactDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="compact 测试 & ! ")
        self.root = Path(self.temp.name)
        self.project = self.root / "原项目 (100%)"
        self.package = self.root / "更新 包"
        self.project.mkdir()
        self.package.mkdir()
        (self.project / "project.godot").write_bytes(b"synthetic base project")
        (self.project / "main.gd").write_bytes(b"old main")
        json_chunk = json.dumps({"asset": {"version": "2.0"}}).encode()
        json_chunk += b" " * ((-len(json_chunk)) % 4)
        self.glb = struct.pack("<4sIIII", b"glTF", 2, 20 + len(json_chunk), len(json_chunk), 0x4E4F534A) + json_chunk
        (self.project / "assets").mkdir()
        (self.project / "shaders").mkdir()
        (self.project / "assets/required.glb").write_bytes(self.glb)
        (self.project / "assets/required.glb.import").write_text('source_file="res://assets/required.glb"\ncompress/mode=0\n')
        (self.project / "shaders/required.gdshader").write_bytes(b"shader_type spatial;\n")
        self.files = {"main.gd": b"new main", "assets/房间.glb": self.glb,
                      "assets/房间.glb.import": 'source_file="res://assets/房间.glb"\ncompress/mode=0\n'.encode(),
                      "source/empty.bin": b"", "docs/说明.md": "模拟\n".encode()}
        self.manifest = {"format": core.FORMAT, "update_id": "compact-synthetic", "baseline_commit": core.BASELINE,
                         "anchors": [{"path": "project.godot", "sha256": core.file_hash(self.project / "project.godot")}],
                         "files": [{"path": p, "old_sha256": core.sha_bytes(b"old main") if p == "main.gd" else None,
                                    "new_sha256": core.sha_bytes(data)} for p, data in self.files.items()]}
        (self.package / "manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")
        for name in ("update_source.py", "compact_source_update.py"):
            shutil.copyfile(TOOLS / name, self.package / name)
        self.prerequisites = {"format": "poolcore-base-prerequisites/v1", "baseline_commit": core.BASELINE,
                              "manifest_sha256": core.manifest_digest(self.manifest),
                              "files": [{"path": p, "sha256": core.file_hash(self.project / p)}
                                        for p in ("project.godot", "assets/required.glb", "shaders/required.gdshader")],
                              "coverage": {"method": "synthetic fixture"}}
        (self.package / compact.PREREQUISITES).write_text(json.dumps(self.prerequisites), encoding="utf-8")
        self.closure_report = self.root / "closure.json"
        self.closure_report.write_text(json.dumps({"runtime_closure": {"pass": True, "missing_required_inputs": [],
            "literal_references": [{"path": "res://assets/required.glb"}, {"path": "res://shaders/required.gdshader"}],
            "expanded_dynamic_references": []}}))
        self.baseline_inventory = self.root / "baseline_inventory.json"
        self.baseline_inventory.write_text(json.dumps({"baseline_commit": core.BASELINE,
            "files": [{"path": p.relative_to(self.project).as_posix(), "sha256": core.file_hash(p)}
                      for p in self.project.rglob("*") if p.is_file()]}))
        self.make_archive()
        self.original = snapshot(self.project)

    def tearDown(self):
        self.temp.cleanup()

    def make_tar(self, members=None, format=tarfile.USTAR_FORMAT):
        memory = io.BytesIO()
        with tarfile.open(fileobj=memory, mode="w", format=format, encoding="utf-8") as archive:
            for name, data, kind in members or [(p, b, tarfile.REGTYPE) for p, b in self.files.items()]:
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.type = kind
                if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE):
                    info.linkname = "../../outside"
                    info.size = 0
                archive.addfile(info, io.BytesIO(data) if info.isfile() or kind in (tarfile.XHDTYPE, tarfile.XGLTYPE, tarfile.GNUTYPE_LONGNAME) else None)
        return memory.getvalue()

    def make_archive(self, members=None, raw=None, compressed=None, format=tarfile.USTAR_FORMAT):
        raw = self.make_tar(members, format=format) if raw is None else raw
        compressed = lzma.compress(raw, preset=0) if compressed is None else compressed
        (self.package / compact.ARCHIVE).write_bytes(compressed)
        sizes = {p: len(b) for p, b in self.files.items()}
        self.descriptor = {"format": compact.FORMAT, "archive": compact.ARCHIVE,
                           "archive_sha256": core.sha_bytes(compressed), "archive_size": len(compressed),
                           "tar_size": compact.tar_size(sizes), "manifest_sha256": core.manifest_digest(self.manifest),
                           "prerequisites_sha256": core.file_hash(self.package / compact.PREREQUISITES),
                           "files": [{"path": p, "size": size} for p, size in sizes.items()]}
        self.save_descriptor()

    def save_descriptor(self):
        (self.package / compact.DESCRIPTOR).write_text(json.dumps(self.descriptor), encoding="utf-8")

    def assert_refused(self, pattern=None):
        with self.assertRaisesRegex(core.UpdateError, pattern or ".+"):
            compact.ensure_payload(self.package)
        self.assertFalse((self.package / "payload").exists())
        self.assertEqual(snapshot(self.project), self.original)

    def cli(self, command, package=None):
        return subprocess.run([sys.executable, str(self.package / "compact_source_update.py"), command,
                               str(self.project), "--package", str(package or self.package)],
                              capture_output=True, text=True, encoding="utf-8")

    def test_check_prepares_package_but_project_remains_identical(self):
        result = self.cli("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"], "ready")
        self.assertIn("does not change the selected project", result.stderr)
        self.assertEqual(snapshot(self.project), self.original)
        for path, data in self.files.items():
            self.assertEqual((self.package / "payload" / path).read_bytes(), data)

    def test_duplicate_preparation_is_noop_and_can_use_verified_payload_without_archive(self):
        self.assertEqual(compact.ensure_payload(self.package)["result"], "prepared")
        before = snapshot(self.package / "payload")
        self.assertEqual(compact.ensure_payload(self.package)["result"], "already_prepared")
        self.assertEqual(snapshot(self.package / "payload"), before)
        (self.package / compact.ARCHIVE).unlink()
        self.assertEqual(compact.ensure_payload(self.package)["result"], "already_prepared")
        self.assertEqual(snapshot(self.package / "payload"), before)

    def test_apply_and_rollback_need_no_compressed_or_expanded_payload_after_install(self):
        result = self.cli("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        (self.package / compact.ARCHIVE).unlink()
        # Removing only this known synthetic fixture proves the rollback route is independent.
        shutil.rmtree(self.package / "payload")
        (self.package / compact.DESCRIPTOR).unlink()
        result = self.cli("rollback")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"], "rolled_back")
        self.assertEqual((self.project / "main.gd").read_bytes(), b"old main")

    def test_bad_compressed_sha_refused_before_staging(self):
        self.descriptor["archive_sha256"] = "0" * 64
        self.save_descriptor()
        self.assert_refused("SHA256")
        self.assertEqual(list(self.package.glob(".poolcore-unpack-*")), [])

    def test_missing_archive_refused_before_staging(self):
        (self.package / compact.ARCHIVE).unlink()
        self.assert_refused("missing")
        self.assertEqual(list(self.package.glob(".poolcore-unpack-*")), [])

    def test_exact_archive_size_checked_before_hashing_or_staging(self):
        self.descriptor["archive_size"] += 1
        self.save_descriptor()
        with patch.object(compact.core, "file_hash", wraps=core.file_hash) as mocked:
            self.assert_refused("size mismatch")
            self.assertNotIn(self.package / compact.ARCHIVE, [call.args[0] for call in mocked.call_args_list])

    def test_missing_member_retains_failed_stage_and_never_publishes(self):
        members = [(p, b, tarfile.REGTYPE) for p, b in self.files.items()][:-1]
        self.make_archive(members)
        self.assert_refused("missing manifest")
        self.assertEqual(len(list(self.package.glob(".poolcore-unpack-*"))), 1)

    def test_unexpected_duplicate_and_unsafe_paths_refused(self):
        baseline = [(p, b, tarfile.REGTYPE) for p, b in self.files.items()]
        for name in ("extra.txt", "main.gd", "../escape", "/tmp/escape", "C:/escape", "a\\b"):
            with self.subTest(name=name):
                self.make_archive(baseline + [(name, b"bad", tarfile.REGTYPE)])
                self.assert_refused()
        self.assertFalse((self.root / "escape").exists())

    def test_symlink_hardlink_directory_devices_fifo_sparse_extensions_refused(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.DIRTYPE, tarfile.CHRTYPE,
                     tarfile.BLKTYPE, tarfile.FIFOTYPE, tarfile.GNUTYPE_SPARSE,
                     tarfile.XHDTYPE, tarfile.XGLTYPE, tarfile.GNUTYPE_LONGNAME):
            with self.subTest(kind=kind):
                self.make_archive([("main.gd", b"", kind)])
                self.assert_refused("Nonordinary/extended|USTAR")

    def test_wrong_member_size_and_hash_refused(self):
        for data in (b"new main plus", b"BAD main"):
            with self.subTest(data=data):
                self.make_archive([("main.gd", data, tarfile.REGTYPE)])
                self.assert_refused("size mismatch|SHA256 mismatch")

    def test_truncated_compression_with_matching_descriptor_is_refused(self):
        compressed = (self.package / compact.ARCHIVE).read_bytes()[:-8]
        self.make_archive(compressed=compressed)
        self.assert_refused("Truncated XZ")

    def test_concatenated_xz_and_nonzero_trailing_tar_refused(self):
        compressed = (self.package / compact.ARCHIVE).read_bytes() + lzma.compress(b"hidden")
        self.make_archive(compressed=compressed)
        self.assert_refused("Trailing/concatenated")
        raw = bytearray(self.make_tar())
        raw[-1] = 1
        self.make_archive(raw=bytes(raw))
        self.assert_refused("Nonzero trailing")

    def test_unbounded_decompressed_output_refused(self):
        self.make_archive(raw=self.make_tar() + b"\0" * 65536)
        self.assert_refused("bounded size")

    def test_invalid_size_table_and_manifest_link_refused_before_staging(self):
        original = copy.deepcopy(self.descriptor)
        mutations = [lambda d: d["files"].append(d["files"][0]),
                     lambda d: d["files"].pop(),
                     lambda d: d["files"][0].update(size=True),
                     lambda d: d["files"][0].update(size=-1),
                     lambda d: d["files"][0].update(size=compact.MAX_FILE_BYTES + 1),
                     lambda d: d.update(tar_size=d["tar_size"] + 512),
                     lambda d: d.update(manifest_sha256="0" * 64)]
        for mutate in mutations:
            self.descriptor = copy.deepcopy(original)
            mutate(self.descriptor)
            self.save_descriptor()
            self.assert_refused()
        self.assertEqual(list(self.package.glob(".poolcore-unpack-*")), [])

    def test_partial_stage_retained_and_retry_publishes_new_complete_stage(self):
        real = compact.inspect_archive
        def fail(package, manifest, descriptor, sizes, destination=None):
            (destination / "partial.txt").write_bytes(b"unfinished")
            raise OSError("injected extraction write failure")
        with patch.object(compact, "inspect_archive", side_effect=fail):
            self.assert_refused("injected extraction")
        failed = list(self.package.glob(".poolcore-unpack-*"))[0]
        self.assertEqual(compact.ensure_payload(self.package)["result"], "prepared")
        self.assertEqual((failed / "payload/partial.txt").read_bytes(), b"unfinished")

    def test_existing_incomplete_or_extra_payload_never_overwritten(self):
        target = self.package / "payload"
        target.mkdir()
        (target / "main.gd").write_bytes(b"user existing content")
        before = snapshot(target)
        with self.assertRaisesRegex(core.UpdateError, "mismatch"):
            compact.ensure_payload(self.package)
        self.assertEqual(snapshot(target), before)

    def test_package_links_and_dangling_descriptor_refused(self):
        outside = self.root / "outside"
        outside.mkdir()
        for name in ("payload", compact.ARCHIVE, compact.DESCRIPTOR, ".poolcore-payload.lock"):
            with self.subTest(name=name):
                target = self.package / name
                saved = target.read_bytes() if target.is_file() else None
                if target.exists():
                    target.unlink()
                target.symlink_to(outside / "does-not-exist")
                with self.assertRaisesRegex(core.UpdateError, "Symlink/junction"):
                    compact.ensure_payload(self.package)
                target.unlink()
                if saved is not None:
                    target.write_bytes(saved)
        self.assertEqual(list(outside.iterdir()), [])

    @unittest.skipIf(os.name == "nt", "POSIX process lock exercise; Windows code is static-reviewed")
    def test_concurrent_preparation_refused(self):
        import fcntl
        with (self.package / ".poolcore-payload.lock").open("wb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.cli("check")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Another process", result.stderr)
        self.assertEqual(snapshot(self.project), self.original)

    def test_check_refuses_package_inside_project_before_any_write(self):
        inside = self.project / "update"
        shutil.copytree(self.package, inside)
        before = snapshot(self.project)
        result = self.cli("check", inside)
        self.assertEqual(result.returncode, 2)
        self.assertIn("separate folder", result.stderr)
        self.assertEqual(snapshot(self.project), before)

    def test_builder_preserves_every_payload_byte_and_expanded_stage(self):
        compact.ensure_payload(self.package)
        (self.package / "README-SOURCE-UPDATE.md").write_text("Synthetic SOURCE update, not a full project.")
        before = snapshot(self.package)
        output, zip_path = self.root / "compact result", self.root / "result.zip"
        result = builder.build(self.package, output, zip_path, self.project, self.closure_report, self.baseline_inventory)
        self.assertEqual(result["files"], len(self.files))
        self.assertEqual(snapshot(self.package), before)
        self.assertFalse((output / "payload").exists())
        required_base = core.read_json(output / compact.PREREQUISITES)
        self.assertNotIn("assets/required.glb.import", [e["path"] for e in required_base["files"]])
        self.assertIn("assets/required.glb.import", required_base["coverage"]["regenerated_baseline_metadata_not_hash_gated"])
        with zipfile.ZipFile(zip_path) as archive:
            self.assertEqual(len(archive.namelist()), 9)
            self.assertIsNone(archive.testzip())
        compact.ensure_payload(output)
        for path, data in self.files.items():
            self.assertEqual((output / "payload" / path).read_bytes(), data)

    def test_builder_refuses_existing_output_and_does_not_replace_it(self):
        compact.ensure_payload(self.package)
        output = self.root / "exists"
        output.mkdir()
        (output / "keep.txt").write_bytes(b"keep")
        with self.assertRaisesRegex(core.UpdateError, "must be new"):
            builder.build(self.package, output, self.root / "new.zip", self.project, self.closure_report, self.baseline_inventory)
        self.assertEqual((output / "keep.txt").read_bytes(), b"keep")

    def test_actual_base_harness_can_start_with_a_cold_compact_package(self):
        spec = importlib.util.spec_from_file_location("review_compact_final", Path(__file__).with_name("verify_final_package.py"))
        reviewer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reviewer)
        self.assertFalse((self.package / "payload").exists())
        result = reviewer.exercise(self.package, self.project, self.root / "disposable tested project", self.manifest)
        self.assertEqual(result["apply"], "installed")
        self.assertEqual(result["rollback"], "rolled_back")
        self.assertTrue(result["later_edit_preserved"])
        self.assertEqual(snapshot(self.project), self.original)

    def test_missing_required_glb_or_shader_refused_before_project_or_package_mutation(self):
        for relative in ("assets/required.glb", "shaders/required.gdshader"):
            with self.subTest(relative=relative):
                path = self.project / relative
                original = path.read_bytes()
                path.unlink()
                before = snapshot(self.project)
                package_before = snapshot(self.package)
                result = self.cli("apply")
                self.assertEqual(result.returncode, 2)
                self.assertIn("Required baseline resource missing or modified", result.stderr)
                self.assertEqual(snapshot(self.project), before)
                self.assertEqual(snapshot(self.package), package_before)
                path.write_bytes(original)

    def test_modified_required_dependency_refused_but_unrelated_user_work_allowed(self):
        (self.project / "personal.txt").write_bytes(b"user work")
        self.assertEqual(self.cli("check").returncode, 0)
        (self.project / "shaders/required.gdshader").write_bytes(b"user shader edit")
        before = snapshot(self.project)
        result = self.cli("apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing or modified", result.stderr)
        self.assertEqual(snapshot(self.project), before)

    def test_rollback_bypasses_missing_base_prerequisites(self):
        self.assertEqual(self.cli("apply").returncode, 0)
        (self.project / "assets/required.glb").unlink()
        (self.package / compact.PREREQUISITES).unlink()
        result = self.cli("rollback")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.project / "main.gd").read_bytes(), b"old main")
        self.assertFalse((self.project / "assets/required.glb").exists())

    def test_missing_descriptor_cannot_silently_downgrade_prepared_compact_package(self):
        compact.ensure_payload(self.package)
        (self.package / compact.DESCRIPTOR).unlink()
        before = snapshot(self.project)
        result = self.cli("apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn("descriptor is missing", result.stderr)
        self.assertEqual(snapshot(self.project), before)

    def test_builder_rejects_required_base_bytes_not_matching_archive_inventory(self):
        compact.ensure_payload(self.package)
        (self.package / "README-SOURCE-UPDATE.md").write_text("synthetic guide")
        (self.project / "shaders/required.gdshader").write_bytes(b"not immutable baseline")
        with self.assertRaisesRegex(core.UpdateError, "immutable 351f inventory"):
            builder.build(self.package, self.root / "bad compact", self.root / "bad.zip", self.project,
                          self.closure_report, self.baseline_inventory)

    def test_regenerated_baseline_import_metadata_does_not_block_source_update(self):
        path = self.project / "assets/required.glb.import"
        path.write_bytes(b"editor regenerated baseline import metadata")
        result = self.cli("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_bytes(), b"editor regenerated baseline import metadata")

    def test_new_shipped_import_metadata_keeps_strict_payload_and_rollback_hashes(self):
        compact.ensure_payload(self.package)
        path = self.package / "payload/assets/房间.glb.import"
        original = path.read_bytes()
        path.write_bytes(b"wrong new import config")
        before = snapshot(self.project)
        result = self.cli("apply")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(snapshot(self.project), before)
        path.write_bytes(original)
        self.assertEqual(self.cli("apply").returncode, 0)
        installed_import = self.project / "assets/房间.glb.import"
        installed_import.write_bytes(b"editor regenerated newly installed import")
        before = snapshot(self.project)
        result = self.cli("rollback")
        self.assertEqual(result.returncode, 2)
        self.assertIn("later edit/deletion", result.stderr)
        self.assertEqual(snapshot(self.project), before)

    def test_builder_rejects_malformed_glb_dependencies_before_output_creation(self):
        compact.ensure_payload(self.package)
        (self.package / "README-SOURCE-UPDATE.md").write_text("synthetic guide")
        def glb(data):
            raw = json.dumps(data).encode()
            raw += b" " * ((-len(raw)) % 4)
            return struct.pack("<4sIIII", b"glTF", 2, 20 + len(raw), len(raw), 0x4E4F534A) + raw
        malformed = [b"glTF", struct.pack("<4sIIII", b"glTF", 2, 20, 0xFFFFFFFC, 0x4E4F534A),
                     glb([]), glb({"images": [{"uri": 123}]}), glb({"images": [False]})]
        for index, data in enumerate(malformed):
            with self.subTest(index=index):
                (self.package / "payload/assets/房间.glb").write_bytes(data)
                manifest = copy.deepcopy(self.manifest)
                next(e for e in manifest["files"] if e["path"] == "assets/房间.glb")["new_sha256"] = core.sha_bytes(data)
                (self.package / "manifest.json").write_text(json.dumps(manifest))
                output = self.root / ("bad-glb-" + str(index))
                with self.assertRaises(core.UpdateError):
                    builder.build(self.package, output, self.root / (str(index) + ".zip"), self.project,
                                  self.closure_report, self.baseline_inventory)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
