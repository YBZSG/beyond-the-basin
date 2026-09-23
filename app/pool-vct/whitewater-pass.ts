import * as T from 'three';
import { colorDepthCopy } from './scene-pass.ts';
import type { Measure } from './perf/recording';
import { Pass, FullScreenQuad } from 'three/addons/postprocessing/Pass.js';

/** Draw airborne liquid with 4x MSAA, sampling the completed water image
 * from a separate source. Composer fullscreen targets stay single sampled. */
export class WhitewaterPass extends Pass {
  readonly color={value:null as T.Texture|null};
  readonly ready={value:1};
  private target=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,samples:4});
  private copy=new T.ShaderMaterial({
    uniforms:{image:{value:null}},
    vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
    fragmentShader:'uniform sampler2D image;varying vec2 vUv;void main(){gl_FragColor=texture2D(image,vUv);}',
    depthWrite:false,depthTest:false,toneMapped:false,
  });
  private quad=new FullScreenQuad(this.copy);
  private depthCopy:T.ShaderMaterial;
  private scene:T.Scene;
  private camera:T.Camera;
  private objects:T.Object3D[];
  private measure:Measure;
  constructor(scene:T.Scene,camera:T.Camera,objects:T.Object3D[],depth:T.DepthTexture,measure:Measure=(_stage,work)=>work()){
    super();this.measure=measure;this.needsSwap=false;this.scene=scene;this.camera=camera;this.objects=objects;
    this.depthCopy=colorDepthCopy(null,depth);
    for(const o of objects)o.layers.set(1);
  }
  render(renderer:T.WebGLRenderer,_write:T.WebGLRenderTarget,read:T.WebGLRenderTarget){
    if(!this.objects.some(o=>o.visible&&(o instanceof T.InstancedMesh?o.count>0:o instanceof T.Mesh?o.geometry.drawRange.count>0:true)))return;
    return this.measure('whitewater',()=>this.draw(renderer,read));
  }
  private draw(renderer:T.WebGLRenderer,read:T.WebGLRenderTarget){
    const background=this.scene.background,layers=this.camera.layers.mask,auto=renderer.autoClear,shadows=renderer.shadowMap.autoUpdate;
    const lights:T.Light[]=[];
    this.scene.traverse(o=>{if(o instanceof T.Light&&!o.layers.isEnabled(1)){o.layers.enable(1);lights.push(o);}});
    try{
      renderer.autoClear=false;renderer.shadowMap.autoUpdate=false;
      this.color.value=read.texture;this.depthCopy.uniforms.image.value=read.texture;
      renderer.setRenderTarget(this.target);renderer.clear();this.quad.material=this.depthCopy;this.quad.render(renderer);
      this.scene.background=null;this.camera.layers.set(1);
      renderer.render(this.scene,this.camera);
      this.copy.uniforms.image.value=this.target.texture;
      renderer.setRenderTarget(read);this.quad.material=this.copy;this.quad.render(renderer);
    }finally{
      this.scene.background=background;this.camera.layers.mask=layers;
      renderer.autoClear=auto;renderer.shadowMap.autoUpdate=shadows;
      for(const light of lights)light.layers.disable(1);
    }
  }
  setSize(width:number,height:number){this.target.setSize(width,height);}
  dispose(){this.target.dispose();this.depthCopy.dispose();this.copy.dispose();this.quad.dispose();}
}
