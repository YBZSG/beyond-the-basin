// Run with the local headed Edge session; records actual input and rendered states.
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
async (page) => {
  await page.bringToFront();
  await page.waitForFunction(()=>!!window.__poolQA?.whitewaterTime);
  const errors=[];
  const onError=e=>errors.push(String(e));
  const onConsole=m=>{if(m.type()==='error'&&!m.text().includes('favicon'))errors.push(m.text());};
  page.on('pageerror',onError);page.on('console',onConsole);
  await page.addStyleTag({content:'.vct-menu,.vct-top,.vct-footer{display:none!important}'});
  await page.evaluate(()=>{const q=window.__poolQA;q.whitewaterTime(1);q.whitewaterSecondary(true);q.simulate(false);q.view([2,.95,3.4],[2,.42,2]);});
  for(let i=0;i<4&&await page.evaluate(()=>window.__poolQA.inspect().filter!==0);i++)await page.keyboard.press('f');
  const clear=()=>{const s=window.__poolQA.whitewaterGeometry();return s.sheets===0&&s.drops===0&&s.bubbles===0;};
  await page.waitForFunction(clear,{timeout:12000});
  const motion=await page.evaluate(async()=>{
    const q=window.__poolQA,frames=[],start=performance.now(),before=q.whitewaterGeometry();
    q.water(2,2,.65);
    await new Promise(resolve=>{const sample=()=>{
      const ms=performance.now()-start;frames.push({ms:Math.round(ms),...q.whitewaterGeometry()});
      if(ms<1800)requestAnimationFrame(sample);else resolve();
    };requestAnimationFrame(sample);});
    return {before,first:frames[0],peakSheets:Math.max(...frames.map(f=>f.sheets)),peakDrops:Math.max(...frames.map(f=>f.drops)),
      frames:frames.filter((_,i)=>i%3===0),after:q.whitewaterGeometry()};
  });
  await page.evaluate(()=>{const q=window.__poolQA;q.view([2,1.2,6],[2,.32,2]);q.simulate(true);});
  const beforeWalk=await page.evaluate(()=>window.__poolQA.inspect());
  await page.keyboard.down('w');await page.waitForTimeout(650);await page.keyboard.down('Shift');await page.waitForTimeout(450);
  await page.keyboard.up('Shift');await page.keyboard.up('w');await page.keyboard.press('Space');await page.waitForTimeout(900);
  const afterWalk=await page.evaluate(()=>window.__poolQA.inspect());
  await page.evaluate(()=>{const q=window.__poolQA;q.placeProp('ball',[2,.6,2]);q.view([2,1.1,4],[2,.6,2]);q.simulate(true);});
  await page.keyboard.press('e');
  const held=await page.evaluate(()=>window.__poolQA.inspect().held);
  await page.mouse.down({button:'right'});await page.waitForTimeout(550);await page.mouse.up({button:'right'});
  const thrown=[];
  for(let i=0;i<16;i++){await page.waitForTimeout(100);thrown.push(await page.evaluate(()=>({...window.__poolQA.whitewaterGeometry(),throws:window.__poolQA.inspect().throws})));}
  await page.evaluate(()=>window.__poolQA.simulate(false));
  await page.waitForFunction(clear,{timeout:12000});
  const settled=await page.evaluate(()=>window.__poolQA.whitewaterGeometry());
  const gpu=await page.evaluate(()=>{const gl=document.querySelector('canvas').getContext('webgl2');const ext=gl.getExtension('WEBGL_debug_renderer_info');return ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER);});
  page.off('pageerror',onError);page.off('console',onConsole);
  const summary={gpu,motion,walk:{before:beforeWalk.position,after:afterWalk.position,impacts:afterWalk.impacts-beforeWalk.impacts},held,thrown,settled,errors};
  if(motion.first.drops!==0||motion.peakSheets<=0||motion.peakDrops<=0||motion.after.ripples<=motion.before.ripples||afterWalk.impacts<=beforeWalk.impacts||!held||!thrown.some(s=>s.throws>0)||errors.length)throw new Error(JSON.stringify(summary));
  return summary;
}
