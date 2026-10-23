#!/usr/bin/env python3
"""Verify a native walk's fixture result together with its actual process exit."""
import argparse
import json
import re
from pathlib import Path


def analyze(path: Path) -> dict:
    text = path.read_text(errors="replace")
    fixture = None
    labels = []
    parse_errors = []
    for line in text.splitlines():
        match = re.fullmatch(r"SOURCE_NATIVE_WALK_(PASS|FAIL) (\{.*\})", line)
        if match:
            labels.append(match.group(1))
            try:
                fixture = json.loads(match.group(2))
            except json.JSONDecodeError as error:
                parse_errors.append(str(error))
    exits = re.findall(r"^SOURCE_NATIVE_WALK_PROCESS_EXIT=([0-9]+)\s*$", text, re.MULTILINE)
    status = int(exits[-1]) if exits else None
    remaining = re.findall(r"^SOURCE_NATIVE_WALK_PROCESS_REMAINING=(.*?)\s*$", text, re.MULTILINE)
    process_check_valid = len(remaining) == 1 and remaining[0] in ("0", "1")
    process_remaining = remaining[0] == "1" if process_check_valid else None
    warnings = [line for line in text.splitlines() if "leaked" in line.lower()]
    runtime_errors = [line for line in text.splitlines()
                      if re.match(r"^(?:SCRIPT ERROR|ERROR):", line) and "leaked" not in line.lower()]
    fixture_pass = (len(labels) == 1 and labels[0] == "PASS" and isinstance(fixture, dict)
                    and fixture.get("pass") is True and fixture.get("failures") == [])
    process_success = len(exits) == 1 and status == 0 and process_check_valid and not process_remaining
    return {
        "log": str(path), "pass": fixture_pass and process_success and not parse_errors and not runtime_errors,
        "fixture_pass": fixture_pass, "fixture": fixture, "parse_errors": parse_errors,
        "process_exit": status, "process_exit_verified": len(exits) == 1,
        "post_exit_process_check_valid": process_check_valid,
        "post_exit_process_remaining": process_remaining,
        "normal_process_exit": process_success, "runtime_errors": runtime_errors,
        "shutdown_rd_texture_warning_count": sum(int(n) for n in re.findall(r'([0-9]+) RIDs of type "Texture" were leaked', text)),
        "shutdown_leak_lines": warnings, "clean_shutdown": fixture_pass and process_success and not warnings and not runtime_errors,
        "scope": "Actual native movement result plus process exit, not target-device performance. A route PASS before timeout/crash is not a successful run. Shutdown leak warnings remain separate and must not be hidden.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    report = analyze(args.log)
    text = json.dumps(report, indent=2) + "\n"
    if args.out:
        args.out.write_text(text)
    print(text)
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
