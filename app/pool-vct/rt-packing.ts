import * as T from 'three';
import { MeshBVHUniformStruct, FloatVertexAttributeTexture, type MeshBVH } from 'three-mesh-bvh';

export type PackedRtTexture={key:'index'|'position'|'bvhBounds'|'bvhContents'|'color';data:Float32Array|Uint32Array;
  width:number;height:number;format:T.DataTexture['format'];type:T.TextureDataType;internalFormat:T.DataTexture['internalFormat']};
// three-mesh-bvh's declaration omits the four public texture fields.
export type ReflectionTextureFields=Record<Exclude<PackedRtTexture['key'],'color'>,T.DataTexture>;

/** CPU-only packing belongs beside BVH construction in the Worker. */
export function packReflectionTextures(bvh:MeshBVH,colors:Float32Array):PackedRtTexture[]{
  const uniform=new MeshBVHUniformStruct(),color=new FloatVertexAttributeTexture();
  uniform.updateFrom(bvh);color.updateFrom(new T.BufferAttribute(colors,4));
  const textures:PackedRtTexture[]=[];
  for(const key of ['index','position','bvhBounds','bvhContents','color'] as const){
    const texture=key==='color'?color:(uniform as unknown as ReflectionTextureFields)[key];
    textures.push({key,data:texture.image.data as Float32Array|Uint32Array,width:texture.image.width,height:texture.image.height,
      format:texture.format,type:texture.type,internalFormat:texture.internalFormat});
  }
  uniform.dispose();color.dispose();return textures;
}
