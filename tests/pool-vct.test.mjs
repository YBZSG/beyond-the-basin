import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { randomFor, roomLayout, blocked, VoxelField } from '../app/pool-vct/world.ts';
import { rayBlocked, InteractiveWater } from '../app/pool-vct/water-system.ts';

test('positive and negative chunks regenerate deterministically',()=>{
  for(const [x,z] of [[0,0],[-123,482],[100000,-100000]]){
    const a=randomFor(x,z,250821),b=randomFor(x,z,250821);
    assert.deepEqual(Array.from({length:50},a),Array.from({length:50},b));
    assert.deepEqual(roomLayout(x,z,250821),roomLayout(x,z,250821));
  }
  assert.notDeepEqual(roomLayout(4,8,1),roomLayout(4,8,2));
});
test('collision respects player radius but does not block submerged floor',()=>{
  const wall={min:new T.Vector3(0,0,0),max:new T.Vector3(1,5,1),color:new T.Color('white')};
  assert.equal(blocked(new T.Vector3(-.2,1,.5),[wall]),true);
  assert.equal(blocked(new T.Vector3(-.4,1,.5),[wall]),false);
  assert.equal(blocked(new T.Vector3(.5,1,.5),[{...wall,max:new T.Vector3(1,.1,1)}]),false);
});
test('radiance injection creates four correctly sized nonempty voxel levels',()=>{
  const field=new VoxelField();
  const floor={min:new T.Vector3(-4,-.5,-4),max:new T.Vector3(4,0,4),color:new T.Color('#8299a5')};
  field.rebuild([floor],[],0,0);
  const sum=()=>field.textures[0].image.data.reduce((s,v,i)=>s+(i%4===3?0:v),0);
  const dark=sum();
  field.rebuild([floor],[{position:new T.Vector3(0,4,0),color:new T.Color('white'),power:20}],0,0);
  assert.ok(sum()>dark);
  assert.deepEqual(field.textures.map(t=>[t.image.width,t.image.height,t.image.depth]),[[128,32,128],[64,16,64],[32,8,32],[16,4,16]]);
  for(const t of field.textures)assert.ok(t.image.data.some(v=>v>0));
  field.dispose();assert.equal(field.textures.length,0);
});
test('caustic light visibility rejects occluders but accepts parallel clear rays',()=>{
  const pillar={min:new T.Vector3(-1,1,-1),max:new T.Vector3(1,3,1),color:new T.Color('white')};
  assert.equal(rayBlocked(new T.Vector3(0,.3,0),new T.Vector3(0,7,0),[pillar]),true);
  assert.equal(rayBlocked(new T.Vector3(3,.3,0),new T.Vector3(3,7,0),[pillar]),false);
  assert.equal(rayBlocked(new T.Vector3(0,4,0),new T.Vector3(0,7,0),[pillar]),false);
});
test('water impulse ring is bounded and follows floating-origin rebases',()=>{
  const water=new InteractiveWater();water.uniforms.waterTime.value=12;
  for(let i=0;i<20;i++)water.impact(i,4,.1);
  assert.equal(water.uniforms.impacts.value.length,12);assert.equal(water.interactionCount,20);
  const before=water.uniforms.impacts.value.map(v=>v.clone());
  water.rebase(new T.Vector3(32,0,-32));
  water.uniforms.impacts.value.forEach((v,i)=>{assert.equal(v.x,before[i].x-32);assert.equal(v.y,before[i].y+32);assert.equal(v.z,12);});
  water.dispose();
});

test('enclosed pool stays flat without disturbances and settles after an impact',()=>{
  const water=new InteractiveWater();
  for(const t of [0,1,12,100]){water.uniforms.waterTime.value=t;assert.equal(water.heightAt(3,-2),0);}
  water.impact(0,0,.13);water.uniforms.waterTime.value=100.4;
  assert.notEqual(water.heightAt(.4,0),0);
  water.uniforms.waterTime.value=116;
  assert.equal(water.heightAt(.4,0),0);water.dispose();
});

test('ripples bounce off solid walls but pass through the portal gaps',()=>{
  // Splash 10m from the +x wall. By age 6 the direct wavefront has passed the
  // receiver at (13,6); the only remaining contribution is the wave bouncing
  // back off the solid wall segment, arriving from the mirrored source.
  const bounce=new InteractiveWater();
  bounce.impact(10,0,.13);bounce.uniforms.waterTime.value=6;
  assert.ok(Math.abs(bounce.heightAt(13,6))>1e-3);
  // A receiver beyond the same wall, sampled once the direct wavefront has also
  // passed it, sees nothing: mirrored sources on its side of the wall are
  // dropped, so ripples do not leak out of the room they belong to.
  bounce.uniforms.waterTime.value=7.3;
  assert.ok(Math.abs(bounce.heightAt(18,6))<1e-6);
  bounce.dispose();
  // Same geometry, but the mirrored path now crosses the wall inside the eight
  // metre portal gap: the reflection is gated off and nothing else is in range.
  const portal=new InteractiveWater();
  portal.impact(10,-3,.13);portal.uniforms.waterTime.value=7.25;
  assert.ok(Math.abs(portal.heightAt(13,6))<1e-6);
  portal.dispose();
});

test('wall reflections are invariant under floating-origin room rebases',()=>{
  const water=new InteractiveWater();
  water.impact(10,0,.13);water.uniforms.waterTime.value=6;
  const inside=Math.abs(water.heightAt(13,6));
  const before=water.uniforms.impacts.value.map(v=>v.clone());
  water.rebase(new T.Vector3(32,0,0));
  water.uniforms.impacts.value.forEach((v,i)=>{assert.equal(v.x,before[i].x-32);assert.equal(v.y,before[i].y);});
  // One room west the splash still resolves against its own room's walls, so
  // the equally shifted receiver sees the identical bounce magnitude.
  assert.ok(Math.abs(Math.abs(water.heightAt(-19,6))-inside)<1e-9);
  water.dispose();
});

test('ripples bounce off waterline pillars and steps, fading past their edges',()=>{
  // Splash 5m west of a 2x2 block; by age 3.5 the direct wavefront has passed
  // the receiver at (-3,0) and only the block-face mirror can still reach it.
  const water=new InteractiveWater();
  water.impact(-5,0,.13);water.uniforms.waterTime.value=3.5;
  assert.ok(Math.abs(water.heightAt(-3,0))<1e-6);
  water.setBlocks([new T.Vector4(-1,-1,1,1)]);
  assert.ok(Math.abs(water.heightAt(-3,0))>1e-3);
  // Beyond the face's ends the mirrored source fades out completely.
  assert.ok(Math.abs(water.heightAt(-3,2.4))<1e-6);
  water.dispose();
  // The same geometry one room east stays silent: splashes from neighbouring
  // rooms never consult the central room's blocks.
  const outer=new InteractiveWater();
  outer.setBlocks([new T.Vector4(29,-1,31,1)]);
  outer.impact(26,0,.13);outer.uniforms.waterTime.value=2.6;
  assert.ok(Math.abs(outer.heightAt(27.5,0))<1e-6);
  outer.dispose();
  const central=new InteractiveWater();
  central.setBlocks([new T.Vector4(-3,-1,-1,1)]);
  central.impact(-6,0,.13);central.uniforms.waterTime.value=2.6;
  assert.ok(Math.abs(central.heightAt(-4.5,0))>1e-3);
  central.dispose();
});

test('three distinct bright rooms and a dark bath are reachable next to the original',()=>{
  for(const seed of [1,250821,999]){
    assert.equal(roomLayout(0,0,seed).variant,0);
    assert.deepEqual([[0,-1],[-1,0],[1,0]].map(([x,z])=>roomLayout(x,z,seed).variant),[3,6,5]);
    assert.equal(roomLayout(0,1,seed).variant,4);
  }
});
test('budgeted voxel phases match the synchronous rebuild',()=>{
  const solids=[{min:new T.Vector3(-4,-.5,-4),max:new T.Vector3(4,0,4),color:new T.Color('#8299a5')},
    {min:new T.Vector3(-1,0,-1),max:new T.Vector3(1,3,1),color:new T.Color('#ccbbaa')}];
  const lamps=[{position:new T.Vector3(2,4,-2),color:new T.Color('white'),power:20},
    {position:new T.Vector3(-6,3,5),color:new T.Color('#a9d8ed'),power:20}];
  const sync=new VoxelField();sync.rebuild(solids,lamps,0,0);
  const phased=new VoxelField();
  phased.begin(solids,lamps,0,0);
  let guard=0;while(!phased.stepRadiance(0)&&guard++<5000);
  phased.finish();
  const sum=f=>f.textures.reduce((s,t)=>s+t.image.data.reduce((a,v,i)=>a+(i%4===3?0:v),0),0);
  assert.equal(sum(phased),sum(sync));
  assert.deepEqual(phased.textures.map(t=>[t.image.width,t.image.height,t.image.depth]),[[128,32,128],[64,16,64],[32,8,32],[16,4,16]]);
  sync.dispose();phased.dispose();
});
test('sliced caustic occlusion matches the synchronous fill and skips distant blocks',()=>{
  const solids=[{min:new T.Vector3(-1,1,-1),max:new T.Vector3(1,3,1),color:new T.Color('white')},
    {min:new T.Vector3(4,-1,4),max:new T.Vector3(6,9,6),color:new T.Color('white')}];
  const direct=new InteractiveWater();direct.rebuildOcclusion(solids);
  const sliced=new InteractiveWater();sliced.beginOcclusion(solids);
  let guard=0;while(!sliced.stepOcclusion(0)&&guard++<2000);
  for(const l of [0,1])assert.deepEqual(Array.from(sliced.masks[l].image.data),Array.from(direct.masks[l].image.data));
  const far=[...solids,{min:new T.Vector3(100,0,100),max:new T.Vector3(110,8,110),color:new T.Color('white')}];
  const distant=new InteractiveWater();distant.rebuildOcclusion(far);
  assert.deepEqual(Array.from(distant.masks[0].image.data),Array.from(direct.masks[0].image.data));
  direct.dispose();sliced.dispose();distant.dispose();
});
