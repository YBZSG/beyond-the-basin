#!/usr/bin/env python3
"""Execute actual adapter with an explicitly isolated source lifecycle double."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="poolcore-reference-adapter-", dir="/tmp") as name:
        fixture = Path(name)
        paths = [ROOT / "scripts/reference_wing" / filename for filename in ("reference_look_settings.gd", "reference_wave_controller.gd", "reference_water_runtime.gd")]
        paths += [p for p in (ROOT / "shaders").rglob("*") if p.suffix in (".gdshader", ".gdshaderinc")]
        paths.append(ROOT / "tests/reference_look/adapter_contract.gd")
        for source in paths:
            target = fixture / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        target = fixture / "scripts/water/source_water_runtime.gd"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "tests/reference_look/fixtures/source_water_runtime_stub.gd", target)
        (fixture / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Reference adapter CPU contract"\n', encoding="utf-8")
        env = {**os.environ, "XDG_DATA_HOME": str(fixture / "data"), "XDG_CACHE_HOME": str(fixture / "cache")}
        result = subprocess.run([args.godot, "--headless", "--path", str(fixture), "--script", "res://tests/reference_look/adapter_contract.gd"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90, check=False)
        print(result.stdout, end="")
        prefix = "REFERENCE_ADAPTER_CONTRACT "
        reports = [json.loads(line[len(prefix):]) for line in result.stdout.splitlines() if line.startswith(prefix)]
        bad = any("SCRIPT ERROR" in line or line.startswith("ERROR:") for line in result.stdout.splitlines())
        if reports and args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(reports[-1], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return result.returncode if reports and reports[-1]["passed"] and not bad else 2


if __name__ == "__main__":
    raise SystemExit(main())
