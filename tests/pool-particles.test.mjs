import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import {SplashParticles} from '../app/pool-vct/splash-particles.ts';

test('droplets have volume, physical materials and real instance transforms',()=>{
  const sp=new SplashParticles();sp.release(10,.5,2,1,1,0,.012);sp.update(0,()=>.32,()=>{});
  const mesh=sp.drops;assert.equal(mesh.isInstancedMesh,true);assert.equal(mesh.material.isMeshPhysicalMaterial,true);
  mesh.geometry.computeBoundingBox();const extent=mesh.geometry.boundingBox.getSize(new T.Vector3());
  assert.ok(extent.x>1&&extent.y>1&&extent.z>1);
  const before={...sp.live[0]};sp.rebase(new T.Vector3(32,0,-32));sp.update(0,()=>.32,()=>{});
  const matrix=new T.Matrix4();mesh.getMatrixAt(0,matrix);
  assert.equal(matrix.elements[12],Math.fround(before.x-32));assert.equal(sp.live[0].z,before.z+32);sp.dispose();
});

test('swept drop contact does not overshoot and produces one ripple, including slow returns',()=>{
  const sp=new SplashParticles(),hits=[],surface=x=>.32+x*.1;
  sp.release(0,.5,0,8,-3,0,.02);sp.update(0,surface,()=>{});
  sp.update(.05,surface,(x,z,s)=>hits.push({x,z,s}));
  assert.equal(sp.count,0);assert.equal(hits.length,1);
  assert.ok(hits[0].x>.29&&hits[0].x<.33);assert.equal(hits[0].z,0);
  sp.update(.05,surface,()=>hits.push({}));assert.equal(hits.length,1);
  sp.release(0,.329,0,0,-.2,0,.01);sp.update(.02,()=>.32,()=>hits.push({}));
  assert.equal(hits.length,2);sp.dispose();
});

test('ripple strength scales with drop volume and relative water-contact velocity',()=>{
  const sp=new SplashParticles(),hits=[];
  sp.release(0,.35,0,0,-2,0,.008);sp.release(.1,.35,0,0,-2,0,.016);
  sp.update(.035,()=>.32,(_x,_z,s)=>hits.push(s));
  assert.equal(hits.length,2);assert.ok(hits[1]>hits[0]*7.5);
  sp.release(0,.405,0,0,.05,0,.01);sp.update(0,()=>.32,()=>{});
  sp.update(.01,()=>.42,()=>hits.push(0));
  assert.equal(hits.length,3,'a rising water surface can catch an upward-moving drop');sp.dispose();
});

test('small entrained air rises, pops once and never becomes a white sphere on top',()=>{
  const sp=new SplashParticles();sp.bubbles(0,.32,0,8);let hits=0;
  for(let i=0;i<400;i++)sp.update(1/60,()=>.32,()=>hits++,()=>({u:.2,v:0}));
  assert.equal(hits,8);assert.equal(sp.count,0);assert.equal(sp.submerged.count,0);sp.dispose();
});

test('spray has a bounded budget, rejects invalid sources and clears on land',()=>{
  const sp=new SplashParticles();
  sp.release(NaN,.5,0,0,1,0,.01);sp.release(0,.5,0,0,1,0,0);assert.equal(sp.count,0);
  for(let i=0;i<2000;i++)sp.release(0,.5,0,0,1,0,.01);
  assert.ok(sp.count<=1024);
  sp.update(.02,()=>.32,()=>{},()=>({u:0,v:0}),()=>0);
  assert.equal(sp.count,0);sp.dispose();
});
