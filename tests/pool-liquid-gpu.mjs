// playwright-cli -s=liquid-sheet run-code --filename tests/pool-liquid-gpu.mjs
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
async(page)=>{
  return await page.evaluate(async()=>{
    const {LIQUID_MPM}=await import('/app/pool-vct/liquid-mpm-shader.ts?verify='+Date.now());
    const adapter=await navigator.gpu.requestAdapter(),device=await adapter.requestDevice();
    const shader=device.createShaderModule({code:LIQUID_MPM});
    const names=['clear','mass','pressure','velocity','gather','resetHeads','link','exportState'];
    const pipelines=await Promise.all(names.map(entryPoint=>device.createComputePipelineAsync({layout:'auto',compute:{module:shader,entryPoint}})));
    const results=[];
    const check=(name,pass,evidence)=>results.push({name,pass:!!pass,evidence});
    async function run(input,steps,h=.02){
      const n=input.length/20,usage=GPUBufferUsage;
      const buffers=[
        device.createBuffer({size:input.byteLength,usage:usage.STORAGE|usage.COPY_DST}),
        device.createBuffer({size:80**3*16,usage:usage.STORAGE}),
        device.createBuffer({size:64,usage:usage.UNIFORM|usage.COPY_DST}),
        device.createBuffer({size:n*80,usage:usage.STORAGE|usage.COPY_SRC}),
        device.createBuffer({size:(n+1)*4,usage:usage.STORAGE}),
        device.createBuffer({size:n*80,usage:usage.MAP_READ|usage.COPY_DST}),
      ];
      const bindings=[[1],[0,1,2],[0,1,2],[1,2,4],[0,1,2,4],[1],[0,1,2,4],[0,1,2,3,4]];
      const groups=pipelines.map((pipeline,i)=>device.createBindGroup({layout:pipeline.getBindGroupLayout(0),entries:bindings[i].map(binding=>({binding,resource:{buffer:buffers[binding]}}))}));
      const params=new Float32Array(16);new Uint32Array(params.buffer)[0]=n;params[1]=h;params[2]=1/720;
      device.queue.writeBuffer(buffers[0],0,input);device.queue.writeBuffer(buffers[2],0,params);
      const encoder=device.createCommandEncoder(),pass=encoder.beginComputePass();
      for(let k=0;k<steps;k++)for(let stage=0;stage<5;stage++){
        pass.setPipeline(pipelines[stage]);pass.setBindGroup(0,groups[stage]);pass.dispatchWorkgroups(stage===0||stage===3?80**3/128:Math.ceil(n/64));
      }
      for(let stage=5;stage<8;stage++){pass.setPipeline(pipelines[stage]);pass.setBindGroup(0,groups[stage]);pass.dispatchWorkgroups(stage===5?80**3/128:Math.ceil(n/64));}pass.end();
      encoder.copyBufferToBuffer(buffers[3],0,buffers[5],0,n*80);device.queue.submit([encoder.finish()]);await buffers[5].mapAsync(GPUMapMode.READ);
      const output=new Float32Array(buffers[5].getMappedRange().slice(0));buffers[5].unmap();buffers.forEach(b=>b.destroy());return output;
    }
    try{
      const free=new Float32Array(20);free.set([40,30,40,1,40,0,-15,1]);
      const frames=120,h=.02,dt=1/720,t=frames*dt,out=await run(free,frames,h);
      check('airborne liquid obeys gravity in metres and seconds',Math.abs(out[5]*h+9.81*t)<.025&&Math.abs((out[1]-30)*h+9.81*dt*dt*frames*(frames+1)/2)<.003,{vy:out[5]*h,fall:(out[1]-30)*h,expectedFall:-9.81*dt*dt*frames*(frames+1)/2});
      check('APIC transfer preserves horizontal inertial motion',Math.abs((out[0]-40)*h-.8*t)<.003&&Math.abs(out[4]*h-.8)<.025,{dx:(out[0]-40)*h,vx:out[4]*h});
      check('surface reconstruction remains finite for an isolated particle',out.every(Number.isFinite)&&out[8]>0&&out[13]>0&&out[18]>0,{axes:[out[8],out[13],out[18]]});
      const dense=[];
      for(let x=0;x<6;x++)for(let y=0;y<6;y++)for(let z=0;z<6;z++)dense.push(38+x*.4,28+y*.4,38+z*.4,8,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0);
      const compressed=await run(new Float32Array(dense),36);
      let outward=0,maxSpeed=0;
      for(let i=0;i<compressed.length;i+=20){outward+=(compressed[i]-39)*compressed[i+4]+(compressed[i+2]-39)*compressed[i+6];maxSpeed=Math.max(maxSpeed,Math.hypot(compressed[i+4],compressed[i+5],compressed[i+6])*.02);}
      check('compressed liquid expands under pressure without an elastic rest shape',compressed.every(Number.isFinite)&&outward>0&&maxSpeed<7.05,{outward,maxSpeed});
      if(results.some(r=>!r.pass))throw new Error(JSON.stringify(results));return results;
    }finally{device.destroy();}
  });
}
