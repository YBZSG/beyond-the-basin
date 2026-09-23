import type { GpuTiming } from './perf-types';

export type GpuSample = { frame:number; stage:string; issuedAt:number; ms:number };
type Query = { query:WebGLQuery; frame:number; stage:string; issuedAt:number };
export interface GpuProfiler {
  readonly supported:boolean;
  begin(frame?:number,stage?:string,issuedAt?:number):boolean;
  end():void;
  snapshot():GpuTiming;
  takeSamples():GpuSample[];
  dispose():void;
}
/** Bounded asynchronous queries; identity belongs to the issuing frame. */
export function createGpuProfiler(gl:WebGL2RenderingContext|WebGLRenderingContext|null):GpuProfiler {
  const ext=typeof WebGL2RenderingContext!=='undefined'&&gl instanceof WebGL2RenderingContext
    ?gl.getExtension('EXT_disjoint_timer_query_webgl2'):null;
  if(!gl||!ext)return {supported:false,begin:()=>false,end(){},snapshot:()=>({supported:false,disjoint:false,last:0,average:0}),takeSamples:()=>[],dispose(){}};
  const context=gl as WebGL2RenderingContext;
  const pending:Query[]=[],pool:WebGLQuery[]=[],completed:GpuSample[]=[];
  let active:Query|null=null,disposed=false,last=0,average=0,disjoint=false;
  const recycle=(q:WebGLQuery)=>{if(pool.length<4)pool.push(q);else context.deleteQuery(q);};
  const drain=()=>{
    if(disposed)return;
    if(context.getParameter(ext.GPU_DISJOINT_EXT)){
      disjoint=true;for(const job of pending)context.deleteQuery(job.query);pending.length=0;completed.length=0;return;
    }
    while(pending.length&&context.getQueryParameter(pending[0].query,context.QUERY_RESULT_AVAILABLE)){
      const job=pending.shift()!;
      const ms=context.getQueryParameter(job.query,context.QUERY_RESULT)/1e6;recycle(job.query);
      if(!Number.isFinite(ms)||ms<0)continue;
      disjoint=false;
      if(job.stage==='frame'){last=ms;average=average?average*.85+ms*.15:ms;}
      completed.push({frame:job.frame,stage:job.stage,issuedAt:job.issuedAt,ms});
      if(completed.length>256)completed.shift();
    }
  };
  return {
    supported:true,
    begin(frame=0,stage='frame',issuedAt=performance.now()){
      if(disposed||active)return false;drain();
      if(pending.length>=8)return false;
      const query=pool.pop()??context.createQuery();if(!query)return false;
      context.beginQuery(ext.TIME_ELAPSED_EXT,query);active={query,frame,stage,issuedAt};return true;
    },
    end(){if(!active)return;context.endQuery(ext.TIME_ELAPSED_EXT);pending.push(active);active=null;drain();},
    snapshot(){drain();return {supported:true,disjoint,last,average};},
    takeSamples(){drain();return completed.splice(0);},
    dispose(){if(disposed)return;disposed=true;if(active){context.endQuery(ext.TIME_ELAPSED_EXT);context.deleteQuery(active.query);active=null;}for(const {query} of pending)context.deleteQuery(query);for(const query of pool)context.deleteQuery(query);pending.length=pool.length=completed.length=0;},
  };
}
