// playwright-cli -s=water-opt run-code --filename tests/pool-water-layers-gpu.mjs
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
async (page) => {
  return await page.evaluate(async()=>{
    const source=await fetch('/app/pool-vct/shallow-water.ts').then(r=>r.text());
    const T=await import(source.match(/from\s+["']([^"']*three[^"']*)["']/)[1]);
    const {ShallowWater}=await import('/app/pool-vct/shallow-water.ts');
    const {RippleDetail}=await import('/app/pool-vct/ripple-detail.ts');
    const {InteractiveWater}=await import('/app/pool-vct/water-system.ts');
    const renderer=new T.WebGLRenderer({powerPreference:'high-performance'});renderer.setSize(64,64);renderer.readRenderTargetPixelsAsync=undefined;
    const results=[],check=(name,pass,evidence)=>results.push({name,pass:!!pass,evidence});
    const read=(field,domain=96)=>{
      const target=field.current??field.target,size=target.width,data=new Uint16Array(size*size*4);
      renderer.readRenderTargetPixels(target,0,0,size,size,data);
      const at=(x,z,k=0)=>T.DataUtils.fromHalfFloat(data[(Math.floor((x/domain+.5)*size)+Math.floor((z/domain+.5)*size)*size)*4+k]);
      let peak=0,energy=0,finite=true,alphaPeak=0;
      for(let i=0;i<data.length;i+=4){const h=T.DataUtils.fromHalfFloat(data[i]);peak=Math.max(peak,Math.abs(h));energy+=h*h;alphaPeak=Math.max(alphaPeak,T.DataUtils.fromHalfFloat(data[i+3]));for(let k=0;k<4;k++)finite&&=Number.isFinite(T.DataUtils.fromHalfFloat(data[i+k]));}
      return {at,peak,energy,finite,alphaPeak};
    };
    for(const size of [384,768,1152]){
      const sw=new ShallowWater(size);sw.setTerrain([]);sw.waveSpeed=3;sw.damping=.05;sw.viscosity=.012;sw.frame(renderer,0);
      for(let i=0;i<120;i++){if(i%12===0)for(let j=0;j<8;j++)sw.impact(Math.sin(j)*2,Math.cos(j)*2,.4);sw.frame(renderer,1/60);}
      const f=read(sw);check(`grid ${size} remains finite at maximum speed and viscosity`,f.finite&&f.peak>.0001&&f.peak<.351,{peak:f.peak,timestep:sw.velocity.uniforms.poolDt.value});sw.dispose();
    }
    let sw=new ShallowWater();sw.setTerrain([]);sw.impact(2,0,.2);sw.frame(renderer,1/60);const original=read(sw);
    const average=k=>(original.at(2.0625,.0625,k)+original.at(2.1875,.0625,k)+original.at(2.0625,.1875,k)+original.at(2.1875,.1875,k))*.25;
    const before=average(0);
    const coarse=new ShallowWater(384);coarse.setTerrain([]);coarse.inherit(renderer,sw);const after=read(coarse).at(2,0);
    check('quality resampling retains live elevation and velocity',Math.abs(after)>.002&&Math.abs(after-before)<.00002&&Math.abs(read(coarse).at(2,0,1)-average(1))<.00002&&!coarse.settled,{before,after});sw.dispose();coarse.dispose();
    const energies=[];
    for(const loss of [0,4]){sw=new ShallowWater();sw.wallLoss=loss;sw.impact(14.8,10,.2);for(let i=0;i<180;i++)sw.frame(renderer,1/120);energies.push(read(sw).energy);sw.dispose();}
    check('lossy pool wall reflects with partial energy absorption',energies[1]>0&&energies[1]<energies[0]*.97,energies);
    sw=new ShallowWater();sw.setTerrain([]);sw.frame(renderer,0);
    const detail=new RippleDetail(768,sw.uniforms.poolDepth);detail.frame(renderer,0,true);
    check('independent ripple field starts exactly still',read(detail,48).peak===0,{});
    detail.impact(0,0,.003);for(let i=0;i<120;i++)detail.frame(renderer,1/120,true);
    let f=read(detail,48);let ring=0;for(let x=.65;x<1.1;x+=.0625)ring=Math.max(ring,Math.abs(f.at(x,0)));
    check('fine ripple propagates while shallow physics remains still',ring>1e-6&&read(sw).peak===0,{ring,detailPeak:f.peak});
    for(let i=0;i<850;i++)detail.frame(renderer,1/120,true);
    check('fine ripple dissipates without residual background noise',read(detail,48).peak===0,{});detail.dispose();
    sw.setBlocks([]);const walls=new RippleDetail(768,sw.uniforms.poolDepth);walls.impact(15.4,10,.003);walls.frame(renderer,1/120,true);f=read(walls,48);
    check('fine ripple injection cannot cross a pool wall',Math.abs(f.at(15.4,10))>1e-4&&f.at(16.6,10)===0,{near:f.at(15.4,10),far:f.at(16.6,10)});
    walls.dispose();sw.dispose();
    const water=new InteractiveWater();water.setTerrain([]);water.applySettings({quality:'Medium',microStrength:0,environmentalStrength:0});water.render(renderer,0);
    const flat=read(water,32);water.impact(0,0,.3);for(let i=1;i<=16;i++)water.render(renderer,i/120);
    const ripple=read(water,32);let change=0;
    for(let z=-2;z<2;z+=.1)for(let x=-2;x<2;x+=.1)change+=Math.abs(flat.at(x,z)-ripple.at(x,z));
    check('computed caustics change with the shared wave normal',change>.01,{change});
    water.dispose();
    // Foam: repeated splashes must deposit into the state alpha channel, stay
    // bounded in [0,1], and decay away once the pool goes quiet again.
    sw=new ShallowWater();sw.setTerrain([]);sw.frame(renderer,0);
    for(let i=0;i<90;i++){if(i%30===0)for(let j=0;j<4;j++)sw.impact(Math.sin(j*2)*1.5,Math.cos(j*2)*1.5,.3);sw.frame(renderer,1/60);}
    const foamy=read(sw);
    check('splash deposits bounded foam into the state alpha channel',foamy.alphaPeak>.02&&foamy.alphaPeak<=1&&foamy.finite,{alphaPeak:foamy.alphaPeak});
    for(let i=0;i<600;i++)sw.frame(renderer,1/60);
    const cleared=read(sw);
    check('foam decays away on a quiet pool',cleared.alphaPeak<foamy.alphaPeak*.5&&cleared.alphaPeak<.01,{before:foamy.alphaPeak,after:cleared.alphaPeak});
    sw.dispose();
    // Gentle interaction and returning droplets cannot seed endless white
    // patches. A forceful entry must remain local even as its wave travels.
    sw=new ShallowWater();sw.setTerrain([]);sw.frame(renderer,0);
    for(let i=0;i<180;i++){if(i%6===0)sw.impact(0,0,.02);sw.frame(renderer,1/60);}
    const gentle=read(sw);
    check('returning droplets do not regenerate surface foam',gentle.alphaPeak<.001,{peak:gentle.alphaPeak});
    sw.dispose();sw=new ShallowWater();sw.setTerrain([]);sw.frame(renderer,0);
    sw.impact(0,0,.5);for(let i=0;i<30;i++)sw.frame(renderer,1/60);
    const local=read(sw);let distant=0;
    for(let x=2;x<12;x+=.25)distant=Math.max(distant,local.at(x,0,3));
    check('entry aeration stays near the impact instead of whitening the wave train',local.alphaPeak>.03&&distant<.01,{peak:local.alphaPeak,distant});
    sw.dispose();
    renderer.dispose();
    if(results.some(r=>!r.pass))throw new Error(JSON.stringify(results));
    return {passed:results.length,total:results.length,results};
  });
}
