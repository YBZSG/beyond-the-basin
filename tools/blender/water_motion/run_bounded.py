"""Two-thread CPU-only Blender authoring, 1.2 GB RSS and 180 s wall guard."""
import os,sys,time,subprocess,json
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
env=dict(os.environ,OMP_NUM_THREADS='2',OPENBLAS_NUM_THREADS='2',TBB_NUM_THREADS='2')
start=time.time();peak=0;reason=None
with (HERE/'authoring.log').open('w') as log:
 p=subprocess.Popen(['blender','-b','-t','2','--python',str(HERE/'author_water_motion.py'),'--']+sys.argv[1:],stdout=log,stderr=subprocess.STDOUT,env=env,cwd=ROOT)
 while p.poll() is None:
  try:
   for line in Path(f'/proc/{p.pid}/status').read_text().splitlines():
    if line.startswith('VmRSS:'):peak=max(peak,int(line.split()[1])*1024)
  except FileNotFoundError:pass
  if peak>1_200_000_000:reason='RSS cap exceeded'
  if time.time()-start>180:reason='Wall cap exceeded'
  if reason:p.terminate();break
  time.sleep(.15)
 p.wait()
result=dict(exit_code=p.returncode,peak_rss_bytes=peak,wall_seconds=time.time()-start,thread_limit=2,no_render=True,guard_reason=reason)
(HERE/'resource_validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(result);print((HERE/'authoring.log').read_text()[-12000:]);sys.exit(0 if p.returncode==0 and not reason else 1)
