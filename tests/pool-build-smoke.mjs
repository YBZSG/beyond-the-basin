// Headed Edge smoke for optimized distribution builds, including QA gating.
// PLAYWRIGHT_MODULE=<existing install> node tests/pool-build-smoke.mjs <artifacts>
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {pathToFileURL} from 'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE).href:'playwright');
const output=resolve(process.argv[2]??'output/build-smoke'),root=resolve('apk/stage');await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{
  const path=new URL(req.url,'http://localhost').pathname;if(path==='/favicon.ico'){res.writeHead(204).end();return;}
  const file=resolve(root,'.'+(path==='/'?'/index.html':path));if(!file.startsWith(root+sep)){res.writeHead(403).end();return;}
  try{res.writeHead(200,{'Content-Type':{'.html':'text/html','.js':'text/javascript','.css':'text/css'}[extname(file)]??'application/octet-stream'}).end(await readFile(file));}
  catch{res.writeHead(404).end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'msedge',headless:false}),results=[];
try{
  for(const [name,url] of [['apk-web',`http://127.0.0.1:${server.address().port}/?qa`],['single',pathToFileURL(resolve('dist-single/BEYOND-THE-BASIN-PoolCore-single.html')).href+'?qa']]){
    const page=await browser.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1}),errors=[];
    page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
    await page.goto(url,{waitUntil:'load',timeout:120000});
    await page.waitForFunction(()=>document.querySelector('.vct-enter')?.disabled===false,null,{timeout:180000});
    await page.waitForTimeout(8000);
    const state=await page.evaluate(()=>({qa:typeof window.__poolQA,canvas:!!document.querySelector('canvas'),error:document.querySelector('.vct-error')?.textContent??''}));
    await page.addStyleTag({content:'.vct-menu,.vct-top,.vct-footer{display:none!important}'});
    await page.screenshot({path:resolve(output,name+'.png')});results.push({name,url,state,errors});
    assert.equal(state.qa,'undefined','ordinary optimized builds must not expose QA');assert.equal(state.error,'');assert.deepEqual(errors,[]);
    await page.close();
  }
}finally{await writeFile(resolve(output,'build-smoke.json'),JSON.stringify(results,null,2));await browser.close();server.close();}
console.log(JSON.stringify(results));
