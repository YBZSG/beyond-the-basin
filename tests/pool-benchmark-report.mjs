// Summarize complete recordings, never the HUD's short ring buffer.
// node tests/pool-benchmark-report.mjs <recording directory>
import {readdir,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(process.argv[2]??'.');
const percentile=(values,p)=>values[Math.min(values.length-1,Math.floor(values.length*p))]??null;
function distribution(values){
  values=values.filter(Number.isFinite).sort((a,b)=>a-b);
  return {samples:values.length,mean:values.length?values.reduce((s,x)=>s+x,0)/values.length:null,
    p50:percentile(values,.5),p95:percentile(values,.95),p99:percentile(values,.99),worst:values.at(-1)??null};
}
const groups=new Map();
for(const file of await readdir(root)){
  if(!/-\d+\.json$/.test(file))continue;
  const record=JSON.parse(await readFile(resolve(root,file),'utf8'));
  if(!groups.has(record.scenario))groups.set(record.scenario,[]);
  groups.get(record.scenario).push(record);
}
const report={};
for(const [scenario,records] of groups){
  // Legacy runners measured their first partial interval against performance.now(),
  // whereas RAF timestamps describe the start of a frame (and can be earlier).
  const frames=records.flatMap(r=>r.frameIntervals==='complete-raf'?r.frames:r.frames.slice(1)),stats=distribution(frames);
  const trace=records.flatMap(r=>r.performance?.frames??[]),cpu={},gpu={};
  for(const stage of new Set(trace.flatMap(f=>Object.keys(f.cpu)))){
    const values=trace.map(f=>f.cpu[stage]??0);cpu[stage]={allFrames:distribution(values),activeFrames:distribution(values.filter(v=>v>0))};
  }
  // A query can arrive after recording starts while belonging to a warmup frame.
  const queries=records.flatMap(r=>{
    const recordedFrames=new Set((r.performance?.frames??[]).map(f=>f.frame));
    return (r.performance?.gpuSamples??[]).filter(s=>recordedFrames.has(s.frame)).map(s=>({...s,repeat:r.repeat}));
  });
  for(const stage of new Set(queries.map(s=>s.stage))){
    const frameTotals=new Map();
    for(const s of queries.filter(s=>s.stage===stage)){const key=`${s.repeat}/${s.frame}`;frameTotals.set(key,(frameTotals.get(key)??0)+s.ms);}
    gpu[stage]=distribution([...frameTotals.values()]);
  }
  const transfer={};
  for(const record of records){
    const metrics=(record.performance?.frames??[]).filter(f=>f.transfer);
    for(const key of Object.keys(metrics.at(-1)?.transfer??{}))transfer[key]=(transfer[key]??0)+metrics.at(-1).transfer[key]-metrics[0].transfer[key];
  }
  report[scenario]={repeats:records.length,machine:records[0].machine,valid:records.every(r=>!r.errors?.length),
    frames:{...stats,fps:stats.mean?1000/stats.mean:null,over33:frames.filter(x=>x>33.3).length,over50:frames.filter(x=>x>50).length},
    longTasks:distribution(records.flatMap(r=>r.longTasks.map(t=>t.duration))),cpuWork:distribution(trace.map(f=>f.cpuMs)),cpu,gpu,
    calls:distribution(trace.map(f=>f.render?.calls)),shadows:distribution(trace.map(f=>f.shadowSlots)),transfer,
    transitionEvents:records.flatMap(r=>r.performance?.events??[]).filter(e=>e.name==='rooms-ready'||e.name==='transition-complete')};
}
console.log(JSON.stringify(report,null,2));
