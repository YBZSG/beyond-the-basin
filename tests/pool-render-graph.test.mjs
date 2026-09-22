import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { PoolScenePass } from '../app/pool-vct/scene-pass.ts';
import { InteractiveWater } from '../app/pool-vct/water-system.ts';
import { advanceTask, backgroundBudget } from '../app/pool-vct/perf/task-budget.ts';
import { LiquidMPM } from '../app/pool-vct/liquid-mpm.ts';

test('opaque geometry including held props is drawn once and supplies stable refraction depth',()=>{
  const scene=new T.Scene(),camera=new T.PerspectiveCamera();
  const building=new T.Mesh(new T.BoxGeometry(),new T.MeshBasicMaterial());
  const held=new T.Group(),prop=new T.Mesh(new T.SphereGeometry(),new T.MeshBasicMaterial());held.add(prop);
  const water=new T.Mesh(new T.PlaneGeometry(),new T.MeshBasicMaterial({transparent:true}));scene.add(building,held,water);
  const read=new T.WebGLRenderTarget(32,32),write=read.clone();let bound,reflections=0;const draws=[];
  const renderer={autoClear:true,shadowMap:{autoUpdate:true},target:null,getRenderTarget(){return this.target;},setRenderTarget(t){this.target=t;},clear(){},render(s){if(s===scene)draws.push({target:this.target,opaque:building.material.visible,held:prop.material.visible,water:water.material.visible,shadow:this.shadowMap.autoUpdate});}};
  const pass=new PoolScenePass(scene,camera,(color,depth)=>{bound={color,depth};},()=>{reflections++;assert.equal(building.material.visible,true);},(_s,fn)=>fn());
  try{
    for(let frame=0;frame<4;frame++){
      draws.length=0;pass.setSize(32+frame,32+frame);pass.render(renderer,frame%2?read:write,frame%2?write:read);
      assert.equal(draws.filter(d=>d.opaque).length,1);assert.equal(draws[0].held,true,'promoted/held props must participate in the refraction source');
      assert.equal(draws[0].water,false);assert.equal(draws[0].shadow,true);assert.equal(draws[1].water,true);assert.equal(draws[1].shadow,false);
      assert.equal(bound.depth,pass.depth);assert.equal(bound.color,pass.opaque.texture);
      assert.notEqual(pass.opaque,read);assert.notEqual(pass.opaque,write);
    }
    assert.equal(reflections,4);assert.equal(renderer.autoClear,true);assert.equal(building.material.visible,true);
  }finally{pass.dispose();read.dispose();write.dispose();for(const m of [building,prop,water]){m.geometry.dispose();m.material.dispose();}}
});

test('a reused refraction capture is not reported as a shadow-producing render',()=>{
  const water=new InteractiveWater(),camera=new T.PerspectiveCamera(),scene=new T.Scene();let renders=0;
  water.waterRef={visible:true};
  const renderer={getDrawingBufferSize:v=>v.set(100,100),getRenderTarget:()=>null,setRenderTarget(){},clear(){},render(){renders++;}};
  try{
    assert.equal(water.captureScene(renderer,scene,camera),'rendered');
    assert.equal(water.captureScene(renderer,scene,camera),'reused');
    assert.equal(renders,1);
    water.waterRef=null;water.applySettings({quality:'Low'});assert.equal(water.captureScene(renderer,scene,camera),'disabled');
  }finally{water.waterRef=null;water.dispose();}
});

test('background work observes a 3ms ceiling and keeps progress across small budgets',()=>{
  let clock=0,units=0;function* work(){for(let i=0;i<10;i++){units++;clock+=.5;yield;}return 'ready';}
  const task=work();assert.equal(advanceTask(task,0,()=>clock),null);assert.equal(units,0);
  advanceTask(task,30,()=>clock);assert.equal(clock,3);assert.equal(units,6);
  let done;while(!done){done=advanceTask(task,.5,()=>clock)?.done;}
  assert.equal(units,10);assert.equal(backgroundBudget(2),3);assert.equal(backgroundBudget(13),1);assert.equal(backgroundBudget(20),0);
});

test('returning liquid is removed once without a per-particle GPU upload',()=>{
  const liquid=new LiquidMPM();const data=new Float32Array(20);data.set([40,12,40,1,0,-1,0,1]);data[8]=data[13]=data[18]=.6;
  const patch={x:0,z:0,base:.3,h:.02,count:1,age:.2,elapsed:0,pending:true,disposed:false,data,previous:data.slice(),blendElapsed:0,sampleDelta:.01,removed:new Uint8Array(1),emerged:new Uint8Array([1]),deletions:new Uint32Array(2),buffers:[]};
  liquid.patches=[patch];let ripples=0;
  try{
    for(let i=0;i<3;i++)liquid.update(.01,()=>.4,()=>1,()=>assert.fail('return is not a detached drop'),()=>ripples++);
    assert.equal(liquid.returns,1);assert.equal(ripples,1);assert.deepEqual([...patch.deletions],[1,0]);assert.equal(liquid.mesh.count,0);
    assert.equal(liquid.transfer.uploadBytes,0);
  }finally{liquid.dispose();}
});
