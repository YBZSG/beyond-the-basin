'use client';
import { useEffect, useRef, useState } from 'react';
import type { createPool, Status } from './engine';
import { isTouchDevice } from './touch';
import './pool.css';

export default function PoolVCT() {
  const host=useRef<HTMLDivElement>(null),engine=useRef<ReturnType<typeof createPool>|null>(null);
  const touch=isTouchDevice();
  const [ready,setReady]=useState(false),[locked,setLocked]=useState(false),[error,setError]=useState('');
  const [seed,setSeed]=useState(250821),[draft,setDraft]=useState('250821');
  const [cameraTime,setCameraTime]=useState('');
  const [sound,setSound]=useState(true),[music,setMusic]=useState(true);
  useEffect(()=>{engine.current?.setSound(sound);},[sound,ready]);
  useEffect(()=>{engine.current?.setMusic(music);},[music,ready]);
  useEffect(()=>{const update=()=>{const d=new Date(),pad=(v:number)=>String(v).padStart(2,'0');setCameraTime(`’${pad(d.getFullYear()%100)} ${pad(d.getMonth()+1)} ${pad(d.getDate())}  ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`);};update();const timer=window.setInterval(update,1000);return()=>window.clearInterval(timer);},[]);
  const [status,setStatus]=useState<Status>({x:0,z:0,rooms:9,discovered:1,fps:0,vct:true,impacts:0,caustics:true,hint:'',filter:1,held:'',throws:0,grabs:0,height:1.5,climbing:false,slides:0,charge:0,paused:true,corrupt:0});
  useEffect(()=>{let cancelled=false;import('./engine').then(({createPool})=>{if(cancelled||!host.current)return;try{engine.current=createPool(host.current,seed,setStatus);if(process.env.NODE_ENV!=='production'&&new URLSearchParams(location.search).has('qa')){(window as Window & {__poolQA?:typeof engine.current.qa}).__poolQA=engine.current.qa;}setReady(true);}catch(e){setError(String(e));}});return()=>{cancelled=true;engine.current?.dispose();engine.current=null;};},[seed]);
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
      {touch?<p className="vct-keys">左侧摇杆移动 · 推满快走 · 「跳」跳跃<br/>右侧滑动转视角 · 轻点水面或道具互动<br/>「拿起」拿起 / 攀爬 / 放下 · 按住「投掷」蓄力松开丢出<br/>右上 ☰ 暂停菜单</p>:<p className="vct-keys">W A S D 移动 · Shift 快走 · 空格跳跃<br/>左键拖动 · E 拿起 / 攀爬 · 右键按住蓄力投掷<br/>滚轮调整距离 · 梯子上 W / S 攀爬<br/>Esc 暂停 · C 焦散 · V 间接光 · R 起点</p>}
      <button className="vct-filter" aria-pressed={sound} onClick={()=>setSound(!sound)}>声音：{sound?'开启':'关闭'} <span>水声 · 脚步 · 碰撞</span></button>
      <button className="vct-filter" aria-pressed={music} onClick={()=>setMusic(!music)}>音乐：{music?'开启':'关闭'} <span>环境底噪 · 循环</span></button>
      <button className="vct-filter" onClick={()=>engine.current?.cycleFilter()}>镜头：{['原始','CCD 摄像机','VHS 录像','冷色纪实'][status.filter]} <span>F 切换 ↻</span></button>
      <nav className="vct-destinations" aria-label="前往房间">
        <span>前往房间 · 也可穿过门洞步行到达</span>
        {([['旧泳池 · 阴暗',0,0],['高拱门大厅 · 明亮',0,-1],['连通浴池 · 明亮',-1,0],['跳台高廊 · 明亮',1,0],['夜间浴场 · 阴暗',0,1],['柱阵水厅 · 波函数坍缩',1,1],['边缘翼区 · 渐崩坏',-4,-4],['对角深处 · 重度崩坏',7,7]] as const).map(([label,x,z])=><button key={label} disabled={!ready} onClick={()=>engine.current?.visitRoom(x,z)}>{label}</button>)}
      </nav>
      {error&&<p role="alert" className="vct-error">渲染初始化失败：{error}</p>}
    </section>}
    {entered&&<><div className="vct-crosshair">{status.held?'◉':'·'}</div>{status.charge>0&&<div className="vct-charge" role="progressbar" aria-label="投掷蓄力" aria-valuenow={Math.round(status.charge*100)}><span style={{transform:`scaleX(${status.charge})`}}/></div>}<div className="vct-hint">{status.hint}</div></>}
    <footer className="vct-footer"><div><span>SECTOR {String(status.x).padStart(2,'0')} / {String(status.z).padStart(2,'0')}</span><small>已探索 {status.discovered} 个区域 · {status.rooms} 个驻留区块 · 崩坏 {['完好','渐衰','显著','严重'][status.corrupt]}</small></div><div className="vct-tech">{status.vct?'体素锥追踪 GI':'GI 对照：关闭'} · {status.caustics?'水光焦散':'焦散关闭'}<small>{status.fps} FPS · SEED {seed} · 水面交互 {status.impacts}</small></div><time aria-label="摄像机本地时间">{cameraTime}</time></footer>
  </main>;
}
