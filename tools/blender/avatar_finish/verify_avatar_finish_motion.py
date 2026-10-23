#!/usr/bin/env python3
"""CPU-only audit of isolated avatar cloth motion evidence, never a visual verdict.

    python3 verify_avatar_finish_motion.py OUT [--encode]
    python3 verify_avatar_finish_motion.py --self-test [--encode]

OUT/captures must be the untouched output of avatar_finish_candidate_motion.gd.
Originals, accepted static evidence, sources and GLBs are never modified. Reports
are created exclusively (a numbered suffix is used on a repeat run). --encode
adds three native-resolution, side-by-side FFV1/bgr0 Matroska clips at 30 fps;
left is baseline, right is candidate. Opaque RGB values are checked after decoding
every clip frame. Successful technical matching does NOT establish no shimmer.
Requires Python 3.10+ and Pillow; encoding additionally needs ffmpeg/ffprobe and
Linux /proc resource accounting. Nothing is installed or uploaded by this tool.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import selectors
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from typing import Any

WIDTH, HEIGHT, FPS = 960, 720, 30
SEQUENCES = {"walk": (60, "Walk"), "wade": (60, "Wade"), "idle_dolly": (120, "Idle")}
TOTAL_FRAMES = 480
LIMIT = 200 * 1024 * 1024
RESERVE = 2 * 1024 * 1024
RSS_LIMIT = 512 * 1024 * 1024
PHASE_TIMEOUT = 120.0
REPORT_NAME = "avatar_finish_candidate_motion_postflight.json"
CAPTURE_REPORT = "avatar_finish_candidate_motion_report.json"
MAX_JSON_BYTES = 4 * 1024 * 1024
MAX_DIAGNOSTIC_BYTES = 256 * 1024

try:
    from PIL import Image
except ImportError:
    Image = None


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: Any, message: str) -> None:
    if not condition:
        raise ValueError(message)


def strict_json(text: str) -> Any:
    def object_pairs(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"Duplicate JSON key: {key}")
            result[key] = value
        return result

    def reject_constant(value):
        raise ValueError(f"Nonfinite JSON number: {value}")

    def finite_float(value):
        parsed = float(value)
        require(math.isfinite(parsed), f"Nonfinite JSON float: {value}")
        return parsed

    return json.loads(text, object_pairs_hook=object_pairs, parse_constant=reject_constant, parse_float=finite_float)


def finite_number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def checked_file(root: Path, relative: str) -> Path:
    require(isinstance(relative, str) and relative != "", "Empty/non-string evidence path")
    parts = PurePosixPath(relative)
    require(not parts.is_absolute() and ".." not in parts.parts and "\\" not in relative,
            f"Unsafe evidence path: {relative!r}")
    path = root
    for part in parts.parts:
        path = path / part
        require(not path.is_symlink(), f"Symlink evidence is not accepted: {relative}")
    require(path.is_file() and stat.S_ISREG(path.stat().st_mode), f"Missing regular file: {relative}")
    require(path.resolve().is_relative_to(root.resolve()), f"Escaping evidence path: {relative}")
    return path


def tree_size(root: Path) -> int:
    require(root.is_dir() and not root.is_symlink(), "OUT must be a real directory")
    total = 0
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            require(not stat.S_ISLNK(mode), f"Symlink in OUT is not accepted: {path}")
            require(stat.S_ISREG(mode) or stat.S_ISDIR(mode), f"Special file in OUT: {path}")
            if stat.S_ISREG(mode):
                total += path.stat().st_size
    return total


def read_json(path: Path) -> Any:
    require(path.stat().st_size <= MAX_JSON_BYTES, f"Oversized JSON input: {path.name}")
    return strict_json(path.read_text(encoding="utf-8"))


def load_png(path: Path):
    require(Image is not None, "Pillow unavailable: PNG integrity and pixel checks are blocked")
    with Image.open(path) as image:
        require(image.format == "PNG", f"Not a PNG: {path.name}")
        require(image.size == (WIDTH, HEIGHT), f"Wrong PNG dimensions: {path.name}: {image.size}")
        require(getattr(image, "n_frames", 1) == 1, f"Animated PNG is not a single frame: {path.name}")
        require(image.mode in ("RGB", "RGBA"), f"Expected 8-bit RGB/RGBA PNG: {path.name}: {image.mode}")
        image.verify()  # Includes PNG chunk checksums, not merely the IHDR size.
    with Image.open(path) as image:
        image.load()  # Force complete lossless deflate/pixel decoding.
        opaque = image.mode == "RGB" or image.getchannel("A").getextrema() == (255, 255)
        return image.convert("RGB"), opaque


def read_f64(data: bytes, count: int, label: str) -> tuple[float, ...]:
    require(len(data) == count * 8, f"{label}: expected {count} little-endian float64 values")
    values = struct.unpack(f"<{count}d", data)
    require(all(math.isfinite(value) for value in values), f"{label}: nonfinite float64 value")
    return values


def camera_contract(values: tuple[float, ...], sequence: str) -> None:
    require(len(values) == 25, "Camera snapshot must contain 25 float64 values")
    # Transform 0:12 followed by the fixed engine fixture settings.
    require(values[12] == 0.0, "Camera projection is not perspective")
    require(values[13] == (45.0 if sequence == "idle_dolly" else 52.0), "Unexpected camera FOV")
    require(math.isclose(values[14], .01, rel_tol=1e-6) and values[15] == 20.0,
            "Unexpected camera clipping distances")
    require(values[21:25] == (960.0, 720.0, 2.0, 0.0), "Viewport/MSAA/TAA differs from fixed fixture")


def new_report(out: Path, encode: bool) -> dict[str, Any]:
    return {
        "schema_version": 1, "kind": "CPU-only isolated dry cloth matched-motion postflight",
        "out": str(out), "created_utc": datetime.now(timezone.utc).isoformat(),
        "passed": False, "technical_match_passed": False, "failures": [],
        "visual_acceptance": "pending owner paired playback review",
        "shimmer_verdict": "not assessed; exact pose/camera and pixel preservation are not a shimmer verdict",
        "production_approval_provided": False,
        "limits": {"total_output_bytes": LIMIT, "encoder_rss_bytes": RSS_LIMIT,
                   "encoder_cpu_cores": 2, "subprocess_timeout_seconds": PHASE_TIMEOUT},
        "encoding": {"requested": encode, "state": "pending" if encode else "not_requested", "clips": []},
    }


def append_failure(report: dict[str, Any], message: str) -> None:
    if len(report["failures"]) < 100:
        report["failures"].append(message)
    else:
        report["suppressed_failure_count"] = report.get("suppressed_failure_count", 0) + 1


def validate(out: Path, result: dict[str, Any]) -> dict[tuple[str, int, str], dict]:
    """Read-only verification. Returns matched frame records only on a full pass."""
    captures = out / "captures"
    size = tree_size(out)
    result["output_bytes_before_postflight"] = size
    require(size <= LIMIT - RESERVE, "OUT lacks the 2 MiB postflight/receipt reserve within 200 MiB")
    require(captures.is_dir() and not captures.is_symlink(), "Missing real OUT/captures directory")
    report_path = checked_file(captures, CAPTURE_REPORT)
    ledger_path = checked_file(captures, "frames.jsonl")
    source_report = read_json(report_path)
    require(isinstance(source_report, dict), "Capture report must be a JSON object")
    require(source_report.get("passed") is True and source_report.get("failures") == [],
            "Engine capture report is not a clean pass")
    for key, expected in (("frames_written", TOTAL_FRAMES), ("pairs_verified", 240), ("fps", FPS),
                          ("output_limit_bytes", LIMIT), ("restored_surfaces", 2)):
        require(type(source_report.get(key)) is int and source_report[key] == expected,
                f"Capture report {key} must be {expected}")
    require(source_report.get("apply", {}).get("applied_surfaces") == 2, "Expected two applied cloth surfaces")
    require(source_report.get("renderer") == "forward_plus", "Capture renderer must be forward_plus")
    layout = source_report.get("pose_layout", {})
    bones, meshes = layout.get("bones"), layout.get("meshes")
    require(isinstance(bones, list) and bones and all(isinstance(x, str) for x in bones), "Missing bone layout")
    require(isinstance(meshes, list) and meshes and all(isinstance(x, str) for x in meshes), "Missing mesh layout")
    require(len(bones) == len(set(bones)) and len(meshes) == len(set(meshes)), "Duplicate bone/mesh layout entry")
    pose_count = 12 * (2 + len(bones) + len(meshes))
    seq_reports = source_report.get("sequences")
    require(isinstance(seq_reports, list) and len(seq_reports) == 3, "Expected exactly three sequence reports")
    seq_info = {}
    for seq, (expected_frames, clip_label) in SEQUENCES.items():
        matches = [entry for entry in seq_reports if isinstance(entry, dict) and entry.get("name") == seq]
        require(len(matches) == 1, f"Missing/duplicate sequence report: {seq}")
        entry = matches[0]
        require(entry.get("frames_per_state") == expected_frames and entry.get("pairs_verified") == expected_frames
                and entry.get("fps") == FPS, f"Sequence count/fps mismatch: {seq}")
        require(finite_number(entry.get("clip_length")) and entry["clip_length"] > 0, f"Invalid clip length: {seq}")
        clip = entry.get("clip")
        require(isinstance(clip, str) and (clip == clip_label or clip.endswith("/" + clip_label)),
                f"Wrong source animation: {seq}")
        seq_info[seq] = entry
    require(ledger_path.stat().st_size <= MAX_JSON_BYTES, "Frame ledger exceeds 4 MiB")
    lines = ledger_path.read_text(encoding="utf-8").splitlines()
    require(len(lines) == TOTAL_FRAMES, f"Expected 480 frame records, got {len(lines)}")
    records = [strict_json(line) for line in lines]
    expected_order = [(seq, index, state) for seq, (count, _) in SEQUENCES.items()
                      for index in range(count) for state in ("baseline", "candidate")]
    result["input_sha256"] = {CAPTURE_REPORT: file_sha256(report_path), "frames.jsonl": file_sha256(ledger_path)}
    result["capture_metadata"] = {key: source_report.get(key) for key in ("engine", "renderer", "adapter_name")}
    result["pose_layout"] = {"bone_count": len(bones), "mesh_count": len(meshes), "float64_values_per_pose": pose_count}
    lookup, snapshots = {}, {}
    referenced = {CAPTURE_REPORT, "frames.jsonl"}
    capture_bytes = ledger_path.stat().st_size
    opaque_all = True
    previous_engine_frame = -1
    for line_number, (record, expected_key) in enumerate(zip(records, expected_order), 1):
        try:
            require(isinstance(record, dict), "Record must be an object")
            seq, index, state = expected_key
            require(record.get("sequence") == seq and type(record.get("frame")) is int and record["frame"] == index,
                    f"Wrong sequence/frame; expected {seq}/{state}/{index:04d}")
            require(type(record.get("finish")) is bool and record["finish"] == (state == "candidate"), "Wrong finish state")
            require(record.get("clip") == seq_info[seq]["clip"], "Animation name differs from sequence report")
            for key in ("sample_seconds", "clip_time"):
                require(finite_number(record.get(key)), f"Invalid/nonfinite {key}")
            require(math.isclose(record["sample_seconds"], index / FPS, rel_tol=0, abs_tol=1e-12),
                    "Sample time does not equal frame / 30")
            duration = seq_info[seq]["clip_length"]
            expected_clip_time = duration * .25 if seq == "idle_dolly" else math.fmod(index / FPS, duration)
            require(math.isclose(record["clip_time"], expected_clip_time, rel_tol=0, abs_tol=1e-10),
                    "Clip time differs from prescribed exact sampling")
            engine_frame = record.get("engine_process_frame")
            require(type(engine_frame) is int and engine_frame > previous_engine_frame,
                    "Engine process frame counter did not strictly advance")
            previous_engine_frame = engine_frame
            stem = f"{seq}/{state}/{index:04d}"
            payloads = {}
            for kind, suffix in (("image", ".png"), ("pose", ".pose.f64le"), ("camera", ".camera.f64le")):
                relative = stem + suffix
                require(record.get(kind) == relative, f"Unexpected {kind} path")
                path = checked_file(captures, relative)
                require(relative not in referenced, f"Duplicate file reference: {relative}")
                referenced.add(relative)
                byte_count = path.stat().st_size
                require(type(record.get(kind + "_bytes")) is int and record[kind + "_bytes"] == byte_count,
                        f"{kind} byte count mismatch")
                require(byte_count <= (16 * 1024 * 1024 if kind == "image" else 1024 * 1024), f"Oversized {kind} file")
                payload = path.read_bytes()
                require(record.get(kind + "_sha256") == sha256(payload), f"{kind} SHA256 mismatch: {relative}")
                capture_bytes += byte_count
                if kind != "image":
                    payloads[kind] = payload
            pose = read_f64(payloads["pose"], pose_count, "Pose")
            camera = read_f64(payloads["camera"], 25, "Camera")
            camera_contract(camera, seq)
            json_camera = record.get("camera_values")
            require(isinstance(json_camera, list) and len(json_camera) == 25
                    and all(finite_number(value) for value in json_camera), "Invalid camera_values JSON")
            require(all(math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12) for a, b in zip(json_camera, camera)),
                    "camera_values JSON disagrees with raw float64 camera")
            rgb, opaque = load_png(captures / record["image"])
            rgb.close()
            opaque_all = opaque_all and opaque
            lookup[expected_key] = record
            snapshots[expected_key] = (payloads["pose"], payloads["camera"], pose, camera)
        except (ValueError, OSError, KeyError, TypeError, struct.error) as error:
            append_failure(result, f"Frame record {line_number}: {error}")
    actual_files = {str(path.relative_to(captures)) for path in captures.rglob("*") if path.is_file()}
    require(actual_files == referenced, f"Capture file set mismatch; unreferenced={sorted(actual_files - referenced)[:8]}, missing={sorted(referenced - actual_files)[:8]}")
    require(source_report.get("capture_bytes_before_report") == capture_bytes,
            f"Capture byte count mismatch: ledger+assets={capture_bytes}, engine={source_report.get('capture_bytes_before_report')}")
    if "capture_limit_bytes" in source_report:
        limit = source_report["capture_limit_bytes"]
        require(type(limit) is int and 0 < limit <= LIMIT, "Invalid engine capture limit")
        require(capture_bytes <= limit, "Captured assets exceed the engine capture limit")
    result["pngs_opaque"] = opaque_all
    result["validated_frame_records"] = len(lookup)
    result["sequences"] = {}
    pairs = 0
    for seq, (count, _) in SEQUENCES.items():
        if any((seq, index, state) not in lookup for index in range(count) for state in ("baseline", "candidate")):
            continue
        for index in range(count):
            baseline, candidate = (seq, index, "baseline"), (seq, index, "candidate")
            a, b = lookup[baseline], lookup[candidate]
            require(snapshots[baseline][:2] == snapshots[candidate][:2], f"Exact pose/camera byte pair mismatch: {seq}/{index}")
            require(a["sample_seconds"] == b["sample_seconds"] and a["clip_time"] == b["clip_time"],
                    f"Exact timestamp pair mismatch: {seq}/{index}")
            pairs += 1
        states = [snapshots[(seq, index, "baseline")] for index in range(count)]
        pose_unique = len({entry[0] for entry in states})
        # Bone blocks, not only root transforms, must actually animate.
        bone_unique = len({entry[0][24 * 8:(24 + len(bones) * 12) * 8] for entry in states})
        camera_unique = len({entry[1] for entry in states})
        if seq == "idle_dolly":
            require(pose_unique == 1, "Idle pose is not frozen across the dolly")
            require(camera_unique == count, "Dolly camera did not move at every sample")
            require(len({entry[1][12 * 8:] for entry in states}) == 1, "Dolly changed camera projection/settings")
            require(len({entry[1][9 * 8:12 * 8] for entry in states}) == count, "Dolly camera position did not move at every sample")
            require(len({lookup[(seq, index, "baseline")]["clip_time"] for index in range(count)}) == 1,
                    "Idle clip time is not frozen")
        else:
            require(pose_unique > 1 and bone_unique > 1, f"{seq}: no actual sampled skeletal pose variation")
            require(camera_unique == 1, f"{seq}: only the dolly is allowed a moving camera")
        result["sequences"][seq] = {"frames_per_state": count, "matched_pairs": count,
                                     "unique_poses": pose_unique, "unique_bone_poses": bone_unique,
                                     "unique_cameras": camera_unique}
    result["exact_pairs_verified"] = pairs
    result["technical_match_passed"] = not result["failures"] and len(lookup) == TOTAL_FRAMES and pairs == 240
    return lookup if result["technical_match_passed"] else {}


def process_rss(pid: int) -> int:
    total, pending, seen = 0, [pid], set()
    while pending:
        child = pending.pop()
        if child in seen:
            continue
        seen.add(child)
        try:
            for line in Path(f"/proc/{child}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    total += int(line.split()[1]) * 1024
            pending.extend(map(int, Path(f"/proc/{child}/task/{child}/children").read_text().split()))
        except (FileNotFoundError, ProcessLookupError):
            pass
    return total


def bounded_command(command: list[str], out: Path, file_limit: int = RESERVE) -> dict[str, Any]:
    """Own process group only: two-core affinity, time/RSS/file-size/output guards."""
    require(sys.platform.startswith("linux") and Path("/proc/self/status").exists()
            and hasattr(os, "sched_getaffinity"), "Bounded encoding requires Linux /proc and CPU affinity")
    import resource
    cpus = sorted(os.sched_getaffinity(0))[:2]
    require(cpus, "No available CPUs for encoding")

    def child_limits():
        signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGTERM, signal.SIGINT})
        os.sched_setaffinity(0, cpus)
        resource.setrlimit(resource.RLIMIT_CPU, (int(PHASE_TIMEOUT), int(PHASE_TIMEOUT) + 1))
        resource.setrlimit(resource.RLIMIT_FSIZE, (file_limit, file_limit))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    start = time.monotonic()
    result = {"command": command, "cpu_affinity": cpus, "rss_limit_bytes": RSS_LIMIT,
              "timeout_seconds": PHASE_TIMEOUT, "file_limit_bytes": file_limit,
              "peak_aggregate_rss_bytes": 0, "exit_code": None, "reason": ""}
    process, selector, buffers = None, selectors.DefaultSelector(), {"stdout": bytearray(), "stderr": bytearray()}
    try:
        env = dict(os.environ, OMP_NUM_THREADS="2", OPENBLAS_NUM_THREADS="2", MKL_NUM_THREADS="2")
        # Avoid a termination signal landing after fork but before this parent
        # has the child handle needed for its own-process-only cleanup.
        old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
        try:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL,
                                       start_new_session=True, preexec_fn=child_limits, env=env)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        for name in buffers:
            pipe = getattr(process, name)
            os.set_blocking(pipe.fileno(), False)
            selector.register(pipe, selectors.EVENT_READ, name)
        while selector.get_map() or process.poll() is None:
            result["peak_aggregate_rss_bytes"] = max(result["peak_aggregate_rss_bytes"], process_rss(process.pid))
            if result["peak_aggregate_rss_bytes"] > RSS_LIMIT:
                raise RuntimeError("512 MiB aggregate subprocess RSS guard exceeded")
            if time.monotonic() - start > PHASE_TIMEOUT:
                raise RuntimeError("120 second subprocess timeout exceeded")
            if tree_size(out) > LIMIT - RESERVE:
                raise RuntimeError("200 MiB output budget/reserve guard exceeded")
            for key, _ in selector.select(timeout=.05):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    buffers[key.data].extend(chunk)
                    if sum(map(len, buffers.values())) > MAX_DIAGNOSTIC_BYTES:
                        raise RuntimeError("Subprocess diagnostic output exceeded 256 KiB")
        result["exit_code"] = process.wait(timeout=1)
        if result["exit_code"]:
            result["reason"] = "Subprocess exited nonzero"
    except Exception as error:
        result["reason"] = f"{type(error).__name__}: {error}"
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            result["exit_code"] = process.returncode
        selector.close()
        if process:
            for name in buffers:
                getattr(process, name).close()
        result["wall_seconds"] = round(time.monotonic() - start, 3)
        result.update({key: bytes(value).decode("utf-8", errors="replace") for key, value in buffers.items()})
    return result


def paired_pixel_hashes(captures: Path, records: dict, seq: str, count: int) -> list[str]:
    hashes = []
    for index in range(count):
        pair = Image.new("RGB", (WIDTH * 2, HEIGHT))
        for offset, state in ((0, "baseline"), (WIDTH, "candidate")):
            rgb, opaque = load_png(captures / records[(seq, index, state)]["image"])
            require(opaque, "bgr0 cannot preserve nonopaque alpha; encode blocked")
            pair.paste(rgb, (offset, 0))
            rgb.close()
        hashes.append(sha256(pair.tobytes()))
        pair.close()
    return hashes


def encode_clips(out: Path, result: dict, records: dict) -> None:
    encoding = result["encoding"]
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    require(ffmpeg and ffprobe, f"Encoding blocked: ffmpeg={ffmpeg!r}, ffprobe={ffprobe!r}; no tools installed")
    require(result.get("pngs_opaque") is True, "Encoding blocked: bgr0 would discard source alpha")
    clip_dir = out / "paired_lossless"
    require(not clip_dir.exists() and not clip_dir.is_symlink(), "Encoding blocked: paired_lossless already exists; no clips overwritten")
    clip_dir.mkdir()
    for seq, (count, _) in SEQUENCES.items():
        entry = {"sequence": seq, "state": "pending", "layout": "baseline left; candidate right; no scaling or overlays",
                 "expected_frames": count, "width": WIDTH * 2, "height": HEIGHT, "fps": FPS,
                 "codec": "ffv1", "pixel_format": "bgr0", "pixel_verification": "pending"}
        encoding["clips"].append(entry)
        try:
            clip = clip_dir / (seq + "_baseline_left_candidate_right.mkv")
            remaining = LIMIT - RESERVE - tree_size(out)
            require(remaining > 1024 * 1024, "Insufficient remaining output budget for another clip")
            command = [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
                       "-threads", "2", "-filter_threads", "2", "-filter_complex_threads", "2",
                       "-framerate", str(FPS), "-start_number", "0", "-i", str(out / "captures" / seq / "baseline/%04d.png"),
                       "-threads", "2", "-framerate", str(FPS), "-start_number", "0", "-i", str(out / "captures" / seq / "candidate/%04d.png"),
                       "-filter_complex", "[0:v]format=bgr0[l];[1:v]format=bgr0[r];[l][r]hstack=inputs=2[v]",
                       "-map", "[v]", "-an", "-c:v", "ffv1", "-level", "3", "-coder", "1", "-context", "1",
                       "-g", "1", "-slices", "4", "-slicecrc", "1", "-threads", "2", "-pix_fmt", "bgr0",
                       "-frames:v", str(count), "-fps_mode", "passthrough",
                       "-fs", str(remaining), "-f", "matroska", str(clip)]
            entry["encode_process"] = bounded_command(command, out, remaining)
            require(entry["encode_process"]["exit_code"] == 0 and not entry["encode_process"]["reason"],
                    "Encoding failed: " + entry["encode_process"]["reason"] + "; " + entry["encode_process"]["stderr"][-2000:])
            entry["path"] = str(clip.relative_to(out))
            entry["bytes"] = clip.stat().st_size
            entry["sha256"] = file_sha256(clip)
            probe = bounded_command([ffprobe, "-v", "error", "-threads", "2", "-count_frames", "-show_streams", "-show_format",
                                     "-of", "json", str(clip)], out)
            entry["probe_process"] = {key: value for key, value in probe.items() if key != "stdout"}
            require(probe["exit_code"] == 0 and not probe["reason"], "ffprobe failed: " + probe["reason"])
            info = strict_json(probe["stdout"])
            streams = info.get("streams", [])
            require(len(streams) == 1, "Clip must have exactly one video stream and no audio")
            stream = streams[0]
            for key, expected in (("codec_name", "ffv1"), ("pix_fmt", "bgr0"), ("width", WIDTH * 2), ("height", HEIGHT),
                                  ("r_frame_rate", "30/1"), ("avg_frame_rate", "30/1"), ("nb_read_frames", str(count))):
                require(stream.get(key) == expected, f"ffprobe {key}: expected {expected!r}, got {stream.get(key)!r}")
            entry["ffprobe"] = info
            expected_hashes = paired_pixel_hashes(out / "captures", records, seq, count)
            decoded = bounded_command([ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-threads", "2",
                                       "-filter_threads", "2", "-i", str(clip), "-map", "0:v:0", "-an", "-c:v", "rawvideo",
                                       "-pix_fmt", "rgb24", "-threads", "2", "-f", "framehash", "-hash", "sha256", "-"], out)
            entry["decode_process"] = {key: value for key, value in decoded.items() if key != "stdout"}
            require(decoded["exit_code"] == 0 and not decoded["reason"], "Lossless decode check failed: " + decoded["reason"])
            require("#tb 0: 1/30" in decoded["stdout"], "Decoded frame timebase is not 1/30")
            rows = [row.split(",") for row in decoded["stdout"].splitlines() if row and not row.startswith("#")]
            require(len(rows) == count, f"Decoded frame hash count mismatch: {len(rows)} != {count}")
            for index, (row, expected_hash) in enumerate(zip(rows, expected_hashes)):
                values = [value.strip() for value in row]
                require(len(values) == 6 and list(map(int, values[:5])) == [0, index, index, 1, WIDTH * 2 * HEIGHT * 3],
                        f"Decoded frame {index}: timestamp/pixel-byte-size mismatch")
                require(values[5] == expected_hash, f"Decoded frame {index}: RGB pixels differ from original PNG pair")
            require(file_sha256(clip) == entry["sha256"], "Clip changed during verification")
            entry["decoded_rgb_frame_sha256"] = expected_hashes
            entry["pixel_verification"] = "all decoded RGB bytes match original full-resolution PNG pair"
            entry["state"] = "verified_lossless"
        except Exception as error:
            entry["state"] = "blocked_or_failed"
            entry["reason"] = f"{type(error).__name__}: {error}"
            raise
    # Bind the derived clips to the same immutable inputs audited initially.
    for name, digest in result["input_sha256"].items():
        require(file_sha256(out / "captures" / name) == digest, f"Input changed during encoding: {name}")
    for record in records.values():
        for kind in ("image", "pose", "camera"):
            path = checked_file(out / "captures", record[kind])
            require(file_sha256(path) == record[kind + "_sha256"], f"Input changed during encoding: {record[kind]}")
    encoding["source_inputs_unchanged_after_encoding"] = True
    encoding["state"] = "verified_lossless"


def write_report(out: Path, report: dict) -> Path:
    """Exclusive creation even on a failed run. Never replace prior evidence."""
    require(not any(parent.is_symlink() for parent in out.absolute().parents), "Cannot write through a symlink OUT ancestor")
    require(not out.is_symlink(), "Cannot write postflight into a symlink OUT")
    out.mkdir(parents=True, exist_ok=True)
    require(out.is_dir(), "Cannot write postflight into a non-directory OUT")
    for index in range(10000):
        name = REPORT_NAME if index == 0 else REPORT_NAME.removesuffix(".json") + f"_{index:04d}.json"
        path = out / name
        report["postflight_report"] = str(path)
        payload = (json.dumps(report, indent=2, allow_nan=False) + "\n").encode()
        # Include this report itself in the final on-disk budget accounting.
        for _ in range(4):
            try:
                report["output_bytes_including_this_report"] = tree_size(out) + len(payload)
                if report["output_bytes_including_this_report"] > LIMIT:
                    report["passed"] = False
                    message = "Final OUT including postflight exceeds 200 MiB"
                    if message not in report["failures"]:
                        append_failure(report, message)
            except (ValueError, OSError) as error:
                report["output_budget_state"] = f"unverifiable: {error}"
                report["passed"] = False
            payload = (json.dumps(report, indent=2, allow_nan=False) + "\n").encode()
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
        except FileExistsError:
            continue
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        return path
    raise RuntimeError("Too many prior postflight reports; none overwritten")


def run(out: Path, encode: bool) -> dict:
    # An OUT symlink is refused before resolve() so no writer follows it.
    result = new_report(out.absolute(), encode)
    try:
        require(not out.is_symlink(), "OUT must not be a symlink")
        require(not any(parent.is_symlink() for parent in out.absolute().parents), "OUT has a symlink ancestor")
        records = validate(out, result)
        if encode and result["technical_match_passed"]:
            encode_clips(out, result, records)
        elif encode:
            result["encoding"]["state"] = "blocked_by_capture_validation"
    except Exception as error:
        append_failure(result, f"{type(error).__name__}: {error}")
        if encode and result["encoding"]["state"] == "pending":
            result["encoding"]["state"] = "blocked_or_failed"
    result["passed"] = result["technical_match_passed"] and not result["failures"]
    result["completed_utc"] = datetime.now(timezone.utc).isoformat()
    try:
        write_report(out, result)
    except Exception as error:
        result["passed"] = False
        append_failure(result, f"Postflight file write blocked: {type(error).__name__}: {error}")
    return result


def synthetic_fixture(out: Path) -> None:
    """Tiny on disk but full 480-frame/960x720 contract, explicitly synthetic."""
    require(Image is not None, "Pillow is required for synthetic self-test")
    captures = out / "captures"
    captures.mkdir(parents=True)
    bones, meshes = ["root", "upper_arm"], ["shirt", "trousers"]
    records, engine_frame, asset_bytes = [], 10, 0
    identity = [1., 0., 0., 0., 1., 0., 0., 0., 1., 0., 0., 0.]
    for seq, (count, clip) in SEQUENCES.items():
        for index in range(count):
            pose = identity * (2 + len(bones) + len(meshes))
            if seq != "idle_dolly":
                pose[24 + 9] = math.sin(index / 30 * math.pi)
            camera = identity + [0., 45. if seq == "idle_dolly" else 52., .01, 20., 1., 0., 0., 1., 524287., 960., 720., 2., 0.]
            if seq == "idle_dolly":
                camera[9] = index / 120
            for state in ("baseline", "candidate"):
                engine_frame += 1
                stem = f"{seq}/{state}/{index:04d}"
                (captures / stem).parent.mkdir(parents=True, exist_ok=True)
                record = dict(sequence=seq, frame=index, finish=state == "candidate", sample_seconds=index / FPS,
                              clip=clip, clip_time=.25 if seq == "idle_dolly" else math.fmod(index / FPS, 1.),
                              camera_values=camera, engine_process_frame=engine_frame)
                color = (index % 256, 20 if state == "baseline" else 30, 50)
                image = Image.new("RGB", (WIDTH, HEIGHT), color)
                image.save(captures / (stem + ".png"), format="PNG")
                image.close()
                for kind, suffix, payload in (("image", ".png", None),
                                               ("pose", ".pose.f64le", struct.pack(f"<{len(pose)}d", *pose)),
                                               ("camera", ".camera.f64le", struct.pack("<25d", *camera))):
                    path = captures / (stem + suffix)
                    if payload is not None:
                        path.write_bytes(payload)
                    payload = path.read_bytes()
                    record.update({kind: stem + suffix, kind + "_bytes": len(payload), kind + "_sha256": sha256(payload)})
                    asset_bytes += len(payload)
                records.append(record)
    ledger = "".join(json.dumps(record, separators=(",", ":")) + "\n" for record in records)
    (captures / "frames.jsonl").write_text(ledger)
    report = dict(passed=True, failures=[], frames_written=480, pairs_verified=240, fps=30,
                  output_limit_bytes=LIMIT, restored_surfaces=2, apply={"applied_surfaces": 2},
                  renderer="forward_plus", engine={"synthetic": True}, adapter_name="synthetic CPU-only fixture, not rendered",
                  pose_layout={"bones": bones, "meshes": meshes}, capture_bytes_before_report=asset_bytes + len(ledger.encode()),
                  sequences=[dict(name=seq, clip=clip, clip_length=1., frames_per_state=count, pairs_verified=count, fps=30)
                             for seq, (count, clip) in SEQUENCES.items()])
    (captures / CAPTURE_REPORT).write_text(json.dumps(report))


def self_test(encode: bool) -> dict:
    with tempfile.TemporaryDirectory(prefix="avatar-motion-cpu-selftest-") as directory:
        out = Path(directory)
        synthetic_fixture(out)
        original = run(out, encode)
        require(original["passed"], "Valid synthetic fixture failed: " + json.dumps(original["failures"]))
        checks = ["480-frame valid synthetic fixture", "exact pair/count/time/pose/camera checks", "PNG decode/checksums"]
        if encode:
            require(original["encoding"]["state"] == "verified_lossless", "Synthetic lossless clip encoding failed")
            checks.append("three FFV1/bgr0 clips: ffprobe and every decoded full-resolution RGB frame hash")
        # Tamper a raw snapshot without updating its recorded digest.
        target = out / "captures/walk/candidate/0000.pose.f64le"
        before = target.read_bytes()
        target.write_bytes(before[:-1] + bytes([before[-1] ^ 1]))
        corrupted = run(out, False)
        require(not corrupted["passed"] and any("SHA256 mismatch" in value for value in corrupted["failures"]), "Tamper test was not rejected")
        require(Path(corrupted["postflight_report"]).exists(), "Failure report was not written")
        target.write_bytes(before)
        checks.append("tampered raw SHA256 rejected with preserved failure report")
        for values, label in (([float("nan")], "NaN"), ([float("inf")], "Infinity")):
            try:
                read_f64(struct.pack("<d", *values), 1, "synthetic")
            except ValueError:
                checks.append(label + " float64 rejected")
            else:
                raise AssertionError(label + " incorrectly accepted")
        try:
            strict_json('{"overflow": 1e999}')
        except ValueError:
            checks.append("overflowed JSON float rejected")
        else:
            raise AssertionError("Overflowed JSON float incorrectly accepted")
        try:
            strict_json('{"frame": 1, "frame": 2}')
        except ValueError:
            checks.append("duplicate JSON keys rejected")
        else:
            raise AssertionError("Duplicate JSON keys incorrectly accepted")
        require(len(list(out.glob("avatar_finish_candidate_motion_postflight*.json"))) == 2, "Prior report was overwritten")
        checks.append("repeat postflight preserved its predecessor")
        ledger_path, source_report_path = out / "captures/frames.jsonl", out / "captures" / CAPTURE_REPORT
        ledger_original, report_original = ledger_path.read_bytes(), source_report_path.read_bytes()
        baseline_records = [strict_json(line) for line in ledger_original.decode().splitlines()]

        def adversarial_case(label, expected_error, mutate):
            records = [dict(record) for record in baseline_records]
            backups = {}

            def edit(seq, index, state, kind, float_index, value):
                record = next(record for record in records if record["sequence"] == seq and record["frame"] == index
                              and record["finish"] == (state == "candidate"))
                path = out / "captures" / record[kind]
                backups.setdefault(path, path.read_bytes())
                raw = bytearray(path.read_bytes())
                struct.pack_into("<d", raw, float_index * 8, value)
                path.write_bytes(raw)
                record[kind + "_sha256"] = sha256(raw)
                if kind == "camera":
                    record["camera_values"] = list(struct.unpack("<25d", raw))

            try:
                mutate(records, edit)
                ledger = "".join(json.dumps(record, separators=(",", ":")) + "\n" for record in records).encode()
                ledger_path.write_bytes(ledger)
                source = strict_json(report_original.decode())
                source["capture_bytes_before_report"] += len(ledger) - len(ledger_original)
                source_report_path.write_text(json.dumps(source))
                failed = run(out, False)
                require(not failed["passed"] and any(expected_error in error for error in failed["failures"]),
                        f"{label} was not rejected correctly: {failed['failures']}")
                checks.append(label)
            finally:
                for path, raw in backups.items():
                    path.write_bytes(raw)
                ledger_path.write_bytes(ledger_original)
                source_report_path.write_bytes(report_original)

        adversarial_case("rehashed unequal raw pair rejected", "byte pair mismatch",
                         lambda records, edit: edit("walk", 0, "candidate", "pose", 1, -0.0))
        adversarial_case("rehashed frozen Walk skeleton rejected", "no actual sampled skeletal pose variation",
                         lambda records, edit: [edit("walk", frame, state, "pose", 33, 0.)
                                                for frame in range(60) for state in ("baseline", "candidate")])
        adversarial_case("rehashed moving Idle pose rejected", "Idle pose is not frozen",
                         lambda records, edit: [edit("idle_dolly", 10, state, "pose", 33, .1)
                                                for state in ("baseline", "candidate")])
        adversarial_case("rehashed moving fixed Walk camera rejected", "only the dolly is allowed",
                         lambda records, edit: [edit("walk", 10, state, "camera", 9, .1)
                                                for state in ("baseline", "candidate")])
        adversarial_case("rehashed stationary Dolly camera rejected", "Dolly camera did not move",
                         lambda records, edit: [edit("idle_dolly", frame, state, "camera", 9, 0.)
                                                for frame in range(120) for state in ("baseline", "candidate")])
        adversarial_case("near-equal but nonexact pair time rejected", "Exact timestamp pair mismatch",
                         lambda records, edit: records[1].update(sample_seconds=1e-14))
        clips = [{"sequence": clip["sequence"], "bytes": clip["bytes"],
                  "encode_seconds": clip["encode_process"]["wall_seconds"],
                  "peak_rss_bytes": clip["encode_process"]["peak_aggregate_rss_bytes"]}
                 for clip in original["encoding"]["clips"]]
        return {"passed": True, "synthetic_only": True, "checks": checks, "clips": clips,
                "temporary_fixture_cleaned": True, "native_engine_started": False,
                "shimmer_verdict": "not assessed"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", nargs="?", type=Path, help="Run directory containing captures/")
    parser.add_argument("--encode", action="store_true", help="Add and pixel-verify three bounded lossless paired clips")
    parser.add_argument("--self-test", action="store_true", help="Use a temporary synthetic fixture, never native evidence")
    args = parser.parse_args()

    def interrupted(signum, frame):
        # Raise through bounded_command's finally so detached child sessions
        # cannot survive an outer watchdog terminating this validator.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise RuntimeError(f"Interrupted by {signal.Signals(signum).name}; owned subprocess cleanup requested")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    if args.self_test:
        if args.out is not None:
            parser.error("--self-test does not accept OUT; it uses and cleans its own temporary directory")
        try:
            result = self_test(args.encode)
        except Exception as error:
            result = {"passed": False, "synthetic_only": True, "failure": f"{type(error).__name__}: {error}"}
    else:
        if args.out is None:
            parser.error("OUT is required unless --self-test is used")
        result = run(args.out.absolute(), args.encode)
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
