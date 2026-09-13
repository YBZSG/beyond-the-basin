// With the local dev server and an Edge session open:
// playwright-cli -s=water-repair run-code --filename tests/pool-water-gpu.mjs
// This function expression is the Playwright CLI's file format.
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
async (page) => {
  return await page.evaluate(async () => {
    const source=await fetch('/app/pool-vct/shallow-water.ts').then(r=>r.text());
    const threeUrl=source.match(/from\s+["']([^"']*three[^"']*)["']/)[1];
    const T=await import(threeUrl);
    const {ShallowWater,SW_SIZE,SW_CELL,SW_HALF,SW_STEP}=await import('/app/pool-vct/shallow-water.ts');
    const renderer=new T.WebGLRenderer({powerPreference:'high-performance'});
    renderer.readRenderTargetPixelsAsync=undefined;
    renderer.setSize(64,64);
    // Read the actual half-float simulation target, rather than a CPU double.
    const read=(sw)=>{
      const data=new Uint16Array(SW_SIZE*SW_SIZE*4);
      renderer.readRenderTargetPixels(sw.current,0,0,SW_SIZE,SW_SIZE,data);
      const at=(x,z,k=0)=>T.DataUtils.fromHalfFloat(data[(Math.floor((x+SW_HALF)/SW_CELL)+Math.floor((z+SW_HALF)/SW_CELL)*SW_SIZE)*4+k]);
      return {data,at};
    };
    const step=(sw,n)=>{for(let i=0;i<n;i++)sw.frame(renderer,SW_STEP);};
    const make=()=>{const sw=new ShallowWater();sw.setTerrain([]);sw.frame(renderer,0);return sw;};
    const results=[];
    const check=(name,ok,evidence)=>{results.push({name,pass:!!ok,evidence});};
    let sw=make();
    sw.impact(30,30,.2);step(sw,20);
    let f=read(sw);
    check('positive quadrant beyond the old 767 boundary evolves',Math.abs(f.at(30,30))>.0001,{height:f.at(30,30)});
    sw.dispose();
    // Wall versus doorway in the same run. No source is on the far side.
    sw=new ShallowWater();sw.frame(renderer,0);sw.impact(14.8,10,.2);sw.impact(14.8,0,.2);step(sw,120);f=read(sw);
    const wall=f.at(17,10),door=f.at(17,0),closed=f.at(16,10);
    check('wall blocks transmission and portal transmits',Math.abs(wall)<1e-5&&Math.abs(door)>.0001&&closed===0,{wall,door,closed});
    sw.dispose();
    // The initial footprint cannot inject directly across a nearby wall.
    sw=new ShallowWater();sw.frame(renderer,0);sw.impact(15.5,10,.3);step(sw,1);f=read(sw);
    check('splash injection does not reach through thin walls',f.at(16.5,10)===0&&Math.abs(f.at(15.5,10))>.003,{near:f.at(15.5,10),far:f.at(16.5,10)});sw.dispose();
    const reflected=[];
    for(const walls of [false,true]){
      sw=make();if(walls)sw.setBlocks([]);sw.impact(14,10,.2);step(sw,150);f=read(sw);
      let signal=0;for(let x=12;x<15;x+=SW_CELL)signal+=Math.abs(f.at(x,10));
      reflected.push(signal);sw.dispose();
    }
    check('wall returns a reflected wave',reflected[1]>reflected[0]*1.3,reflected);
    sw=make();sw.setTerrain([{center:new T.Vector3(0,0,0),half:new T.Vector3(.7,2,.7),radius:.7}]);
    sw.impact(-2.2,0,.2);step(sw,96);const sides=[0,0];let behind=0;
    for(let i=0;i<12;i++){step(sw,12);f=read(sw);
      sides[0]=Math.max(sides[0],Math.abs(f.at(.6,1.0625)));sides[1]=Math.max(sides[1],Math.abs(f.at(.6,-1.0625)));
      behind=Math.max(behind,Math.abs(f.at(1.5,0)));}
    check('waves propagate around both sides of a round pillar',sides.every(v=>v>.00005)&&behind>.00005&&f.at(0,0)===0,{sides,behind,inside:f.at(0,0)});sw.dispose();
    // Still water over a step must remain exactly still.
    sw=make();sw.setTerrain([{center:new T.Vector3(0,-.4,0),half:new T.Vector3(6,.4,6)}]);
    sw.push(-15,-15,.01,0,.3);step(sw,120);f=read(sw);
    check('resting water over a bed step remains balanced',f.at(0,0)===0&&f.at(6,0)===0,{shallow:sw.depthAt(0,0),deep:sw.depthAt(8,0),edgeHeight:f.at(6,0)});
    sw.dispose();
    // Same source and elapsed time in two constant-depth basins.
    const arrival=[];
    for(const depth of [.26,1.04]){
      sw=make();if(depth<1)sw.setTerrain([{center:new T.Vector3(0,-.47,0),half:new T.Vector3(47,.53,47)}]);
      sw.impact(0,0,.12);step(sw,120);f=read(sw);
      let weight=0,moment=0;
      for(let x=.5;x<5;x+=SW_CELL){const a=Math.abs(f.at(x,0));weight+=a;moment+=x*a;}
      arrival.push({depth,centre:moment/weight,sample3:f.at(3,0)});sw.dispose();
    }
    check('waves propagate faster in deeper water',arrival[1].centre>arrival[0].centre*1.4,arrival);
    // Translation is a single exact copy, and newly exposed cells are zero.
    sw=make();sw.impact(10,2,.2);step(sw,15);const before=read(sw).at(10,2);
    sw.rebase(32,0);sw.setTerrain([]);sw.frame(renderer,0);f=read(sw);
    check('room rebase preserves the overlapping wave once',Math.abs(before)>.0001&&Math.abs(f.at(-22,2)-before)<1e-6&&f.at(42,2)===0,{before,after:f.at(-22,2),exposed:f.at(42,2)});
    sw.dispose();
    // Many independent events in one step, all must reach the texture.
    sw=make();const sources=[];
    for(let j=0;j<6;j++)for(let i=0;i<8;i++){const x=-24+i*6,z=-18+j*6;sources.push([x,z]);sw.impact(x,z,.12);}
    step(sw,1);f=read(sw);const present=sources.filter(([x,z])=>Math.abs(f.at(x,z))>.003).length;
    check('48 simultaneous disturbances survive batching',present===48&&sw.pendingSplats.length===0,{present});sw.dispose();
    // Continuous momentum gives a bow/trailing height pair and a flow field.
    sw=make();for(let i=0;i<180;i++){sw.push(-3+i*SW_STEP*2,0,2*.45*SW_STEP,0,.3);step(sw,1);}
    f=read(sw);const bow=f.at(.3,0),tail=f.at(-1.5,0),flow=f.at(-.2,0,1);
    check('continuous movement leaves a wake and flow',Math.abs(bow)+Math.abs(tail)>.002&&Math.abs(flow)>.005,{bow,tail,flow});
    sw.dispose();
    // Couple an actual prop to the actual GPU velocity field, with reaction.
    const {PropPhysics}=await import('/app/pool-vct/physics.ts');
    sw=make();const body={position:new T.Vector3(0,.445,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:.2,floatBias:.125,name:'duck',kind:'duck',visual:new T.Group(),parts:[],promoted:true,splashCooldown:0,hitCooldown:0};
    const physics=new PropPhysics(new T.Scene(),()=>{},(x,z)=>.32+sw.heightAt(x,z),undefined,(x,z)=>sw.flowAt(x,z),(x,z,u,v,r)=>sw.push(x,z,u,v,r));
    physics.add(body);const camera=new T.PerspectiveCamera();camera.position.set(8,3,8);
    for(let i=0;i<240;i++){sw.push(-.4,0,.65*SW_STEP,0,.5);step(sw,1);physics.update(SW_STEP,camera,[],i*SW_STEP);}
    check('floating duck is transported by the GPU flow',body.position.x>.06&&Math.abs(body.position.y-.445)<.12,{position:body.position.toArray(),velocity:body.velocity.toArray()});
    // Thousands of coupled ticks must dissipate after the forcing is removed.
    let maxHeight=0;
    for(let i=0;i<1800;i++){
      if(i<180&&i%6===0)for(let j=0;j<24;j++)sw.impact(Math.sin(j*2.4)*3,Math.cos(j*2.4)*3,.2);
      step(sw,1);physics.update(SW_STEP,camera,[],i*SW_STEP);
      if(i%300===0){f=read(sw);for(let j=0;j<f.data.length;j+=4)maxHeight=Math.max(maxHeight,Math.abs(T.DataUtils.fromHalfFloat(f.data[j])));}
    }
    f=read(sw);let finalPeak=0,finite=true;
    for(let i=0;i<f.data.length;i++){const v=T.DataUtils.fromHalfFloat(f.data[i]);if(!Number.isFinite(v))finite=false;if(i%4===0)finalPeak=Math.max(finalPeak,Math.abs(v));}
    check('sustained multi-source and prop interaction stays finite and decays',finite&&maxHeight<.351&&finalPeak<.003,{maxHeight,finalPeak,energy:sw.energy,props:body.position.toArray()});
    sw.dispose();
    renderer.dispose();
    if(results.some(r=>!r.pass))throw new Error(JSON.stringify(results.filter(r=>!r.pass)));
    return {passed:results.filter(r=>r.pass).length,total:results.length,results};
  });
}
