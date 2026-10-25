"""Tiny isolated CPU/headless export test. Does not import the real project.

The original Windows preset is copied unchanged into a temporary project with
only a script and the five geometry JSONs. A second diagnostic export adds their
explicit include filter in the temporary copy only. No source preset is edited.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ROOMS = ("stair_gallery", "colonnade", "cyan_corridor", "octagonal_bath", "ball_lounge")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="/usr/local/bin/godot")
    args = parser.parse_args()
    preset = (ROOT / "export_presets.cfg").read_text().split("[preset.1]")[0]
    paths = ["res://assets/models/reference_wing/" + room + ".geometry.json" for room in ROOMS]
    script = '''extends SceneTree
func _init() -> void:
    var paths = %s
    var result := {}
    for path in paths:
        result[path] = FileAccess.file_exists(path)
    print("PORTABILITY_PACK_JSON=" + JSON.stringify(result))
    quit()
''' % json.dumps(paths)
    results = {}
    with tempfile.TemporaryDirectory(prefix="reference-wing-export-") as folder:
        base = Path(folder)
        project, runner = base / "source", base / "empty_runtime"
        project.mkdir(); runner.mkdir()
        env = dict(os.environ)
        for key, folder_name in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("XDG_DATA_HOME", "data")):
            target = base / folder_name
            target.mkdir()
            env[key] = str(target)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Portability probe"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (project / "portability_export_check.gd").write_text(script)
        for path in paths:
            relative = path.removeprefix("res://")
            destination = project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        for name, config in (("unchanged_preset", preset), ("explicit_json_filter", re.sub(
                r'include_filter="([^"]*)"', lambda m: 'include_filter="' + m[1] + ',assets/models/reference_wing/*.geometry.json"', preset))):
            (project / "export_presets.cfg").write_text(config)
            pack = base / (name + ".pck")
            command = [args.godot, "--headless", "--path", str(project), "--export-pack", "Windows Desktop", str(pack)]
            exported = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90, env=env)
            (HERE / ("portability_export_" + name + ".txt")).write_text(exported.stdout)
            if exported.returncode or not pack.is_file():
                raise RuntimeError("Isolated export failed: " + exported.stdout[-2500:])
            ran = subprocess.run([args.godot, "--headless", "--main-pack", str(pack), "--script", "res://portability_export_check.gd"],
                                 cwd=runner, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45, env=env)
            (HERE / ("portability_export_" + name + "_run.txt")).write_text(ran.stdout)
            line = next((x for x in ran.stdout.splitlines() if x.startswith("PORTABILITY_PACK_JSON=")), None)
            if ran.returncode or line is None:
                raise RuntimeError("Isolated exported-pack probe failed: " + ran.stdout[-2500:])
            exists = json.loads(line.split("=", 1)[1])
            results[name] = {"pack_bytes": pack.stat().st_size, "geometry_files_present": exists,
                             "pass": all(exists.values())}
    results["scope"] = "Existing Godot 4.6.3, headless isolated temporary project; no original config or shared import changes"
    (HERE / "portability_export_report.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
    return 0 if results["unchanged_preset"]["pass"] and results["explicit_json_filter"]["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
