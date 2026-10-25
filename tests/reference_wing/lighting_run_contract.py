#!/usr/bin/env python3
"""No editor/import/GPU. Real node contract with isolated HOME and all XDG paths."""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tools/blender/reference_wing/native_light_proxy.py"


def same(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(a, b, rel_tol=2e-6, abs_tol=2e-6)
    return a == b


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--report", type=Path, default=ROOT / "tests/reference_wing/lighting_contract_report.json")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="reference-lighting-", dir="/tmp") as directory:
        fixture = Path(directory)
        env = dict(os.environ)
        for name in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
            path = fixture / name.lower(); path.mkdir(); env[name] = str(path)
        command = [args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/reference_wing/lighting_contract.gd"]
        try:
            result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90, check=False)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes): output = output.decode("utf-8", errors="replace")
            result = subprocess.CompletedProcess(command, 124, output + "\nERROR: Lighting contract timed out without completion.\n")
    prefix = "REFERENCE_LIGHTING_CONTRACT "
    reports = [json.loads(line[len(prefix):]) for line in result.stdout.splitlines() if line.startswith(prefix)]
    report = reports[-1] if reports else {"passed": False, "errors": ["No completed Godot contract"]}
    report["engine_error"] = any("SCRIPT ERROR" in line or line.startswith("ERROR:") for line in result.stdout.splitlines())
    report["process_exit"] = result.returncode
    report["isolated_home_and_all_xdg"] = True
    module_spec = importlib.util.spec_from_file_location("native_light_proxy", HELPER)
    module = importlib.util.module_from_spec(module_spec); module_spec.loader.exec_module(module)
    parity = []
    for room in report.get("rooms", []):
        raw = json.loads((ROOT / "assets/models/reference_wing" / (room["id"] + ".geometry.json")).read_text())
        expected = [module.binding(item) for item in raw["lights"] if item.get("runtime_enabled", True)]
        parity.append({"id": room["id"], "native_python_binding_equal": same(room["bindings"], expected)})
    report["blender_helper_binding_parity"] = parity
    originals = ["scripts/rendering/pool_lighting.gd", "scripts/water/source_water_runtime.gd"]
    report["original_source_unchanged"] = {}
    for relative in originals:
        current = (ROOT / relative).read_bytes()
        baseline = subprocess.check_output(["git", "show", "HEAD:" + relative], cwd=ROOT)
        report["original_source_unchanged"][relative] = current == baseline
    source_files = originals + ["scripts/reference_wing/reference_lighting.gd", "scripts/reference_wing/reference_scene_water_runtime.gd", "scripts/reference_wing/reference_catalog.gd", str(HELPER.relative_to(ROOT))]
    report["source_sha256"] = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in source_files}
    report["geometry_sha256"] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((ROOT / "assets/models/reference_wing").glob("*.geometry.json"))}
    report["passed"] = bool(report.get("passed")) and result.returncode == 0 and not report["engine_error"] and all(item["native_python_binding_equal"] for item in parity) and len(parity) == 5 and all(report["original_source_unchanged"].values())
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    for line in result.stdout.splitlines():
        if not line.startswith(prefix): print(line)
    print("REFERENCE_LIGHTING_REVIEW", json.dumps({"passed": report["passed"], "checks": report.get("checks"), "errors": report.get("errors"), "native_fixture_total": report.get("native_fixture_total"), "helper_parity": parity, "report": str(args.report)}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
