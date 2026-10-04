import * as T from 'three';
import type { WebGPURenderer } from 'three/webgpu';

export function createPlanarCapture(renderer:WebGPURenderer,scene:T.Scene,camera:T.PerspectiveCamera,water:T.Mesh,
  uniforms:Record<string,T.IUniform>,size:()=>number) {
  const target=new T.RenderTarget(size(),size(),{type:T.HalfFloatType});
  const reflected=camera.clone(),direction=new T.Vector3(),plane=new T.Plane(),clip=new T.Vector4(),q=new T.Vector4();
  uniforms.mirrorSampler.value=target.texture;
  const matrix=uniforms.textureMatrix.value as T.Matrix4;
  return {
    target,
    render(){
      if(camera.position.y<=water.position.y)return;
      if(target.width!==size())target.setSize(size(),size());
      camera.updateMatrixWorld();camera.getWorldDirection(direction);
      reflected.position.copy(camera.position);reflected.position.y=2*water.position.y-camera.position.y;
      direction.y=-direction.y;reflected.up.set(0,-1,0);reflected.lookAt(direction.add(reflected.position));
      reflected.coordinateSystem=renderer.coordinateSystem;reflected.aspect=camera.aspect;
      reflected.updateProjectionMatrix();reflected.updateMatrixWorld();
      matrix.set(.5,0,0,.5,0,.5,0,.5,0,0,1,0,0,0,0,1).multiply(reflected.projectionMatrix).multiply(reflected.matrixWorldInverse);
      plane.set(new T.Vector3(0,1,0),-water.position.y).applyMatrix4(reflected.matrixWorldInverse);
      clip.set(plane.normal.x,plane.normal.y,plane.normal.z,plane.constant);
      const p=reflected.projectionMatrix.elements;
      q.set((Math.sign(clip.x)+p[8])/p[0],(Math.sign(clip.y)+p[9])/p[5],-1,(1+p[10])/p[14]);
      clip.multiplyScalar(1/clip.dot(q));p[2]=clip.x;p[6]=clip.y;p[10]=clip.z;p[14]=clip.w;
      const previous=renderer.getRenderTarget(),visible=water.visible;
      try{water.visible=false;renderer.setRenderTarget(target);renderer.clear();renderer.render(scene,reflected);}
      finally{water.visible=visible;renderer.setRenderTarget(previous);}
    },
  };
}
