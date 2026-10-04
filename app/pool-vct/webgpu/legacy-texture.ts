import * as T from 'three';
import * as TSL from 'three/tsl';
import { TextureNode, Texture3DNode, type Node, type NodeBuilder } from 'three/webgpu';

class LiveTextureNode extends TextureNode {
  getUniformHash(){return this.getBase().uuid;}
}
class LiveVolumeNode extends Texture3DNode {
  getUniformHash(){return this.getBase().uuid;}
}

function bindLive<NodeType extends TextureNode>(node:NodeType,entry:T.IUniform){
  const proxy=TSL.nodeObject(node);
  Object.defineProperty(proxy,'value',{get:()=>entry.value});
  proxy.updateMatrix=false;
  return proxy;
}

/** Distinct live uniforms may initially point at the same placeholder texture.
 * Their bindings must remain distinct when the four voxel levels are uploaded. */
export function liveTexture(entry:T.IUniform,volume=false){
  return bindLive(volume?new LiveVolumeNode(entry.value):new LiveTextureNode(entry.value),entry);
}

/** GLSL shaders use bottom-left coordinates; WebGPU attachments use top-left.
 * Keep that convention at the sampler boundary, including cloned samples and
 * integer texel loads. Uploaded data/image textures retain their own layout. */
class LegacyTextureNode extends LiveTextureNode {
  setupUV(builder:NodeBuilder,uv:Node){
    const texture=this.value;
    if(builder.renderer.coordinateSystem===T.WebGPUCoordinateSystem &&
      (texture.isRenderTargetTexture||texture instanceof T.DepthTexture)){
      const integerUv=TSL.ivec2(uv as Node<'ivec2'>);
      return this.sampler?TSL.vec2(uv as Node<'vec2'>).flipY():integerUv.setY(
        TSL.int(TSL.ivec2(TSL.textureSize(this,this.levelNode) as unknown as Node<'ivec2'>).y).sub(integerUv.y).sub(1));
    }
    return uv;
  }
}

export function legacyTexture(entry:T.IUniform){
  return bindLive(new LegacyTextureNode(entry.value),entry);
}
