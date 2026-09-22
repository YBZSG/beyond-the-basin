import test from 'node:test';
import assert from 'node:assert/strict';
import { createCpuProfiler, readRendererMetrics } from '../app/pool-vct/perf/cpu-profiler.ts';
import { createGpuProfiler } from '../app/pool-vct/perf/webgl-gpu-profiler.ts';

test('frame percentiles survive a single hitch and stay inside the window',()=>{
  const profiler=createCpuProfiler();
  for(let i=0;i<200;i++)profiler.sample(10);
  const flat=profiler.stats();
  assert.equal(flat.samples,200);
  assert.ok(Math.abs(flat.p50-10)<1e-9);
  assert.ok(Math.abs(flat.p95-10)<1e-9);
  assert.ok(Math.abs(flat.p99-10)<1e-9);
  profiler.reset();
  // 90 smooth frames and 10 hitch frames. The mean calls this scene 15 ms
  // ("about 65 FPS"); p95 says one frame in ten costs 80 ms. That gap is why
  // the HUD leads with percentiles instead of an average.
  for(let i=0;i<90;i++)profiler.sample(8);
  for(let i=0;i<10;i++)profiler.sample(80);
  const spiked=profiler.stats();
  assert.ok(Math.abs(spiked.mean-15.2)<1e-6,`mean ${spiked.mean}`);
  assert.equal(spiked.p50,8);
  assert.equal(spiked.p95,80);
  assert.equal(spiked.p99,80);
  assert.equal(spiked.worst,80);
  profiler.reset();
  // The ring is bounded, so a long session cannot grow the percentile cost.
  for(let i=0;i<1000;i++)profiler.sample(20);
  assert.equal(profiler.stats().samples,240);
  assert.equal(profiler.stats().p50,20);
  // Garbage in is ignored rather than poisoning the distribution.
  profiler.sample(0);profiler.sample(-5);profiler.sample(NaN);
  assert.equal(profiler.stats().samples,240);
  profiler.reset();
  assert.equal(profiler.stats().samples,0);
  assert.equal(profiler.stats().fps,0);
});

test('renderer metrics read draw calls, triangles and program count',()=>{
  const metrics=readRendererMetrics({info:{render:{calls:412,triangles:98765,points:3,lines:1},memory:{geometries:57,textures:23},programs:[{},{}]}});
  assert.deepEqual(metrics,{calls:412,triangles:98765,points:3,lines:1,programs:2,geometries:57,textures:23});
  // `programs` is null before the first compile in some three versions.
  assert.equal(readRendererMetrics({info:{render:{calls:0,triangles:0,points:0,lines:0},memory:{geometries:0,textures:0},programs:null}}).programs,0);
});

test('GPU profiler is inert without a WebGL2 context',()=>{
  const profiler=createGpuProfiler(null);
  assert.equal(profiler.supported,false);
  profiler.begin();profiler.end();
  assert.deepEqual(profiler.snapshot(),{supported:false,disjoint:false,last:0,average:0});
  profiler.dispose();
  // A WebGL1 context must not be mistaken for a WebGL2 one.
  assert.equal(createGpuProfiler({getExtension:()=>({})}).supported,false);
});

/**
 * Minimal stand-in for the bits of WebGL2 the profiler touches.
 *
 * Availability is per-ISSUE, not per-object: a query only becomes readable
 * after `endQuery`, exactly like a real driver. A recycled query that is
 * reopened by `beginQuery` must read "not available" again, otherwise the
 * profiler would sample the previous frame's duration and every number in the
 * HUD would be one frame stale.
 *
 * `ns` and `resolve()` are sticky so a query created after the call still gets
 * the configured duration; without that, `resolve()` before the first
 * `begin()` would iterate an empty map and quietly do nothing.
 */
function fakeGL({disjoint=false,ns=1e7}={}){
  let next=1;
  let defaultDone=false;
  let defaultNs=ns;
  let open=null;
  const live=new Map(); // query object -> {done, ns, open}
  const gl={
    QUERY_RESULT_AVAILABLE:0x8867,QUERY_RESULT:0x8866,
    getExtension:(name)=>name==='EXT_disjoint_timer_query_webgl2'?{TIME_ELAPSED_EXT:0x88BF,GPU_DISJOINT_EXT:0x8FBB}:null,
    getParameter:(p)=>p===0x8FBB?disjoint:undefined,
    createQuery:()=>{const q={id:next++};live.set(q,{done:false,ns:defaultNs,open:false});return q;},
    deleteQuery:(q)=>live.delete(q),
    beginQuery:(_target,q)=>{
      if(!q||!live.has(q))return;
      const state=live.get(q);
      state.open=true;
      // Reopening invalidates the previous result until this issue completes.
      state.done=false;
      open=q;
    },
    endQuery:()=>{if(open&&live.has(open))live.get(open).done=defaultDone;open=null;},
    getQueryParameter:(q,p)=>p===0x8867?!!live.get(q)?.done:(live.get(q)?.ns??0),
  };
  return {
    gl,
    live,
    resolve:()=>{defaultDone=true;for(const state of live.values())state.done=true;},
    hold:()=>{defaultDone=false;for(const state of live.values())state.done=false;},
    setNs:(value)=>{defaultNs=value;for(const state of live.values())state.ns=value;},
  };
}

test('GPU profiler drains its query ring and never reports a disjoint sample',()=>{
  // `WebGL2RenderingContext` does not exist in Node, so the profiler's
  // instanceof guard needs a stand-in to see a "real" context.
  const OriginalGlobal=globalThis.WebGL2RenderingContext;
  class FakeContext{}
  globalThis.WebGL2RenderingContext=FakeContext;
  try{
    const {gl,live,resolve,setNs}=fakeGL();
    Object.setPrototypeOf(gl,FakeContext.prototype);
    const profiler=createGpuProfiler(gl);
    assert.equal(profiler.supported,true);
    // First frame: the query is issued but the GPU has not answered yet, so the
    // reading must stay at 0 rather than pretending the frame was free.
    profiler.begin();profiler.end();
    assert.equal(profiler.snapshot().last,0);
    // Once the result lands it flows through converted to milliseconds.
    resolve();
    profiler.begin();profiler.end();
    const snap=profiler.snapshot();
    assert.equal(snap.last,10,'nanoseconds must be converted to milliseconds');
    assert.ok(snap.average>0);
    // A 16 ms frame after that: the smoothed average moves but stays between.
    // The query is issued first and its duration is written after, exactly as a
    // driver behaves - sampling before `begin()` would test nothing.
    gl.getQueryParameter=(q,p)=>p===0x8867?true:(live.get(q)?.ns??0);
    profiler.begin();setNs(16e6);profiler.end();
    assert.equal(profiler.snapshot().last,16);
    assert.ok(profiler.snapshot().average>10&&profiler.snapshot().average<16);
    // Only one query may be open at a time: a second begin() is ignored rather
    // than nesting, which would corrupt every measurement after it.
    profiler.begin();profiler.begin();profiler.end();
    assert.ok(live.size<=4,`query ring grew to ${live.size}`);
    // Disposal must not leave query objects behind on the context.
    profiler.dispose();
    assert.equal(live.size,0);
    profiler.begin();profiler.end();
    assert.equal(live.size,0,'a disposed profiler must stop issuing queries');
  }finally{
    if(OriginalGlobal===undefined)delete globalThis.WebGL2RenderingContext;
    else globalThis.WebGL2RenderingContext=OriginalGlobal;
  }
});

test('a disjoint event drops the bad batch but does not latch the meter off',()=>{
  const OriginalGlobal=globalThis.WebGL2RenderingContext;
  class FakeContext{}
  globalThis.WebGL2RenderingContext=FakeContext;
  try{
    let disjoint=false;
    const {gl,resolve,setNs}=fakeGL({disjoint:false});
    // Rebuild the flag reader so the test can flip it mid-run.
    gl.getParameter=(p)=>p===0x8FBB?disjoint:undefined;
    Object.setPrototypeOf(gl,FakeContext.prototype);
    const profiler=createGpuProfiler(gl);
    resolve();setNs(12e6);
    profiler.begin();profiler.end();
    assert.equal(profiler.snapshot().last,12);
    // The GPU is pre-empted: the in-flight sample is meaningless and must be
    // dropped, and the HUD has to say so rather than quietly report stale data.
    disjoint=true;
    profiler.begin();profiler.end();
    assert.equal(profiler.snapshot().disjoint,true,'the hiccup must be surfaced');
    assert.equal(profiler.snapshot().last,12,'a dropped sample must not overwrite the reading');
    // THE REGRESSION THIS TEST EXISTS FOR: the old implementation latched the
    // flag, so from here on every frame displayed "sampling interrupted" even
    // though timing was working again.
    disjoint=false;
    resolve();
    profiler.begin();setNs(9e6);profiler.end();
    const recovered=profiler.snapshot();
    assert.equal(recovered.last,9);
    assert.equal(recovered.disjoint,false,'the meter must recover once the GPU is clean again');
    profiler.dispose();
  }finally{
    if(OriginalGlobal===undefined)delete globalThis.WebGL2RenderingContext;
    else globalThis.WebGL2RenderingContext=OriginalGlobal;
  }
});

test('unresolved queries are bounded and preserve issuing frame and stage',()=>{
  const original=globalThis.WebGL2RenderingContext;class FakeContext{}globalThis.WebGL2RenderingContext=FakeContext;
  try{
    const {gl,live,resolve}=fakeGL();Object.setPrototypeOf(gl,FakeContext.prototype);
    const profiler=createGpuProfiler(gl);
    for(let i=0;i<100;i++){profiler.begin(i,'opaque',i*16);profiler.end();}
    assert.equal(live.size,8,'an unavailable GPU must not create unbounded queries');
    resolve();const samples=profiler.takeSamples();assert.equal(samples.length,8);
    assert.deepEqual(samples[3],{frame:3,stage:'opaque',issuedAt:48,ms:10});
    assert.equal(profiler.snapshot().last,0,'stage timings must not overwrite whole-frame time');
    profiler.begin(101,'frame');profiler.dispose();assert.equal(live.size,0,'active queries are freed too');
  }finally{if(original===undefined)delete globalThis.WebGL2RenderingContext;else globalThis.WebGL2RenderingContext=original;}
});
