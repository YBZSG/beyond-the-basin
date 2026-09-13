import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import {ShallowWater,poolWallAt,crestPower,SW_SIZE,SW_PHYS,SW_HALF,SW_DOMAIN,SW_CELL,SW_STEP} from '../app/pool-vct/shallow-water.ts';
import {InteractiveWater} from '../app/pool-vct/water-system.ts';
import {WATER_SETTINGS_DEFAULT,sanitizeWaterSettings} from '../app/pool-vct/water-settings.ts';

// These checks exercise terrain, scheduling and CPU/GPU exchange. Numerical
// propagation is checked against the real shaders by pool-water-gpu.mjs.
function renderer(){
  return {draws:0,target:null,autoClear:true,setRenderTarget(t){this.target=t;},getRenderTarget(){return this.target;},
    render(){this.draws++;},getClearColor:c=>c,getClearAlpha:()=>1,setClearColor(){},clear(){this.draws++;}};
}
function encoded(h=0,u=0,v=0){
  const bytes=new Uint16Array(SW_PHYS*SW_PHYS*4);
  for(let i=0;i<bytes.length;i+=4){bytes[i]=T.DataUtils.toHalfFloat(h);bytes[i+1]=T.DataUtils.toHalfFloat(u);bytes[i+2]=T.DataUtils.toHalfFloat(v);bytes[i+3]=0x3c00;}
  return bytes;
}
test('room masonry and its GPU depth texture agree, with open portals',()=>{
  const sw=new ShallowWater(),tex=sw.uniforms.poolDepth.value.image.data;
  for(let j=13;j<SW_SIZE;j+=31)for(let i=7;i<SW_SIZE;i+=29){
    const x=-SW_HALF+(i+.5)*SW_CELL,z=-SW_HALF+(j+.5)*SW_CELL,wall=poolWallAt(x,z);
    assert.equal(sw.isLand(x,z),wall);assert.equal(tex[i+j*SW_SIZE]===0,wall);
  }
  assert.ok(sw.isLand(16,10));assert.equal(sw.isLand(16,0),false);sw.dispose();
});
test('submerged stairs change depth, round pillars remain round, overhead decks stay open',()=>{
  const sw=new ShallowWater();
  sw.setTerrain([
    {center:new T.Vector3(0,-.3,0),half:new T.Vector3(2,.3,2)},
    {center:new T.Vector3(5,0,0),half:new T.Vector3(1,2,1),radius:1},
    {center:new T.Vector3(-5,2,0),half:new T.Vector3(2,.2,2)},
    {center:new T.Vector3(0,-.3,8),half:new T.Vector3(2,.15,2),rotation:new T.Quaternion().setFromAxisAngle(new T.Vector3(1,0,0),.2)},
  ]);
  assert.ok(Math.abs(sw.depthAt(0,0)-.32)<1e-6);
  assert.equal(sw.isLand(5,0),true);assert.equal(sw.isLand(5.85,.85),false);
  assert.ok(Math.abs(sw.depthAt(-5,0)-1.04)<1e-6);
  assert.ok(Math.abs(sw.depthAt(0,7)-sw.depthAt(0,9))>.25,'sloped collider contributes varying bed depth');
  sw.dispose();
});
test('all queued disturbances are consumed in one update, including more than 128 sources',()=>{
  const sw=new ShallowWater(),r=renderer();sw.setTerrain([]);sw.frame(r,0);
  for(let i=0;i<200;i++){sw.impact((i%20)-10,Math.floor(i/20),.1);sw.push(0,0,.01,0,.4);}
  assert.equal(sw.pendingSplats.length/4,200);assert.equal(sw.pendingPushes.length/5,200);
  sw.frame(r,SW_STEP);assert.equal(sw.pendingSplats.length,0);assert.equal(sw.pendingPushes.length,0);sw.dispose();
});
test('invalid input and dry-land splashes never wake the solver',()=>{
  const sw=new ShallowWater();sw.impact(16,10,.1);sw.impact(NaN,0,.1);sw.push(0,0,Infinity,0,.3);sw.impact(0,0,-1);
  assert.equal(sw.pendingSplats.length,0);assert.equal(sw.pendingPushes.length,0);assert.equal(sw.settled,true);sw.dispose();
});
test('fixed stepping agrees at 30 and 144 FPS and a stalled frame leaves no backlog',()=>{
  const run=fps=>{const sw=new ShallowWater(),r=renderer();sw.impact(0,0,.1);for(let i=0;i<fps;i++)sw.frame(r,1/fps);const d=sw.debug();sw.dispose();return d;};
  assert.ok(Math.abs(run(30).simulated-run(144).simulated)<1e-6);
  const sw=new ShallowWater(),r=renderer();sw.impact(0,0,.1);sw.frame(r,2);
  const before=sw.debug().simulated;sw.frame(r,0);assert.equal(sw.debug().simulated,before);assert.ok(before<=8*SW_STEP+1e-9);
  assert.equal(r.target,null);assert.equal(r.autoClear,true);sw.dispose();
});
test('still-water readback decodes exact zero and invalid bytes preserve the previous field',()=>{
  const sw=new ShallowWater();sw.parseReadback(encoded());assert.equal(sw.energy,0);assert.deepEqual(sw.flowAt(0,0),{u:0,v:0});
  sw.parseReadback(encoded(.1,.3,-.2));const h=sw.heightAt(0,0);sw.parseReadback(new Uint16Array(SW_PHYS*SW_PHYS*4));
  assert.equal(sw.heightAt(0,0),h);assert.equal(sw.debug().rejected,1);assert.ok(sw.flowAt(0,0).u>.28);sw.dispose();
});
test('async readback starts immediately and a pre-rebase completion cannot overwrite the new field',async()=>{
  const sw=new ShallowWater(),r=renderer();let complete,buffer;
  r.readRenderTargetPixelsAsync=(t,x,y,w,h,b)=>{buffer=b;return new Promise(resolve=>{complete=resolve;});};
  sw.impact(0,0,.1);sw.frame(r,SW_STEP);assert.ok(complete,'async read must not require a preceding synchronous read');
  sw.rebase(32,0);sw.setTerrain([]);buffer.set(encoded(.2,.3,0));complete();await Promise.resolve();
  sw.frame(r,0);assert.equal(sw.heightAt(0,0),0);assert.equal(sw.debug().asyncLands,0);sw.dispose();
});
test('timed-out async reads have separate buffers and synchronous fallback keeps working',async()=>{
  const sw=new ShallowWater(),r=renderer();let late,old;
  r.readRenderTargetPixelsAsync=(t,x,y,w,h,b)=>{old=b;return new Promise(resolve=>{late=resolve;});};
  r.readRenderTargetPixels=(t,x,y,w,h,b)=>b.set(encoded(.12,.2,0));
  sw.impact(0,0,.1);sw.frame(r,SW_STEP);sw.frame(r,1.1);assert.ok(sw.heightAt(0,0)>.11);
  old.set(encoded(-.2,-.2,0));late();await Promise.resolve();sw.frame(r,SW_STEP);
  assert.ok(sw.heightAt(0,0)>.11,'late data must not alias the current buffer');sw.dispose();
});
test('rebase preserves overlapping buoyancy and flow while clearing newly exposed regions',()=>{
  const sw=new ShallowWater();sw.setTerrain([]);sw.parseReadback(encoded(.1,.2,0));
  sw.impact(10,2,.1);sw.rebase(32,0);sw.rebase(0,-32);
  assert.ok(Math.abs(sw.heightAt(-22,34)-.1)<1e-4);assert.ok(sw.flowAt(-22,34).u>.19);
  assert.equal(sw.heightAt(40,-40),0);assert.deepEqual(sw.pendingShift.toArray(),[32,-32]);
  assert.equal(sw.pendingSplats[0],-22);assert.equal(sw.pendingSplats[1],34);sw.dispose();
});
test('an active push prevents settling and a quiet pool eventually caches',()=>{
  const sw=new ShallowWater(),r=renderer();sw.frame(r,0);const boot=r.draws;sw.frame(r,.01);assert.equal(r.draws,boot);
  sw.push(0,0,.1,0,.4);sw.frame(r,SW_STEP);assert.equal(sw.settled,false);
  for(let i=0;i<24*30;i++)sw.frame(r,1/30);
  assert.equal(sw.settled,true);const stopped=r.draws;sw.frame(r,1/60);assert.equal(r.draws,stopped);sw.dispose();
});
test('render and physics grids preserve whole texels across room shifts',()=>{
  assert.equal(SW_SIZE*SW_CELL,SW_DOMAIN);assert.equal(SW_SIZE%3,0);assert.equal(SW_SIZE%SW_PHYS,0);
  assert.equal(32/SW_CELL,Math.round(32/SW_CELL));assert.equal(SW_HALF,SW_DOMAIN/2);
});
test('Ultra at maximum wave speed shortens the timestep and never leaves a backlog',()=>{
  const sw=new ShallowWater(1152),r=renderer();sw.waveSpeed=3;sw.impact(0,0,.2);sw.frame(r,.2);
  const step=sw.velocity.uniforms.poolDt.value;
  assert.ok(step<SW_STEP);assert.ok(step*(Math.sqrt(9.81*3*1.39)+2)*Math.SQRT2/sw.cell<=.70001);
  assert.ok(sw.debug().simulated<=8*step+1e-9);
  const before=sw.debug().simulated;sw.frame(r,0);assert.equal(sw.debug().simulated,before);sw.dispose();
});
test('persisted water settings reject nonfinite values, invalid flags and unknown quality',()=>{
  const s=sanitizeWaterSettings({quality:'Extreme',damping:NaN,waveSpeed:100,viscosity:-4,ripples:'false',foam:false,spray:99,foamLife:-2,foamStrength:NaN,debugView:100});
  assert.equal(s.quality,'High');assert.equal(s.damping,WATER_SETTINGS_DEFAULT.damping);assert.equal(s.waveSpeed,3);
  assert.equal(s.viscosity,0);assert.equal(s.ripples,true);assert.equal(s.foam,false);assert.equal(s.spray,2);
  assert.equal(s.foamLife,.5);assert.equal(s.foamStrength,WATER_SETTINGS_DEFAULT.foamStrength);assert.equal(s.debugView,11);
});
test('foam uniforms expose gain, decay, diffusion and splash deposit each step',()=>{
  const sw=new ShallowWater(),r=renderer();sw.frame(r,0);sw.impact(0,0,.1);sw.frame(r,SW_STEP);
  for(const key of ['poolFoamGain','poolFoamDecay','poolFoamDiff','poolFoamSplash'])assert.ok(key in sw.height.uniforms,key);
  sw.foamGain=1.5;sw.foamDecay=.5;sw.foamDiff=.05;sw.foamSplash=2;sw.frame(r,SW_STEP);
  assert.equal(sw.height.uniforms.poolFoamGain.value,1.5);assert.equal(sw.height.uniforms.poolFoamDecay.value,.5);
  assert.equal(sw.height.uniforms.poolFoamDiff.value,.05);assert.equal(sw.height.uniforms.poolFoamSplash.value,2);
  sw.dispose();
});
test('crest spray fires only on Froude-critical or strongly converging cells',()=>{
  // Gentle slosh in deep water: sub-critical, no convergence, flat enough.
  assert.equal(crestPower(.05,.3,0,0,1.04,9.81),0);
  // A fast shelf flow over .12 m of water breaks: sqrt(9.81*.12)≈1.08 m/s.
  assert.ok(crestPower(.05,1.2,0,0,.12,9.81)>.4,'shelf Froude breaking');
  // A colliding front: strong convergence throws spray even in deep water.
  assert.ok(crestPower(.05,2,0,-4,1.04,9.81)>.4,'converging front');
  // Dead-flat water never sprays regardless of readback noise.
  assert.equal(crestPower(.001,2,0,-4,1.04,9.81),0);
  // Nonfinite readback samples stay silent.
  assert.equal(crestPower(NaN,2,0,-4,1.04,9.81),0);
});
test('crest spray respects the spray slider, quality tier and a settled pool',()=>{
  const water=new InteractiveWater();let n=0;
  const emit=()=>n++;
  water.crestSpray(1/60,emit);assert.equal(n,0,'settled pool must stay quiet');
  water.applySettings({spray:0,quality:'High'});water.swe.settled=false;water.swe.peak=.1;
  water.crestSpray(1/60,emit);assert.equal(n,0,'spray slider 0 disables emission');
  water.applySettings({spray:1,quality:'Low'});water.crestSpray(1/60,emit);assert.equal(n,0,'Low quality disables emission');
  water.applySettings({spray:1,quality:'Ultra'});water.crestSpray(1/60,emit);assert.equal(n,0,'zero readback fields emit nothing');
  // Wire the foam lifetime through the decay rate.
  water.applySettings({foamLife:4});assert.ok(Math.abs(water.swe.foamDecay-.25)<1e-9);
  water.dispose();
});
test('splash amplitude and ring fineness are live-tunable',()=>{
  const sw=new ShallowWater(),r=renderer();sw.frame(r,0);
  sw.impact(0,0,.1);const amp=sw.pendingSplats[2];
  sw.impactScale=2.5;sw.impact(0,0,.1);
  assert.ok(Math.abs(sw.pendingSplats[6]-amp*2.5)<1e-6,'impact scale did not multiply amplitude');
  sw.impactScale=1;sw.ringWaves=16;sw.impact(0,0,.1);sw.frame(r,SW_STEP);
  assert.equal(sw.sourceMaterial.uniforms.poolRingW.value,Math.min(16,Math.PI/(2*sw.cell)),'source must honour the four-cell wavelength limit');
  sw.dispose();
});
test('slope push reads -g*slope, Stokes drift follows eta*flow, land reads zero',()=>{
  // Constructor's setBlocks keeps the perimeter wall cells as land.
  const sw=new ShallowWater();
  // A 1 cm/m tilt in x: the hydrostatic push is -9.81 * 0.01.
  for(let j=0;j<SW_PHYS;j++)for(let i=0;i<SW_PHYS;i++)sw.physicsEta[i+j*SW_PHYS]=(i-SW_PHYS/2)*.0025;
  let f=sw.slopeAt(0,0);
  assert.ok(Math.abs(f.ax+.0981)<.002,`slope accel ${f.ax}`);
  assert.ok(Math.abs(f.az)<1e-12,`cross slope ${f.az}`);
  // Stokes drift is quadratic in wave intensity: eta .02 riding a .3 m/s current.
  sw.physicsEta.fill(.02);sw.physicsU.fill(.3);sw.physicsV.fill(0);
  f=sw.slopeAt(0,0);
  assert.ok(Math.abs(f.ux-.66)<.002,`stokes drift ${f.ux}`);
  // Caps bound extreme overlaps: a 35 cm/m slope and a full splash current.
  for(let j=0;j<SW_PHYS;j++)for(let i=0;i<SW_PHYS;i++)sw.physicsEta[i+j*SW_PHYS]=(i-SW_PHYS/2)*.0875;
  sw.physicsU.fill(0);
  f=sw.slopeAt(0,0);
  assert.ok(Math.abs(f.ax+3)<1e-6,`slope cap failed: ${f.ax}`);
  sw.physicsEta.fill(.35);sw.physicsU.fill(2);
  f=sw.slopeAt(0,0);
  assert.ok(Math.abs(f.ux-1.5)<1e-6,`drift cap failed: ${f.ux}`);
  // Land at the centre or any probe suppresses the force entirely.
  sw.physicsEta.fill(.3);sw.physicsU.fill(2);
  assert.deepEqual(sw.slopeAt(16,10),{ax:0,az:0,ux:0,uz:0});
  sw.dispose();
});
