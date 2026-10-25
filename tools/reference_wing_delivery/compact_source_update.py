#!/usr/bin/env python3
"""Standard-library entry for a compact SOURCE update; Python 3.9+.

check/apply may prepare files INSIDE THE UPDATE PACKAGE. check never writes the
selected project. rollback/status use the unchanged core and need no archive.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import lzma
import os
from pathlib import Path
import stat
import sys
import tarfile
import tempfile

import update_source as core


FORMAT = "poolcore-compact-source-update/v1"
DESCRIPTOR = "compact_payload.json"
ARCHIVE = "payload.tar.xz"
PREREQUISITES = "base_prerequisites.json"
MAX_FILE_BYTES = 8 * 1024 ** 3
MAX_TOTAL_BYTES = 32 * 1024 ** 3
MAX_ARCHIVE_BYTES = 8 * 1024 ** 3
XZ_MEMORY_LIMIT = 256 * 1024 ** 2


def require(condition, message):
    if not condition:
        raise core.UpdateError(message)


def read_descriptor(package, manifest):
    value = core.read_json(package / DESCRIPTOR)
    keys = {"format", "archive", "archive_sha256", "archive_size", "tar_size", "manifest_sha256", "prerequisites_sha256", "files"}
    require(isinstance(value, dict) and set(value) == keys, "Invalid compact payload descriptor")
    require(value["format"] == FORMAT and value["archive"] == ARCHIVE, "Unsupported compact payload format/archive")
    require(core.valid_hash(value["archive_sha256"]), "Invalid compact archive SHA256")
    require(core.valid_hash(value["prerequisites_sha256"]), "Invalid base prerequisites SHA256")
    require(value["manifest_sha256"] == core.manifest_digest(manifest), "Compact descriptor/manifest mismatch")
    require(type(value["archive_size"]) is int and 0 < value["archive_size"] <= MAX_ARCHIVE_BYTES,
            "Invalid or excessive compressed archive size")
    require(isinstance(value["files"], list), "Invalid compact file-size table")
    expected = {item["path"] for item in manifest["files"]}
    sizes = {}
    for item in value["files"]:
        require(isinstance(item, dict) and set(item) == {"path", "size"}, "Invalid compact size entry")
        relative = core.validate_relative(item["path"])
        require(relative in expected and relative not in sizes, "Unexpected/duplicate compact path: " + relative)
        require(type(item["size"]) is int and 0 <= item["size"] <= MAX_FILE_BYTES,
                "Invalid or excessive file size: " + relative)
        sizes[relative] = item["size"]
    require(set(sizes) == expected and sum(sizes.values()) <= MAX_TOTAL_BYTES,
            "Compact size table is incomplete or exceeds the total limit")
    expected_tar_size = tar_size(sizes)
    require(type(value["tar_size"]) is int and value["tar_size"] == expected_tar_size,
            "Compact tar length does not match the exact file-size table")
    return value, sizes


def tar_size(sizes):
    contents = sum(512 + ((size + 511) // 512) * 512 for size in sizes.values())
    return ((contents + 1024 + 10239) // 10240) * 10240


def check_prerequisites(root, package):
    """Read-only required BASE checks, deliberately bypassed by rollback/status."""
    manifest = core.validate_manifest(core.read_json(package / "manifest.json"))
    descriptor, _ = read_descriptor(package, manifest)
    path = core.checked_path(package / PREREQUISITES)
    require(core.file_hash(path) == descriptor["prerequisites_sha256"], "Base prerequisites file missing or SHA256 mismatch")
    data = core.read_json(path)
    require(isinstance(data, dict) and set(data) == {"format", "baseline_commit", "manifest_sha256", "files", "coverage"},
            "Invalid base prerequisites document")
    require(data["format"] == "poolcore-base-prerequisites/v1" and data["baseline_commit"] == core.BASELINE
            and data["manifest_sha256"] == core.manifest_digest(manifest), "Base prerequisites/manifest mismatch")
    require(isinstance(data["files"], list) and bool(data["files"]), "Empty base prerequisites")
    payload = {core.path_key(e["path"]) for e in manifest["files"]}
    seen = set()
    for item in data["files"]:
        require(isinstance(item, dict) and set(item) == {"path", "sha256"}, "Invalid base prerequisite entry")
        relative = core.validate_relative(item["path"])
        key = core.path_key(relative)
        require(key not in seen and key not in payload and core.valid_hash(item["sha256"]),
                "Invalid/duplicate/overlapping base prerequisite: " + relative)
        require(core.file_hash(core.member(root, relative)) == item["sha256"],
                "Required baseline resource missing or modified: " + relative + "; project not changed")
        seen.add(key)
    require("project.godot" in seen, "Base prerequisites must include project.godot")
    return len(seen)


@contextmanager
def preparation_lock(package):
    """Nonblocking package-local process lock. External editors are not locked."""
    path = core.checked_path(package / ".poolcore-payload.lock")
    fd = os.open(str(path), os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "r+b") as stream:
        require(stat.S_ISREG(os.fstat(stream.fileno()).st_mode), "Preparation lock is not an ordinary file")
        require(os.fstat(stream.fileno()).st_nlink == 1, "Hard-linked preparation lock refused")
        try:
            if os.name == "nt":
                import msvcrt
                if stream.seek(0, os.SEEK_END) == 0:
                    stream.write(b"0")
                    stream.flush()
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise core.UpdateError("Another process is preparing this package; close it and retry") from exc
        try:
            yield
        finally:
            if os.name == "nt":
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)


class BoundedXZReader:
    """Single XZ stream, decoder memory cap and exact-size-derived output cap."""
    def __init__(self, source, limit):
        self.source = source
        self.decoder = lzma.LZMADecompressor(format=lzma.FORMAT_XZ, memlimit=XZ_MEMORY_LIMIT)
        self.limit = limit
        self.count = 0
        self.buffer = b""
        self.finished = False

    def read(self, size):
        require(type(size) is int and size >= 0, "Unbounded archive read refused")
        while len(self.buffer) < size and not self.finished:
            chunk = self.source.read(65536) if self.decoder.needs_input else b""
            require(chunk or not self.decoder.needs_input, "Truncated XZ archive")
            output = self.decoder.decompress(chunk, max_length=65536)
            self.count += len(output)
            require(self.count <= self.limit, "Decompressed archive exceeds its bounded size")
            self.buffer += output
            if self.decoder.eof:
                require(not self.decoder.unused_data and not self.source.read(1),
                        "Trailing/concatenated compressed data refused")
                self.finished = True
        result, self.buffer = self.buffer[:size], self.buffer[size:]
        return result


def verify_payload(payload, manifest, sizes):
    payload = core.checked_path(payload)
    require(payload.is_dir(), "Prepared payload is not an ordinary directory")
    expected = {item["path"]: item["new_sha256"] for item in manifest["files"]}
    allowed_directories = {"/".join(path.split("/")[:n]) for path in expected
                           for n in range(1, len(path.split("/")))}
    seen = set()
    for path in payload.rglob("*"):
        path = core.checked_path(path)
        relative = path.relative_to(payload).as_posix()
        if path.is_dir():
            require(relative in allowed_directories, "Unexpected prepared payload directory: " + relative)
            continue
        require(relative in expected, "Unexpected prepared payload file: " + relative)
        require(path.stat().st_size == sizes[relative], "Prepared payload size mismatch: " + relative)
        require(core.file_hash(path) == expected[relative], "Prepared payload SHA256 mismatch: " + relative)
        seen.add(relative)
    require(seen == set(expected), "Prepared payload is incomplete; it will not be overwritten")


def inspect_archive(package, manifest, descriptor, sizes, destination=None):
    """Validate compressed bytes first, then stream/hash every allowlisted member.

    With destination=None this is a read-only archive verification for the builder.
    No tar extract/extractall call is used; only explicitly checked bytes are written.
    """
    archive_path = core.checked_path(package / ARCHIVE)
    require(archive_path.is_file(), "Compact payload archive is missing or not an ordinary file")
    require(archive_path.stat().st_size == descriptor["archive_size"], "Compact archive size mismatch")
    require(core.file_hash(archive_path) == descriptor["archive_sha256"],
            "Compact archive SHA256 mismatch; nothing was decompressed")
    expected = {item["path"]: item["new_sha256"] for item in manifest["files"]}
    seen = set()
    with archive_path.open("rb") as compressed:
        reader = BoundedXZReader(compressed, descriptor["tar_size"])
        consumed = 0
        def exact(size):
            nonlocal consumed
            value = reader.read(size)
            require(len(value) == size, "Truncated tar stream")
            consumed += len(value)
            return value
        while True:
            header = exact(512)
            if header == b"\0" * 512:
                require(exact(512) == b"\0" * 512, "Tar end markers are incomplete")
                while consumed < descriptor["tar_size"]:
                    padding = exact(min(65536, descriptor["tar_size"] - consumed))
                    require(not padding.strip(b"\0"), "Nonzero trailing tar content refused")
                require(not reader.read(1), "Trailing decompressed content refused")
                break
            require(header[257:263] == b"ustar\0", "Only strict USTAR file headers are supported")
            item = tarfile.TarInfo.frombuf(header, "utf-8", "strict")
            require(item.type in (tarfile.REGTYPE, tarfile.AREGTYPE),
                    "Nonordinary/extended archive header refused: " + item.name)
            relative = core.validate_relative(item.name)
            require(relative in expected and relative not in seen,
                    "Unexpected/duplicate archive member: " + relative)
            require(item.size == sizes[relative], "Archive member size mismatch: " + relative)
            output = None
            try:
                if destination is not None:
                    path = core.member(destination, relative)
                    core.safe_mkdir(path.parent)
                    output = path.open("xb")
                digest = hashlib.sha256()
                remaining = item.size
                while remaining:
                    block = exact(min(1024 * 1024, remaining))
                    remaining -= len(block)
                    digest.update(block)
                    if output is not None:
                        output.write(block)
                require(digest.hexdigest() == expected[relative], "Archive member SHA256 mismatch: " + relative)
                if output is not None:
                    output.flush()
                    os.fsync(output.fileno())
                    os.chmod(path, 0o644)
            finally:
                if output is not None:
                    output.close()
            padding = exact((-item.size) % 512)
            require(not padding.strip(b"\0"), "Nonzero member padding refused: " + relative)
            seen.add(relative)
    require(seen == set(expected), "Archive is missing manifest members")
    require(reader.finished, "XZ stream did not finish cleanly")


def ensure_payload(package, *, allow_expanded=False):
    package = core.checked_path(package)
    manifest = core.validate_manifest(core.read_json(package / "manifest.json"))
    if not core.checked_path(package / DESCRIPTOR).exists():
        require(allow_expanded and not core.checked_path(package / ARCHIVE).exists()
                and not core.checked_path(package / PREREQUISITES).exists(),
                "Compact descriptor is missing. Do not bypass preparation; use a complete trusted package")
        # Explicit developer-only staging, never a damaged compact-package fallback.
        core.load_package(package)
        return {"result": "expanded_payload", "package": str(package)}
    descriptor, sizes = read_descriptor(package, manifest)
    payload = core.checked_path(package / "payload")
    with preparation_lock(package):
        # Re-read after locking so a completed peer or altered package is not missed.
        manifest = core.validate_manifest(core.read_json(package / "manifest.json"))
        descriptor, sizes = read_descriptor(package, manifest)
        if payload.exists():
            verify_payload(payload, manifest, sizes)
            return {"result": "already_prepared", "package": str(package)}
        archive = core.checked_path(package / ARCHIVE)
        require(archive.is_file(), "Compact payload archive is missing or not an ordinary file")
        require(archive.stat().st_size == descriptor["archive_size"], "Compact archive size mismatch")
        require(core.file_hash(archive) == descriptor["archive_sha256"],
                "Compact archive SHA256 mismatch; no extraction started")
        stage = Path(tempfile.mkdtemp(prefix=".poolcore-unpack-", dir=str(package)))
        staged_payload = stage / "payload"
        try:
            core.safe_mkdir(staged_payload)
            inspect_archive(package, manifest, descriptor, sizes, staged_payload)
            verify_payload(staged_payload, manifest, sizes)
            require(core.manifest_digest(core.validate_manifest(core.read_json(package / "manifest.json")))
                    == core.manifest_digest(manifest), "Manifest changed during package preparation")
            current_descriptor, _ = read_descriptor(package, manifest)
            require(current_descriptor == descriptor, "Compact descriptor changed during preparation")
            core.checked_path(payload)
            require(not payload.exists(), "Payload destination appeared during preparation; not overwritten")
            # Renaming the completed directory publishes all payload files together.
            os.rename(staged_payload, payload)
            core.fsync_dir(package)
            stage.rmdir()  # Only our now-empty directory; no recursive cleanup.
            core.fsync_dir(package)
        except BaseException as exc:
            raise core.UpdateError("Package preparation failed. Keep/inspect the staging directory: "
                                   + str(stage) + "; selected project has not been touched; " + str(exc)) from exc
    return {"result": "prepared", "package": str(package), "files": len(sizes)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "apply", "rollback", "status"))
    parser.add_argument("project")
    parser.add_argument("--package", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--update-id")
    parser.add_argument("--expanded", action="store_true", help="Developer-only expanded staging, not a compact package")
    args = parser.parse_args(argv)
    try:
        if args.command in {"check", "apply"}:
            require(not args.update_id, "--update-id is only valid with rollback/status")
            # Validate the selected root before any unnecessary package preparation.
            root = core.project_root(args.project)
            package = core.checked_path(args.package)
            require(root != package and root not in package.parents and package not in root.parents,
                    "Unpack the update into a separate folder outside the selected project, not an ancestor of it")
            if core.checked_path(package / DESCRIPTOR).exists():
                count = check_prerequisites(root, package)
                print("Required unchanged baseline resources verified: " + str(count), file=sys.stderr)
            print("Preparing/verifying the update package only. 'check' does not change the selected project.",
                  file=sys.stderr)
            result = ensure_payload(args.package, allow_expanded=args.expanded)
            print("Package: " + result["result"], file=sys.stderr)
            if core.checked_path(package / DESCRIPTOR).exists():
                check_prerequisites(root, package)
        forwarded = [args.command, args.project, "--package", str(args.package)]
        if args.update_id:
            forwarded += ["--update-id", args.update_id]
        return core.main(forwarded)
    except (core.UpdateError, OSError, ValueError, tarfile.TarError, lzma.LZMAError) as exc:
        print("REFUSED / ERROR: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    if sys.version_info < (3, 9):
        print("Python 3.9 or newer is required. No project files were changed.", file=sys.stderr)
        sys.exit(2)
    sys.exit(main())
