"""Run child with /proc RSS guard; preserve logs and kill only its own child."""
import argparse,json,subprocess,time,pathlib,os,signal
p=argparse.ArgumentParser();p.add_argument('--log',required=True);p.add_argument('--limit-mib',type=float,default=768);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args()
cmd=a.command[1:] if a.command and a.command[0]=='--' else a.command
peak=0;terminated=False;start=time.monotonic()
with open(a.log,'w') as log:
 proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'OMP_NUM_THREADS':'2','OPENBLAS_NUM_THREADS':'2'},start_new_session=True)
 while proc.poll() is None:
  try:
   status=pathlib.Path(f'/proc/{proc.pid}/status').read_text()
   rss=int(next(x.split()[1] for x in status.splitlines() if x.startswith('VmRSS:')))*1024
   peak=max(peak,rss)
   if rss>a.limit_mib*1024**2:
    terminated=True;os.killpg(proc.pid,signal.SIGTERM);break
  except (FileNotFoundError,StopIteration):pass
  time.sleep(.15)
 if terminated:
  try:proc.wait(timeout=3)
  except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL)
 code=proc.wait()
report={'command':cmd,'exit_code':code,'peak_rss_mib':peak/1024**2,'rss_limit_mib':a.limit_mib,'guard_terminated':terminated,'elapsed_seconds':time.monotonic()-start}
pathlib.Path(a.log+'.guard.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));raise SystemExit(code if not terminated else 78)
