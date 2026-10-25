#!/usr/bin/env python3
"""Run the isolated contact regression without imports, meshes, water, or GPU.

Default: 48 fixture cases plus 120 Hz state-preserving minimal A/B.
--full: also replay the entrance approach, then recover the same stuck body.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORK = Path("/tmp/poolcore-reference-contact")


def run(script, arguments, name, expected_success):
    env = os.environ.copy()
    for key, leaf in [("HOME", "home"), ("XDG_CONFIG_HOME", "xdg"), ("XDG_DATA_HOME", "xdg")]:
        path = WORK / leaf
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    (WORK / "output").mkdir(parents=True, exist_ok=True)
    command = ["godot", "--headless", "--path", str(ROOT), "--fixed-fps", "60", "--script", script, "--", *arguments]
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, timeout=90)
    log = result.stdout + result.stderr
    (WORK / "output" / f"{name}.log").write_text(log)
    assert "SCRIPT ERROR:" not in log and "ERROR:" not in log, log[-4000:]
    report = json.loads((WORK / "output" / f"{name}.json").read_text())
    success = report.get("passed", report.get("failures") == 0)
    assert success is expected_success, (name, success, report.get("legs"))
    assert result.returncode == (0 if expected_success else 1), (name, result.returncode)
    print(f"PASS {name}: expected pass={expected_success}")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()
    matrix = run("tests/reference_wing/stair_contact_matrix.gd", [], "matrix", True)
    baseline = {(row["hz"], row["fixture"]): row for row in matrix["cases"] if row["mode"] == "baseline"}
    for row in matrix["cases"]:
        if row["mode"] == "fallback":
            old = baseline[row["hz"], row["fixture"]]
            assert row["position"] == old["position"], (row, old)
            assert row["recovery_steps"] == 0, row
    print("PASS 24 fixture trajectories identical; no fallback activated.")
    for hz in [15, 60, 120]:
        for mode in ["baseline", "fallback"]:
            run("tests/reference_wing/stair_contact_probe.gd", ["--route=stalled-seeded", f"--mode={mode}", f"--hz={hz}"], f"stalled-seeded-{mode}-{hz}", mode != "baseline" or hz != 120)
    if args.full:
        for mode in ["baseline", "late-fallback"]:
            run("tests/reference_wing/stair_contact_probe.gd", ["--route=full", f"--mode={mode}"], f"full-{mode}-120", mode != "baseline")


if __name__ == "__main__":
    main()
