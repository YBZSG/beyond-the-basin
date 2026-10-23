"""Run a GPU check with a separate user profile; never change the player's settings."""
import argparse
import json
import os
import re
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("name")
parser.add_argument("--case", default="controls")
parser.add_argument("--engine", required=True, type=Path)
parser.add_argument("--project", type=Path)
parser.add_argument("--pack", type=Path)
parser.add_argument("--width", type=int, default=1920)
parser.add_argument("--height", type=int, default=1080)
parser.add_argument("--release", action="store_true")
parser.add_argument("--script", default="check_dlss.gd")
parser.add_argument("--fg", choices=["on","off"])
parser.add_argument("--rt", choices=["on","off"])
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = root / "output/dlss" / args.name
out.mkdir(parents=True, exist_ok=False)
appdata = out / "appdata"
relative = Path("Godot/app_userdata/BEYOND THE BASIN - PoolCore Native")
profile = appdata / relative
profile.mkdir(parents=True)
for name in ["settings.cfg", "desktop_quality.cfg"]:
    shutil.copy2(Path(os.environ["APPDATA"]) / relative / name, profile / name)
if args.release:
    assert args.case in ["Off", "Quality", "Balanced", "Performance", "DLAA"]
    cfg = profile / "desktop_quality.cfg"
    saved = cfg.read_text(encoding="utf8")
    setting = 'dlss="' + args.case + '"'
    saved = re.sub(r'^dlss=.*$', setting, saved, flags=re.M) if re.search(r'^dlss=', saved, re.M) else saved + '\n' + setting + '\n'
    for key, value in [("frame_generation",args.fg),("raytracing",args.rt)]:
        if value is not None:
            setting = key + "=" + ("true" if value == "on" else "false")
            saved = re.sub(r"^"+key+r"=.*$",setting,saved,flags=re.M) if re.search(r"^"+key+"=",saved,re.M) else saved+'\n'+setting+'\n'
    cfg.write_text(saved, encoding="utf8")
env = os.environ.copy()
env["APPDATA"] = str(appdata)
# This machine has a global ReShade layer whose DLL fails initialization (1114).
# Disable that external injector only for this child process, as in our launcher.
env["DISABLE_VK_LAYER_reshade_1"] = "1"
env["VK_LOADER_LAYERS_DISABLE"] = ",".join(filter(None, [env.get("VK_LOADER_LAYERS_DISABLE", ""), "VK_LAYER_reshade"]))
cmd = [str(args.engine), "--verbose"]
if not args.release:
    cmd += ["--main-pack", str(args.pack)] if args.pack else ["--path", str(args.project or root)]
cmd += ["--rendering-method", "forward_plus", "--rendering-driver", "vulkan",
        "--windowed", "--resolution", f"{args.width}x{args.height}",
        "--audio-driver", "Dummy"]
if args.release:
    cmd += ["--", "--qa", "--qa-wait-ready", "--qa-benchmark", "--qa-user-water",
            "--qa-frames=360", "--qa-out=" + str(out / "release.png"),
            "--original-world", "--no-exploration-notes"]
else:
    cmd += ["--script", str(root / "tools/qa" / args.script),
        "--", "--qa", "--qa-wait-ready", "--qa-external-lighting-runner",
        "--original-world", "--no-exploration-notes", "--dlss-case=" + args.case,
        "--dlss-out=" + str(out)]
(out / "command.json").write_text(json.dumps(cmd, indent=2), encoding="utf8")
with (out / "engine.log").open("w", encoding="utf8") as log:
    process = subprocess.run(cmd, cwd=args.engine.parent, env=env, stdout=log,
                             stderr=subprocess.STDOUT, timeout=600)
print(json.dumps({"output": str(out), "exit_code": process.returncode}))
log_text = (out / "engine.log").read_text(encoding="utf8")
failures = re.findall(r"^(?:SCRIPT ERROR|SHADER ERROR|ERROR:|WARNING: (?:Dumped failed shader|RT .*compile).*|Image \(binding:).*$", log_text, re.M)
print(log_text[-2500:])
if failures:
    print("RENDER_ERRORS", json.dumps(sorted(set(failures))[:25]))
raise SystemExit(process.returncode or bool(failures))
