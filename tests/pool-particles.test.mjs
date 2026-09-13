import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { SplashParticles } from '../app/pool-vct/splash-particles.ts';

test('splash throws a power-scaled crown of droplets that ripple on re-entry',()=>{
  const sp=new SplashParticles();
  sp.splash(0,.4,0,.4);
  assert.ok(sp.count>=25,`expected a crown, got ${sp.count}`);
  const ripples=[];
  for(let i=0;i<400&&sp.count>0;i++)sp.update(1/60,()=>.32,(x,z,s)=>ripples.push(s));
  assert.equal(sp.count,0,'all droplets land within their lifetime');
  assert.ok(ripples.length>0,'re-entry hands ripples to the water field');
  sp.dispose();
});

test('particle attributes reach the shader and room rebases preserve their position',()=>{
  const sp=new SplashParticles();sp.splash(10,.4,2,.2);sp.update(0,()=>.32,()=>{});
  const geometry=sp.points.geometry;
  assert.equal(geometry.attributes.aData.itemSize,2);assert.match(sp.points.material.vertexShader,/attribute vec2 aData/);
  assert.ok(geometry.attributes.aData.array[0]>0);
  const first={...sp.live[0]};sp.rebase(new T.Vector3(32,0,-32));sp.update(0,()=>.32,()=>{});
  assert.equal(sp.live[0].x,first.x-32);assert.equal(sp.live[0].z,first.z+32);
  assert.equal(geometry.attributes.position.array[0],first.x-32);sp.dispose();
});

test('bubbles buoy upward and pop at the surface, never above it',()=>{
  const sp=new SplashParticles();
  sp.bubbles(0,.05,0,8);
  assert.equal(sp.count,8);
  const ripples=[];let peak=-1e9;
  for(let i=0;i<400&&sp.count>0;i++){
    sp.update(1/60,()=>.32,(x,z,s)=>ripples.push(s));
    for(const p of sp.live)peak=Math.max(peak,p.y);
  }
  assert.equal(sp.count,0,'every bubble pops');
  assert.ok(peak<=.33,`bubble escaped the surface: ${peak}`);
  assert.equal(ripples.length,8,'each pop leaves a ripple');
  sp.dispose();
});

test('the pool caps at 512 particles and keeps integrating',()=>{
  const sp=new SplashParticles();
  for(let i=0;i<60;i++)sp.splash(0,.4,0,.5);
  assert.ok(sp.count<=512,`pool overflowed: ${sp.count}`);
  sp.update(1/60,()=>.32,()=>{});
  assert.ok(sp.count>0,'live particles still integrate');
  sp.dispose();
});
