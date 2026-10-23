#!/usr/bin/env python3
"""Read native owner-lifecycle logs. Never launches Godot or infers leaks from bytes."""
import argparse
import json
import re
from pathlib import Path


def analyze(path: Path) -> dict:
    text = path.read_text(errors="replace")
    result = None
    report_count = 0
    parse_errors = []
    for line in text.splitlines():
        match = re.fullmatch(r"SOURCE_RUNTIME_LIFECYCLE_(PASS|FAIL) (\{.*\})", line)
        if match:
            report_count += 1
            try:
                candidate = json.loads(match.group(2))
            except json.JSONDecodeError as error:
                parse_errors.append(str(error))
                continue
            result = candidate
            result["fixture_pass"] = match.group(1) == "PASS" and not result.get("failures", [])
    warnings = [line for line in text.splitlines() if "leaked" in line.lower()]
    rd_textures = sum(int(n) for n in re.findall(r'([0-9]+) RIDs of type "Texture" were leaked', text))
    rows = result.get("rows", []) if result else []
    textures = [row["after_dispose"]["texture_bytes"] for row in rows]
    buffers = [row["after_dispose"]["buffer_bytes"] for row in rows]
    ownership = []
    for row in rows:
        before = row.get("ownership_before", {})
        after = row.get("ownership_after", {})
        if not before or not after:
            continue
        ownership.append({
            "cycle": row["cycle"],
            "recorded_owned_textures": before["remembered_textures"],
            "recorded_cached_sets": before["remembered_sets"],
            "recorded_wrapper_views": before["remembered_wrapper_views"],
            "owned_textures_alive_after_dispose": after["previous_textures_alive"],
            "cached_sets_alive_after_dispose": after["previous_sets_alive"],
            "wrapper_views_alive_after_dispose": after["previous_wrapper_views_alive"],
            "all_wrappers_detached": all(
                v["width"] == v["height"] == 0 and not v["rd_texture_alive"]
                for v in after["wrappers"].values()),
        })
    status = re.findall(r"^NATIVE_LIFECYCLE_PROCESS_EXIT=([0-9]+)\s*$", text, re.MULTILINE)
    normal_exit = len(status) == 1 and int(status[0]) == 0
    process_checks = re.findall(r"^NATIVE_LIFECYCLE_PROCESS_REMAINING=(.*?)\s*$", text, re.MULTILINE)
    process_check_valid = not process_checks or (len(process_checks) == 1 and process_checks[0] in ("0", "1"))
    process_remaining = (process_checks[0] == "1") if len(process_checks) == 1 and process_check_valid else None
    runtime_errors = [line for line in text.splitlines()
                      if re.match(r"^(?:SCRIPT ERROR|ERROR):", line) and "leaked" not in line.lower()]
    return {
        "log": str(path), "process_exit": int(status[-1]) if status else None,
        "fixture_report_present": result is not None,
        "fixture_report_count": report_count, "parse_errors": parse_errors,
        "complete": result is not None and report_count == 1 and not parse_errors and normal_exit and process_check_valid and not process_remaining, "fixture": result,
        "post_exit_process_remaining": process_remaining,
        "post_exit_process_check_valid": process_check_valid,
        "normal_process_exit": normal_exit, "runtime_errors": runtime_errors,
        "shutdown_rd_texture_warning_count": rd_textures,
        "all_shutdown_leak_lines": warnings,
        "post_cleanup_texture_bytes": textures, "post_cleanup_buffer_bytes": buffers,
        "explicit_owner_liveness": ownership,
        "texture_change_after_first_cycle": [value - textures[0] for value in textures],
        "interpretation": (
            "Repeated resource-owner creation/disposal, not a continuous room-travel test. "
            "Memory monitors may be unsupported and lazy renderer caches can grow. "
            "A shutdown RID warning identifies unfreed handles, not their owner or per-room growth. "
            "Owner liveness covers only recorded runtime allocations and existing shared views, "
            "checked while high-level owner/wrapper references are intentionally retained. "
            "A timeout/incomplete process cannot establish clean teardown."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path, nargs="+")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--require-clean", action="store_true")
    args = parser.parse_args()
    runs = [analyze(path) for path in args.logs]
    report = {"runs": runs, "scope": "Native resource-owner bisect; no target-device performance claim"}
    text = json.dumps(report, indent=2) + "\n"
    if args.out:
        args.out.write_text(text)
    print(text)
    incomplete = any(not run["complete"] or run["runtime_errors"]
                     or not run["fixture"].get("fixture_pass", False) for run in runs)
    unclean = any(run["all_shutdown_leak_lines"] for run in runs)
    return int(incomplete or (args.require_clean and unclean))


if __name__ == "__main__":
    raise SystemExit(main())
