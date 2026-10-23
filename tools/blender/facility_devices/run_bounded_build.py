#!/usr/bin/env python3
"""Run the approved no-render two-thread Blender build with a 950 MiB RSS guard."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

parser=argparse.ArgumentParser()
parser.add_argument("--output-root",type=Path)
parser.add_argument("--script",type=Path)
parser.add_argument("--report",type=Path,required=True)
parser.add_argument("--log",type=Path,required=True)
args=parser.parse_args()
script=args.script.resolve() if args.script else Path(__file__).with_name("build_facility_devices.py")
command=["blender","--background","--factory-startup","--threads","2","--python",str(script)]
if args.output_root:command += ["--","--output-root",str(args.output_root.resolve())]
limit=950*1024 # KiB; all Blender threads share this process address space.
peak=0
start=time.monotonic()
reason=""
env=dict(os.environ,OMP_NUM_THREADS="2",OPENBLAS_NUM_THREADS="1",MALLOC_ARENA_MAX="2")
args.report.parent.mkdir(parents=True,exist_ok=True)
args.log.parent.mkdir(parents=True,exist_ok=True)
with args.log.open("w") as log:
    process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env)
    while process.poll() is None:
        try:
            status=Path(f"/proc/{process.pid}/status").read_text()
            rss=int(next(line.split()[1] for line in status.splitlines() if line.startswith("VmRSS:")))
            peak=max(peak,rss)
            if rss>limit:reason="RSS exceeded 950 MiB guard"
        except (FileNotFoundError,StopIteration):pass
        if time.monotonic()-start>180:reason="Authoring exceeded 180 second timeout"
        if reason:
            process.terminate()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
            break
        time.sleep(.05)
report={"command":command,"exit_code":process.returncode,"peak_rss_kib":peak,
        "limit_rss_kib":limit,"elapsed_seconds":round(time.monotonic()-start,3),
        "rendered":False,"reason":reason,"success":process.returncode==0 and not reason}
args.report.write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report))
raise SystemExit(0 if report["success"] else 1)
