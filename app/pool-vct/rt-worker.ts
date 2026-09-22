import * as T from 'three';
import { MeshBVH } from 'three-mesh-bvh';
import { packReflectionTextures } from './rt-packing';

type Item={position:Float32Array;index:Uint32Array|null;matrix:number[];color:number[];tile:number};
// Buffers are independent snapshots; no live geometry is ever transferred away.
globalThis.addEventListener('message',(event:MessageEvent<{version:number;items:Item[]}>)=>{
  const {version,items}=event.data;
  try{
    const vertices=items.reduce((n,item)=>n+(item.index?.length??item.position.length/3),0);
    const positions=new Float32Array(vertices*3),colors=new Float32Array(vertices*4);
    const v=new T.Vector3(),matrix=new T.Matrix4();let cursor=0;
    for(const item of items){matrix.fromArray(item.matrix);const count=item.index?.length??item.position.length/3;
      for(let j=0;j<count;j++){
        const i=item.index?item.index[j]:j;v.fromArray(item.position,i*3).applyMatrix4(matrix);
        v.toArray(positions,cursor*3);colors.set([...item.color,item.tile],cursor*4);cursor++;
      }
    }
    const geometry=new T.BufferGeometry();geometry.setAttribute('position',new T.BufferAttribute(positions,3));
    const bvh=new MeshBVH(geometry),textures=packReflectionTextures(bvh,colors);
    const serialized=MeshBVH.serialize(bvh,{cloneBuffers:false});
    const transfers=new Set<ArrayBuffer>([...textures.map(t=>t.data.buffer as ArrayBuffer),...serialized.roots as ArrayBuffer[]]);
    if(serialized.index)transfers.add(serialized.index.buffer as ArrayBuffer);
    globalThis.postMessage({version,textures,serialized},{transfer:[...transfers]});geometry.dispose();
  }catch(error){globalThis.postMessage({version,error:String(error)});}
});
