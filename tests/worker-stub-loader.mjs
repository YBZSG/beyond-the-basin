// Node does not implement Vite's inline Worker import. Keep the production
// ReflectionField lifecycle intact while controlling worker delivery in tests.
export async function resolve(specifier,context,nextResolve){
  if(specifier.endsWith('rt-worker?worker&inline'))return {shortCircuit:true,url:'data:text/javascript,'+encodeURIComponent(`export default class {
    constructor(){(globalThis.__bvhWorkers??=[]).push(this);}
    postMessage(message){this.message=message;}
    terminate(){this.terminated=true;}
  }`)};
  if(specifier==='./perf/task-budget')return nextResolve(specifier+'.ts',context);
  return nextResolve(specifier,context);
}
