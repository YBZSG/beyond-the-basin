'use client';
import { useEffect, useRef, useState } from 'react';
import type { createPool, Status, WaterSettings } from './engine';
import { isTouchDevice } from './touch';
import './pool.css';
import { WATER_SETTINGS_DEFAULT as WATER_DEFAULT, WATER_SLIDERS, WATER_QUALITY, WATER_LAYERS, WATER_DEBUG, sanitizeWaterSettings, type WaterQuality } from './water-settings';

const WATER_STORE='pool-water-settings';
/** Stage label -> key in `Status.timings`. Shared by the panel and the HUD. */
const TIMING_ROWS=([['道具物理','props'],['白水/浪花','liquid'],['粒子','particles'],['水体渲染','water'],['反射抓帧','capture'],['后期合成','composer']] as const);
const WATER_PRESETS:[string,WaterSettings][]=[
  ['恢复默认',{...WATER_DEFAULT}],
  ['细腻明显',{...WATER_DEFAULT,waveHeight:.8,rippleGain:1.6,normalBoost:1.7,distortion:.75,impact:1.3,ringWaves:15,wavePush:1.1,waveSpeed:1.15}],
  ['平静如镜',{...WATER_DEFAULT,waveHeight:.2,rippleGain:.5,normalBoost:1,distortion:.3,impact:.6,ringWaves:9,wavePush:.5,waveSpeed:.75}],
];
const loadWater=():WaterSettings=>{
  try{const raw=localStorage.getItem(WATER_STORE);if(raw)return sanitizeWaterSettings({...JSON.parse(raw),debugView:0});}catch{}
  return {...WATER_DEFAULT};
};
export default function PoolVCT() {
  const host=useRef<HTMLDivElement>(null),engine=useRef<ReturnType<typeof createPool>|null>(null);
  const touch=isTouchDevice();
  const [ready,setReady]=useState(false),[locked,setLocked]=useState(false),[error,setError]=useState('');
  const [seed,setSeed]=useState(250821),[draft,setDraft]=useState('250821');
  const [cameraTime,setCameraTime]=useState('');
  const [sound,setSound]=useState(true),[music,setMusic]=useState(true);
  // Start from the defaults so server and client render identical markup;
  // persisted values load right after hydration (localStorage is client-only).
  const [water,setWater]=useState<WaterSettings>(WATER_DEFAULT);
  const [debugOpen,setDebugOpen]=useState(false),[waterStats,setWaterStats]=useState('');
  // The frame profiler costs a branch per stage when off, so it is tied to the
  // debug panel's lifetime: open the panel and the numbers appear in `status`.
  useEffect(()=>{engine.current?.setProfiling(debugOpen);return()=>{engine.current?.setProfiling(false);};},[debugOpen,ready]);
  // The panel's own toggle lives inside the pause menu, which is exactly where
  // you cannot watch the frame rate. G opens it mid-game so the numbers can be
  // read while actually walking.
  useEffect(()=>{const onKey=(e:KeyboardEvent)=>{if(e.code==='KeyG'&&!e.repeat&&!e.metaKey&&!e.ctrlKey&&!e.altKey){e.preventDefault();setDebugOpen(v=>!v);}};window.addEventListener('keydown',onKey);return()=>window.removeEventListener('keydown',onKey);},[]);
  useEffect(()=>{if(!debugOpen)return;const timer=window.setInterval(()=>{const d=engine.current?.waterDebug();if(d)setWaterStats(`${d.grid}² 浅水 · ${d.detailGrid}² 细波 · ${d.causticSize}² 焦散\n峰值 ${d.peak.toFixed(4)} m · ${d.settled?'物理已平静':'波场传播中'} · 读回异常 ${d.rejected}\n焦散重绘 ${d.causticFrames} 次 · 求解丢时 ${d.droppedTime.toFixed(2)}s\n质量 ${d.quality} · 反射 ${d.reflectionSize}² · 细波 ${d.detailActive?'启用':'停用'}\n折射抓帧 ${d.captureFrames} 次 · 缓存龄 ${d.refractionAge} 帧`);},500);return()=>clearInterval(timer);},[debugOpen]);
  useEffect(()=>{
    const id=requestAnimationFrame(()=>setWater(loadWater()));
    return()=>cancelAnimationFrame(id);
  },[]);
  useEffect(()=>{engine.current?.setSound(sound);},[sound,ready]);
  useEffect(()=>{engine.current?.setMusic(music);},[music,ready]);
  // Sliders write through to the live renderer and persist for next sessions.
  useEffect(()=>{if(!ready)return;engine.current?.waterSettings(water);try{localStorage.setItem(WATER_STORE,JSON.stringify(water));}catch{}},[ready,water]);
  useEffect(()=>{const update=()=>{const d=new Date(),pad=(v:number)=>String(v).padStart(2,'0');setCameraTime(`’${pad(d.getFullYear()%100)} ${pad(d.getMonth()+1)} ${pad(d.getDate())}  ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`);};update();const timer=window.setInterval(update,1000);return()=>window.clearInterval(timer);},[]);
  const [status,setStatus]=useState<Status>({x:0,z:0,rooms:9,discovered:1,fps:0,vct:true,impacts:0,caustics:true,hint:'',filter:1,held:'',throws:0,grabs:0,height:1.5,climbing:false,slides:0,charge:0,paused:true,corrupt:0});
  useEffect(()=>{let cancelled=false;import('./engine').then(({createPool})=>{if(cancelled||!host.current)return;try{engine.current=createPool(host.current,seed,setStatus);if(process.env.NODE_ENV!=='production'&&new URLSearchParams(location.search).has('qa')){(window as Window & {__poolQA?:typeof engine.current.qa}).__poolQA=engine.current.qa;}(window as Window & {__poolPause?:()=>void}).__poolPause=()=>engine.current?.pause();setReady(true);}catch(e){setError(String(e));}});return()=>{cancelled=true;engine.current?.dispose();engine.current=null;};},[seed]);
  useEffect(()=>{const onLock=()=>setLocked(!!document.pointerLockElement);document.addEventListener('pointerlockchange',onLock);return()=>document.removeEventListener('pointerlockchange',onLock);},[]);
  // Touch sessions have no pointer lock; the engine's paused flag drives the menu instead.
  const entered=touch?!status.paused:locked;
  return <main className="vct-page">
    <div className="vct-canvas" ref={host}/>
    <div className="vct-top"><span>POOLCORE <i> / </i> VOL. 02</span><span><b className="vct-dot"/> {ready?'空间已生成':'正在填充体素光照场'}</span></div>
    {!entered&&<section className="vct-menu">
      <p className="vct-kicker">一座没有出口的旧泳池</p>
      <h1>深水之外<span>BEYOND THE BASIN</span></h1>
      <p className="vct-description">灯还亮着，水还在动。<br/>穿过廊柱，下一座泳池正在等你。</p>
      <button className="vct-enter" disabled={!ready||!!error} onClick={()=>engine.current?.enter()}>{ready?'进入水中':'正在准备场景'}<span>↗</span></button>
      <div className="vct-seed"><label htmlFor="pool-seed">世界种子</label><input id="pool-seed" value={draft} maxLength={10} onChange={e=>setDraft(e.target.value.replace(/\D/g,''))}/><button disabled={!ready} onClick={()=>{const next=Number(draft)||250821;if(next!==seed){setReady(false);setError('');setSeed(next);}}}>重新生成</button></div>
      {touch?<p className="vct-keys">左侧摇杆移动 · 推满快走 · 「跳」跳跃<br/>右侧滑动转视角 · 轻点水面或道具互动<br/>「拿起」拿起 / 攀爬 / 放下 · 按住「投掷」蓄力松开丢出<br/>右上 ☰ 暂停菜单 · 内含水面设置</p>:<p className="vct-keys">W A S D 移动 · Shift 快走 · 空格跳跃<br/>左键拖动 · E 拿起 / 攀爬 · 右键按住蓄力投掷<br/>滚轮调整距离 · 梯子上 W / S 攀爬<br/>Esc 暂停（含水面设置） · C 焦散 · V 间接光 · R 起点 · G 帧耗时</p>}
      <button className="vct-filter" aria-pressed={sound} onClick={()=>setSound(!sound)}>声音：{sound?'开启':'关闭'} <span>水声 · 脚步 · 碰撞</span></button>
      <button className="vct-filter" aria-pressed={music} onClick={()=>setMusic(!music)}>音乐：{music?'开启':'关闭'} <span>环境底噪 · 循环</span></button>
      <button className="vct-filter" onClick={()=>engine.current?.cycleFilter()}>镜头：{['原始','CCD 摄像机','VHS 录像','冷色纪实'][status.filter]} <span>F 切换 ↻</span></button>
      <section className="vct-water" aria-label="水面设置">
        <span>水面设置 · 实时生效 · 自动保存</span>
        <label className="vct-water-select">水体质量<select aria-label="水体质量" value={water.quality} onChange={e=>setWater(w=>({...w,quality:e.target.value as WaterQuality}))}>{Object.keys(WATER_QUALITY).map(q=><option key={q}>{q}</option>)}</select></label>
        <button className="vct-filter" onClick={()=>setDebugOpen(v=>!v)}>Water Debug Panel <span>{debugOpen?'收起':'展开分层视图 ↗'}</span></button>
      <p className="vct-keys" style={{margin:'6px 0 0'}}>游戏中按 <b>G</b> 可直接开关帧耗时浮层（走路时看哪一阶段最耗时）</p>
        {WATER_SLIDERS.map(s=><label key={s.key} className="vct-water-row">
          <span>{s.label}</span>
          <input type="range" min={s.min} max={s.max} step={s.step} value={water[s.key]} onChange={e=>setWater(w=>({...w,[s.key]:Number(e.target.value)}))}/>
          <output>{water[s.key].toFixed(s.step>=1?0:s.step<.001?4:2)}</output>
        </label>)}
        <div className="vct-water-actions">
          {WATER_PRESETS.map(([label,values])=><button key={label} onClick={()=>setWater({...values})}>{label}</button>)}
        </div>
      </section>
      <nav className="vct-destinations" aria-label="前往房间">
        <span>前往房间 · 也可穿过门洞步行到达</span>
        {([['旧泳池 · 阴暗',0,0],['高拱门大厅 · 明亮',0,-1],['连通浴池 · 明亮',-1,0],['跳台高廊 · 明亮',1,0],['夜间浴场 · 阴暗',0,1],['柱阵水厅 · 波函数坍缩',1,1],['边缘翼区 · 渐崩坏',-4,-4],['对角深处 · 重度崩坏',7,7]] as const).map(([label,x,z])=><button key={label} disabled={!ready} onClick={()=>engine.current?.visitRoom(x,z)}>{label}</button>)}
      </nav>
      {error&&<p role="alert" className="vct-error">渲染初始化失败：{error}</p>}
    </section>}
    {debugOpen&&<aside className="vct-water-debug" aria-label="Water Debug Panel">
      <div className="vct-water-debug-head"><strong>Water Debug Panel</strong><button aria-label="关闭水体调试" onClick={()=>{setDebugOpen(false);setWater(w=>({...w,debugView:0}));}}>×</button></div>
      <label className="vct-water-select">实时视图<select aria-label="水体调试视图" value={water.debugView} onChange={e=>setWater(w=>({...w,debugView:Number(e.target.value)}))}>{WATER_DEBUG.map((label,i)=><option key={label} value={i}>{label}</option>)}</select></label>
      <div className="vct-water-layers">{Object.entries(WATER_LAYERS).map(([key,label])=><label key={key}><input type="checkbox" checked={water[key as keyof typeof WATER_LAYERS]} onChange={e=>setWater(w=>({...w,[key]:e.target.checked}))}/>{label}</label>)}</div>
      <pre aria-live="off">{waterStats}</pre>
      {status.timings&&<div className="vct-water-timings" aria-label="逐阶段帧耗时">
        <div><strong>逐阶段耗时 / ms</strong><small>卡顿时看哪一行最大</small></div>
        {TIMING_ROWS.map(([label,key])=>{const ms=status.timings![key]??0,total=Math.max(status.timings!.total,1e-6);return <div key={key} className={ms/total>.4?'vct-hot':undefined}><span>{label}</span><i style={{width:`${Math.min(100,ms/total*100)}%`}}/><b>{ms.toFixed(2)}</b></div>;})}
        <div><span>阶段合计</span><b>{status.timings.total.toFixed(2)}</b></div>
        <div><span>探针开销</span><b>{status.timings.probe.toFixed(3)}</b></div>
        <div><span>理论帧率上限</span><b>{status.timings.total>0?Math.round(1000/status.timings.total):0} FPS</b></div>
      </div>}
      <p>Low：基础水面；Medium：细波、折射与池底焦散；High / Ultra：加入微法线与池壁焦散。质量档位决定可用层。</p>
    </aside>}
    {entered&&<><div className="vct-crosshair">{status.held?'◉':'·'}</div>{status.charge>0&&<div className="vct-charge" role="progressbar" aria-label="投掷蓄力" aria-valuenow={Math.round(status.charge*100)}><span style={{transform:`scaleX(${status.charge})`}}/></div>}<div className="vct-hint">{status.hint}</div></>}
    {/* Compact HUD: the full panel lives in the pause menu, which is the one
        place you cannot watch the frame rate. G toggles this mid-game. */}
    {debugOpen&&entered&&status.timings&&<aside className="vct-perf-hud" aria-label="实时帧耗时">
      <div className="vct-perf-head"><strong>{status.fps} FPS</strong><span>{status.timings.total.toFixed(1)} ms / 帧</span></div>
      {TIMING_ROWS.map(([label,key])=>{const ms=status.timings![key]??0,total=Math.max(status.timings!.total,1e-6);return <div key={key} className={ms/total>.4?'vct-hot':undefined}><span>{label}</span><i style={{width:`${Math.min(100,ms/total*100)}%`}}/><b>{ms.toFixed(1)}</b></div>;})}
    </aside>}
    <footer className="vct-footer"><div><span>SECTOR {String(status.x).padStart(2,'0')} / {String(status.z).padStart(2,'0')}</span><small>已探索 {status.discovered} 个区域 · {status.rooms} 个驻留区块 · 崩坏 {['完好','渐衰','显著','严重'][status.corrupt]}</small></div><div className="vct-tech">{status.vct?'体素锥追踪 GI':'GI 对照：关闭'} · {status.caustics?'水光焦散':'焦散关闭'}<small>{status.fps} FPS · SEED {seed} · 水面交互 {status.impacts}</small></div><time aria-label="摄像机本地时间">{cameraTime}</time></footer>
  </main>;
}
