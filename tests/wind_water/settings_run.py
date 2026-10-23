#!/usr/bin/env python3
"""Run CPU-only wind settings checks with throwaway user settings, no editor/import."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="poolcore-wind-settings-", dir="/tmp") as data:
    cache = Path(data) / "cache"
    cache.mkdir()
    env = {**os.environ, "XDG_DATA_HOME": data, "XDG_CACHE_HOME": str(cache)}
    result = subprocess.run(
        ["godot", "--headless", "--path", str(ROOT), "--script", "res://tests/wind_water/settings_contract.gd"],
        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=60, check=False,
    )
    print(result.stdout, end="")
    prefix = "WIND_SETTINGS_CONTRACT "
    reports = [json.loads(line[len(prefix):]) for line in result.stdout.splitlines() if line.startswith(prefix)]
    if reports:
        (ROOT / "tests/wind_water/settings_report.json").write_text(json.dumps(reports[-1], ensure_ascii=False, indent=2) + "\n")
    engine_errors = [line for line in result.stdout.splitlines() if "SCRIPT ERROR" in line or line.startswith("ERROR:")]
    raise SystemExit(result.returncode if reports and not engine_errors else 2)
