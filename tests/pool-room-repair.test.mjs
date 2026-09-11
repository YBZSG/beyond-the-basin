import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { createBeachBallGeometry,createBeachBallTexture,BEACH_BALL_RADIUS } from '../app/pool-vct/beach-ball.ts';
import { RoomLights } from '../app/pool-vct/room-lights.ts';
import { PlayerPhysics } from '../app/pool-vct/physics.ts';

test('beach ball is smooth, centred and fits its collision sphere across every panel',()=>{
  const g=createBeachBallGeometry(),p=g.getAttribute('position'),n=g.getAttribute('normal');
  assert.ok(g.index.count/3>=6000);
  for(let i=0;i<p.count;i++){
    const point=new T.Vector3().fromBufferAttribute(p,i),normal=new T.Vector3().fromBufferAttribute(n,i);
    assert.ok(Math.abs(point.length()-BEACH_BALL_RADIUS)<1e-7);
    assert.ok(point.normalize().dot(normal)>.99999);
  }
  const texture=createBeachBallTexture();
  assert.equal(texture.image.data.length,1024*512*4);
  g.dispose();texture.dispose();
});

test('room lighting retains two shadow maps and the same light objects through dead/extra lamps',()=>{
  const scene=new T.Scene(),pool=new RoomLights(scene),ids=pool.lights.map(l=>l.uuid);
  const tube=new T.PointLight(0xffdddd,50,36),exit=new T.PointLight(0xff0000,7,7);
  pool.select([tube,exit],Array.from({length:24},()=>tube));
  assert.equal(pool.lights[0].intensity,50);assert.equal(pool.lights[1].intensity,0);
  assert.equal(pool.lights[2].intensity,7);assert.equal(pool.lights.filter(l=>l.castShadow).length,2);
  pool.select([tube,tube],[]);tube.position.set(32,7,-32);tube.intensity=13;pool.update();
  assert.equal(pool.lights[1].intensity,13);assert.deepEqual(pool.lights[1].position.toArray(),[32,7,-32]);
  assert.deepEqual(pool.lights.map(l=>l.uuid),ids);assert.equal(scene.children.length,27);
  pool.dispose();assert.equal(scene.children.length,0);
});

test('player can jump from water, holding jump cannot fly, and landing generates one ripple',()=>{
  const events=[],player=new PlayerPhysics((x,z,power)=>events.push(power)),camera=new T.PerspectiveCamera();
  camera.position.set(0,1.5,0);
  for(let i=0;i<120;i++)player.update(1/60,camera,new Set(),[]);
  let peak=0;
  for(let i=0;i<240;i++){player.update(1/60,camera,new Set(['Space']),[]);peak=Math.max(peak,camera.position.y);}
  assert.ok(peak>1.95&&peak<2.15,`water jump peak ${peak}`);
  assert.equal(events.length,2);assert.equal(events[0],.14);assert.ok(events[1]>=.14);
  assert.ok(camera.position.y<1.5);
  player.update(1/60,camera,new Set(),[]);player.update(1/60,camera,new Set(['Space']),[]);
  assert.ok(player.vertical>3.5);assert.equal(events.length,3);
});

test('high dive splashes before touching the bottom; a dry platform does not splash',()=>{
  const run=colliders=>{const events=[],player=new PlayerPhysics((x,z,power)=>events.push(power)),camera=new T.PerspectiveCamera();camera.position.set(0,7,0);for(let i=0;i<300;i++)player.update(1/60,camera,new Set(),colliders);return events;};
  const dive=run([]);assert.equal(dive.length,1);assert.ok(dive[0]>.35);
  assert.equal(run([{center:new T.Vector3(0,.4,0),half:new T.Vector3(3,.4,3)}]).length,0);
});

test('a jump pressed between 120 Hz physics ticks is retained',()=>{
  const player=new PlayerPhysics(),camera=new T.PerspectiveCamera();camera.position.set(0,1.3,0);
  player.update(1/240,camera,new Set(['Space']),[]);
  player.update(1/240,camera,new Set(),[]);
  assert.ok(player.vertical>3.7);
});

test('dry-ground jump is higher than the restrained water jump',()=>{
  const height=colliders=>{const player=new PlayerPhysics(),camera=new T.PerspectiveCamera();camera.position.set(0,2.5,0);for(let i=0;i<180;i++)player.update(1/60,camera,new Set(),colliders);const base=camera.position.y;let peak=base;for(let i=0;i<180;i++){player.update(1/60,camera,new Set(['Space']),colliders);peak=Math.max(peak,camera.position.y);}return peak-base;};
  const wet=height([]),dry=height([{center:new T.Vector3(0,.4,0),half:new T.Vector3(3,.4,3)}]);
  assert.ok(wet>.65&&wet<.8,`water rise ${wet}`);
  assert.ok(dry>1.15&&dry<1.35,`dry rise ${dry}`);
  assert.ok(dry>wet+.4);
});
