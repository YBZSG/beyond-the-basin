import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import {sphereContact,PropPhysics,PlayerPhysics} from '../app/pool-vct/physics.ts';

test('cylinder uses round volume and oriented chute has sloped contact normal',()=>{
  const c={center:new T.Vector3(),half:new T.Vector3(1,3,1),radius:1};
  assert.equal(sphereContact(new T.Vector3(.95,0,.95),.1,c),null);
  assert.ok(sphereContact(new T.Vector3(1.05,0,0),.1,c));
  const rotation=new T.Quaternion().setFromAxisAngle(new T.Vector3(1,0,0),.4);
  const p=new T.Vector3(0,.1,0).applyQuaternion(rotation);
  const hit=sphereContact(p,.2,{center:new T.Vector3(),half:new T.Vector3(1,.08,3),rotation});
  assert.ok(hit&&hit.normal.y>.8&&hit.normal.z>.3);
});
function body(p){return {position:p,velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.18,floatBias:0,name:'鸡蛋',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0};}
test('throw cannot tunnel through a thin wall at fixed physics steps',()=>{
  const physics=new PropPhysics(new T.Scene(),()=>{}),egg=body(new T.Vector3(0,2,0));physics.add(egg);
  const camera=new T.PerspectiveCamera();camera.position.set(-1,2,0);camera.lookAt(2,2,0);camera.updateMatrixWorld();physics.grab(egg);physics.release(camera);
  const wall={center:new T.Vector3(1,2,0),half:new T.Vector3(.05,4,4)};
  for(let i=0;i<60;i++){physics.update(1/60,camera,[wall],i/60);assert.ok(egg.position.x<.79);}
  assert.equal(physics.throws,1);
});
test('thrown object enters water, emits a splash and floats back up',()=>{
  let splashes=0;const physics=new PropPhysics(new T.Scene(),()=>splashes++),egg=body(new T.Vector3(0,2,0));physics.add(egg);
  const camera=new T.PerspectiveCamera();camera.position.set(0,1.5,3);
  for(let i=0;i<360;i++)physics.update(1/60,camera,[],i/60);
  assert.ok(splashes>=1);assert.ok(egg.position.y>.2&&egg.position.y<.42);
});
test('charged throws launch at the given speed and make bigger ripples',()=>{
  const powers=[];const physics=new PropPhysics(new T.Scene(),(x,z,power)=>powers.push(power));
  const egg=body(new T.Vector3(0,2,0));physics.add(egg);
  const camera=new T.PerspectiveCamera();camera.position.set(0,1.5,3);
  camera.lookAt(0,0,0);camera.updateMatrixWorld();
  physics.grab(egg);physics.release(camera,15);
  const speed0=egg.velocity.length();
  for(let i=0;i<600;i++)physics.update(1/60,camera,[],i/60);
  assert.ok(speed0>14&&speed0<17);
  assert.ok(powers.some(p=>p>.3));
});
test('duck-sized body floats at its biased waterline and rests flush on dry ground',()=>{
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32);
  const duck={position:new T.Vector3(0,.6,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'小黄鸭',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0};
  physics.add(duck);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  for(let i=0;i<240;i++)physics.update(1/60,camera,[],100);
  assert.ok(Math.abs(duck.position.y-(.32+.125))<.01);
  const deck={center:new T.Vector3(0,.35,0),half:new T.Vector3(8,.35,8)};
  duck.position.set(0,2,0);duck.velocity.set(0,0,0);duck.splashCooldown=0;
  for(let i=0;i<240;i++)physics.update(1/60,camera,[deck],100);
  assert.ok(Math.abs(duck.position.y-(.7+.2))<.01);
});
test('ladder reaches the platform exit and releases climbing state',()=>{
  const player=new PlayerPhysics(),camera=new T.PerspectiveCamera();camera.position.set(0,1.5,0);
  const ladder={base:new T.Vector3(0,0,0),top:new T.Vector3(0,2,.1),exit:new T.Vector3(0,2,1)};
  player.toggle(camera,[ladder]);assert.ok(player.climbing);
  for(let i=0;i<68;i++)player.update(1/60,camera,new Set(['KeyW']),[]);
  assert.equal(player.climbing,null);assert.ok(camera.position.y>3.5);assert.ok(camera.position.z>.8);
});
test('hard wall hits emit impact events and resting contact stays quiet',()=>{
  let events=[];
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32,{impact:(b,s)=>events.push([b.name,s])});
  const egg=body(new T.Vector3(0,2,0));physics.add(egg);
  const camera=new T.PerspectiveCamera();camera.position.set(-1,2,0);camera.lookAt(2,2,0);camera.updateMatrixWorld();
  physics.grab(egg);physics.release(camera);
  const wall={center:new T.Vector3(1,2,0),half:new T.Vector3(.05,4,4)};
  for(let i=0;i<60;i++)physics.update(1/60,camera,[wall],i/60);
  assert.ok(events.length>=1&&events.length<=4);
  assert.ok(events.every(([name,s])=>name==='鸡蛋'&&s>1.15));
  // Once settled against the wall the egg stops reporting.
  const settled=events.length;
  for(let i=0;i<120;i++)physics.update(1/60,camera,[wall],i/60);
  assert.ok(events.length-settled<=1);
});
test('grabbing a prop fires the grab callback',()=>{
  let grabs=0;
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32,{grab:()=>grabs++});
  const duck=body(new T.Vector3(0,2,0));physics.add(duck);
  physics.grab(duck);assert.equal(grabs,1);
  physics.grab(duck);assert.equal(grabs,2);
});
