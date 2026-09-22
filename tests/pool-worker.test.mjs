import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import * as T from 'three';
import { MeshBVH } from 'three-mesh-bvh';
import { packReflectionTextures } from '../app/pool-vct/rt-packing.ts';
register('./worker-stub-loader.mjs',import.meta.url);
const { ReflectionField }=await import('../app/pool-vct/rt.ts');

test('replaced and disposed BVH workers cannot publish stale worlds',()=>{
  const field=new ReflectionField(),geometry=new T.BoxGeometry().toNonIndexed();
  geometry.clearGroups();
  try{
    field.beginRebuild([],[]);field.stepRebuild(3);
    const old=globalThis.__bvhWorkers.at(-1),oldVersion=old.message.version;
    field.invalidate();field.beginRebuild([],[]);field.stepRebuild(3);
    const current=globalThis.__bvhWorkers.at(-1);
    assert.equal(old.terminated,true);
    old.onmessage({data:{version:oldVersion,error:'obsolete'}});
    old.onerror({message:'obsolete failure'});
    assert.equal(field.stepRebuild(3),false);assert.equal(field.error,'');
    const bvh=new MeshBVH(geometry),textures=packReflectionTextures(bvh,new Float32Array(geometry.attributes.position.count*4));
    current.onmessage({data:{version:current.message.version,textures:[...textures],serialized:MeshBVH.serialize(bvh)}});
    assert.equal(field.stepRebuild(3),false);let uploads=0;
    for(let i=0;i<textures.length;i++){
      assert.equal(field.uniforms.rtReady.value,0,'partial uploads must not expose an incomplete BVH');
      assert.equal(field.stepRebuild(3,{initTexture(texture){uploads++;assert.equal(texture.image.data,textures[i].data);}}),i===textures.length-1);
      assert.equal(uploads,i+1,'one upload per scheduled frame');
    }
    assert.equal(field.uniforms.rtReady.value,1);
    field.dispose();current.onmessage({data:{version:current.message.version,error:'after disposal'}});
    assert.equal(field.uniforms.rtReady.value,0);assert.equal(field.ready,null);assert.equal(current.terminated,true);
  }finally{geometry.dispose();field.dispose();delete globalThis.__bvhWorkers;}
});
