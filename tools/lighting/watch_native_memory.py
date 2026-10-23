#!/usr/bin/env python3
"""Bounded child runner with actual /proc RSS/HWM sampling; no OOM inference."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time
p = argparse.ArgumentParser()
p.add_argument('--output', required=True)
p.add_argument('--seconds', type=int, default=1200)
p.add_argument('command', nargs=argparse.REMAINDER)
a = p.parse_args()
command = a.command[1:] if a.command and a.command[0] == '--' else a.command
if not command or not 1 <= a.seconds <= 3600: p.error('A bounded child command is required')
out = Path(a.output)
if out.exists(): p.error('Refusing to overwrite memory evidence')
child = subprocess.Popen(command)
start = time.monotonic()
rows = []
timed_out = False

def write(final=False):
    values = [row.get('VmRSS_kib', 0) for row in rows]
    result = {'pid':child.pid,'command':command,'elapsed_seconds':time.monotonic()-start,
        'finished':final,'returncode':child.poll(),'timed_out':timed_out,
        'sample_interval_seconds':1,'max_observed_rss_kib':max(values,default=0),
        'max_observed_hwm_kib':max((row.get('VmHWM_kib',0) for row in rows),default=0),
        'rows':rows,'scope':'Actual child /proc samples. SIGKILL alone does not establish an OOM cause; final high-water mark may be missed after process disappearance.'}
    temporary = out.with_suffix(out.suffix+'.tmp')
    temporary.write_text(json.dumps(result,indent=2)+'\n')
    temporary.replace(out)

while child.poll() is None:
    row = {'elapsed_seconds':time.monotonic()-start}
    try:
        for line in Path(f'/proc/{child.pid}/status').read_text().splitlines():
            name, _, value = line.partition(':')
            if name in ('VmRSS','VmHWM','VmSize'): row[name+'_kib'] = int(value.split()[0])
            elif name == 'Threads': row[name] = int(value)
        for line in Path('/proc/meminfo').read_text().splitlines():
            if line.startswith('MemAvailable:'): row['system_mem_available_kib'] = int(line.split()[1])
    except (OSError, ValueError) as error:
        row['read_error'] = str(error)
    rows.append(row)
    write()
    if time.monotonic()-start >= a.seconds:
        timed_out = True
        child.terminate()
        try: child.wait(timeout=20)
        except subprocess.TimeoutExpired: child.kill(); child.wait()
        break
    time.sleep(1)
write(True)
print('NATIVE_MEMORY_RESULT', json.dumps({'returncode':child.returncode,'timed_out':timed_out,'report':str(out)}))
raise SystemExit(124 if timed_out else 128-child.returncode if child.returncode < 0 else child.returncode)
