// Run against the development server in Edge with playwright-cli run-code.
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
async (page) => {
  return await page.evaluate(async()=>{
    const source=await fetch('/app/pool-vct/wet-reflections.ts').then(r=>r.text());
    const T=await import(source.match(/from\s+["']([^"']*three[^"']*)["']/)[1]);
    const {WetReflectionPass}=await import('/app/pool-vct/wet-reflections.ts');
    const renderer=new T.WebGLRenderer({powerPreference:'high-performance'});renderer.setSize(256,256);
    const scene=new T.Scene(),camera=new T.PerspectiveCamera(55,1,.1,40);
    camera.position.set(3,2.5,6);camera.lookAt(0,.8,0);camera.updateMatrixWorld();
    const map=new T.DataTexture(new Uint8Array([128,128,255,255]),1,1);map.needsUpdate=true;
    const rough=new T.DataTexture(new Uint8Array([128,128,128,255]),1,1);rough.needsUpdate=true;
    const tile=new T.MeshPhysicalMaterial({color:'#cccccc',clearcoat:1,clearcoatNormalMap:map,roughnessMap:rough});
    const floor=new T.Mesh(new T.PlaneGeometry(20,20),tile);floor.rotation.x=-Math.PI/2;floor.position.y=.4;scene.add(floor);
    const red=new T.MeshBasicMaterial({color:'#ff0000'}),box=new T.Mesh(new T.BoxGeometry(1.2,1.2,1.2),red);
    box.position.set(0,1.1,0);scene.add(box);scene.add(new T.AmbientLight(0xffffff,1));
    const image=new T.WebGLRenderTarget(256,256,{type:T.HalfFloatType});image.depthTexture=new T.DepthTexture(256,256);
    const output=new T.WebGLRenderTarget(256,256,{type:T.HalfFloatType});
    const pass=new WetReflectionPass(scene,camera,new Set([tile]),image.texture,image.depthTexture,(_stage,fn)=>fn());pass.setSize(256,256);
    const sample=()=>{
      renderer.setRenderTarget(image);renderer.clear();renderer.render(scene,camera);pass.render(renderer,output,image);
      const target=pass.reflections,data=new Uint16Array(target.width*target.height*4);
      renderer.readRenderTargetPixels(target,0,0,target.width,target.height,data);
      let count=0,cx=0,valid=0,alphaPeak=0;const ray=new T.Raycaster();
      for(let y=0;y<target.height;y++)for(let x=0;x<target.width;x++){
        const i=(x+y*target.width)*4,r=T.DataUtils.fromHalfFloat(data[i]),g=T.DataUtils.fromHalfFloat(data[i+1]),a=T.DataUtils.fromHalfFloat(data[i+3]);
        alphaPeak=Math.max(alphaPeak,a);
        if(r>.6&&g<.12&&a>.002){
          count++;cx+=x;
          ray.setFromCamera(new T.Vector2((x+.5)/target.width*2-1,(y+.5)/target.height*2-1),camera);
          const hit=ray.intersectObject(floor)[0];
          if(hit){const dir=ray.ray.direction.clone().reflect(new T.Vector3(0,1,0));ray.set(hit.point.clone().addScaledVector(dir,.03),dir);if(ray.intersectObject(box).length)valid++;}
        }
      }
      return {count,cx:cx/Math.max(1,count),valid,alphaPeak};
    };
    const before=sample();box.position.x=1.8;box.updateMatrixWorld();const moved=sample();
    box.visible=false;const removed=sample();box.visible=true;
    const glError=renderer.getContext().getError(),results=[
      {name:'current-frame props remain visible in wet ceramic reflections',pass:before.count>10&&before.alphaPeak>.005,evidence:before},
      {name:'reflected prop follows its new position without stale capture',pass:moved.count>10&&Math.abs(moved.cx-before.cx)>5,evidence:moved},
      {name:'reflection hits agree with independent geometry raycasts',pass:before.valid/before.count>.9&&moved.valid/moved.count>.9,evidence:{before:before.valid/before.count,moved:moved.valid/moved.count}},
      {name:'removed props leave no residual reflection and no GL errors',pass:removed.count===0&&glError===0,evidence:{removed,glError}},
    ];
    pass.dispose();image.dispose();output.dispose();floor.geometry.dispose();box.geometry.dispose();tile.dispose();red.dispose();map.dispose();rough.dispose();renderer.dispose();
    if(results.some(r=>!r.pass))throw new Error(JSON.stringify(results));
    return {passed:results.length,results};
  });
}
