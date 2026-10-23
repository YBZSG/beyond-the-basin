"""Own-process-only timeout and aggregate descendant RSS guard for native QA."""
import argparse,json,os,signal,subprocess,time
from pathlib import Path
from datetime import datetime,timezone
p=argparse.ArgumentParser();p.add_argument('--label',required=True);p.add_argument('--seconds',type=float,required=True);p.add_argument('--rss-mib',type=float,default=1228);p.add_argument('--log',type=Path,required=True);p.add_argument('--receipt',type=Path,required=True);p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args();cmd=a.command[1:] if a.command[:1]==['--'] else a.command
start=time.monotonic();peak=0;reason='';exit_code=1;process=None

def rss_tree(pid):
    seen=set();stack=[pid];rss=0
    while stack:
        x=stack.pop()
        if x in seen:continue
        seen.add(x)
        try:
            for line in Path(f'/proc/{x}/status').read_text().splitlines():
                if line.startswith('VmRSS:'):rss+=int(line.split()[1])*1024
            stack.extend(int(y) for y in Path(f'/proc/{x}/task/{x}/children').read_text().split())
        except (FileNotFoundError,ProcessLookupError):pass
    return rss

try:
    with a.log.open('w') as log:
        process=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        while process.poll() is None:
            peak=max(peak,rss_tree(process.pid))
            if peak>a.rss_mib*1024*1024:reason='RSS guard exceeded';break
            if time.monotonic()-start>a.seconds:reason='Phase timeout';break
            time.sleep(.2)
        if reason:
            os.killpg(process.pid,signal.SIGTERM)
            try:process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
            exit_code=124
        else:exit_code=process.returncode
except Exception as error:
    reason=f'{type(error).__name__}: {error}'
    if process and process.poll() is None:
        os.killpg(process.pid,signal.SIGTERM)
        try:process.wait(timeout=10)
        except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
finally:
    receipt=dict(phase=a.label,completed=True,exit_code=exit_code,reason=reason,
        peak_aggregate_rss_bytes=peak,rss_limit_bytes=int(a.rss_mib*1024*1024),
        wall_seconds=time.monotonic()-start,completed_utc=datetime.now(timezone.utc).isoformat(),command=cmd)
    a.receipt.write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt))
raise SystemExit(0 if exit_code==0 else 1)
