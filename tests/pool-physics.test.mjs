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
test('a dropped prop plunges underwater before floating back up',()=>{
  const physics=new PropPhysics(new T.Scene(),()=>{});
  const egg={position:new T.Vector3(0,2,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.18,floatBias:0,name:'鸡蛋',kind:'egg',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0};
  physics.add(egg);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  let minY=9;
  for(let i=0;i<360;i++){physics.update(1/60,camera,[],i/60);minY=Math.min(minY,egg.position.y);}
  // Entry momentum must carry the body well under the waterline, not park it at
  // the surface, and buoyancy must then recover it to the tuned waterline.
  assert.ok(minY<.1,`never plunged: minY ${minY.toFixed(3)}`);
  assert.ok(Math.abs(egg.position.y-.32)<.02,`failed to refloat: ${egg.position.y.toFixed(3)}`);
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
test('floating props drift with the shallow-water flow',()=>{
  // A steady .8 m/s current: strong drag against the resting-water damping
  // converges to most of the flow speed while the duck keeps its waterline.
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32,undefined,()=>({u:.8,v:0}));
  const duck={position:new T.Vector3(0,.45,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'小黄鸭',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0};
  physics.add(duck);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  for(let i=0;i<300;i++)physics.update(1/60,camera,[],i/60);
  assert.ok(duck.velocity.x>.55,`flow drag failed: ${duck.velocity.x}`);
  assert.ok(Math.abs(duck.position.y-(.32+.125))<.05,`waterline drifted: ${duck.position.y}`);
});
test('wave slope force rocks and carries floaters',()=>{
  // A fixed 2 m/s² wave push stands in for the solver: drag equilibrium lands
  // at accel / drag rate (2/8 = .25 m/s) while the waterline holds.
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32,undefined,()=>({u:0,v:0}),undefined,()=>({ax:2,az:0,ux:0,uz:0}));
  const duck={position:new T.Vector3(0,.45,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'小黄鸭',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0};
  physics.add(duck);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  for(let i=0;i<120;i++)physics.update(1/60,camera,[],i/60);
  assert.ok(duck.velocity.x>.15,`slope force failed: ${duck.velocity.x}`);
  assert.ok(Math.abs(duck.velocity.z)<.02,`cross drift leaked: ${duck.velocity.z}`);
  assert.ok(Math.abs(duck.position.y-(.32+.125))<.05,`waterline drifted: ${duck.position.y}`);
});
test('floaters glide with the Stokes drift of a passing wave train',()=>{
  // The wave push doubles as a drift velocity the drag chases: a sustained
  // .7 m/s transport carries the duck along instead of just rocking it.
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32,undefined,()=>({u:0,v:0}),undefined,()=>({ax:0,az:0,ux:.7,uz:0}));
  const duck={position:new T.Vector3(0,.45,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'小黄鸭',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0};
  physics.add(duck);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  for(let i=0;i<180;i++)physics.update(1/60,camera,[],i/60);
  assert.ok(duck.velocity.x>.4,`drift failed: ${duck.velocity.x}`);
  assert.ok(duck.position.x>.3,`no glide: ${duck.position.x}`);
  assert.ok(Math.abs(duck.position.y-(.32+.125))<.05,`waterline drifted: ${duck.position.y}`);
});
test('low-drag skimmers still exchange momentum with the water',()=>{
  const events=[];
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32,undefined,()=>({u:0,v:0}),(x,z,ix,iz)=>events.push([ix,iz]));
  const ball={position:new T.Vector3(0,.45,0),velocity:new T.Vector3(.6,0,0),rotation:new T.Quaternion(),radius:.21,floatBias:.05,name:'海滩球',kind:'ball',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0,flowRate:1.6,wakeTimer:0};
  physics.add(ball);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  for(let i=0;i<120;i++)physics.update(1/60,camera,[],i/60);
  assert.ok(events.length>=6,`skimmer produced ${events.length} wake events`);
  assert.ok(events.every(([ix])=>ix>0),'wake lost its direction');
  // The low drag rate itself is untouched: the ball keeps skimming slowly.
  assert.ok(ball.velocity.x>.1,`unexpected braking: ${ball.velocity.x}`);
});
test('dense eggs bottom out and refloat slowly; light ducks pop right back up',()=>{
  const floor={center:new T.Vector3(0,-1.22,0),half:new T.Vector3(8,.5,8)};
  const run=(kind,radius,bias,props)=>{
    const physics=new PropPhysics(new T.Scene(),()=>{});
    const b={position:new T.Vector3(0,2,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius,floatBias:bias,name:kind,kind,visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0,...props};
    physics.add(b);
    const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
    let minY=9,backAt=Infinity;
    for(let i=0;i<600;i++){physics.update(1/60,camera,[floor],i/60);
      minY=Math.min(minY,b.position.y);
      if(backAt===Infinity&&i>60&&Math.abs(b.position.y-(.32+bias))<.012)backAt=i/60;}
    return {minY,backAt};
  };
  const egg=run('egg',.17,0,{buoyK:16,buoyZeta:.5,buoyMax:4,flowRate:5});
  const duck=run('duck',.2,.125,{buoyK:90,buoyZeta:.32,buoyMax:30,flowRate:12});
  // The dense egg dives well under the waterline (deep enough to find the
  // floor on a thrown entry) and takes its time coming back.
  assert.ok(egg.minY<-.25,`egg never sank: ${egg.minY.toFixed(3)}`);
  assert.ok(Number.isFinite(egg.backAt)&&egg.backAt<10,`egg failed to refloat: ${egg.backAt}`);
  assert.ok(duck.backAt<egg.backAt,`duck surfaced at ${duck.backAt}s, egg at ${egg.backAt}s`);
});
test('hard egg entries splash harder than the same drop of a duck',()=>{
  const powers=[];
  const physics=new PropPhysics(new T.Scene(),(x,z,p)=>powers.push(p));
  const egg={position:new T.Vector3(0,4,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.17,floatBias:0,name:'鸡蛋',kind:'egg',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0,splashBoost:1.6};
  physics.add(egg);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  for(let i=0;i<300;i++)physics.update(1/60,camera,[],i/60);
  const eggPower=Math.max(...powers);
  powers.length=0;
  const duck={position:new T.Vector3(0,4,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'小黄鸭',kind:'duck',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0};
  physics.add(duck);
  for(let i=0;i<300;i++)physics.update(1/60,camera,[],i/60);
  const duckPower=Math.max(...powers);
  assert.ok(eggPower>duckPower*1.2,`egg ${eggPower.toFixed(3)} vs duck ${duckPower.toFixed(3)}`);
  assert.ok(eggPower>.4,`egg splash too weak: ${eggPower.toFixed(3)}`);
});
test('moving floaters exchange momentum with the water on a cadence; resting ones stay quiet',()=>{
  const events=[];
  const flow={u:.35,v:0};
  const physics=new PropPhysics(new T.Scene(),()=>{},()=>.32,undefined,()=>flow,(x,z,ix,iz,sigma)=>events.push({ix,iz,sigma}));
  const duck={position:new T.Vector3(0,.45,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'小黄鸭',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0,wakeTimer:0};
  physics.add(duck);
  const camera=new T.PerspectiveCamera();camera.position.set(6,2,6);
  for(let i=0;i<180;i++)physics.update(1/60,camera,[],i/60);
  assert.ok(events.length>=1,`exchange cadence ${events.length}`);
  assert.ok(Math.abs(events[0].ix)<.2,`impulse too strong: ${events[0].ix}`);
  assert.ok(events.reduce((sum,e)=>sum+Math.abs(e.ix),0)<.35*.08,'water impulse cannot exceed the body momentum exchange budget');
  // A floater in still water is silent.
  events.length=0;duck.velocity.set(0,0,0);duck.wakeTimer=0;flow.u=0;flow.v=0;
  for(let i=0;i<180;i++)physics.update(1/60,camera,[],i/60);
  assert.equal(events.length,0,'resting floater churned the pool');
});
test('update() reports movement only when a shadow-casting prop actually moves',()=>{
  const physics=new PropPhysics(new T.Scene(),()=>{});
  // Rest a prop at the tuned waterline so buoyancy holds it essentially still.
  const duck={position:new T.Vector3(0,.445,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'小黄鸭',kind:'duck',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0};
  physics.add(duck);
  const camera=new T.PerspectiveCamera();camera.position.set(0,2,4);
  // Settle first: the very first call seeds the tracked position, and the
  // waterline equilibrium then has to be reached before "still" is meaningful.
  for(let i=0;i<600;i++)physics.update(1/60,camera,[],i/60);
  let still=0;
  for(let i=0;i<180;i++)if(physics.update(1/60,camera,[],(600+i)/60))still++;
  assert.ok(still/180<.15,`a resting prop should report almost no movement, got ${still}/180`);
  // Now throw it: every frame it travels must report movement.
  const egg=body(new T.Vector3(0,2,0));physics.add(egg);
  camera.position.set(-1,2,0);camera.lookAt(2,2,0);camera.updateMatrixWorld();
  physics.grab(egg);physics.release(camera);
  let moving=0;
  for(let i=0;i<60;i++)if(physics.update(1/60,camera,[],(780+i)/60))moving++;
  assert.ok(moving>40,`a thrown prop must report movement, got ${moving}/60`);
});
test('a prop beyond shadow range does not invalidate the shadow cache',()=>{
  const physics=new PropPhysics(new T.Scene(),()=>{});
  const far=body(new T.Vector3(200,2,200));physics.add(far);
  const camera=new T.PerspectiveCamera();camera.position.set(0,2,0);
  physics.update(1/60,camera,[],0);            // seed
  far.position.x+=1;                            // move it, but stay far away
  assert.equal(physics.update(1/60,camera,[],1/60),false,'distant props are outside every shadow light');
});
test('movedCasters carries the swept volume per-slot invalidation needs, and is cleared every frame',()=>{
  const physics=new PropPhysics(new T.Scene(),()=>{});
  const duck=body(new T.Vector3(0,2,0));physics.add(duck);
  const camera=new T.PerspectiveCamera();camera.position.set(0,2,6);
  // Seed frame: last position is recorded, nothing has moved yet.
  physics.update(1/60,camera,[],0);
  // Seed frame also integrates one step of buoyancy, so compare against the
  // settled position rather than the one we asked for.
  const seeded=duck.position.clone();
  assert.equal(physics.movedCasters.length,0);
  duck.position.set(3,2,0);
  physics.update(1/60,camera,[],1/60);
  assert.equal(physics.movedCasters.length,1);
  const [caster]=physics.movedCasters;
  assert.equal(caster.body,duck);
  assert.deepEqual(caster.previous.toArray(),seeded.toArray(),'previous must be last frame, not the live vector');
  assert.ok(caster.current.distanceTo(new T.Vector3(3,2,0))<1e-2);
  assert.equal(caster.radius,duck.radius);
  // The entries are pooled, so a second move reuses the same object rather than
  // allocating - this loop runs every frame for every visible prop.
  const afterMove=duck.position.clone();
  duck.position.set(6,2,0);
  physics.update(1/60,camera,[],2/60);
  assert.equal(physics.movedCasters.length,1);
  assert.equal(physics.movedCasters[0],caster,'caster records must be pooled per body');
  assert.deepEqual(caster.previous.toArray(),afterMove.toArray());
  // Far props are excluded even when they move: beyond 40m they cast nothing.
  duck.position.set(300,2,300);duck.velocity.set(0,0,0);
  physics.update(1/60,camera,[],4/60);
  assert.equal(physics.movedCasters.length,0);
});
test('shadow cube maps are only rebuilt when a slot is handed a different light',async()=>{
  const {RoomLights}=await import('../app/pool-vct/room-lights.ts');
  const scene=new T.Scene();
  const lights=new RoomLights(scene);
  // Four shadow slots at a modest resolution: a point light shadow is 6 faces,
  // so 1024^2 keeps the per-pass cost sane.
  for(const l of lights.lights.slice(0,4)){
    assert.equal(l.castShadow,true);
    assert.equal(l.shadow.mapSize.x,1024);
    assert.equal(l.shadow.autoUpdate,false,'cached shadows must not re-render every frame');
  }
  // Build the real composition: one current-room tube, one exit lamp, and two
  // next-door tubes. Only the current-room tube lands in `tubes` (the sequence
  // with a fixed order); everything else goes through the direction-ranked
  // `rest`, which is what makes the shadow slots follow the view.
  const tube=new T.PointLight(0xffdddd,50,36);tube.position.set(0,7,0);
  const exit=new T.PointLight(0xff0000,7,7);exit.position.set(.5,.5,.5);
  const nearTube=new T.PointLight(0xffdddd,40,36);nearTube.position.set(-12,7,0);
  const farTube=new T.PointLight(0xffdddd,40,36);farTube.position.set(40,7,0);
  for(const l of [tube,exit,nearTube,farTube])scene.add(l);
  lights.select([tube,exit],[nearTube,farTube]);
  const dirtySlots=lights.lights.slice(0,4).filter(l=>l.shadow.needsUpdate).length;
  assert.equal(dirtySlots,4,'first update must invalidate every slot');
  // Same camera pose again: nothing moved, so nothing may be marked dirty.
  for(const l of lights.lights)l.shadow.needsUpdate=false;
  lights.update(new T.Vector3(0,2,0),new T.Vector3(0,0,-1));
  assert.equal(lights.lights.filter(l=>l.shadow.needsUpdate).length,0,'a stable view must keep the cache');
  // Turn around: re-ranking pulls different lights into the next-door shadow
  // slots, so the affected slots must rebuild.
  lights.update(new T.Vector3(0,2,0),new T.Vector3(0,0,1));
  assert.ok(lights.lights.some(l=>l.shadow.needsUpdate),'re-ranking must invalidate reassigned slots');
  // An explicit invalidate (a prop moved) must dirty the whole set.
  for(const l of lights.lights)l.shadow.needsUpdate=false;
  lights.invalidate();
  lights.update(new T.Vector3(0,2,0),new T.Vector3(0,0,1));
  assert.equal(lights.lights.filter(l=>l.shadow.needsUpdate).length,4,'invalidate() must rebuild every slot');
});
