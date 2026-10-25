#!/usr/bin/env python3
"""Geometry plus actual new adapter with isolated source scheduler double."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def invoke(path, script, env, prefix):
    result = subprocess.run(["godot", "--headless", "--path", str(path), "--script", script], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60, check=False)
    print(result.stdout, end="")
    reports = [json.loads(line[len(prefix):]) for line in result.stdout.splitlines() if line.startswith(prefix)]
    bad = any("SCRIPT ERROR" in line or line.startswith("ERROR:") for line in result.stdout.splitlines())
    return result.returncode == 0 and bool(reports) and reports[-1]["passed"] and not bad


def main():
    with tempfile.TemporaryDirectory(prefix="poolcore-water-review-", dir="/tmp") as tmp:
        base = Path(tmp)
        env = {**os.environ, "XDG_DATA_HOME": str(base / "data"), "XDG_CACHE_HOME": str(base / "cache")}
        ok = invoke(ROOT, "res://tests/reference_wing/water_geometry_contract.gd", env, "REFERENCE_WATER_GEOMETRY ")
        ok = invoke(ROOT, "res://tests/reference_wing/water_production_contract.gd", env, "REFERENCE_WATER_PRODUCTION ") and ok
        fixture = base / "fixture"
        files = ["scripts/reference_wing/reference_scene_water_runtime.gd", "scripts/reference_wing/reference_depth_field.gd", "scripts/reference_wing/reference_surface_mesh.gd", "scripts/reference_wing/reference_catalog.gd", "tests/reference_wing/water_scheduler_contract.gd", "tests/reference_wing/water_scheduler_identity.gd"]
        files += [str(p.relative_to(ROOT)) for p in (ROOT / "assets/models/reference_wing").glob("*.geometry.json")]
        for relative in files:
            target = fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        shutil.copy2(ROOT / "tests/reference_wing/water_scheduler_base.gd", fixture / "scripts/reference_wing/reference_water_runtime.gd")
        (fixture / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Water scheduler isolated review"\n')
        ok = invoke(fixture, "res://tests/reference_wing/water_scheduler_contract.gd", env, "REFERENCE_WATER_SCHEDULER ") and ok
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
