#!/usr/bin/env python3
"""Run new optical modules only in an isolated dummy-renderer Godot project.

No editor/import, full game, GDExtension, rendering device or graphics API launch.
The real project and the user's preferences are not touched by this runner.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FILES = (
    "scripts/reference_wing/reference_look_settings.gd",
    "scripts/reference_wing/reference_wave_controller.gd",
    "shaders/reference_wing/reference_camera_look.gdshader",
    "shaders/reference_wing/reference_ripples.gdshaderinc",
    "tests/reference_look/module_contract.gd",
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="poolcore-reference-look-", dir="/tmp") as name:
        fixture = Path(name)
        for relative in FILES:
            target = fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        (fixture / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Reference look CPU contract"\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n', encoding="utf-8")
        env = {**os.environ, "XDG_DATA_HOME": str(fixture / "data"), "XDG_CACHE_HOME": str(fixture / "cache")}
        result = subprocess.run([args.godot, "--headless", "--path", str(fixture), "--script", "res://tests/reference_look/module_contract.gd"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90, check=False)
        print(result.stdout, end="")
        prefix = "REFERENCE_LOOK_CONTRACT "
        reports = [json.loads(line[len(prefix):]) for line in result.stdout.splitlines() if line.startswith(prefix)]
        bad = any("SCRIPT ERROR" in line or line.startswith("ERROR:") for line in result.stdout.splitlines())
        if reports and args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(reports[-1], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return result.returncode if reports and reports[-1]["passed"] and not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
