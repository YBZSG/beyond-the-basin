import * as T from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

/** Batch immutable architecture per room/material. Point-light shadows draw
 * six views each; batching preserves the exact triangles and live materials
 * while avoiding thousands of repeated draw submissions every frame. */
export function batchArchitecture(root:T.Group){
  root.updateMatrixWorld(true);
  const inverse=root.matrixWorld.clone().invert();
  const batches=new Map<string,T.Mesh[]>();
  root.traverse(object=>{
    if(!(object instanceof T.Mesh)||object instanceof T.InstancedMesh||Array.isArray(object.material)||!object.visible)return;
    if(object.userData.luminaire||object.customDepthMaterial||object.customDistanceMaterial||object.geometry.morphAttributes.position)return;
    const key=[object.material.uuid,object.castShadow,object.receiveShadow,object.renderOrder,object.layers.mask].join('/');
    if(!batches.has(key))batches.set(key,[]);batches.get(key)!.push(object);
  });
  for(const meshes of batches.values()){
    if(meshes.length<2)continue;
    const parts=meshes.map(mesh=>{
      const geometry=mesh.geometry.index?mesh.geometry.toNonIndexed():mesh.geometry.clone();
      geometry.applyMatrix4(inverse.clone().multiply(mesh.matrixWorld));
      // Architecture uses position/normal/UV only; preserve these attributes
      // for both the lit material and the triangle-based reflection BVH.
      for(const key of Object.keys(geometry.attributes))if(!['position','normal','uv'].includes(key))geometry.deleteAttribute(key);
      if(!geometry.attributes.normal)geometry.computeVertexNormals();
      if(!geometry.attributes.uv)geometry.setAttribute('uv',new T.BufferAttribute(new Float32Array(geometry.attributes.position.count*2),2));
      return geometry;
    });
    const geometry=mergeGeometries(parts);for(const part of parts)part.dispose();
    if(!geometry)continue;
    const source=meshes[0],batch=new T.Mesh(geometry,source.material);
    batch.name='Batched room architecture';batch.userData.batchedArchitecture=true;
    batch.castShadow=source.castShadow;batch.receiveShadow=source.receiveShadow;
    batch.renderOrder=source.renderOrder;batch.layers.mask=source.layers.mask;
    for(const mesh of meshes)mesh.removeFromParent();root.add(batch);
  }
}
