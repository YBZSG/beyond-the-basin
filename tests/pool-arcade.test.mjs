import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { createArcadeGeometry,arcadeSolids } from '../app/pool-vct/arcade.ts';

test('arcade portals are open in both the rendered wall and collision proxies',()=>{
  const geometry=createArcadeGeometry(),mesh=new T.Mesh(geometry,new T.MeshBasicMaterial({side:T.DoubleSide}));
  mesh.updateMatrixWorld();
  const solids=arcadeSolids(0,0,new T.Color());
  const occupied=(x,y)=>solids.some(s=>x>s.min.x&&x<s.max.x&&y>s.min.y&&y<s.max.y);
  const rendered=(x,y)=>new T.Raycaster(new T.Vector3(x,y,3),new T.Vector3(0,0,-1)).intersectObject(mesh).length>0;
  for(const centre of [-10.6,0,10.6]){
    for(const x of [centre-3.5,centre,centre+3.5]){
      assert.equal(rendered(x,1.6),false);assert.equal(occupied(x,1.6),false);
      assert.equal(rendered(x,.32),false);assert.equal(occupied(x,.32),false,'water portal was blocked');
    }
    assert.equal(rendered(centre,3.5),false);assert.equal(occupied(centre,3.5),false);
    assert.equal(rendered(centre,4.2),true);assert.equal(occupied(centre,4.2),true);
  }
  for(const x of [-15.5,-5.3,5.3,15.5]){
    assert.equal(rendered(x,1.6),true);assert.equal(occupied(x,1.6),true);
  }
  geometry.dispose();mesh.material.dispose();
});

test('arcade collision proxies retain open water after a room offset',()=>{
  const geometry=createArcadeGeometry(),mesh=new T.Mesh(geometry,new T.MeshBasicMaterial({side:T.DoubleSide}));
  mesh.position.set(64,0,-32);mesh.updateMatrixWorld();
  const solids=arcadeSolids(64,-32,new T.Color());
  for(const x of [-15.5,-10.6,-5.3,0,5.3,10.6,15.5].map(x=>x+64)){
    const rendered=new T.Raycaster(new T.Vector3(x,1.6,-29),new T.Vector3(0,0,-1)).intersectObject(mesh).length>0;
    const occupied=solids.some(s=>x>s.min.x&&x<s.max.x&&-31.5>s.min.z&&-31.5<s.max.z&&1.6>s.min.y&&1.6<s.max.y);
    assert.equal(occupied,rendered,`offset wall mismatch at x=${x}`);
  }
  geometry.dispose();mesh.material.dispose();
});
