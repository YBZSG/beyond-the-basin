"""Run two-thread, no-render Blender UV job with a strict 1GB RSS guard."""
from pathlib import Path
import json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[3]
out=Path(__file__).resolve().parent/'audit';peak=0;start=time.time()
env=dict(os.environ,OMP_NUM_THREADS='2',OPENBLAS_NUM_THREADS='2',TBB_NUM_THREADS='2')
with (out/'avatar_finish_candidate_blender_build.log').open('w') as log:
 p=subprocess.Popen(['blender','-b','-t','2','--python',str(Path(__file__).with_name('build_avatar_finish_candidate.py'))],stdout=log,stderr=subprocess.STDOUT,env=env,cwd=ROOT)
 while p.poll() is None:
  try:
   for line in Path(f'/proc/{p.pid}/status').read_text().splitlines():
    if line.startswith('VmRSS:'):peak=max(peak,int(line.split()[1])*1024)
  except FileNotFoundError:pass
  if peak>1_000_000_000:p.terminate();raise RuntimeError('CPU build RSS budget exceeded')
  if time.time()-start>120:p.terminate();raise RuntimeError('CPU build timeout')
  time.sleep(.1)
 result=dict(exit_code=p.returncode,peak_rss_bytes=peak,wall_seconds=time.time()-start,threads_limit=2,rendered=False)
 (out/'avatar_finish_candidate_blender_resources.json').write_text(json.dumps(result,indent=2)+'\n');print(result)
print((out/'avatar_finish_candidate_blender_build.log').read_text()[-12000:])
raise SystemExit(0 if p.returncode==0 else 1)
