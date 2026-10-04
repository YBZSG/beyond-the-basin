// Run in Microsoft Edge against the dev server with playwright-cli run-code.
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
async (page) => {
  const errors=[];
  const listener=message=>{if(message.type()==='error')errors.push(message.text());};
  page.on('console',listener);
  try{return await page.evaluate(async()=>{
    const T=await import('/node_modules/.vite/deps/three.js');
    const {createBackend}=await import('/app/pool-vct/backend.ts');
    const {colorDepthCopy}=await import('/app/pool-vct/scene-pass.ts');
    const {FullScreenQuad}=await import('/node_modules/three/examples/jsm/postprocessing/Pass.js');
    const {ShallowWater}=await import('/app/pool-vct/shallow-water.ts');
    const N=await import('/node_modules/.vite/deps/three_tsl.js');
    const W=await import('/node_modules/.vite/deps/three_webgpu.js');
    const {liveTexture}=await import('/app/pool-vct/webgpu/legacy-texture.ts');
    const {renderer,kind}=await createBackend(false,'webgpu');
    renderer.setSize(64,64);
    const results=[],check=(name,pass,evidence)=>results.push({name,pass,evidence});
    const rt=()=>{const target=new T.RenderTarget(16,16,{type:T.HalfFloatType});target.depthTexture=new T.DepthTexture(16,16);return target;};
    const targets=[rt(),rt(),rt()];
    const material=new W.NodeMaterial();material.toneMapped=false;material.depthFunc=T.AlwaysDepth;
    material.vertexNode=N.vec4(N.positionGeometry.xy,N.uv().y.mul(.5).add(.2),1);
    material.fragmentNode=N.vec4(N.uv(),.25,1);
    const quad=new FullScreenQuad(material);
    renderer.setRenderTarget(targets[0]);renderer.clear();quad.render(renderer);
    const copy=colorDepthCopy(targets[0].texture,targets[0].depthTexture);
    quad.material=copy;
    for(let i=1;i<3;i++){
      copy.uniforms.image.value=targets[i-1].texture;copy.uniforms.depthImage.value=targets[i-1].depthTexture;
      renderer.setRenderTarget(targets[i]);renderer.clear();quad.render(renderer);
    }
    const data=await Promise.all(targets.map(t=>renderer.readRenderTargetPixelsAsync(t,0,0,16,16)));
    const green=i=>T.DataUtils.fromHalfFloat(data[i][4*8+1]);
    const error=(a,b)=>Math.max(...data[a].map((v,i)=>Math.abs(T.DataUtils.fromHalfFloat(v)-T.DataUtils.fromHalfFloat(data[b][i]))));
    check('WebGPU is the active backend',kind==='webgpu',{kind});
    check('asymmetric frame stays upright through successive colour/depth copies',green(0)>.9&&error(0,1)<.002&&error(0,2)<.002,{topGreen:data.map((_,i)=>green(i)),copyError:[error(0,1),error(0,2)]});
    const depthProbe=new T.ShaderMaterial({uniforms:{source:{value:targets[0].depthTexture}},
      vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
      fragmentShader:'uniform sampler2D source;varying vec2 vUv;void main(){gl_FragColor=vec4(vec3(texture2D(source,vUv).r),1);}',toneMapped:false,depthWrite:false,depthTest:false});
    const scratch=new T.RenderTarget(16,16,{type:T.HalfFloatType,depthBuffer:false}),depths=[];
    quad.material=depthProbe;
    for(const target of targets){depthProbe.uniforms.source.value=target.depthTexture;renderer.setRenderTarget(scratch);quad.render(renderer);depths.push(await renderer.readRenderTargetPixelsAsync(scratch,0,0,16,16));}
    const depthError=Math.max(...depths[0].map((v,i)=>Math.max(Math.abs(T.DataUtils.fromHalfFloat(v)-T.DataUtils.fromHalfFloat(depths[1][i])),Math.abs(T.DataUtils.fromHalfFloat(v)-T.DataUtils.fromHalfFloat(depths[2][i])))));
    check('colour and nonuniform depth retain the same vertical coordinates',T.DataUtils.fromHalfFloat(depths[0][0])>.65&&depthError<.002,{topDepth:T.DataUtils.fromHalfFloat(depths[0][0]),depthError});
    const volume=value=>{const t=new T.Data3DTexture(new Uint8Array([value,0,0,255]),1,1,1);t.needsUpdate=true;t.minFilter=t.magFilter=T.LinearFilter;return t;};
    const empty=volume(0),boxes=Array.from({length:4},()=>({value:empty})),maps=boxes.map(u=>liveTexture(u,true));
    const sample=N.wgslFn('fn liveVolumes(a:texture_3d<f32>,b:texture_3d<f32>,c:texture_3d<f32>,d:texture_3d<f32>,s:sampler)->vec4f{return vec4f(textureSampleLevel(a,s,vec3f(.5),0).r,textureSampleLevel(b,s,vec3f(.5),0).r,textureSampleLevel(c,s,vec3f(.5),0).r,textureSampleLevel(d,s,vec3f(.5),0).r);}');
    const liveMaterial=new W.NodeMaterial();liveMaterial.fragmentNode=sample(...maps,N.sampler(maps[0]));liveMaterial.toneMapped=false;
    quad.material=liveMaterial;quad.render(renderer);
    boxes.forEach((u,i)=>u.value=volume((i+1)*51));empty.dispose();quad.render(renderer);
    const levels=await renderer.readRenderTargetPixelsAsync(scratch,0,0,1,1),actual=Array.from(levels,T.DataUtils.fromHalfFloat);
    check('voxel texture bindings split and update after a shared placeholder is disposed',actual.every((v,i)=>Math.abs(v-(i+1)*.2)<.003),{actual});
    boxes.forEach(u=>u.value.dispose());liveMaterial.dispose();depthProbe.dispose();scratch.dispose();
    const sw=new ShallowWater(384);sw.setTerrain([]);sw.frame(renderer,0);sw.impact(2,7,.2);
    for(let i=0;i<32;i++){
      sw.frame(renderer,1/120);
      if(i%4===3)await renderer.readRenderTargetPixelsAsync(sw.current,0,0,1,1);
    }
    sw.frame(renderer,0);
    const wave=await renderer.readRenderTargetPixelsAsync(sw.current,0,0,384,384);
    let nan=0,peak=0,weightedZ=0,total=0;
    for(let i=0;i<wave.length;i+=4){
      const h=T.DataUtils.fromHalfFloat(wave[i]);
      if(!Number.isFinite(h))nan++;
      peak=Math.max(peak,Math.abs(h));
      const x=(i/4%384+.5)*.25-48,z=48-(Math.floor(i/4/384)+.5)*.25;
      if(Math.abs(x-2)<3&&Math.abs(z-7)<3){const w=Math.abs(h);total+=w;weightedZ+=w*z;}
    }
    const near=sw.heightAt(2,7),mirrored=sw.heightAt(2,-7);
    check('finite waves and CPU buoyancy readback agree at asymmetric world Z',nan===0&&peak>.001&&Math.abs(near)>.001&&Math.abs(mirrored)<Math.abs(near)*.1&&Math.abs(weightedZ/total-7)<.5,{nan,peak,near,mirrored,centroidZ:weightedZ/total,debug:sw.debug()});
    sw.dispose();quad.dispose();material.dispose();copy.dispose();targets.forEach(t=>t.dispose());renderer.dispose();
    return {results,passed:results.every(r=>r.pass)};
  }).then(result=>({...result,errors}));}
  finally{page.off('console',listener);}
}
