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

test('room lighting keeps four shadow maps — two here, two next door — and the same light objects',()=>{
  const scene=new T.Scene(),pool=new RoomLights(scene),ids=pool.lights.map(l=>l.uuid);
  const tube=new T.PointLight(0xffdddd,50,36),exit=new T.PointLight(0xff0000,7,7);
  exit.position.set(.5,.5,.5);
  const nearTube=new T.PointLight(0xffdddd,40,36);nearTube.position.set(-12,7,0);
  const farTube=new T.PointLight(0xffdddd,40,36);farTube.position.set(40,7,0);
  pool.select([tube,exit],[nearTube,farTube]);
  // Looking along -z: both neighbour tubes sit square in the view and win the
  // next-door slots; the exit lamp behind the camera ranks last.
  pool.update(new T.Vector3(),new T.Vector3(0,0,-1));
  assert.equal(pool.lights[0].intensity,50);
  assert.equal(pool.lights.filter(l=>l.castShadow).length,4,'shadow slot count changed');
  assert.equal(pool.lights[2].shadow.mapSize.x,1024,'next-door slots should use the cheap 1024 maps');
  assert.equal(pool.lights[1].intensity,40);
  assert.equal(pool.lights[2].intensity,40);
  assert.equal(pool.lights[3].intensity,7);
  assert.equal(pool.lights[4].intensity,0,'lights beyond the shadow slots must stay unlit');
  pool.select([tube,tube],[]);tube.position.set(32,7,-32);tube.intensity=13;pool.update(new T.Vector3(),new T.Vector3(0,0,-1));
  assert.equal(pool.lights[1].intensity,13);assert.deepEqual(pool.lights[1].position.toArray(),[32,7,-32]);
  assert.deepEqual(pool.lights.map(l=>l.uuid),ids);assert.equal(scene.children.length,27);
  pool.dispose();assert.equal(scene.children.length,0);
});

test('shadow invalidation is per slot: one moving prop rebuilds one cube map, not four',()=>{
  const scene=new T.Scene(),pool=new RoomLights(scene);
  // Widely separated tubes so a caster's swept sphere (radius 1, light reach 36)
  // can only reach the slot it sits under.
  const tubes=[0,200,400,600].map(x=>{const l=new T.PointLight(0xffffff,50,36);l.position.set(x,7,0);return l;});
  pool.select(tubes,[]);
  const focus=new T.Vector3(),dir=new T.Vector3(0,0,-1);
  // Stand in for the shadow pass consuming the flags it was given.
  const consume=()=>{for(let i=0;i<4;i++){pool.lights[i].shadow.needsUpdate=false;}};
  const flags=()=>pool.lights.slice(0,4).map(l=>l.shadow.needsUpdate);
  consume();
  // `select()` primes internally; a second update with the same sources has
  // nothing to rebuild, which is what buys a free shadow pass on a still frame.
  pool.update(focus,dir);
  assert.equal(pool.shadowSlotsUpdated,0,'unchanged sources must not re-rasterize any cube map');
  const casterAt=(x)=>({body:{radius:1},previous:new T.Vector3(x,7,0),current:new T.Vector3(x+.3,7,0),radius:1});
  pool.invalidateBodies([casterAt(0)]);
  pool.update(focus,dir);
  assert.equal(pool.shadowSlotsUpdated,1,'only the slot above the mover may rebuild');
  assert.deepEqual(flags(),[true,false,false,false]);
  consume();
  // A mover outside every light's reach invalidates nothing at all.
  pool.invalidateBodies([casterAt(900)]);
  pool.update(focus,dir);
  assert.equal(pool.shadowSlotsUpdated,0,'a mover beyond every light must cost nothing');
  assert.deepEqual(flags(),[false,false,false,false]);
  // The swept test catches a prop crossing a light's range edge in either
  // direction: it started inside, so the slot it is leaving still rebuilds.
  pool.invalidateBodies([{body:{radius:1},previous:new T.Vector3(0,7,0),current:new T.Vector3(60,7,0),radius:1}]);
  pool.update(focus,dir);
  assert.equal(pool.shadowSlotsUpdated,1,'leaving a light still dirties that slot');
  consume();
  // Escape hatch: a room transition or quality change rebuilds everything.
  pool.invalidate();pool.update(focus,dir);
  assert.equal(pool.shadowSlotsUpdated,4);
  // Re-ranking swaps sources between slots; only the slots that actually
  // changed hands rebuild, not all four.
  pool.select([tubes[1],tubes[0],tubes[2],tubes[3]],[]);
  assert.equal(pool.shadowSlotsUpdated,2,'only slots handed a new source rebuild');
  pool.dispose();
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


test('architecture batching preserves world-space triangles and excludes moving props and light fixtures',async()=>{
  const {batchArchitecture}=await import('../app/pool-vct/static-geometry.ts');
  const root=new T.Group(),material=new T.MeshStandardMaterial(),geometry=new T.BoxGeometry(1,1,1);
  const a=new T.Mesh(geometry,material),b=new T.Mesh(geometry,material);
  a.position.set(1,2,3);b.position.set(-2,1,4);b.rotation.y=.4;a.castShadow=b.castShadow=true;
  root.add(a,b);
  const moving=new T.InstancedMesh(geometry,material,1),fixture=new T.Mesh(geometry,material);fixture.userData.luminaire=true;
  root.add(moving,fixture);root.position.set(32,0,-32);root.updateMatrixWorld(true);
  // Expected triangle soup: expand each source's index (if any) into the same
  // vertex order the rasterizer would visit, in world space.
  const expected=[];
  for(const mesh of [a,b]){
    const g=mesh.geometry,positions=g.attributes.position,index=g.index,point=new T.Vector3();
    const visit=i=>{point.fromBufferAttribute(positions,i).applyMatrix4(mesh.matrixWorld);expected.push(...point.toArray());};
    if(index)for(let i=0;i<index.count;i++)visit(index.getX(i));
    else for(let i=0;i<positions.count;i++)visit(i);
  }
  batchArchitecture(root);root.updateMatrixWorld(true);
  assert.equal(moving.parent,root);assert.equal(fixture.parent,root);
  const batch=root.children.find(o=>o.userData.batchedArchitecture);assert.ok(batch&&batch.castShadow);assert.equal(batch.material,material);
  // Indexed sources must stay indexed through the merge: expanding them would
  // triple the vertex workload in the main and all six shadow views.
  assert.ok(batch.geometry.index,'indexed architecture must keep its index after batching');
  const actual=[];
  {const g=batch.geometry,positions=g.attributes.position,index=g.index,point=new T.Vector3();
    const visit=i=>{point.fromBufferAttribute(positions,i).applyMatrix4(batch.matrixWorld);actual.push(...point.toArray());};
    if(index)for(let i=0;i<index.count;i++)visit(index.getX(i));
    else for(let i=0;i<positions.count;i++)visit(i);}
  assert.equal(actual.length,expected.length);
  assert.ok(actual.every((n,i)=>Math.abs(n-expected[i])<.000002));
  batch.geometry.dispose();moving.dispose();geometry.dispose();material.dispose();
});

test('batching keeps a mixed indexed / non-indexed material in two separate batches',async()=>{
  const {batchArchitecture}=await import('../app/pool-vct/static-geometry.ts');
  const root=new T.Group(),material=new T.MeshStandardMaterial();
  const triangle=()=>{
    const geometry=new T.BufferGeometry();
    geometry.setAttribute('position',new T.BufferAttribute(new Float32Array([0,0,0, 1,0,0, 0,1,0]),3));
    geometry.computeVertexNormals();return geometry;
  };
  const boxes=[0,1].map(i=>{const mesh=new T.Mesh(new T.BoxGeometry(1,1,1),material);mesh.position.set(i*3,0,0);return mesh;});
  const tris=[0,1].map(i=>{const mesh=new T.Mesh(triangle(),material);mesh.position.set(10+i*3,0,0);return mesh;});
  for(const mesh of [...boxes,...tris]){mesh.castShadow=true;root.add(mesh);}
  root.updateMatrixWorld(true);
  batchArchitecture(root);
  const batches=root.children.filter(o=>o.userData.batchedArchitecture);
  assert.equal(batches.length,2,'indexed and non-indexed must not share one batch');
  const withIndex=batches.filter(b=>b.geometry.index),withoutIndex=batches.filter(b=>!b.geometry.index);
  assert.equal(withIndex.length,1);assert.equal(withoutIndex.length,1);
  assert.ok(withIndex[0].geometry.index.count>0);
  assert.equal(withoutIndex[0].geometry.attributes.position.count,6,'two triangles stay unindexed');
  for(const batch of batches)batch.geometry.dispose();
  material.dispose();
});
