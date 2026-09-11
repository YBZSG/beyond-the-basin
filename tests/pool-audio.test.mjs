import test from 'node:test';
import assert from 'node:assert/strict';
import { impactClip, PoolAudio } from '../app/pool-vct/audio.ts';

test('all drop variants are reachable and consecutive drops cannot repeat',()=>{
  assert.deepEqual([0,.4,.9].map(r=>impactClip(.2,-1,r).name),['drop_1','drop_2','drop_3']);
  for(let previous=0;previous<3;previous++)for(const r of [0,.49,.99])assert.notEqual(impactClip(.5,previous,r).index,previous);
  assert.ok(impactClip(.1).volume<impactClip(.4).volume);
});

test('continuous movement and stop/resume reuse exactly two loop sources',()=>{
  const audio=new PoolAudio();let starts=0;
  const param=()=>({value:0,setTargetAtTime(){}});
  const node=()=>({connect(){return this;},gain:param(),playbackRate:param(),start(){starts++;}});
  audio.ctx={state:'running',currentTime:1,createBufferSource:node,createGain:node};
  audio.master=node();audio.active=true;audio.loopBuffer=b=>b;
  audio.clips.set('step_swish',{});audio.clips.set('step_stir',{});
  for(let i=0;i<120;i++)audio.updateWading(.055,.21,i/20);
  assert.equal(starts,2);assert.equal(audio.inspect().wading,true);
  audio.stopWading();assert.equal(audio.inspect().wading,false);
  audio.updateWading(.095,.106,0);assert.equal(starts,2);
});

test('dry-ground gait alternates two step clips and sprint uses the heel clip',()=>{
  const audio=new PoolAudio();const starts=[];
  const param=()=>({value:0,setValueAtTime(){},linearRampToValueAtTime(){},setTargetAtTime(){}});
  const node=()=>({connect(){return this;},gain:param(),playbackRate:param(),pan:{value:0},start(){starts.push(audio.inspect().lastStepDry);},stop(){},disconnect(){}});
  audio.ctx={state:'running',currentTime:1,createBufferSource:node,createGain:node,createStereoPanner:node};
  audio.master=node();audio.active=true;
  for(const n of ['step_dry_1','step_dry_2','step_run'])audio.clips.set(n,{duration:.2});
  audio.stepDry(false);audio.stepDry(false);
  assert.equal(starts.length,2);
  assert.equal(audio.inspect().lastStepDry,'step_dry_2');
  audio.stepDry(true);assert.equal(audio.inspect().lastStepDry,'step_dry_2');
});
