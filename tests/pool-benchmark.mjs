// PLAYWRIGHT_MODULE may point at an existing local Playwright installation.
// node tests/pool-benchmark.mjs <static build directory> <artifact directory>
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

const [rootArg, outputArg] = process.argv.slice(2);
if (!rootArg || !outputArg) throw new Error('Provide a static build directory and an external artifact directory.');
const root = resolve(rootArg), output = resolve(outputArg);
const moduleName = process.env.PLAYWRIGHT_MODULE;
const { chromium } = await import(moduleName ? pathToFileURL(moduleName).href : 'playwright');
await mkdir(output, { recursive: true });
const types = { '.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.jpg':'image/jpeg', '.png':'image/png', '.ogg':'audio/ogg', '.json':'application/json' };
const server = createServer(async (req,res) => {
  const pathname = decodeURIComponent(new URL(req.url,'http://localhost').pathname);
  if(pathname==='/favicon.ico'){res.writeHead(204).end();return;}
  const file = resolve(root, '.' + (pathname==='/'?'/index.html':pathname));
  if (!file.startsWith(root+sep)) {res.writeHead(403).end();return;}
  try {const bytes=await readFile(file);res.writeHead(200,{'Content-Type':types[extname(file)]??'application/octet-stream'}).end(bytes);}
  catch {res.writeHead(404).end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url=`http://127.0.0.1:${server.address().port}/?qa&benchmark`;
const browser=await chromium.launch({channel:'msedge',headless:false,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows','--disable-features=CalculateNativeWinOcclusion','--window-size=1920,1080']});
const context=await browser.newContext({viewport:{width:1920,height:1080},deviceScaleFactor:1});
const page=await context.newPage();
const errors=[];page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
const seconds=Number(process.env.BENCH_SECONDS??60), repeats=Number(process.env.BENCH_REPEATS??3),warmup=Number(process.env.BENCH_WARMUP??15);
const scenarios=(process.env.BENCH_SCENARIOS??'still,turn,interaction,transition,shafts').split(',');
const results=[];
try {
  for(let repeat=0;repeat<repeats;repeat++)for(const scenario of scenarios){
    await page.goto(url,{waitUntil:'load',timeout:120000});
    await page.bringToFront();
    await page.waitForFunction(()=>window.__poolQA?.inspect().vctReady,null,{timeout:180000});
    await page.addStyleTag({content:'.vct-menu,.vct-top,.vct-footer,.vct-perf{display:none!important}'});
    await page.evaluate(({scenario,gpu})=>{const q=window.__poolQA;q.waterSettings({quality:'High'});q.simulate(scenario==='interaction');q.view([2,1.5,6],[2,.5,-4]);q.forceShafts(scenario==='shafts');q.performance?.gpu(gpu);}, {scenario,gpu:process.env.BENCH_GPU!=='off'});
    // Compile the interaction-only liquid/particle programs before measuring.
    if(scenario==='interaction')await page.evaluate(()=>{const q=window.__poolQA;q.water(2,2,.65);});
    await page.waitForTimeout(warmup*1000);
    const data=await page.evaluate(async({seconds,scenario})=>{
      const q=window.__poolQA,frames=[],longTasks=[],visibility=[{at:performance.now(),hidden:document.hidden}];
      const visible=()=>visibility.push({at:performance.now(),hidden:document.hidden});document.addEventListener('visibilitychange',visible);
      const observer=new PerformanceObserver(list=>longTasks.push(...list.getEntries().map(e=>({start:e.startTime,duration:e.duration}))));observer.observe({type:'longtask'});
      const canvas=document.querySelector('canvas'),gl=canvas.getContext('webgl2'),ext=gl.getExtension('WEBGL_debug_renderer_info');
      const machine={gpu:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),userAgent:navigator.userAgent,viewport:[innerWidth,innerHeight],dpr:devicePixelRatio,buffer:[canvas.width,canvas.height]};
      q.performance?.start();const start=performance.now();let last=start,action=-1;
      await new Promise(done=>{function tick(now){
        const t=(now-start)/1000;if(t>seconds){done();return;}frames.push(now-last);last=now;
        if(scenario==='turn')q.view([2+Math.sin(t*.6)*2,1.5,6+Math.cos(t*.6)*2],[Math.sin(t*.5)*9,.5,-5]);
        if(scenario==='interaction'){
          const code=t%6<3?'KeyW':'KeyS',old=code==='KeyW'?'KeyS':'KeyW';
          window.dispatchEvent(new KeyboardEvent('keyup',{code:old}));window.dispatchEvent(new KeyboardEvent('keydown',{code}));
        }
        const step=Math.floor(t/(scenario==='transition'?8:3));
        if(step!==action){action=step;
          if(scenario==='interaction'){q.water(2,2,.65);q.placeProp('ball',[2,.6,2]);q.view([2,1.1,4],[2,.6,2]);q.grab();q.throw(11);}
          if(scenario==='transition'){q.view([step%2===0?34:-34,1.5,0],[step%2===0?40:-40,1.5,0]);}
        }
        requestAnimationFrame(tick);
      }requestAnimationFrame(tick);});
      observer.disconnect();document.removeEventListener('visibilitychange',visible);const sorted=[...frames].sort((a,b)=>a-b),at=p=>sorted[Math.min(sorted.length-1,Math.floor(sorted.length*p))];
      const mean=frames.reduce((a,b)=>a+b,0)/frames.length;
      return {machine,frames,longTasks,visibility,stats:{mean,fps:1000/mean,p50:at(.5),p95:at(.95),p99:at(.99),worst:sorted.at(-1),over33:frames.filter(x=>x>33.3).length,over50:frames.filter(x=>x>50).length},performance:q.performance?.stop(),state:q.inspect()};
    },{seconds,scenario});
    const name=`${scenario}-${repeat+1}`;
    if(data.visibility.some(e=>e.hidden))errors.push(`${name}: document was hidden during recording`);
    await page.screenshot({path:resolve(output,`${name}.png`)});
    await writeFile(resolve(output,`${name}.json`),JSON.stringify({...data,scenario,repeat,errors},null,2));
    results.push({scenario,repeat,...data.stats,machine:data.machine,valid:errors.length===0});
    console.log(JSON.stringify(results.at(-1)));
    await writeFile(resolve(output,'summary.json'),JSON.stringify({url,seconds,warmup,repeats,results,errors},null,2));
  }
  if(errors.length)process.exitCode=1;
} finally {await browser.close();server.close();}
