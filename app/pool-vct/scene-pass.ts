import * as T from 'three';
import { Pass, FullScreenQuad } from 'three/addons/postprocessing/Pass.js';
import type { Measure } from './perf/recording';

/** Copy resolved colour AND depth without sampling the destination. */
export function colorDepthCopy(color:T.Texture|null,depth:T.DepthTexture){
  return new T.ShaderMaterial({uniforms:{image:{value:color},depthImage:{value:depth}},
    vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
    fragmentShader:'uniform sampler2D image,depthImage;varying vec2 vUv;void main(){gl_FragColor=texture2D(image,vUv);gl_FragDepth=texture2D(depthImage,vUv).r;}',
    depthTest:true,depthWrite:true,depthFunc:T.AlwaysDepth,toneMapped:false,blending:T.NoBlending});
}

/** One opaque scene traversal supplies both refraction and the main image.
 * Geometry keeps 4x MSAA; the composer's fullscreen-only targets are single
 * sampled. Depth ownership never depends on composer swap parity. */
export class PoolScenePass extends Pass {
  readonly opaque=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,samples:4});
  private composite=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,samples:4});
  readonly depth=new T.DepthTexture(1,1);
  private copy:T.ShaderMaterial;
  private quad:FullScreenQuad;
  private scene:T.Scene;private camera:T.PerspectiveCamera;
  private bind:(color:T.Texture,depth:T.DepthTexture,camera:T.PerspectiveCamera)=>void;
  private reflection:()=>void;private measure:Measure;
  constructor(scene:T.Scene,camera:T.PerspectiveCamera,
    bind:(color:T.Texture,depth:T.DepthTexture,camera:T.PerspectiveCamera)=>void,
    reflection:()=>void,measure:Measure){
    super();this.scene=scene;this.camera=camera;this.bind=bind;this.reflection=reflection;this.measure=measure;this.needsSwap=false;this.opaque.depthTexture=this.depth;
    this.copy=colorDepthCopy(this.opaque.texture,this.depth);this.quad=new FullScreenQuad(this.copy);
  }
  render(renderer:T.WebGLRenderer,_write:T.WebGLRenderTarget,read:T.WebGLRenderTarget){
    const target=renderer.getRenderTarget(),auto=renderer.autoClear,shadows=renderer.shadowMap.autoUpdate,background=this.scene.background;
    const materials=new Map<T.Material,boolean>();
    this.scene.traverse(o=>{if(o instanceof T.Mesh)for(const m of Array.isArray(o.material)?o.material:[o.material])materials.set(m,m.visible);});
    try{
      for(const [m,visible] of materials)m.visible=visible&&!m.transparent;
      renderer.autoClear=true;
      this.measure('opaque',()=>{renderer.setRenderTarget(this.opaque);renderer.render(this.scene,this.camera);});
      for(const [m,visible] of materials)m.visible=visible;
      renderer.shadowMap.autoUpdate=false;
      this.bind(this.opaque.texture,this.depth,this.camera);
      // The reflected view needs the complete scene, before hiding opaque materials.
      this.reflection();
      renderer.autoClear=false;renderer.setRenderTarget(this.composite);renderer.clear();
      this.copy.uniforms.image.value=this.opaque.texture;this.quad.render(renderer);
      for(const [m,visible] of materials)m.visible=visible&&m.transparent;
      this.scene.background=null;
      this.measure('transparent',()=>renderer.render(this.scene,this.camera));
      renderer.setRenderTarget(read);renderer.clear();
      this.copy.uniforms.image.value=this.composite.texture;this.quad.render(renderer);
    }finally{
      for(const [m,visible] of materials)m.visible=visible;
      this.scene.background=background;renderer.autoClear=auto;renderer.shadowMap.autoUpdate=shadows;renderer.setRenderTarget(target);
    }
  }
  setSize(width:number,height:number){this.opaque.setSize(width,height);this.composite.setSize(width,height);}
  dispose(){this.opaque.dispose();this.composite.dispose();this.copy.dispose();this.quad.dispose();}
}
