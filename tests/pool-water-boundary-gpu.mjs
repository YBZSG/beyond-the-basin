// Run via playwright-cli run-code in headed Edge against the local dev server.
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
async(page)=>{
  return await page.evaluate(async()=>{
    const source=await fetch('/app/pool-vct/shallow-water.ts').then(r=>r.text());
    const T=await import(source.match(/from\s+["']([^"']*three[^"']*)["']/)[1]);
    const {ShallowWater}=await import('/app/pool-vct/shallow-water.ts?boundary='+Date.now());
    const {WATER_FRAGMENT}=await import('/app/pool-vct/water-optics.ts?boundary='+Date.now());
    const renderer=new T.WebGLRenderer({powerPreference:'high-performance'});
    renderer.setSize(32,32);renderer.readRenderTargetPixelsAsync=undefined;
    const results=[],check=(name,pass,evidence)=>results.push({name,pass:!!pass,evidence});
    const vertexShader='void main(){gl_Position=vec4(position.xy,0,1);}';
    const cylinder={center:new T.Vector3(.03,0,.07),half:new T.Vector3(.65,2,.65),radius:.65};
    const wall={center:new T.Vector3(3,0,0),half:new T.Vector3(.2,2,2),rotation:new T.Quaternion().setFromAxisAngle(new T.Vector3(0,1,0),.57)};
    for(const size of [384,768,1152]){
      const sw=new ShallowWater(size);sw.setTerrain([cylinder,wall]);sw.foamGain=0;sw.frame(renderer,0);
      const initial=new T.ShaderMaterial({vertexShader,fragmentShader:`uniform sampler2D depth;
        void main(){gl_FragColor=texture2D(depth,gl_FragCoord.xy/${size}.0).r>0.0?vec4(0,.22,.11,.5):vec4(0);}`,
        uniforms:{depth:sw.uniforms.poolDepth},depthTest:false,depthWrite:false});
      sw.draw(renderer,initial,sw.current);initial.dispose();sw.wake();
      for(let i=0;i<60;i++)sw.frame(renderer,1/120);
      const data=new Uint16Array(size*size*4);renderer.readRenderTargetPixels(sw.current,0,0,size,size,data);
      const f=(x,z)=>T.DataUtils.fromHalfFloat(data[(x+z*size)*4+3]);
      const sample=(x,z)=>f(Math.floor((x+48)/sw.cell),Math.floor((z+48)/sw.cell));
      const reference=sample(-3,-3);let min=1,max=0,dry=0,n=0;
      for(let z=1;z<size-1;z++)for(let x=1;x<size-1;x++){
        const wx=(x+.5)*sw.cell-48,wz=(z+.5)*sw.cell-48;
        if(Math.abs(wx)>5||Math.abs(wz)>4)continue;
        if(sw.depthData[x+z*size]<=0){dry=Math.max(dry,f(x,z));continue;}
        if([x-1+z*size,x+1+z*size,x+(z-1)*size,x+(z+1)*size].some(i=>sw.depthData[i]<=0)){
          min=Math.min(min,f(x,z));max=Math.max(max,f(x,z));n++;
        }
      }
      check(`${size}: foam at curved and diagonal walls has no extra loss`,n>0&&reference>0&&Math.abs(min-reference)<.001&&Math.abs(max-reference)<.001&&dry===0,{n,min,max,reference,dry});
      // Exercise the actual render reconstruction on a ring just outside the
      // cylinder. Every angle must stay covered, including cut-cell corners.
      const foam=WATER_FRAGMENT.slice(WATER_FRAGMENT.indexOf('float foamField'),WATER_FRAGMENT.indexOf('float foamNoise'));
      const ring=new T.ShaderMaterial({vertexShader,fragmentShader:`uniform sampler2D poolSurface,poolDepth;uniform float poolCell;
        ${foam}
        void main(){float angle=gl_FragCoord.x/256.0*6.283185307;vec2 p=vec2(.03,.07)+vec2(cos(angle),sin(angle))*.66;
          gl_FragColor=vec4(foamField(p),0,0,1);}`,
        uniforms:{poolSurface:{value:sw.current.texture},poolDepth:sw.uniforms.poolDepth,poolCell:{value:sw.cell}},depthTest:false,depthWrite:false});
      const target=new T.WebGLRenderTarget(256,1,{type:T.HalfFloatType,depthBuffer:false});
      sw.draw(renderer,ring,target);const pixels=new Uint16Array(256*4);renderer.readRenderTargetPixels(target,0,0,256,1,pixels);
      let ringMin=1,ringMax=0;for(let i=0;i<256;i++){const v=T.DataUtils.fromHalfFloat(pixels[i*4]);ringMin=Math.min(ringMin,v);ringMax=Math.max(ringMax,v);}
      check(`${size}: rendered foam reaches every side of the cylinder`,Math.abs(ringMin-reference)<.001&&Math.abs(ringMax-reference)<.001,{ringMin,ringMax,reference});
      ring.dispose();target.dispose();sw.dispose();
    }
    const q=window.__poolQA;q.simulate(false);q.view([-6.85,1.2,2.15],[-8,.25,1]);
    check('game preserves cylindrical collider through room assembly',q.waterDepth(-7.5,1.5)>.5&&q.waterDepth(-8,1)===0,{corner:q.waterDepth(-7.5,1.5),inside:q.waterDepth(-8,1)});
    const gl=renderer.getContext(),ext=gl.getExtension('WEBGL_debug_renderer_info');
    const gpu=ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER);renderer.dispose();
    if(results.some(r=>!r.pass))throw new Error(JSON.stringify({gpu,results}));
    return {gpu,passed:results.length,results};
  });
}
