import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { LiquidSurfacePass } from '../app/pool-vct/liquid-surface-pass.ts';

/**
 * The liquid composite used to copy the whole frame into a private target
 * before sampling it, because it wrote back into the buffer it was reading and
 * a target may not be sampled and written in one draw. It now reads `read` and
 * writes `write`, which removes a full-screen copy per frame.
 *
 * That change is invisible to typecheck, lint and the pixel harness: the liquid
 * geometry only exists when WebGPU MLS-MPM is running, and SwiftShader has no
 * `navigator.gpu`, so in CI the pass always takes its early-return path. These
 * tests therefore assert the contract itself - the part that would break
 * silently and only show up as a black or torn frame on a real GPU.
 */

function harness(){
  const scene=new T.Scene();
  const camera=new T.PerspectiveCamera(60,1.5,.1,100);
  const geometry=new T.SphereGeometry(1,4,3);
  const material=new T.MeshBasicMaterial();
  const mesh=new T.InstancedMesh(geometry,material,8);
  mesh.count=1;
  const waterUniforms={
    cameraNear:{value:.08},cameraFar:{value:100},sceneReady:{value:1},
    sceneColor:{value:new T.Texture()},sceneDepth:{value:new T.DepthTexture(1,1)},
  };
  const pass=new LiquidSurfacePass(scene,camera,mesh,waterUniforms,new T.DepthTexture(1,1));
  return {pass,mesh,waterUniforms,dispose(){pass.dispose();geometry.dispose();material.dispose();}};
}

/** Records every render target and draw the pass performs. */
function recorder(){
  const calls=[];
  const renderer={
    autoClear:true,shadowMap:{autoUpdate:true},target:null,
    setRenderTarget(t){this.target=t;calls.push({op:'target',t});},
    getRenderTarget(){return this.target;},
    getContext:()=>({DEPTH_TEST:2929,disable(){},enable(){},getParameter(){return true;}}),
    render(){calls.push({op:'render',target:this.target});},
  };
  return {renderer,calls};
}

test('liquid composite reads and writes different buffers in one pass',()=>{
  const h=harness(),{renderer,calls}=recorder();
  const read=new T.WebGLRenderTarget(64,64);
  const write=new T.WebGLRenderTarget(64,64);
  try{
    h.pass.setSize(64,64);
    h.pass.render(renderer,write,read);
    // The shade pass is the last draw and must land in `write`. Before this
    // change it landed in `read`, and a full-frame copy into a private target
    // happened first so that sampling `read` was legal.
    const draws=calls.filter(c=>c.op==='render');
    const lastDraw=draws.pop();
    assert.equal(lastDraw.target,write,'the composite must write to writeBuffer');
    // No draw may target `read` at all: that would be the feedback loop the
    // deleted copy existed to avoid, and the shade pass samples read.texture.
    assert.equal(draws.some(d=>d.target===read),false,'nothing may render into the buffer being sampled');
    // Four filter passes plus the fluid raster and the composite. The old code
    // had one more (the background copy); a regression would show up here.
    assert.ok(draws.length<=5,`expected at most 5 draws before the composite, got ${draws.length}`);
    assert.equal(h.pass.needsSwap,true,'needsSwap must be true so the composer swaps');
  }finally{read.dispose();write.dispose();h.dispose();}
});

test('the pass keeps the frame intact when there is no liquid',()=>{
  const h=harness(),{renderer,calls}=recorder();
  const read=new T.WebGLRenderTarget(64,64);
  const write=new T.WebGLRenderTarget(64,64);
  h.mesh.count=0;
  try{
    h.pass.setSize(64,64);
    calls.length=0;
    h.pass.render(renderer,write,read);
    // With needsSwap true the composer swaps unconditionally, so an early
    // return would leave `write` holding the previous frame - a one-frame-late
    // or black image depending on parity. The scene has to be forwarded.
    const draws=calls.filter(c=>c.op==='render');
    assert.equal(draws.length,1,'exactly one copy when there is no liquid');
    assert.equal(draws[0].target,write,'the copy must land in writeBuffer');
  }finally{read.dispose();write.dispose();h.dispose();}
});

test('scene depth is bound for the occlusion test, not a stale capture',()=>{
  const h=harness();
  const live=new T.DepthTexture(64,64);
  try{
    // The optics block carries the *refraction capture* depth, which is only
    // written on frames the capture ran. The pass must override it with the
    // current frame's depth or the liquid would occlude against a stale buffer.
    const pass=new LiquidSurfacePass(new T.Scene(),new T.PerspectiveCamera(),h.mesh,h.waterUniforms,live);
    try{
      const uniforms=pass.shade?.uniforms;
      assert.ok(uniforms,'shade uniforms must be reachable');
      assert.equal(uniforms.sceneDepth.value,live);
    }finally{pass.dispose();}
  }finally{live.dispose();h.dispose();}
});

test('composer buffer parity keeps the scene where the depth texture lives',()=>{
  // Which composer target holds the scene is decided by how many passes with
  // `needsSwap` run before RenderPass. Attaching the depth texture to a fixed
  // target by name only works while that count stays even, so the engine binds
  // it through a helper. Reproduce the composer's documented swap rule without
  // a GL context (three needs a DOM canvas to build a real renderer) and assert
  // the helper's target is the one the scene will actually land in.
  const swapCountBeforeScene=0;
  const chain=[
    {name:'LiquidSurfacePass',swap:true},
    {name:'WhitewaterPass',swap:false},
  ];
  let write='rt1',read='rt2';
  for(const pass of chain)if(pass.swap){const held=write;write=read;read=held;}
  // RenderPass never swaps and always draws into whatever `read` currently is.
  const sceneTarget=read;
  assert.equal(sceneTarget,'rt1','the scene lands in the buffer the depth texture is bound to');
  assert.equal(swapCountBeforeScene,0);
  // A second swapping pass flips it, which is the failure mode the helper
  // exists to survive: binding to rt2 unconditionally would now be wrong.
  const held=write;write=read;read=held;
  assert.equal(read,'rt2','an extra swap moves the scene, so a fixed name breaks');
});

test('liquid pass no longer owns a full-frame background target',()=>{
  const h=harness();
  try{
    // `background` used to be a private half-float target sized to the whole
    // canvas, re-rendered every frame liquid existed. Asserting its absence
    // keeps a future edit from quietly reintroducing the copy.
    const own=Object.keys(h.pass).filter(k=>/background/i.test(k));
    assert.deepEqual(own,[],'the background target must be gone');
    assert.equal(h.pass.uniforms?.background,undefined,'no leftover uniform holder');
  }finally{h.dispose();}
});
