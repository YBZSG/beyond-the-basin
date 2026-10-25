#!/usr/bin/env python3
"""Reversible, allowlisted SOURCE update. Python 3.9+; no third-party packages.

This program never invokes Godot, Git, a network client, or an export tool.
The manifest is a trusted package's explicit allowlist, not a general patch.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import unicodedata

BASELINE = "351fcd6f8f2bb5fe21851482e2526dfa262ef406"
FORMAT = "poolcore-source-update/v1"
STATE_DIR = ".poolcore-source-updates"
HASH_RE = re.compile(r"[0-9a-f]{64}\Z")
ID_RE = re.compile(r"[a-z0-9][a-z0-9_-]{0,79}\Z")
FORBIDDEN = {".git", ".godot", STATE_DIR, "output", "cache", "__pycache__",
             "candidates", "references", "secrets", ".aws", ".ssh", ".codex"}
WINDOWS_RESERVED = re.compile(r"(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?\Z", re.I)


class UpdateError(Exception):
    """A safe refusal or recoverable installer error."""


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def path_key(value):
    return unicodedata.normalize("NFC", value).casefold()


def validate_relative(value):
    if not isinstance(value, str) or not value or "\\" in value:
        raise UpdateError("Invalid relative path: " + repr(value))
    parts = value.split("/")
    for part in parts:
        if (part in {"", ".", ".."} or part[-1:] in {" ", "."}
                or any(ord(c) < 32 or c in '<>:"|?*' for c in part)
                or WINDOWS_RESERVED.fullmatch(part)
                or path_key(part) in FORBIDDEN
                or part.lower() == ".env" or part.lower().startswith(".env.")):
            raise UpdateError("Unsafe or excluded relative path: " + value)
    return value


def checked_path(path):
    """Reject symlinks, Windows junctions/reparse points, and non-directory ancestors."""
    path = Path(os.path.abspath(path))
    for current in reversed((path, *path.parents)):
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise UpdateError("Symlink/junction/reparse path refused: " + str(current))
        if current != path and not stat.S_ISDIR(info.st_mode):
            raise UpdateError("Non-directory ancestor: " + str(current))
    return path


def member(root, relative):
    validate_relative(relative)
    return checked_path(root / relative)


def file_hash(path):
    path = checked_path(path)
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode):
        raise UpdateError("Expected an ordinary file: " + str(path))
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def unique_json(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise UpdateError("Duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(path):
    path = checked_path(path)
    if file_hash(path) is None:
        raise UpdateError("Required file missing: " + str(path))
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_json)
    except (ValueError, UnicodeError) as exc:
        raise UpdateError("Invalid JSON: " + str(path)) from exc


def manifest_digest(manifest):
    return sha_bytes(json.dumps(manifest, ensure_ascii=False, sort_keys=True,
                               separators=(",", ":")).encode("utf-8"))


def valid_hash(value):
    return isinstance(value, str) and HASH_RE.fullmatch(value)


def validate_manifest(data):
    required = {"format", "update_id", "baseline_commit", "anchors", "files"}
    if not isinstance(data, dict) or set(data) != required:
        raise UpdateError("Manifest must contain exactly: " + ", ".join(sorted(required)))
    if data["format"] != FORMAT or data["baseline_commit"] != BASELINE:
        raise UpdateError("Unsupported manifest format or baseline; requires " + BASELINE)
    if not isinstance(data["update_id"], str) or not ID_RE.fullmatch(data["update_id"]):
        raise UpdateError("Unsafe update_id")
    if not isinstance(data["anchors"], list) or not data["anchors"]:
        raise UpdateError("Manifest anchors are required")
    if not isinstance(data["files"], list) or not data["files"]:
        raise UpdateError("Empty or invalid file allowlist")
    seen = set()
    paths = []
    for group, keys in (("anchors", {"path", "sha256"}),
                        ("files", {"path", "old_sha256", "new_sha256"})):
        for item in data[group]:
            if not isinstance(item, dict) or set(item) != keys:
                raise UpdateError("Invalid " + group + " entry")
            relative = validate_relative(item["path"])
            key = path_key(relative)
            if key in seen:
                raise UpdateError("Duplicate/case/Unicode-colliding manifest path: " + relative)
            seen.add(key)
            paths.append(key)
            for field in keys - {"path"}:
                if field == "old_sha256" and item[field] is None:
                    continue
                if not valid_hash(item[field]):
                    raise UpdateError("Invalid SHA256 for " + relative)
            if group == "files" and item["old_sha256"] == item["new_sha256"]:
                raise UpdateError("No-op entries are not allowed: " + relative)
    for relative in paths:
        parts = relative.split("/")
        if any("/".join(parts[:i]) in seen for i in range(1, len(parts))):
            raise UpdateError("File/directory collision in allowlist: " + relative)
    if not any(item["path"] == "project.godot" for item in data["anchors"]):
        raise UpdateError("An unchanged project.godot SHA256 anchor is required")
    return data


def load_package(package):
    package = checked_path(package)
    manifest = validate_manifest(read_json(package / "manifest.json"))
    for item in manifest["files"]:
        actual = file_hash(member(package / "payload", item["path"]))
        if actual != item["new_sha256"]:
            raise UpdateError("Payload missing or SHA256 mismatch: " + item["path"])
    return package, manifest


def project_root(root):
    root = checked_path(root)
    if not root.is_dir() or file_hash(root / "project.godot") is None:
        raise UpdateError("Select the project root containing project.godot: " + str(root))
    return root


def check_anchors(root, manifest):
    for item in manifest["anchors"]:
        if file_hash(member(root, item["path"])) != item["sha256"]:
            raise UpdateError("Baseline anchor mismatch: " + item["path"])


def current_hashes(root, manifest):
    return {item["path"]: file_hash(member(root, item["path"]))
            for item in manifest["files"]}


def classify_project(root, manifest):
    check_anchors(root, manifest)
    hashes = current_hashes(root, manifest)
    if all(hashes[item["path"]] == item["new_sha256"] for item in manifest["files"]):
        return "already_applied"
    for item in manifest["files"]:
        if hashes[item["path"]] != item["old_sha256"]:
            reason = "New path already exists" if item["old_sha256"] is None else "Modified/non-baseline file"
            raise UpdateError(reason + ": " + item["path"] + "; nothing was overwritten")
    return "ready"


def fsync_dir(path):
    # Windows does not support opening a directory for fsync through os.open.
    if os.name == "nt":
        return
    fd = os.open(str(path), os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def safe_mkdir(path):
    path = checked_path(path)
    if path.exists():
        if not path.is_dir():
            raise UpdateError("Directory path is occupied: " + str(path))
        return
    safe_mkdir(path.parent)
    path.mkdir()
    fsync_dir(path.parent)


_UNSPECIFIED = object()


def atomic_write(path, *, data=None, source=None, expected_hash=None, mode=0o644,
                 expected_current=_UNSPECIFIED):
    """Write a same-directory temporary file, fsync, then replace atomically."""
    path = checked_path(path)
    if path.exists() and not path.is_file():
        raise UpdateError("Non-file destination: " + str(path))
    safe_mkdir(path.parent)
    fd, temporary = tempfile.mkstemp(prefix=".poolcore-write-", dir=str(path.parent))
    try:
        digest = hashlib.sha256()
        with os.fdopen(fd, "wb") as output:
            if source is not None:
                with checked_path(source).open("rb") as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        output.write(block)
                        digest.update(block)
            else:
                output.write(data)
                digest.update(data)
            output.flush()
            os.fsync(output.fileno())
        if expected_hash is not None and digest.hexdigest() != expected_hash:
            raise UpdateError("Source changed during copy: " + str(source))
        os.chmod(temporary, mode)
        checked_path(path)
        if expected_current is not _UNSPECIFIED and file_hash(path) != expected_current:
            raise UpdateError("Destination changed before atomic replacement: " + str(path))
        os.replace(temporary, path)
        fsync_dir(path.parent)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def write_receipt(path, receipt, status):
    receipt["status"] = status
    receipt["updated_at"] = now()
    atomic_write(path, data=(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))


@contextmanager
def project_lock(root):
    state = checked_path(root / STATE_DIR)
    safe_mkdir(state)
    lock_path = checked_path(state / "installer.lock")
    fd = os.open(str(lock_path), os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "r+b") as lock:
        try:
            if os.name == "nt":
                import msvcrt
                if lock.seek(0, os.SEEK_END) == 0:
                    lock.write(b"0")
                    lock.flush()
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise UpdateError("Another installer owns this project lock; close it and retry") from exc
        try:
            yield
        finally:
            if os.name == "nt":
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(lock, fcntl.LOCK_UN)


def receipt_location(root, update_id):
    if not isinstance(update_id, str) or not ID_RE.fullmatch(update_id):
        raise UpdateError("Unsafe update_id")
    return checked_path(root / STATE_DIR / update_id / "receipt.json")


def load_receipt(path):
    receipt = read_json(path)
    if not isinstance(receipt, dict) or receipt.get("receipt_format") != 1:
        raise UpdateError("Unsupported local receipt")
    manifest = validate_manifest(receipt.get("manifest"))
    if receipt.get("manifest_sha256") != manifest_digest(manifest):
        raise UpdateError("Local receipt manifest integrity failure")
    if path.parent.name != manifest["update_id"]:
        raise UpdateError("Receipt update_id does not match its directory")
    if receipt.get("status") not in {"prepared", "applying", "installed", "rolling_back",
                                      "rolled_back", "rollback_failed"}:
        raise UpdateError("Unknown receipt status")
    modes = receipt.get("original_modes")
    if not isinstance(modes, dict) or set(modes) != {e["path"] for e in manifest["files"]}:
        raise UpdateError("Invalid receipt original modes")
    if any(type(mode) is not int or not 0 <= mode <= 0o777 for mode in modes.values()):
        raise UpdateError("Unsafe receipt file mode")
    directories = receipt.get("created_directories")
    if not isinstance(directories, list):
        raise UpdateError("Invalid receipt directory list")
    allowed_dirs = {str(Path(e["path"]).parent).replace("\\", "/") for e in manifest["files"]}
    allowed_dirs |= {"/".join(e["path"].split("/")[:i]) for e in manifest["files"]
                     for i in range(1, len(e["path"].split("/")))}
    for relative in directories:
        validate_relative(relative)
        if relative not in allowed_dirs:
            raise UpdateError("Unrelated directory in receipt: " + relative)
    return receipt


def existing_receipt(root, manifest):
    path = receipt_location(root, manifest["update_id"])
    if not path.exists():
        if path.parent.exists():
            raise UpdateError("Incomplete backup preparation found (no source writes started). Keep this directory and inspect: "
                              + str(path.parent))
        return None
    receipt = load_receipt(path)
    if receipt["manifest_sha256"] != manifest_digest(manifest):
        raise UpdateError("This update_id already belongs to a different manifest")
    if receipt["status"] not in {"installed", "rolled_back"}:
        raise UpdateError("Interrupted update found. Run rollback first; receipt: " + str(path))
    return receipt


def verify_backups(receipt_path, manifest):
    for item in manifest["files"]:
        if item["old_sha256"] is not None:
            backup = member(receipt_path.parent / "originals", item["path"])
            if file_hash(backup) != item["old_sha256"]:
                raise UpdateError("Backup missing or SHA256 mismatch: " + item["path"])


def rollback_locked(root, receipt_path, receipt):
    manifest = receipt["manifest"]
    check_anchors(root, manifest)
    verify_backups(receipt_path, manifest)
    hashes = current_hashes(root, manifest)
    if receipt["status"] == "rolled_back":
        if not all(hashes[e["path"]] == e["old_sha256"] for e in manifest["files"]):
            raise UpdateError("Project changed after rollback; no files were overwritten")
        return "already_rolled_back"
    # A completed installation can only be rolled back as a whole. Interrupted
    # transactions may contain old or new bytes, never an unrelated third value.
    for item in manifest["files"]:
        allowed = {item["new_sha256"]}
        if receipt["status"] != "installed":
            allowed.add(item["old_sha256"])
        if hashes[item["path"]] not in allowed:
            raise UpdateError("Rollback refused to preserve a later edit/deletion: " + item["path"])
    write_receipt(receipt_path, receipt, "rolling_back")
    try:
        for item in reversed(manifest["files"]):
            destination = member(root, item["path"])
            actual = file_hash(destination)
            if actual == item["old_sha256"]:
                continue
            if actual != item["new_sha256"]:
                raise UpdateError("File changed during rollback: " + item["path"])
            if item["old_sha256"] is None:
                checked_path(destination).unlink()
                fsync_dir(destination.parent)
            else:
                atomic_write(destination,
                             source=member(receipt_path.parent / "originals", item["path"]),
                             expected_hash=item["old_sha256"],
                             expected_current=item["new_sha256"],
                             mode=receipt["original_modes"][item["path"]])
        for relative in sorted(set(receipt["created_directories"]), key=lambda p: (-p.count("/"), p)):
            directory = member(root, relative)
            if directory.is_dir():
                try:
                    directory.rmdir()  # Never remove a nonempty directory or a user's new file.
                    fsync_dir(directory.parent)
                except OSError:
                    pass
        write_receipt(receipt_path, receipt, "rolled_back")
        return "rolled_back"
    except BaseException:
        # SIGKILL/power loss cannot run this; the earlier durable rolling_back
        # receipt still supports a safe recovery attempt with the same command.
        try:
            write_receipt(receipt_path, receipt, "rollback_failed")
        except BaseException:
            pass
        raise


def apply_update(root, package):
    root = project_root(root)
    package, manifest = load_package(package)  # All payloads checked before any project write.
    receipt_path = receipt_location(root, manifest["update_id"])
    previous = existing_receipt(root, manifest)
    state = classify_project(root, manifest)
    if state == "already_applied":
        if receipt_path.exists() and previous["status"] != "installed":
            raise UpdateError("Files and local receipt disagree; keep both and inspect before continuing")
        return {"result": state, "receipt": str(receipt_path) if receipt_path.exists() else None,
                "note": "No project files changed. Rollback requires this installation's local receipt/backups."}
    with project_lock(root):
        # Recheck after acquiring the process lock; external editors are not locked.
        load_package(package)
        if classify_project(root, manifest) != "ready":
            raise UpdateError("Project changed before transaction started; run check again")
        if receipt_path.exists():
            receipt = load_receipt(receipt_path)
            if receipt["manifest_sha256"] != manifest_digest(manifest) or receipt["status"] != "rolled_back":
                raise UpdateError("Existing receipt is not a clean, matching rollback")
            verify_backups(receipt_path, manifest)
        else:
            if receipt_path.parent.exists():
                raise UpdateError("Incomplete backup preparation found (no source writes started). Keep this directory and inspect: "
                                  + str(receipt_path.parent))
            safe_mkdir(receipt_path.parent)
            directories = set()
            modes = {}
            for item in manifest["files"]:
                destination = member(root, item["path"])
                parent = destination.parent
                while parent != root and not parent.exists():
                    directories.add(parent.relative_to(root).as_posix())
                    parent = parent.parent
                modes[item["path"]] = stat.S_IMODE(destination.stat().st_mode) & 0o777 if destination.exists() else 0o644
                if item["old_sha256"] is not None:
                    atomic_write(member(receipt_path.parent / "originals", item["path"]),
                                 source=destination, expected_hash=item["old_sha256"],
                                 mode=modes[item["path"]])
            receipt = {"receipt_format": 1, "manifest": manifest,
                       "manifest_sha256": manifest_digest(manifest), "created_at": now(),
                       "original_modes": modes, "created_directories": sorted(directories)}
            write_receipt(receipt_path, receipt, "prepared")
        write_receipt(receipt_path, receipt, "applying")
        try:
            for item in manifest["files"]:
                destination = member(root, item["path"])
                if file_hash(destination) != item["old_sha256"]:
                    raise UpdateError("File changed during installation: " + item["path"])
                atomic_write(destination, source=member(package / "payload", item["path"]),
                             expected_hash=item["new_sha256"], expected_current=item["old_sha256"],
                             mode=receipt["original_modes"][item["path"]])
            if classify_project(root, manifest) != "already_applied":
                raise UpdateError("Post-install SHA256 verification failed")
            write_receipt(receipt_path, receipt, "installed")
        except BaseException as exc:
            try:
                rollback_locked(root, receipt_path, receipt)
            except BaseException as rollback_exc:
                raise UpdateError("Installation interrupted; rollback could not complete. Do not force-copy files. "
                                  "Keep the local backup and run rollback after resolving the reported conflict. Receipt: "
                                  + str(receipt_path) + "; install: " + str(exc)
                                  + "; rollback: " + str(rollback_exc)) from exc
            raise UpdateError("Installation failed; original source files were restored. Receipt: "
                              + str(receipt_path) + "; cause: " + str(exc)) from exc
    return {"result": "installed", "files": len(manifest["files"]), "receipt": str(receipt_path)}


def rollback_update(root, update_id):
    root = project_root(root)
    receipt_path = receipt_location(root, update_id)
    receipt = load_receipt(receipt_path)
    with project_lock(root):
        receipt = load_receipt(receipt_path)
        result = rollback_locked(root, receipt_path, receipt)
    return {"result": result, "receipt": str(receipt_path)}


def main(argv=None):
    parser = argparse.ArgumentParser(description="SOURCE INCREMENTAL UPDATE, not a full project/PCK/engine.")
    parser.add_argument("command", choices=("check", "apply", "rollback", "status"))
    parser.add_argument("project", help="Existing 351f baseline project root containing project.godot")
    parser.add_argument("--package", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--update-id", help="Rollback/status from the LOCAL receipt without the original package")
    args = parser.parse_args(argv)
    try:
        root = project_root(args.project)
        if args.command in {"check", "apply"} and args.update_id:
            raise UpdateError("--update-id is only valid with rollback/status")
        if args.command == "apply":
            result = apply_update(root, args.package)
        elif args.command == "check":
            _, manifest = load_package(args.package)
            existing_receipt(root, manifest)
            result = {"result": classify_project(root, manifest), "files": len(manifest["files"]),
                      "writes": False}
        else:
            update_id = args.update_id
            if not update_id:
                manifest = validate_manifest(read_json(checked_path(args.package) / "manifest.json"))
                update_id = manifest["update_id"]
            if args.command == "rollback":
                result = rollback_update(root, update_id)
            else:
                receipt_path = receipt_location(root, update_id)
                receipt = load_receipt(receipt_path)
                hashes = current_hashes(root, receipt["manifest"])
                result = {"result": receipt["status"], "receipt": str(receipt_path),
                          "files": [{"path": e["path"], "current_sha256": hashes[e["path"]],
                                     "matches_installed": hashes[e["path"]] == e["new_sha256"],
                                     "matches_baseline": hashes[e["path"]] == e["old_sha256"]}
                                    for e in receipt["manifest"]["files"]]}
        try:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        except UnicodeEncodeError:
            # Redirected Windows terminals can use a legacy output encoding.
            print(json.dumps(result, indent=2, ensure_ascii=True))
        return 0
    except (UpdateError, OSError) as exc:
        print("REFUSED / ERROR: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    if sys.version_info < (3, 9):
        print("Python 3.9 or newer is required. No files were changed.", file=sys.stderr)
        sys.exit(2)
    sys.exit(main())
