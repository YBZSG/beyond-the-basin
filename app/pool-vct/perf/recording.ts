import type { GpuProfiler, GpuSample } from './webgl-gpu-profiler';

export const GPU_STAGES=['frame','water-sim','caustics','opaque','reflection','transparent','liquid-depth','liquid-filter','liquid-composite','whitewater','post','probe','pmrem'] as const;
export type Measure = <R>(stage:string,work:()=>R)=>R;
export class PerformanceRecording {
  frame=0;cpu:Record<string,number>={};gpu:Record<string,GpuSample>={};cpuMs=0;
  enabled=true;recording=false;benchmark=false;
  private start=0;private lastSample=-Infinity;private selected='';private rotation=0;private whole=false;
  private frames:unknown[]=[];private gpuSamples:GpuSample[]=[];private events:unknown[]=[];
  private profiler:GpuProfiler;
  constructor(profiler:GpuProfiler){this.profiler=profiler;}
  begin(now:number){
    this.frame++;this.start=now;this.cpu={};this.selected='';
    const ready=this.profiler.takeSamples();for(const sample of ready){
      const previous=this.gpu[sample.stage];
      this.gpu[sample.stage]=previous?.frame===sample.frame?{...sample,ms:previous.ms+sample.ms}:sample;
    }
    if(this.recording)this.gpuSamples.push(...ready.map(s=>({...s,receivedFrame:this.frame,ageFrames:this.frame-s.frame})));
    if(this.enabled&&(this.benchmark||now-this.lastSample>=1000)){
      this.selected=this.benchmark?GPU_STAGES[this.rotation++%GPU_STAGES.length]:'frame';this.lastSample=now;
    }
    this.whole=this.selected==='frame'&&this.profiler.begin(this.frame,'frame',now);
  }
  measure:Measure=(stage,work)=>{
    const start=performance.now();
    const query=!this.whole&&this.selected===stage&&this.profiler.begin(this.frame,stage,start);
    try{return work();}finally{if(query)this.profiler.end();this.cpu[stage]=(this.cpu[stage]??0)+performance.now()-start;}
  };
  end(interval:number|null,metrics:object){
    if(this.whole)this.profiler.end();this.whole=false;this.cpuMs=performance.now()-this.start;
    if(this.recording)this.frames.push({frame:this.frame,at:this.start,interval,cpuMs:this.cpuMs,cpu:this.cpu,...metrics});
  }
  event(name:string,data:unknown){if(this.recording)this.events.push({frame:this.frame,name,data});}
  startRecording(){this.frames=[];this.events=[];this.gpuSamples=[];this.recording=true;}
  stopRecording(){this.recording=false;return {frames:this.frames,gpuSamples:[...this.gpuSamples,...this.profiler.takeSamples()],events:this.events,gpuScope:'WebGL only; independent WebGPU liquid compute is excluded'};}
  get stages(){return {cpu:this.cpu,cpuMs:this.cpuMs,gpu:Object.fromEntries(Object.entries(this.gpu).map(([name,s])=>[name,{...s,ageFrames:this.frame-s.frame}]))};}
}
