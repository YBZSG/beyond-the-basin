#!/usr/bin/env python3
"""Read-only RGB8 temporal residual audit; NOT a visual/shimmer acceptance test.

Requires existing Python, NumPy and Pillow. No engine, display, network or encoder.
Usage:
  python3 avatar_finish_candidate_temporal_residuals.py --self-test
  python3 avatar_finish_candidate_temporal_residuals.py RUN_DIRECTORY
  python3 avatar_finish_candidate_temporal_residuals.py RUN_DIRECTORY --verify-existing

The normal command exclusively creates one new JSON report, never overwriting it.
--verify-existing recomputes and compares all deterministic results without writes.
Input captures, native receipts, clips, materials and geometry are never modified.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import platform
import sys

import numpy as np
from PIL import Image, __version__ as PILLOW_VERSION


REPORT = "avatar_finish_candidate_temporal_residuals.json"
POSTFLIGHT = "avatar_finish_candidate_motion_postflight.json"
CAPTURE_REPORT = "avatar_finish_candidate_motion_report.json"
SEQUENCES = {"walk": 60, "wade": 60, "idle_dolly": 120}
WIDTH, HEIGHT, FPS = 960, 720, 30
LIMIT = 200 * 1024 * 1024
PERCENTILES = (50, 90, 95, 99)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def safe_file(root, relative):
    parts = PurePosixPath(relative)
    require(not parts.is_absolute() and ".." not in parts.parts and "\\" not in relative,
            f"Unsafe evidence path: {relative}")
    path = root
    for part in parts.parts:
        path /= part
        require(not path.is_symlink(), f"Symlink evidence rejected: {relative}")
    require(path.is_file(), f"Missing evidence: {relative}")
    return path


def tree_bytes(root):
    total = 0
    for path in root.rglob("*"):
        require(not path.is_symlink(), f"Symlink in run rejected: {path}")
        if path.is_file():
            total += path.stat().st_size
        else:
            require(path.is_dir(), f"Non-regular evidence: {path}")
    return total


def strict_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f"Duplicate JSON key: {key}")
            result[key] = value
        return result

    def reject(value):
        raise ValueError(f"Non-finite JSON value: {value}")

    return json.loads(data, object_pairs_hook=pairs, parse_constant=reject)


def rgb8(data, label):
    with Image.open(io.BytesIO(data)) as image:
        require(image.format == "PNG" and image.size == (WIDTH, HEIGHT),
                f"PNG format/dimension mismatch: {label}")
        require(image.mode in ("RGB", "RGBA") and getattr(image, "n_frames", 1) == 1,
                f"Not single-frame RGB8/RGBA8: {label}")
        image.verify()
    with Image.open(io.BytesIO(data)) as image:
        image.load()
        require(image.mode == "RGB" or image.getchannel("A").getextrema() == (255, 255),
                f"Nonopaque PNG: {label}")
        # Convert BEFORE subtraction. Residual range +/-255, delta range +/-510.
        return np.asarray(image.convert("RGB"), dtype=np.int16)


def number(value):
    return round(float(value), 9)


def quantile(histogram, percentile):
    count = int(histogram.sum())
    if not count:
        return None
    rank = max(1, math.ceil(count * percentile / 100))
    return int(np.searchsorted(np.cumsum(histogram), rank))


def magnitude_distribution(histogram):
    count = int(histogram.sum())
    if not count:
        return {"samples": 0, "mean": None, "rms": None, "max": None,
                "absolute_percentiles": {str(p): None for p in PERCENTILES}}
    values = np.arange(histogram.size, dtype=np.float64)
    return {
        "samples": count,
        "mean": number(np.dot(histogram, values) / count),
        "rms": number(math.sqrt(np.dot(histogram, values * values) / count)),
        "max": int(np.flatnonzero(histogram)[-1]),
        "absolute_percentiles": {str(p): quantile(histogram, p) for p in PERCENTILES},
    }


class Accumulator:
    """Fixed-size exact integer histograms; no video-sized in-memory allocation."""

    def __init__(self, bound):
        self.bound = bound
        self.signed_hist = np.zeros((3, 2 * bound + 1), dtype=np.int64)
        self.pixel_max_hist = np.zeros(bound + 1, dtype=np.int64)

    def add(self, signed):
        require(signed.dtype == np.int16 and signed.ndim == 3 and signed.shape[2] == 3,
                "Expected HxWx3 signed int16 values")
        require(int(signed.min()) >= -self.bound and int(signed.max()) <= self.bound,
                "Signed values exceed mathematical range")
        for channel in range(3):
            self.signed_hist[channel] += np.bincount(
                (signed[..., channel].ravel() + self.bound), minlength=2 * self.bound + 1)
        absolute = np.abs(signed)
        pixel_max = np.max(absolute, axis=2)
        histogram = np.bincount(pixel_max.ravel(), minlength=self.bound + 1)
        self.pixel_max_hist += histogram
        # Convert to float64 before square; int16 square would overflow.
        as_float = signed.astype(np.float64)
        return [
            int(pixel_max.size - histogram[0]),
            number(np.mean(absolute)),
            number(math.sqrt(np.mean(as_float * as_float))),
            number(np.mean(pixel_max)),
            int(np.max(pixel_max)),
        ]

    def channel_stats(self, histogram):
        values = np.arange(-self.bound, self.bound + 1, dtype=np.int64)
        absolute_hist = np.zeros(self.bound + 1, dtype=np.int64)
        np.add.at(absolute_hist, np.abs(values), histogram)
        result = magnitude_distribution(absolute_hist)
        result["signed_mean"] = number(np.dot(histogram, values) / int(histogram.sum()))
        occupied = np.flatnonzero(histogram)
        result["signed_min"] = int(values[occupied[0]])
        result["signed_max"] = int(values[occupied[-1]])
        return result

    def finish(self):
        nonzero_hist = self.pixel_max_hist.copy()
        nonzero_hist[0] = 0
        return {
            "channel_absolute_and_signed": {
                "pooled_RGB": self.channel_stats(self.signed_hist.sum(axis=0)),
                **{label: self.channel_stats(self.signed_hist[index])
                   for index, label in enumerate(("R", "G", "B"))},
            },
            "pixel_max_absolute_channel": {
                "whole_frame": magnitude_distribution(self.pixel_max_hist),
                "nonzero_support_only": magnitude_distribution(nonzero_hist),
                "nonzero_support_fraction": number(nonzero_hist.sum() / self.pixel_max_hist.sum()),
            },
        }


def read_metadata(out):
    filenames = [f"captures/{CAPTURE_REPORT}", "captures/frames.jsonl", POSTFLIGHT,
                 "postflight_receipt.json", "completed_exit_receipt.json"]
    data = {name: safe_file(out, name).read_bytes() for name in filenames}
    hashes = {name: sha256(value) for name, value in data.items()}
    capture = strict_json(data[f"captures/{CAPTURE_REPORT}"])
    postflight = strict_json(data[POSTFLIGHT])
    receipt = strict_json(data["postflight_receipt.json"])
    completed = strict_json(data["completed_exit_receipt.json"])
    require(postflight.get("passed") is True and postflight.get("technical_match_passed") is True
            and postflight.get("failures") == [], "Existing postflight is not a clean technical pass")
    require(postflight.get("exact_pairs_verified") == 240 and postflight.get("pngs_opaque") is True,
            "Postflight pair count/opacity mismatch")
    require(capture.get("passed") is True and capture.get("failures") == []
            and capture.get("pairs_verified") == 240 and capture.get("frames_written") == 480
            and capture.get("fps") == FPS, "Capture report is not the expected completed pass")
    require(receipt.get("completed") is True and receipt.get("exit_code") == 0,
            "Postflight exit receipt is not successful")
    require(completed.get("completed") is True and completed.get("exit_code") == 0
            and completed.get("technical_pass") is True and completed.get("production_enabled") is False,
            "Completed native receipt does not establish successful isolated run")
    for name in (CAPTURE_REPORT, "frames.jsonl"):
        require(postflight.get("input_sha256", {}).get(name) == hashes[f"captures/{name}"],
                f"Current {name} does not match existing postflight input hash")
    records = [strict_json(line) for line in data["captures/frames.jsonl"].splitlines()]
    require(len(records) == 480, "Expected 480 ledger records")
    return hashes, records, capture, postflight


def validate_pairs(out, records, capture, postflight):
    """Check EVERY pose/camera pair and all file hashes before metric computation."""
    captures = out / "captures"
    pairs = {}
    position = 0
    capture_sequences = {entry["name"]: entry for entry in capture["sequences"]}
    require(set(capture_sequences) == set(SEQUENCES), "Unexpected capture sequences")
    for sequence, count in SEQUENCES.items():
        require(capture_sequences[sequence]["frames_per_state"] == count
                and postflight["sequences"][sequence]["matched_pairs"] == count,
                f"Sequence frame count mismatch: {sequence}")
        pairs[sequence] = []
        for frame in range(count):
            pair = records[position:position + 2]
            position += 2
            for record, state in zip(pair, ("baseline", "candidate")):
                require(record["sequence"] == sequence and type(record["frame"]) is int
                        and record["frame"] == frame and record["finish"] is (state == "candidate"),
                        f"Unexpected ledger ordering: {sequence}/{frame}/{state}")
                require(math.isclose(record["sample_seconds"], frame / FPS, abs_tol=1e-12),
                        f"Non-contiguous sample timing: {sequence}/{frame}")
                for kind, suffix in (("image", "png"), ("pose", "pose.f64le"), ("camera", "camera.f64le")):
                    relative = f"{sequence}/{state}/{frame:04d}.{suffix}"
                    require(record[kind] == relative, f"Unexpected {kind} path")
                    data = safe_file(captures, relative).read_bytes()
                    require(len(data) == record[f"{kind}_bytes"] and sha256(data) == record[f"{kind}_sha256"],
                            f"Current {kind} differs from ledger: {relative}")
            for field in ("pose_sha256", "camera_sha256", "clip", "clip_time", "sample_seconds", "camera_values"):
                require(pair[0][field] == pair[1][field],
                        f"Baseline/candidate {field} mismatch: {sequence}/{frame}")
            pairs[sequence].append(pair)
    return pairs


def frame_reference(sequence, frame, temporal=False):
    indices = [frame - 1, frame] if temporal else [frame]
    return {
        "sequence": sequence,
        "frames": indices,
        "sample_seconds": [number(index / FPS) for index in indices],
        "baseline_images": [f"captures/{sequence}/baseline/{index:04d}.png" for index in indices],
        "candidate_images": [f"captures/{sequence}/candidate/{index:04d}.png" for index in indices],
    }


def worst_records(sequence, rows, temporal=False):
    result = {}
    for label, column in (("highest_whole_frame_channel_MAE", 2),
                          ("highest_single_pixel_channel_magnitude", 5)):
        value = max(row[column] for row in rows)
        tied = [row for row in rows if row[column] == value]
        result[label] = {
            "value_RGB8_code_values": value,
            "tie_count": len(tied),
            "first_tied_reference": frame_reference(sequence, tied[0][0], temporal),
            "all_tied_frame_indices": [row[0] for row in tied],
        }
    return result


def compute_sequences(out, pairs):
    sequences = {}
    for sequence, matching in pairs.items():
        residual_acc = Accumulator(255)
        delta_acc = Accumulator(510)
        residual_rows, delta_rows = [], []
        previous = None
        for frame, pair in enumerate(matching):
            images = []
            for record in pair:
                data = safe_file(out / "captures", record["image"]).read_bytes()
                require(sha256(data) == record["image_sha256"], "Image changed after validation")
                images.append(rgb8(data, record["image"]))
            residual = images[1] - images[0]
            residual_rows.append([frame, *residual_acc.add(residual)])
            if previous is not None:
                delta = residual - previous
                delta_rows.append([frame, *delta_acc.add(delta)])
            previous = residual
        sequences[sequence] = {
            "matched_frames": len(matching),
            "adjacent_pairs": len(delta_rows),
            "unique_pose_hashes": len({pair[0]["pose_sha256"] for pair in matching}),
            "unique_camera_hashes": len({pair[0]["camera_sha256"] for pair in matching}),
            "residual_candidate_minus_baseline": residual_acc.finish(),
            "temporal_delta_of_residual": delta_acc.finish(),
            "largest_residual_frames": worst_records(sequence, residual_rows),
            "largest_temporal_delta_pairs": worst_records(sequence, delta_rows, temporal=True),
            "residual_per_frame": residual_rows,
            "temporal_delta_per_adjacent_pair": delta_rows,
        }
    return sequences


def self_test():
    baseline = np.array([[[255, 0, 0], [0, 0, 0]]], dtype=np.uint8)
    candidate = np.array([[[0, 255, 0], [0, 0, 0]]], dtype=np.uint8)
    residual = candidate.astype(np.int16) - baseline.astype(np.int16)
    require(residual.tolist() == [[[-255, 255, 0], [0, 0, 0]]], "Signed subtraction self-test failed")
    acc = Accumulator(255)
    row = acc.add(residual)
    result = acc.finish()
    require(row[0] == 1 and row[1] == 85.0 and row[4] == 255, "Residual stats self-test failed")
    require(result["channel_absolute_and_signed"]["pooled_RGB"]["signed_mean"] == 0,
            "Signed mean self-test failed")
    require(result["pixel_max_absolute_channel"]["nonzero_support_fraction"] == .5,
            "Support denominator self-test failed")
    delta = -residual - residual
    acc = Accumulator(510)
    delta_row = acc.add(delta)
    require(delta.tolist() == [[[510, -510, 0], [0, 0, 0]]] and delta_row[4] == 510,
            "Temporal signed range self-test failed")
    require(abs(delta_row[2] - math.sqrt(2 * 510 ** 2 / 6)) < 1e-8,
            "Squared-value overflow self-test failed")
    zeros = Accumulator(255)
    zeros.add(np.zeros((1, 2, 3), dtype=np.int16))
    require(zeros.finish()["pixel_max_absolute_channel"]["nonzero_support_only"]["mean"] is None,
            "Empty support self-test failed")
    require(quantile(np.array([1, 2, 1]), 50) == 1, "Nearest-rank percentile self-test failed")
    print("Self-test passed: signed residual +/-255, temporal +/-510, float64 squares, exact histograms, empty support.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify-existing", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    require(args.run_directory is not None, "Provide RUN_DIRECTORY or --self-test")
    out = args.run_directory.resolve()
    require(out.is_dir(), "Run directory missing")
    target = out / REPORT
    require(args.verify_existing or not target.exists(), "Report exists; use --verify-existing, never overwrite")
    before = tree_bytes(out)
    require(before < LIMIT, "Run is already at/above 200 MiB")
    hashes, records, capture, postflight = read_metadata(out)
    pairs = validate_pairs(out, records, capture, postflight)
    script_hash = sha256(Path(__file__).read_bytes())
    report = {
        "schema_version": 1,
        "kind": "CPU-only matched dry-cloth RGB8 residual diagnostics, no visual verdict",
        "input_sha256": hashes,
        "script_sha256": script_hash,
        "runtime": {"python": platform.python_version(), "numpy": np.__version__, "pillow": PILLOW_VERSION},
        "verification": {
            "existing_postflight_clean_pass": True,
            "postflight_inputs_match_current_ledger_and_capture_report": True,
            "current_image_pose_camera_files_match_ledger": True,
            "exact_pose_camera_and_sample_time_pairs_checked_before_computation": 240,
            "dimensions": [WIDTH, HEIGHT], "fps": FPS,
        },
        "method": {
            "residual": "R_t(x,y,c) = candidate_t(x,y,c) - baseline_t(x,y,c)",
            "temporal_delta": "D_t(x,y,c) = R_t(x,y,c) - R_(t-1)(x,y,c), only consecutive frames within each sequence; no last-to-first wrap",
            "arithmetic": "Decode unchanged opaque PNG RGB8; cast both inputs to int16 before subtraction; signed residual +/-255 and signed temporal delta +/-510; float64 before square; int64 exact histogram counts",
            "units": "Every intensity magnitude, mean, RMS and percentile is in RGB8 code values. Divide by 255 for full-scale normalized RGB8 units, including temporal delta (not /510). These are encoded pixel values, not linear-light radiance or physical luminance; no gamma conversion is applied.",
            "aggregation": "Pool all pixel/channel observations across each sequence, not averages of frame percentiles. Pooled_RGB has 3 samples per pixel; R/G/B each have one. Pixel_max_absolute_channel has one sample per pixel: max(abs(value_R), abs(value_G), abs(value_B)).",
            "percentiles": "Exact integer histogram nearest-rank inverse empirical CDF (first magnitude with cumulative count >= ceil(p*N/100)); no interpolation",
            "support": "Data-dependent nonzero support means pixel_max_absolute_channel > 0. Residual and delta have independently defined support. This is NOT a cloth, body, foreground or semantic segmentation; selecting changed pixels conditions the distribution on the observed difference.",
            "whole_frame": "All 960x720 pixels are included; unchanged background dilutes whole-frame means and percentiles. Support-only pixel-max statistics are separately labeled and have a different denominator.",
            "per_frame_columns": ["frame_index (delta row pairs previous frame with this frame)", "nonzero_pixels", "whole_frame_channel_MAE", "whole_frame_channel_RMS", "whole_frame_pixel_max_channel_mean", "maximum_absolute_channel_value"],
            "ranking": "Largest/worst identifiers rank raw numeric magnitude or whole-frame channel MAE only, not visual quality; ties are retained. No acceptance thresholds are used.",
        },
        "limitations": [
            "No optical flow, motion compensation, reprojection, cloth mask, temporal filter, registration across time or perceptual model is used.",
            "Baseline and candidate match pose/camera at the SAME frame, but moving geometry or camera means the SAME pixel location need not represent the same surface at adjacent times.",
            "Legitimate moving fabric detail/grain, edge coverage, lighting, occlusion and disocclusion can change the residual. These raw metrics cannot prove or reject shimmer, flicker, aliasing or perceptual stability.",
            "Evidence is this isolated dry-cloth fixture and existing native captures only, not gameplay, wetness, all viewing distances, GPU performance or a production acceptance test.",
        ],
        "shimmer_verdict": "not assessed; owner paired playback review remains required",
        "production_approval_provided": False,
        "source_material_and_geometry_modified": False,
        "sequences": compute_sequences(out, pairs),
    }
    # Ensure receipts/ledger/report did not change during this read-only computation.
    for name, expected in hashes.items():
        require(sha256(safe_file(out, name).read_bytes()) == expected, f"Metadata changed during audit: {name}")
    require(sha256(Path(__file__).read_bytes()) == script_hash, "Audit script changed while running")
    if args.verify_existing:
        existing_bytes = safe_file(out, REPORT).read_bytes()
        existing = strict_json(existing_bytes)
        for key, value in report.items():
            require(existing.get(key) == value, f"Recomputed result differs: {key}")
        print(json.dumps({"verified_existing_report": str(target), "sha256": sha256(existing_bytes),
                          "deterministic_results_match": True, "run_bytes": tree_bytes(out)}))
        return
    require(tree_bytes(out) == before, "Run file sizes changed during audit")
    report["created_utc"] = datetime.now(timezone.utc).isoformat()
    report["storage"] = {"run_bytes_before": before, "report_bytes": 0,
                         "run_bytes_including_report": before, "run_limit_bytes": LIMIT}
    for _ in range(10):
        encoded = (json.dumps(report, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode()
        if report["storage"]["report_bytes"] == len(encoded):
            break
        report["storage"]["report_bytes"] = len(encoded)
        report["storage"]["run_bytes_including_report"] = before + len(encoded)
    require(report["storage"]["report_bytes"] == len(encoded), "Report size accounting did not converge")
    require(before + len(encoded) < LIMIT, "Report would exceed 200 MiB run limit")
    require(len(encoded) <= 128 * 1024, "Compact report exceeds 128 KiB")
    with target.open("xb") as stream:
        stream.write(encoded)
    print(json.dumps({"created_report": str(target), "sha256": sha256(encoded),
                      "report_bytes": len(encoded), "run_bytes": tree_bytes(out),
                      "matched_frames": 240, "adjacent_pairs": 237,
                      "shimmer_verdict": "not assessed"}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(f"Temporal residual audit blocked: {exc}", file=sys.stderr)
        sys.exit(1)
