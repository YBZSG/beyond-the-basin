import * as T from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

/** Batch immutable architecture per room/material. Point-light shadows draw
 * six views each; batching preserves the exact triangles and live materials
 * while avoiding thousands of repeated draw submissions every frame.
 *
 * Batches are additionally split by indexed state: indexed meshes keep their
 * index (BoxGeometry reuses its 8 corners across 36 indices; expanding to
 * non-indexed triples the vertex buffer, the vertex shader invocations and
 * the shadow-pass vertex workload for every room). Merging stays legal
 * because mergeGeometries only requires a consistent indexed state within
 * one batch; the cost is at most one extra batch per material. */
export function batchArchitecture(root:T.Group){for(const _ of batchArchitectureSteps(root))void _;}
export function* batchArchitectureSteps(root:T.Group):Generator<void,void>{
  root.updateMatrixWorld(true);
  const inverse=root.matrixWorld.clone().invert();
  const batches=new Map<string,T.Mesh[]>();
  root.traverse(object=>{
    if(!(object instanceof T.Mesh)||object instanceof T.InstancedMesh||Array.isArray(object.material)||!object.visible)return;
    if(object.userData.luminaire||object.customDepthMaterial||object.customDistanceMaterial||object.geometry.morphAttributes.position)return;
    const key=[object.material.uuid,object.castShadow,object.receiveShadow,object.renderOrder,object.layers.mask,object.geometry.index?1:0].join('/');
    if(!batches.has(key))batches.set(key,[]);batches.get(key)!.push(object);
  });
  for(const meshes of batches.values()){
    if(meshes.length<2)continue;
    const parts:T.BufferGeometry[]=[];
    for(const mesh of meshes){
      // Clone as-is: indexed inputs stay indexed so shared vertices survive
      // the merge instead of being fanned out into per-triangle copies.
      const geometry=mesh.geometry.clone();
      geometry.applyMatrix4(inverse.clone().multiply(mesh.matrixWorld));
      // Architecture uses position/normal/UV only; preserve these attributes
      // for both the lit material and the triangle-based reflection BVH.
      for(const key of Object.keys(geometry.attributes))if(!['position','normal','uv'].includes(key))geometry.deleteAttribute(key);
      if(!geometry.attributes.normal)geometry.computeVertexNormals();
      if(!geometry.attributes.uv)geometry.setAttribute('uv',new T.BufferAttribute(new Float32Array(geometry.attributes.position.count*2),2));
      parts.push(geometry);yield;
    }
    const geometry=mergeGeometries(parts);for(const part of parts)part.dispose();
    if(!geometry)continue;
    const source=meshes[0],batch=new T.Mesh(geometry,source.material);
    batch.name='Batched room architecture';batch.userData.batchedArchitecture=true;
    batch.castShadow=source.castShadow;batch.receiveShadow=source.receiveShadow;
    batch.renderOrder=source.renderOrder;batch.layers.mask=source.layers.mask;
    for(const mesh of meshes)mesh.removeFromParent();root.add(batch);yield;
  }
}

/** Aggregate vertex/triangle counts for a subtree; used once at room build to
 * log what batching actually produced (never in the frame loop). */
export function geometryStats(root:T.Object3D){
  let vertices=0,triangles=0,meshes=0,indexed=0;
  root.traverse(o=>{
    if(!(o instanceof T.Mesh))return;
    meshes++;
    const geometry=o.geometry;
    const count=geometry.attributes.position?.count??0;
    vertices+=count;
    triangles+=geometry.index?geometry.index.count/3:count/3;
    if(geometry.index)indexed++;
  });
  return {meshes,vertices,triangles,indexed};
}
