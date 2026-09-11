import * as T from 'three';
import { Water } from 'three/addons/objects/Water.js';
import { createBeachBallGeometry, createBeachBallTexture, BEACH_BALL_RADIUS } from './beach-ball';
import { RoomLights } from './room-lights';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ROOM, VoxelField, blocked, randomFor, roomLayout, type Solid, type Lamp } from './world';
import { InteractiveWater } from './water-system';
import { PropPhysics, PlayerPhysics, type Collider, type Ladder, type PropBody, type PropKind } from './physics';
import { ReflectionField, type RtItem } from './rt';
import { isTouchDevice, stickToKeys } from './touch';
import { PoolAudio } from './audio';
import { collapseInterior, WFC_SIZE, WFC_CELL, type WfcTile } from './wfc';

type Flicker={light:T.PointLight;glow:T.MeshBasicMaterial;base:number;seed:number;amp:number};
type Chunk = { group: T.Group; solids: Solid[]; lamps: Lamp[]; floats: T.Group[]; lights: T.PointLight[]; bodies:PropBody[]; colliders:Collider[]; ladders:Ladder[]; flickers:Flicker[] };
export type Status = { x: number; z: number; rooms: number; discovered: number; fps: number; vct: boolean; impacts: number; caustics: boolean; hint:string; filter:number; held:string; throws:number; grabs:number; height:number; climbing:boolean; slides:number; charge:number; paused:boolean; corrupt:number };
export function createPool(host: HTMLElement, seed: number, report: (s: Status) => void) {
  const touch=isTouchDevice();
  const renderer = new T.WebGLRenderer({ antialias: !touch, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(devicePixelRatio, touch?1.25:1.5));
  renderer.setSize(host.clientWidth, host.clientHeight);
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = T.PCFShadowMap;
  renderer.toneMapping = T.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.08;
  host.appendChild(renderer.domElement);
  const scene = new T.Scene(); scene.background = new T.Color('#08121a'); scene.fog = new T.FogExp2('#10232d', .024);
  const roomLights=new RoomLights(scene);
  // Per-decay-level mood targets: exponential fog density and backdrop colour.
  const CORRUPT_FOG=[.024,.031,.042,.055];
  const CORRUPT_BG=['#08121a','#071016','#050c10','#03080c'].map(c=>new T.Color(c));
  const camera = new T.PerspectiveCamera(62, host.clientWidth / host.clientHeight, .08, 100);
  camera.position.set(10, 1.5, 12); camera.rotation.order = 'YXZ'; camera.lookAt(-4, 1.9, -10);
  const field = new VoxelField();
  const waterSystem=new InteractiveWater();
  const audio=new PoolAudio();
  const splash=(x:number,z:number,power:number,step=false)=>{
    waterSystem.impact(x,z,power);
    const dx=x-camera.position.x,dz=z-camera.position.z,distance=Math.hypot(dx,dz);
    audio.splash(power,distance,(dx*Math.cos(camera.rotation.y)-dz*Math.sin(camera.rotation.y))/Math.max(1,distance),step);
  };
  // Hard surface hits from thrown/dropped props: eggs crack, ducks squeak-bounce,
  // beach balls land with a hollow vinyl thump.
  const propImpact=(b:PropBody,strength:number)=>{
    const dx=b.position.x-camera.position.x,dz=b.position.z-camera.position.z,distance=Math.hypot(dx,dz);
    const pan=distance>1?(dx*Math.cos(camera.rotation.y)-dz*Math.sin(camera.rotation.y))/distance:0;
    const power=T.MathUtils.clamp((strength-1.15)/9,0,1);
    if(b.kind==='egg')audio.eggHit(power,pan,distance);
    else if(b.kind==='ball')audio.ballHit(power,pan,distance);
    else audio.duckHit(power,pan,distance);
  };
  const props=new PropPhysics(scene,(x,z,power)=>splash(x,z,power),(x,z)=>.32+waterSystem.heightAt(x,z),{impact:propImpact,grab:b=>{if(b.kind==='duck')audio.duckPickup();else if(b.kind==='ball')audio.ballPickup();}});
  const player=new PlayerPhysics((x,z,power)=>{
    waterSystem.impact(x,z,power);
    if(power>.22)audio.diveIn();else audio.splash(power,0,0);
  },(x,z)=>.32+waterSystem.heightAt(x,z));
  const tile = new T.MeshStandardMaterial({ color: '#63899d', roughness: .3, metalness: 0 }); field.apply(tile, true);
  const pale = new T.MeshStandardMaterial({ color: '#aab6b0', roughness: .36, metalness: 0 }); field.apply(pale, true);
  const daylightTile=new T.MeshStandardMaterial({color:'#75adb2',roughness:.3,metalness:0});field.apply(daylightTile,true,true);
  const daylightPale=new T.MeshStandardMaterial({color:'#dbddd0',roughness:.36,metalness:0});field.apply(daylightPale,true,true);
  const metal = new T.MeshStandardMaterial({ color: '#6e6a51', roughness: .4, metalness: .78 }); field.apply(metal);
  const yellow = new T.MeshStandardMaterial({ color: '#f2c32c', roughness: .3 }); field.apply(yellow);
  const orange = new T.MeshStandardMaterial({ color: '#d36a24', roughness: .35 }); field.apply(orange);
  const black = new T.MeshStandardMaterial({ color: '#151713', roughness: .27 }); field.apply(black);
  const ivory = new T.MeshStandardMaterial({ color: '#b9b398', roughness: .23 }); field.apply(ivory);
  waterSystem.attachReceiver(tile);waterSystem.attachReceiver(pale);
  waterSystem.attachReceiver(daylightTile);waterSystem.attachReceiver(daylightPale);
  const chrome=new T.MeshStandardMaterial({color:'#b1c5c9',metalness:1,roughness:.12});field.apply(chrome);
  const red=new T.MeshStandardMaterial({color:'#75443d',roughness:.22,metalness:.35});field.apply(red);
  // Ray-traced reflections: a shader-side BVH of the static building replaces the blurry
  // probe specular on the glazed surfaces with true reflection rays.
  const rt=new ReflectionField();
  waterSystem.attachTracing(rt);
  // Rough ceramic uses the prefiltered room probe. Reserve per-pixel reflection
  // rays for actual metal; tracing every tile was both mirror-like and costly.
  rt.apply(chrome,'pool-vct-rt-chrome-1'); rt.apply(red,'pool-vct-rt-red-1');
  tile.envMapIntensity=.8; pale.envMapIntensity=.75;
  const glow = new T.MeshBasicMaterial({ color: new T.Color(3.4, 3.6, 3.5) });
  // Deep-corruption rooms swap the clean tile set for a damp, mossy one.
  const grimTile=new T.MeshStandardMaterial({color:'#4f6b64',roughness:.44,metalness:0});field.apply(grimTile,true);
  const grimPale=new T.MeshStandardMaterial({color:'#828b7a',roughness:.52,metalness:0});field.apply(grimPale,true);
  waterSystem.attachReceiver(grimTile);waterSystem.attachReceiver(grimPale);
  // Dead tubes keep their fixture but stop emitting; skylights in decayed wings cloud over.
  const glowOff=new T.MeshBasicMaterial({color:new T.Color(.14,.17,.18)});
  const skylightGlow=new T.MeshBasicMaterial({color:new T.Color(.68,.79,.84)});
  const skylightDim=new T.MeshBasicMaterial({color:new T.Color(.1,.13,.15)});
  // Red exit lamp: emissive box + a small warm point light, mounted over the
  // dry room on top of the WFC chamber's stair column.
  const exitGlow=new T.MeshBasicMaterial({color:new T.Color(2.1,.3,.2)});
  const lampHousing=new T.MeshStandardMaterial({color:'#667474',roughness:.48,metalness:.65});
  daylightTile.envMapIntensity=.8;daylightPale.envMapIntensity=.75;
  const materials: T.Material[] = [tile, pale, daylightTile,daylightPale,metal, yellow, orange, black, ivory, glow,skylightGlow,lampHousing,chrome,red,grimTile,grimPale,glowOff,skylightDim,exitGlow];
  const cube = new T.BoxGeometry(1, 1, 1), sphere = new T.SphereGeometry(1, 16, 12);
  const cylinder = new T.CylinderGeometry(1, 1, 1, 32);
  // ---- Prop kinds: eggs sink, ducks bob, beach balls bounce ----
  // Each kind fixes its collider radius, waterline bias and display name; the
  // visual is assembled per kind below (procedural duck/egg and smooth beach ball).
  const PROP_SPEC: Record<PropKind, { radius: number; floatBias: number; name: string; sink: number }> = {
    egg: { radius: .17, floatBias: 0, name: '鸡蛋', sink: 0 },
    duck: { radius: .2, floatBias: .125, name: '小黄鸭', sink: .125 },
    ball: { radius: BEACH_BALL_RADIUS, floatBias: .05, name: '海滩球', sink: 0 },
  };
  const ballGeometry=createBeachBallGeometry(),ballTexture=createBeachBallTexture();
  ballTexture.anisotropy=Math.min(8,renderer.capabilities.getMaxAnisotropy());
  const ballMaterial=new T.MeshStandardMaterial({map:ballTexture,roughness:.27,metalness:0,envMapIntensity:.7});
  field.apply(ballMaterial);materials.push(ballMaterial);
  // Closed solids cast their front surface; back-face depth creates a visible
  // gap under small props and along thin wall bases.
  for(const material of materials)material.shadowSide=T.FrontSide;
  for(const material of [ballMaterial,ivory,yellow,orange,black])material.shadowSide=T.BackSide;
  const archShape=new T.Shape();
  archShape.moveTo(-4.6,0);archShape.lineTo(-4.6,5.3);
  archShape.absarc(0,5.3,4.6,Math.PI,0,true);archShape.lineTo(4.6,0);
  archShape.lineTo(3.5,0);archShape.lineTo(3.5,5.3);
  archShape.absarc(0,5.3,3.5,0,Math.PI,false);archShape.lineTo(-3.5,0);archShape.closePath();
  const archGeometry=new T.ExtrudeGeometry(archShape,{depth:.8,bevelEnabled:false,curveSegments:32});
  const textures: T.Texture[] = [ballTexture];
  const chunks = new Map<string, Chunk>(); const visited = new Set<string>();
  let allSolids: Solid[] = [], cx = NaN, cz = NaN, originX=0, originZ=0;
  let allColliders:Collider[]=[],allLadders:Ladder[]=[];
  // A room crossing defers the heavy rebuilds into this budgeted state machine instead of
  // blocking one frame: BVH rebuild -> radiance injection slices -> caustic occlusion
  // slices -> one cube probe face per frame -> PMREM swap. Stale GI/probe/reflections keep
  // rendering until each swaps.
  let transition:null|{bvhDone:boolean;radianceDone:boolean;occlusionDone:boolean;probeFace:number}=null;
  const signMaterials=new Map<string,T.MeshStandardMaterial>();
  const signGeometry=new T.PlaneGeometry(.72,.9);
  function box(chunk: Chunk, x: number, y: number, z: number, w: number, h: number, d: number, mat = tile, solid = true) {
    const m = new T.Mesh(cube, mat); m.position.set(x, y, z); m.scale.set(w, h, d); m.castShadow = true; m.receiveShadow = true; chunk.group.add(m);
    if (solid) chunk.solids.push({ min: new T.Vector3(x-w/2,y-h/2,z-d/2), max: new T.Vector3(x+w/2,y+h/2,z+d/2), color: mat.color });
    return m;
  }
  function rod(chunk: Chunk, a: number[], b: number[], radius = .035,collision=true) {
    const start = new T.Vector3(...a), end = new T.Vector3(...b), delta = end.clone().sub(start);
    const m = new T.Mesh(cylinder, metal); m.position.copy(start.add(end).multiplyScalar(.5)); m.scale.set(radius, delta.length(), radius);
    m.quaternion.setFromUnitVectors(new T.Vector3(0,1,0),delta.normalize()); m.castShadow = true; chunk.group.add(m);
    if(collision)chunk.colliders.push({center:m.position.clone(),half:new T.Vector3(radius,m.scale.y/2,radius),rotation:m.quaternion.clone()});
  }
  function rail(c: Chunk, x: number, y: number, z: number, length: number, alongX = true) {
    const end = alongX ? [x+length,y+1,z] : [x,y+1,z+length];
    rod(c,[x,y+1,z],end); rod(c,[x,y+.48,z],alongX?[x+length,y+.48,z]:[x,y+.48,z+length]);
    for(let t=0;t<=length+.01;t+=length/Math.ceil(length/1.8)) rod(c,alongX?[x+t,y,z]:[x,y,z+t],alongX?[x+t,y+1,z]:[x,y+1,z+t]);
  }
  function sign(c: Chunk, x: number, y: number, z: number, text: string, angle = 0, dark = false) {
    const cacheKey=text+dark;let mat=signMaterials.get(cacheKey);
    if(!mat){const canvas=document.createElement('canvas'); canvas.width=256; canvas.height=320;
    const ctx=canvas.getContext('2d')!; ctx.fillStyle=dark?'#17252b':'#c4c8bd'; ctx.fillRect(0,0,256,320);
    ctx.strokeStyle=dark?'#7c8063':'#873e32'; ctx.lineWidth=5; ctx.strokeRect(10,10,236,300);
    ctx.fillStyle=dark?'#b4ac78':'#973f30'; ctx.textAlign='center'; ctx.font='bold 44px serif';
    text.split('\n').forEach((s,i)=>ctx.fillText(s,128,66+i*58)); ctx.font='16px monospace';ctx.fillText('POOL  /  1.2 M',128,284);
    const texture=new T.CanvasTexture(canvas); texture.colorSpace=T.SRGBColorSpace; textures.push(texture);
    mat=new T.MeshStandardMaterial({map:texture,roughness:.7}); materials.push(mat);signMaterials.set(cacheKey,mat);}
    const mesh=new T.Mesh(signGeometry,mat); mesh.position.set(x,y,z); mesh.rotation.y=angle;c.group.add(mesh);
  }
  function ladder(c: Chunk, x: number, z: number, height: number,exitZ=z-.65) {
    // Rails start below the flooded floor (top at -0.72) instead of hovering.
    for(const dx of [-.43,.43]) rod(c,[x+dx,-.78,z+.7],[x+dx,height+1,z],.035,false);
    for(let y=.3;y<height+.5;y+=.34) rod(c,[x-.43,y,z+.7*(1-y/(height+1))],[x+.43,y,z+.7*(1-y/(height+1))],.027,false);
    c.ladders.push({base:new T.Vector3(x,-.15,z+1.1),top:new T.Vector3(x,height+.16,z+.45),exit:new T.Vector3(x,height+.16,exitZ)});
  }
  function tower(c: Chunk, x: number, z: number) {
    box(c,x,2.06,z,.85,5.68,1.1,pale);
    for(const y of [2.5,5]) {
      box(c,x-.6,y,z,2.8,.22,2.4,pale); rail(c,x-2,y+.12,z-1.05,2.8); rail(c,x-2,y+.12,z-1.05,2.1,false);
      rail(c,x-2,y+.12,z+1.05,1.7); ladder(c,x+.55+(y===5?-.9:0),z+1.55,y,z+.75);
    }
    sign(c,x-.65,3.6,z+.57,'禁止\n跳水');
  }
  // Sign copy decays with the room: pristine rooms keep their familiar notices,
  // deep rooms replace them with quietly wrong ones. Same rng stream, so the
  // same room always picks the same line.
  const DECAY_TEXT:[string[],string[]]=[['本区\n已停用','维护\n中','暂不\n开放'],['请勿\n逗留','水位\n上升','此处\n无人']];
  function decayText(rng:()=>number,pristine:string,corrupt:number){
    if(corrupt<2)return pristine;
    const pool=DECAY_TEXT[corrupt>=3?1:0];
    return pool[Math.floor(rng()*pool.length)];
  }
  function prop(c: Chunk, x: number, z: number, yaw: number, kind: PropKind) {
    // Prop visuals sit relative to the group origin so the collision sphere
    // wraps the body: ducks sink 12.5cm (body below origin, head above), eggs
    // keep their centred ellipsoid, beach balls are a single centred sphere.
    const sink=PROP_SPEC[kind].sink;
    const g=new T.Group();g.position.set(x,.32+sink,z);g.rotation.y=yaw;
    const part=(mat:T.Material,px:number,py:number,pz:number,sx:number,sy:number,sz:number)=>{
      const m=new T.Mesh(sphere,mat);m.position.set(px,py,pz);m.scale.set(sx,sy,sz);m.castShadow=true;m.receiveShadow=true;g.add(m);
    };
    if(kind==='ball') {
      const m=new T.Mesh(ballGeometry,ballMaterial);m.castShadow=m.receiveShadow=true;g.add(m);
    } else if(kind==='egg') part(ivory,0,0,0,.145,.205,.145);
    else {
      part(yellow,0,.04-sink,0,.16,.105,.235);part(yellow,0,.19-sink,-.1,.11,.12,.115);part(orange,0,.17-sink,-.222,.075,.026,.06);
      for(const side of [-1,1])part(black,side*.087,.223-sink,-.158,.018,.02,.015);
      part(yellow,-.125,.07-sink,.025,.052,.055,.13);part(yellow,.125,.07-sink,.025,.052,.055,.13);
    }
    g.userData.phase=yaw;g.userData.kind=kind; c.group.add(g);c.floats.push(g);
  }
  function generate(rx: number, rz: number): Chunk {
    const c:Chunk={group:new T.Group(),solids:[],lamps:[],floats:[],lights:[],bodies:[],colliders:[],ladders:[],flickers:[]};
    const x=(rx-originX)*ROOM,z=(rz-originZ)*ROOM,rng=randomFor(rx,rz,seed),layout=roomLayout(rx,rz,seed);
    // Structures reach the flooded floor (top at y=-0.72) and are buried 6cm
    // so nothing reads as hovering above the pool bottom.
    const GROUND=-.78;
    const bright=layout.variant===3||layout.variant===5||layout.variant===6;
    // 柱阵水厅（variant 7）抬到 13m：柱子撑满高度，柱顶还要留出干燥
    // 小房间和人的净空。
    const ceiling=layout.variant===3?14:layout.variant===7?13:(layout.variant===4||layout.variant===6)?5.8:9.2;
    // Exploration decay: 0 pristine near spawn, 3 far out. Lights die off first,
    // then geometry tilts and pales, then signs stop making sense.
    const corrupt=layout.corrupt;
    let wfcGrid:WfcTile[][]|null=null;
    box(c,x,-.995,z,32,.55,32);
    if(bright){
      // Recessed luminous clerestory; actual ceiling opening, with a thick reveal.
      box(c,x-11,ceiling,z,10,.6,32,pale);box(c,x+11,ceiling,z,10,.6,32,pale);
      box(c,x,ceiling,z-11,12,.6,10,pale);box(c,x,ceiling,z+11,12,.6,10,pale);
      box(c,x,ceiling+1.2,z,12,.12,12,skylightGlow as unknown as T.MeshStandardMaterial,false);
      for(const dx of [-6,6])box(c,x+dx,ceiling+.5,z,.25,1.4,12,pale);
      for(const dz of [-6,6])box(c,x,ceiling+.5,z+dz,12,1.4,.25,pale);
      for(const offset of [-6,-3,0,3,6]){
        box(c,x+offset,ceiling+1.08,z,.12,.16,12,lampHousing);
        box(c,x,ceiling+1.08,z+offset,12,.16,.12,lampHousing);
      }
    }else box(c,x,ceiling,z,32,.6,32,pale);
    // Four aligned portals; split walls are owned by each room's north and west edges.
    for(const side of [-1,1]) {
      box(c,x+side*10,(ceiling+GROUND)/2,z-16,12,ceiling-GROUND,.6);
      box(c,x-16,(ceiling+GROUND)/2,z+side*10,.6,ceiling-GROUND,12);
    }
    box(c,x,(ceiling+5.4)/2,z-16,8,ceiling-5.4,.6);box(c,x-16,(ceiling+5.4)/2,z,.6,ceiling-5.4,8);
    for(const axis of ['x','z'] as const){
      const neighbour=roomLayout(rx+(axis==='x'?1:0),rz+(axis==='z'?1:0),seed).variant;
      const adjacentTop=neighbour===3?14:neighbour===7?13:(neighbour===4||neighbour===6)?5.8:9.2;
      if(ceiling>adjacentTop)box(c,x+(axis==='x'?16:0),(ceiling+adjacentTop)/2,z+(axis==='z'?16:0),axis==='x'?.6:32,ceiling-adjacentTop,axis==='x'?32:.6,pale);
    }
    if(layout.variant<3){
    for(const dx of [-10,-3,4,11]) {
      box(c,x+dx,(6+GROUND)/2,z-9,1,6-GROUND,1);
      box(c,x+dx,7.45,z-9,.65,2.9,.65);
    }
    box(c,x,5.85,z-11.7,31,.35,5.5);box(c,x,5.5,z-9,31,.6,.55);
    rail(c,x-15,6.05,z-9,30);
    ladder(c,x-12,z-8.4,6.04,z-10.1);
    // Dark recessed bays and structural ceiling beams.
    for(const dx of [-14,-7,0,7,14])box(c,x+dx,8.65,z,.32,.6,31);
    for(const dz of [-5,6])box(c,x,8.65,z+dz,31,.6,.4);
    sign(c,x-3,3.4,z-8.48,'禁止\n跳水'); sign(c,x+10,3.4,z-15.68,decayText(rng,'泳池\n须知',corrupt),0,true);
    if(layout.variant!==2) tower(c,x+6,z-6);
    else {
      for(const dx of [-7,7])box(c,x+dx,(4.8+GROUND)/2,z,1.1,4.8-GROUND,1.1,pale);
      // A tiled landing joins the west wall. Each visible step is its own
      // collider, leaving the centre and all four doorways open water.
      rng(); // Preserve the room's seeded prop and fixture placement.
      box(c,x-12.75,.08,z-6,5.9,1.72,4,pale);
      for(let i=0;i<5;i++){
        const top=.94-(i+1)*.28;
        box(c,x-9.5+i*.62,(GROUND+top)/2,z-6,.64,top-GROUND,3.2,pale);
      }
      rail(c,x-15.6,.94,z-8,5.6);
    }
    // Lifeguard chair with slanted legs, seat and backrest.
    for(const dx of [-.65,.65])for(const dz of [-.6,.6])rod(c,[x+12+dx,GROUND,z-7+dz],[x+12+dx*.65,2.8,z-7+dz*.65],.045);
    box(c,x+12,2.45,z-7,1,.13,.9,pale);box(c,x+12,2.95,z-7.4,1,.9,.1,pale);ladder(c,x+12,z-6.6,2.2);
    for(const dz of [-3,5]) {box(c,x-13,.72,z+dz,2.4,.12,.65,pale);for(const dx of [-.8,.8])rod(c,[x-13+dx,GROUND,z+dz],[x-13+dx,.7,z+dz]);}
    // Round columns have cylindrical colliders, not oversized square blockers.
    for(const dz of [1,9]){
      const m=new T.Mesh(cylinder,tile);m.position.set(x-8,(8.9+GROUND)/2,z+dz);m.scale.set(.65,8.9-GROUND,.65);
      // Far-out rooms lean their columns a few degrees; colliders stay as the
      // upright box, well within the tilt, so nothing falls or clips.
      if(corrupt>=2){m.rotation.z=(rng()-.5)*.15;m.rotation.x=(rng()-.5)*.15;}
      m.castShadow=m.receiveShadow=true;c.group.add(m);
      c.colliders.push({center:m.position.clone(),half:new T.Vector3(.65,(8.9-GROUND)/2,.65),radius:.65});
    }
    // A walkable chute, side rails and a ladder/platform at its high end.
    const slideStart=new T.Vector3(x+10,3.3,z+2),slideEnd=new T.Vector3(x+10,GROUND,z+8);
    const delta=slideEnd.clone().sub(slideStart),slope=Math.atan2(slideStart.y-slideEnd.y,slideEnd.z-slideStart.z);
    const chute=new T.Mesh(cube,red);chute.position.copy(slideStart).add(slideEnd).multiplyScalar(.5);chute.scale.set(1.65,.16,delta.length());chute.rotation.x=slope;chute.castShadow=chute.receiveShadow=true;c.group.add(chute);
    c.colliders.push({center:chute.position.clone(),half:new T.Vector3(.825,.08,delta.length()/2),rotation:chute.quaternion.clone(),slide:true});
    for(const side of [-1,1])rod(c,[slideStart.x+side*.86,slideStart.y+.3,slideStart.z],[slideEnd.x+side*.86,slideEnd.y+.3,slideEnd.z],.075);
    box(c,x+10,3.22,z+1.1,2,.16,1.8,pale);ladder(c,x+10,z-.15,3.3,z+.65);
    // A chrome sphere on a grounded pedestal, and a freestanding door leading nowhere.
    box(c,x-5,.21,z+7,1.5,1.98,1.5,pale);
    const odd=new T.Mesh(sphere,chrome);odd.position.set(x-5,1.9,z+7);odd.scale.setScalar(.8);odd.castShadow=odd.receiveShadow=true;c.group.add(odd);
    c.colliders.push({center:odd.position.clone(),half:new T.Vector3(.8,.8,.8),radius:.8});
    for(const dx of [-.8,.8])box(c,x+3+dx,1.11,z+8,.15,3.78,.25,metal);
    box(c,x+3,3,z+8,1.75,.16,.25,metal);sign(c,x+3,2.55,z+8.14,'出口\n不存在',0,true);
    if(layout.variant===1){const extra=new T.Mesh(sphere,yellow);extra.position.set(x-3,.87,z);extra.scale.setScalar(1.6);extra.castShadow=true;c.group.add(extra);c.colliders.push({center:extra.position.clone(),half:new T.Vector3(1.6,1.6,1.6),radius:1.6});}
    }else if(layout.variant===3){
      // Tall, sunlit arcades with open central sightlines and a submerged stair.
      for(const dx of [-8,8])for(const dz of [-9,3]){
        const arch=new T.Mesh(archGeometry,pale);arch.position.set(x+dx,GROUND,z+dz);arch.castShadow=arch.receiveShadow=true;c.group.add(arch);
        for(const side of [-1,1])c.solids.push({min:new T.Vector3(x+dx+side*4.05-.55,GROUND,z+dz),max:new T.Vector3(x+dx+side*4.05+.55,5.3,z+dz+.8),color:pale.color});
      }
      for(let i=0;i<5;i++)box(c,x-12,GROUND+(i+1)*.16,z+10-i*.65,5,(i+1)*.32,.68,pale);
      rail(c,x-14,1,z+7,4);sign(c,x+12,3,z-15.65,decayText(rng,'静水\n回廊',corrupt));
    }else if(layout.variant===4||layout.variant===6){
      // Low fluorescent baths: broad dry islands and narrow linked basins.
      for(const dx of [-10,0,10])for(const dz of [-9,3]){
        box(c,x+dx,2.5,z+dz,1.25,6.56,1.25,pale);
        box(c,x+dx,-.07,z+dz,5.8,1.42,5.8,pale);
        for(let i=0;i<3;i++)box(c,x+dx,-.58+i*.18,z+dz+3.1+i*.5,3,.28,.52,pale);
      }
      for(const dz of [-9,3])box(c,x,.59,z+dz,26,.12,1.5,pale);
      sign(c,x+10,3,z-15.65,decayText(rng,'夜间\n浴场',corrupt));
    }else if(layout.variant===7){
      // 柱阵水厅：内部布局由波函数坍缩求解——柱子互不相邻、平台聚成
      // 岛、门洞走廊恒为空水。WFC 用独立随机流（seed+911），同一
      // (x,z,seed) 结果确定，流式重生成不漂移。崩坏等级抬高柱子权重，
      // 越深处的柱阵越密；重度崩坏还会让平台岛整块沉没缺失。
      wfcGrid=collapseInterior(randomFor(rx,rz,seed+911),WFC_SIZE,1+corrupt*.55);
      // 螺旋楼梯绕「离房间中心最近」的柱子盘旋而上，通往同一根柱腰上
      // 悬挑出的干燥小房间；重度崩坏时楼梯和小房间一起消失。
      const pillars:[number,number][]=[];
      for(let j=0;j<WFC_SIZE;j++)for(let i=0;i<WFC_SIZE;i++)if(wfcGrid[j][i]==='P')pillars.push([i,j]);
      const stair:[number,number]|null=pillars.length?pillars.reduce((a,b)=>{
        const d=([i,j]:[number,number])=>Math.hypot(i-(WFC_SIZE-1)/2,j-(WFC_SIZE-1)/2);
        return d(b)<d(a)?b:a;
      }):null;
      const cell=([i,j]:[number,number])=>[x+(i-(WFC_SIZE-1)/2)*WFC_CELL,z+(j-(WFC_SIZE-1)/2)*WFC_CELL] as [number,number];
      for(let j=0;j<WFC_SIZE;j++)for(let i=0;i<WFC_SIZE;i++){
        const [wx,wz]=cell([i,j]);
        if(wfcGrid[j][i]==='P'){
          const m=new T.Mesh(cylinder,tile);m.position.set(wx,(ceiling+GROUND)/2,wz);m.scale.set(.65,ceiling-GROUND,.65);
          // 楼梯柱保持笔直（踏步要贴着它绕），其余柱子在深处照旧倾斜。
          if(corrupt>=2&&!(stair&&stair[0]===i&&stair[1]===j)){m.rotation.z=(rng()-.5)*.15;m.rotation.x=(rng()-.5)*.15;}
          m.castShadow=m.receiveShadow=true;c.group.add(m);
          c.solids.push({min:new T.Vector3(wx-.65,GROUND,wz-.65),max:new T.Vector3(wx+.65,ceiling,wz+.65),color:tile.color});
        }else if(wfcGrid[j][i]==='S'&&(corrupt<3||rng()>=.3))box(c,wx,(.64+GROUND)/2,wz,2.25,.64-GROUND,2.25,pale);
      }
      if(stair&&corrupt<3){
        const [sx,sz]=cell(stair);
        // 32 级踏步、每级抬升 .3m、绕柱 30°——两圈半从水里盘到 8.8m。
        // 起步角朝房间中心，玩家涉水过来第一眼就能看到入口。
        const theta0=Math.atan2(z-sz,x-sx),steps=32,rise=.3,stepAngle=Math.PI/6,R=1.05;
        for(let s=0;s<steps;s++){
          const theta=theta0+s*stepAngle,m=new T.Mesh(cube,pale);
          m.position.set(sx+Math.cos(theta)*R,GROUND+.045+s*rise,sz+Math.sin(theta)*R);
          m.scale.set(.95,.09,1.04);m.rotation.y=-theta;
          m.castShadow=m.receiveShadow=true;c.group.add(m);
          c.colliders.push({center:m.position.clone(),half:new T.Vector3(.475,.045,.52),rotation:m.quaternion.clone()});
        }
        // 柱顶干燥小房间：平台向楼梯到达方向的反侧偏移，开口正对最后
        // 一级踏步，三面齐腰矮墙，对面挂一盏红色出口灯俯瞰整个水厅。
        const end=theta0+steps*stepAngle,ox=Math.cos(end),oz=Math.sin(end);
        const px=sx-ox*.9,pz=sz-oz*.9;
        box(c,px,8.96,pz,2.6,.12,2.6,pale);
        const open: [number, number] = Math.abs(ox) > Math.abs(oz) ? [Math.sign(ox), 0] : [0, Math.sign(oz)];
        for(const [dx,dz] of [[1,0],[-1,0],[0,1],[0,-1]] as [number,number][]){
          if(dx===open[0]&&dz===open[1])continue;
          box(c,px+dx*1.3,9.55,pz+dz*1.3,dx?.12:2.6,.7,dz?.12:2.6,pale);
        }
        box(c,px+ox*1.22,9.32,pz+oz*1.22,Math.abs(ox)>.5?.16:.42,.52,Math.abs(ox)>.5?.42:.16,exitGlow as unknown as T.MeshStandardMaterial,false);
        const redLight=new T.PointLight('#ff4a30',7,7,2);redLight.position.set(px+ox*1.05,9.4,pz+oz*1.05);redLight.shadow.bias=-.001;redLight.shadow.normalBias=0;
        c.lights.push(redLight);
        c.lamps.push({position:redLight.position.clone(),color:new T.Color('#ff4a30'),power:1.4});
        sign(c,px-open[0]*1.22,9.62,pz-open[1]*1.22,corrupt>=2?'上方\n禁止\n停留':'柱顶\n观察间',Math.atan2(open[0],open[1]));
      }
      for(const dx of [-14,-7,0,7,14])box(c,x+dx,12.4,z,.32,.6,31);
      sign(c,x+8,3,z-15.65,decayText(rng,'柱影\n重重',corrupt));
    }else{
      // Dreamlike gallery: paired colonnades, an elevated balcony and blue bands.
      for(const dx of [-10,10])for(const dz of [-10,-3,4,11]){
        box(c,x+dx,4.1,z+dz,1.5,9.76,1.5,pale);
        box(c,x+dx,5.5,z+dz,4,.3,3,pale);
      }
      box(c,x,5.5,z-12,28,.35,3,pale);rail(c,x-14,5.7,z-10.6,28);
      ladder(c,x+12,z-9.8,5.7,z-11.4);
      tower(c,x-10,z+2);sign(c,x+8,3,z-15.65,decayText(rng,'午后\n无人',corrupt));
    }
    // Lighting decays with the room. The fixtures stay mounted forever; deep
    // out the tubes die one by one (dark glass, no PointLight) and the
    // survivors flicker like failing ballasts. At least one tube per room
    // stays alive — total darkness would wall off exploration. rng draws are
    // unconditional so the same room always regenerates the same failures.
    const powerScale=[1,.78,.52,.32][corrupt];
    const survival=[1,1,.6,.28][corrupt];
    const flickerChance=[0,.5,.8,1][corrupt];
    const flickerAmp=[0,.35,.6,.85][corrupt];
    const alive=[rng()<survival,rng()<survival];
    if(!alive[0]&&!alive[1])alive[rng()<.5?0:1]=true;
    for(const slot of [0,1]) {
      const dx=slot===0?-9:8;
      const pos=new T.Vector3(x+dx,Math.min(7.3,ceiling-.7),z-5),color=new T.Color(bright?'#fff5de':dx<0?'#b5dfdc':'#eee9d5');
      const power=(bright?175:layout.variant===4?55:95)*powerScale;
      const flickerVote=rng(),flickerSeed=rng()*37;
      const flicker=alive[slot]&&flickerVote<flickerChance;
      if(alive[slot]){
        const l=new T.PointLight(color,power,36,2);l.position.copy(pos);l.shadow.mapSize.set(2048,2048);l.shadow.bias=-.001;l.shadow.normalBias=0;
        // Tighten the shadow frustum to the light's actual reach: the default 500m
        // far plane wastes depth precision and fuzzes contact shadows. A slightly
        // larger sampling disk softens object shadow edges.
        l.shadow.camera.far=40;l.shadow.radius=3;c.lights.push(l);
        c.lamps.push({position:pos,color,power:power/4.75});
        if(flicker)c.flickers.push({light:l,glow:glow,base:power,seed:flickerSeed,amp:flickerAmp});
      }
      // Visible suspended double-tube luminaire, colocated with its actual light.
      // The punctual proxy represents an extended tube: exclude its own small
      // housing from shadow casting, or it projects giant razor-edged wedges.
      const luminaireStart=c.group.children.length;
      box(c,pos.x,pos.y+.18,pos.z,2.85,.18,.52,lampHousing,false);
      // Dead tubes get dark glass; flickering ones get their own material so the
      // glass can dim in sync with the point light.
      let tubeMat:T.MeshBasicMaterial=glow as T.MeshBasicMaterial;
      if(!alive[slot])tubeMat=glowOff;
      else if(flicker){tubeMat=new T.MeshBasicMaterial({color:new T.Color(3.4,3.6,3.5)});materials.push(tubeMat);c.flickers[c.flickers.length-1].glow=tubeMat;}
      for(const dz of [-.14,.14])box(c,pos.x,pos.y+.055,pos.z+dz,2.55,.11,.095,tubeMat as unknown as T.MeshStandardMaterial,false);
      for(const end of [-1.35,1.35])box(c,pos.x+end,pos.y+.09,pos.z,.12,.24,.5,lampHousing,false);
      for(const end of [-1.05,1.05])rod(c,[pos.x+end,pos.y+.28,pos.z],[pos.x+end,ceiling-.25,pos.z],.025);
      for(const fixture of c.group.children.slice(luminaireStart)){
        fixture.castShadow=false;fixture.userData.luminaire=true;
      }
    }
    // Deep-corruption rooms go quiet: half the floaters are simply gone.
    const duckCount=corrupt>=3?Math.ceil(layout.ducks/2):layout.ducks;
    // 海滩球是稀客：多数房间漂着一个，偶尔成对，剩下的没有。
    const ballCount=Math.floor(rng()*2.4);
    const spawn=(px:number,pz:number,yaw:number,kind:PropKind)=>{if(!blocked(new T.Vector3(px,1,pz),c.solids))prop(c,px,pz,yaw,kind);};
    if(wfcGrid){
      // WFC 房间：道具只落在坍缩出的空水格上，不会卡进柱子或平台。
      const empties:[number,number][]=[];
      for(let j=0;j<WFC_SIZE;j++)for(let i=0;i<WFC_SIZE;i++)if(wfcGrid[j][i]==='E')empties.push([i,j]);
      const pick=()=>{const [ci,cj]=empties[Math.floor(rng()*empties.length)];return [x+(ci-(WFC_SIZE-1)/2)*WFC_CELL+(rng()-.5)*1.1,z+(cj-(WFC_SIZE-1)/2)*WFC_CELL+(rng()-.5)*1.1] as [number,number];};
      for(let i=0;i<duckCount;i++){const [px,pz]=pick();spawn(px,pz,rng()*Math.PI*2,i%3!==0?'egg':'duck');}
      for(let i=0;i<ballCount;i++){const [px,pz]=pick();spawn(px,pz,rng()*Math.PI*2,'ball');}
    }else{
      const pick=()=>[x+(rng()-.5)*28,z+(rng()-.5)*27] as [number,number];
      for(let i=0;i<duckCount*2;i++){const [px,pz]=pick();spawn(px,pz,rng()*Math.PI*2,i%3!==0?'egg':'duck');}
      for(let i=0;i<ballCount;i++){const [px,pz]=pick();spawn(px,pz,rng()*Math.PI*2,'ball');}
    }
    // Shared geometry/materials keep the smooth balls at one draw call per room.
    const batches=new Map<string,{geometry:T.BufferGeometry;mat:T.Material;entries:{body:PropBody;local:T.Matrix4}[]}>();
    for(const g of c.floats){
      const kind=g.userData.kind as PropKind,spec=PROP_SPEC[kind];
      const body:PropBody={position:g.position.clone(),velocity:new T.Vector3(),rotation:g.quaternion.clone(),radius:spec.radius,floatBias:spec.floatBias,name:spec.name,kind,visual:g,parts:[],promoted:false,splashCooldown:0,hitCooldown:0};
      c.bodies.push(body);props.add(body);
      for(const part of g.children){const m=part as T.Mesh;m.updateMatrix();const key=`${m.geometry.uuid}|${(m.material as T.Material).uuid}`;
        if(!batches.has(key))batches.set(key,{geometry:m.geometry,mat:m.material as T.Material,entries:[]});
        batches.get(key)!.entries.push({body,local:m.matrix.clone()});}
      c.group.remove(g);}
    c.floats=[];
    for(const {geometry,mat,entries} of batches.values()){const mesh=new T.InstancedMesh(geometry,mat,entries.length);entries.forEach(({body,local},index)=>{body.parts.push({mesh,index,local});mesh.setMatrixAt(index,new T.Matrix4().compose(body.position,body.rotation,new T.Vector3(1,1,1)).multiply(local));});mesh.castShadow=true;mesh.receiveShadow=true;mesh.frustumCulled=false;c.group.add(mesh);}
    if(bright)c.group.traverse(o=>{if(o instanceof T.Mesh){if(o.material===tile)o.material=daylightTile;else if(o.material===pale)o.material=daylightPale;
      // Decayed wings keep their skylight geometry, but the glass has gone dark.
      if(corrupt>=2&&o.material===skylightGlow)o.material=skylightDim;}});
    // Non-daylit deep rooms swap the clean ceramic for a damp, mossy set.
    else if(corrupt>=2)c.group.traverse(o=>{if(o instanceof T.Mesh){if(o.material===tile)o.material=grimTile;else if(o.material===pale)o.material=grimPale;}});
    scene.add(c.group);return c;
  }
  function stream() {
    const nx=originX+Math.floor((camera.position.x+16)/ROOM),nz=originZ+Math.floor((camera.position.z+16)/ROOM);
    if(nx===cx&&nz===cz)return;
    cx=nx;cz=nz;visited.add(`${cx},${cz}`);
    for(const [key,c] of chunks) {
      const [x,z]=key.split(',').map(Number);
      if(Math.abs(x-cx)>1||Math.abs(z-cz)>1) {scene.remove(c.group);props.remove(c.bodies);c.group.traverse(o=>{if(o instanceof T.InstancedMesh)o.dispose();});for(const l of c.lights)l.dispose();chunks.delete(key);}
    }
    const shift=new T.Vector3((cx-originX)*ROOM,0,(cz-originZ)*ROOM);
    camera.position.sub(shift);
    waterSystem.rebase(shift);
    props.rebase(shift);
    for(const c of chunks.values()){for(const child of c.group.children)child.position.sub(shift);for(const b of c.solids){b.min.sub(shift);b.max.sub(shift);}for(const l of c.lamps)l.position.sub(shift);for(const l of c.lights)l.position.sub(shift);for(const col of c.colliders)col.center.sub(shift);for(const l of c.ladders){l.base.sub(shift);l.top.sub(shift);l.exit.sub(shift);}}
    originX=cx;originZ=cz;
    for(let x=cx-1;x<=cx+1;x++)for(let z=cz-1;z<=cz+1;z++)if(!chunks.has(`${x},${z}`))chunks.set(`${x},${z}`,generate(x,z));
    allSolids=[...chunks.values()].flatMap(c=>c.solids);
    allColliders=allSolids.map(b=>({center:b.min.clone().add(b.max).multiplyScalar(.5),half:b.max.clone().sub(b.min).multiplyScalar(.5)})).concat([...chunks.values()].flatMap(c=>c.colliders));
    allLadders=[...chunks.values()].flatMap(c=>c.ladders);
    roomLights.select(chunks.get(`${cx},${cz}`)!.lights,[...chunks.entries()].filter(([key])=>key!==`${cx},${cz}`).flatMap(([,c])=>c.lights));
    field.begin(allSolids,[...chunks.values()].flatMap(c=>c.lamps),0,0);
    waterSystem.setLamps(chunks.get(`${cx},${cz}`)!.lamps);
    waterSystem.beginOcclusion(allSolids);
    // Ripples bounce off pillars and steps too: gather the waterline-crossing
    // obstacles of the central room as XZ boxes. Walls are excluded (the wall
    // mirrors already reflect) and anything below 10cm thick is visual clutter.
    const roomChunk=chunks.get(`${cx},${cz}`)!;
    const blocks:T.Vector4[]=[];
    for(const b of roomChunk.solids){
      if((b.max.x-b.min.x)/2>=8||(b.max.z-b.min.z)/2>=8)continue;
      if(b.min.x<-15.9||b.max.x>15.9||b.min.z<-15.9||b.max.z>15.9)continue;
      if(b.min.y>=.32||b.max.y<=.32)continue;
      blocks.push(new T.Vector4(b.min.x,b.min.z,b.max.x,b.max.z));
    }
    for(const c of roomChunk.colliders){
      if(c.radius===undefined||c.radius<.1||c.rotation)continue;
      if(c.center.y-c.half.y>=.32||c.center.y+c.half.y<=.32)continue;
      blocks.push(new T.Vector4(c.center.x-c.radius,c.center.z-c.radius,c.center.x+c.radius,c.center.z+c.radius));
    }
    if(blocks.length>16){
      blocks.sort((a,b)=>Math.hypot((a.x+a.z)/2,(a.y+a.w)/2)-Math.hypot((b.x+b.z)/2,(b.y+b.w)/2));
      blocks.length=16;
    }
    waterSystem.setBlocks(blocks);
    // The old BVH no longer matches the rebased world; reflections drop to the
    // faint probe until the deferred rebuild swaps in.
    rt.invalidate();
    transition={bvhDone:false,radianceDone:false,occlusionDone:false,probeFace:0};
    // The current room's decay drives the global mood: thicker fog, darker
    // backdrop and a slightly detuned ambience bed.
    currentCorrupt=roomLayout(cx,cz,seed).corrupt;
    audio.setCorruption(currentCorrupt);
  }
  let currentCorrupt=0;
  // Reflection BVH contents: static building meshes with their material colors,
  // low-poly proxies of the floaters near the current room, and any promoted
  // (held/thrown) prop bodies. Props snapshot per crossing; their bobbing is
  // smaller than the reflection width on tile.
  const rtTileMaterials=new Set([tile,pale,daylightTile,daylightPale,grimTile,grimPale]);
  const rtProxy=new T.SphereGeometry(1,8,6);
  const rtInstance=new T.Matrix4(), rtPos=new T.Vector3();
  const collectRtItems=()=>{
    scene.updateMatrixWorld(true);
    const items:RtItem[]=[];
    for(const c of chunks.values())c.group.traverse(o=>{
      if(o instanceof T.InstancedMesh){
        o.updateWorldMatrix(true,false);
        const color=(o.material as T.MeshStandardMaterial).color;
        for(let i=0;i<o.count;i++){
          o.getMatrixAt(i,rtInstance);
          rtPos.setFromMatrixPosition(rtInstance);
          if(rtPos.y>2||Math.abs(rtPos.x)>17||Math.abs(rtPos.z)>17)continue;
          items.push({geometry:rtProxy,matrix:new T.Matrix4().multiplyMatrices(o.matrixWorld,rtInstance),color,tile:0});
        }
      } else if(o instanceof T.Mesh&&!o.userData.luminaire&&!(o.material instanceof T.MeshBasicMaterial)){
        const m=o.material as T.MeshStandardMaterial;
        items.push({geometry:o.geometry,matrix:o.matrixWorld,color:m.color,tile:rtTileMaterials.has(m)?1:0});
      }
    });
    for(const b of props.bodies){
      if(!b.promoted)continue;
      b.visual.updateWorldMatrix(true,true);
      b.visual.traverse(o=>{if(o instanceof T.Mesh)items.push({geometry:o.geometry,matrix:o.matrixWorld,color:(o.material as T.MeshStandardMaterial).color,tile:0});});
    }
    return items;
  };
  stream(); scene.add(new T.AmbientLight('#9dbacb',.095));
  const normals=new T.TextureLoader().load('/assets/textures/waternormals.jpg');normals.wrapS=normals.wrapT=T.RepeatWrapping;textures.push(normals);
  const water=new Water(new T.PlaneGeometry(96,96,384,384),{textureWidth:768,textureHeight:768,waterNormals:normals,sunDirection:new T.Vector3(-.3,1,-.3),sunColor:'#a1bdc3',waterColor:'#327c80',distortionScale:.42,alpha:.48,fog:true});
  water.material.fragmentShader=water.material.fragmentShader.replace('vec3( 1.5, 1.0, 1.5 )','vec3( 0.5, 1.0, 0.5 )');
  waterSystem.attach(water);
  water.rotation.x=-Math.PI/2;water.position.y=.28;water.material.transparent=true;water.material.depthWrite=false;
  water.material.uniforms.size.value=5;
  // Water owns its reflection target in a closure; retain it for full teardown.
  let reflectionTarget:Parameters<typeof renderer.setRenderTarget>[0]=null;
  const renderWater=water.onBeforeRender;
  water.onBeforeRender=function(...args){
    const setTarget=renderer.setRenderTarget;
    renderer.setRenderTarget=function(target,...rest){
      const uniforms=water.material.uniforms as Record<string,{value:unknown}>|undefined;
      if(uniforms&&target?.texture===uniforms.mirrorSampler?.value)reflectionTarget=target;
      return setTarget.call(this,target,...rest);
    };
    try{renderWater.apply(this,args);}finally{renderer.setRenderTarget=setTarget;}
  };
  scene.add(water);
  const probeTarget=new T.WebGLCubeRenderTarget(1024,{type:T.HalfFloatType});
  const probe=new T.CubeCamera(.1,65,probeTarget);const pmrem=new T.PMREMGenerator(renderer);
  probe.position.set(0,3.4,0);
  const probeFaces=probe.children as unknown as T.PerspectiveCamera[];
  let environment:T.WebGLRenderTarget|null=null;
  scene.environmentIntensity=.75;
  tile.envMapIntensity=.8; pale.envMapIntensity=.75;
  // Capture a single cube face; spreading the six renders across frames keeps each one cheap.
  // Shadows are not re-rendered per face — the main pass already produced them this frame.
  const captureProbeFace=(face:number)=>{
    if(face===0){
      if(probe.coordinateSystem!==renderer.coordinateSystem){probe.coordinateSystem=renderer.coordinateSystem;probe.updateCoordinateSystem();}
      probe.updateMatrixWorld();
    }
    const waterVisible=water.visible;water.visible=false;
    const generateMipmaps=probeTarget.texture.generateMipmaps;
    if(face<5)probeTarget.texture.generateMipmaps=false;
    const shadows=renderer.shadowMap.autoUpdate;renderer.shadowMap.autoUpdate=false;
    const previous=renderer.getRenderTarget();
    renderer.setRenderTarget(probeTarget,face,0);renderer.render(scene,probeFaces[face]);
    renderer.setRenderTarget(previous);
    renderer.shadowMap.autoUpdate=shadows;
    probeTarget.texture.generateMipmaps=generateMipmaps;
    water.visible=waterVisible;
  };
  const finishTransition=()=>{
    const next=pmrem.fromCubemap(probeTarget.texture);
    environment?.dispose();environment=next;scene.environment=environment.texture;
    field.finish();
  };
  const composer=new EffectComposer(renderer);
  // The Tyndall pass reads the scene's own depth so sun shafts stop at walls,
  // arches and columns instead of shining through them. RenderPass draws into
  // renderTarget1, so its depth attachment is the one to sample.
  composer.renderTarget1.depthTexture=new T.DepthTexture(composer.renderTarget1.width,composer.renderTarget1.height);
  composer.addPass(new RenderPass(scene,camera));
  // Real volumetric light scattering: a screen-space raymarch through the
  // slanted shaft the clerestory casts, with forward-scattering phase (look
  // toward the skylight and the beams brighten), occlusion-tested per step
  // against the depth buffer, and drifting humid-air density. The sun matches
  // the water caustics' direction.
  const tyndall=new ShaderPass({
    uniforms:{tDiffuse:{value:null},tDepth:{value:composer.renderTarget1.depthTexture},lightPos:{value:new T.Vector3(0,15,0)},
      camPos:{value:new T.Vector3()},camMat:{value:new T.Matrix4()},viewMat:{value:new T.Matrix4()},
      proj:{value:new T.Matrix4()},projInv:{value:new T.Matrix4()},intensity:{value:0},time:{value:0}},
    vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}',
    fragmentShader:`uniform sampler2D tDiffuse;uniform sampler2D tDepth;
      uniform vec3 lightPos;uniform vec3 camPos;uniform mat4 camMat;uniform mat4 viewMat;uniform mat4 proj;uniform mat4 projInv;
      uniform float intensity;uniform float time;varying vec2 vUv;
      // Sun direction, normalised at build time (GLSL constants can't call normalize()).
      const vec3 SUN=vec3(.274,-.913,.274);
      void main(){
        vec3 base=texture2D(tDiffuse,vUv).rgb;
        if(intensity<=.001){gl_FragColor=vec4(base,1.);return;}
        // Reconstruct this pixel's world-space view ray from NDC.
        vec2 ndc=vUv*2.-1.;
        vec4 nearH=projInv*vec4(ndc,-1.,1.);
        vec4 farH=projInv*vec4(ndc,1.,1.);
        vec3 dir=normalize(mat3(camMat)*(farH.xyz/farH.w-nearH.xyz/nearH.w));
        // Raymarch the shaft volume; a static per-pixel jitter hides the banding.
        const int STEPS=20;
        float dt=36./float(STEPS);
        float jitter=fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233)))*43758.5453);
        vec3 acc=vec3(0.);
        for(int i=0;i<STEPS;i++){
          vec3 p=camPos+dir*((float(i)+jitter)*dt);
          // Shafts live between the clerestory and the water surface only.
          if(p.y<.28)break;
          // Occlusion: geometry already drawn in front of this sample blocks it.
          vec4 clip=proj*viewMat*vec4(p,1.);
          if(clip.w<=0.)continue;
          vec2 suv=clip.xy/clip.w*.5+.5;
          if(suv.x<0.||suv.x>1.||suv.y<0.||suv.y>1.)continue;
          if(clip.z/clip.w*.5+.5>texture2D(tDepth,suv).x+.0015)continue;
          // Inside the slanted shaft? Distance to the axis through the skylight.
          vec3 rel=p-lightPos;
          float along=dot(rel,SUN);
          if(along<0.)continue;
          vec3 perp=rel-SUN*along;
          float spread=5.4*(1.+along*.028);
          float radial=length(perp);
          if(radial>spread)continue;
          float edge=1.-smoothstep(spread*.55,spread,radial);
          // Humid air: slow drifting density so the beams read as air, not glass.
          float drift=.72+.28*sin(p.x*.9+time*.32+sin(p.z*.7-time*.21)*1.4);
          // Forward scattering: looking up toward the sun brightens the shafts.
          float mu=max(dot(dir,-SUN),0.);
          float phase=.16+1.5*pow(mu,5.);
          acc+=vec3(.62,.78,.84)*edge*drift*phase*dt;
        }
        gl_FragColor=vec4(base+acc*intensity,1.);
      }`
  });composer.addPass(tyndall);
  let tyndallLevel=0;
  const bloom=new UnrealBloomPass(new T.Vector2(host.clientWidth,host.clientHeight),.045,.25,1.6);composer.addPass(bloom);composer.addPass(new OutputPass());
  const film=new ShaderPass({
    uniforms:{tDiffuse:{value:null},time:{value:0},filterMode:{value:1}},
    vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}',
    fragmentShader:`uniform sampler2D tDiffuse;uniform float time;uniform int filterMode;varying vec2 vUv;
      void main(){
        vec2 p=vUv-.5,uv=vUv;float r2=dot(p,p);
        // Modest barrel / wide converter distortion from a consumer CCD camcorder.
        if(filterMode==1)uv=.5+p*(1.0+.28*r2);
        if(filterMode==2)uv.x+=sin(uv.y*390.+time*4.)*.0006;
        float fringe=filterMode==2?.002:filterMode==1?.0008*r2:0.;
        vec3 c=vec3(texture2D(tDiffuse,uv+p*fringe).r,texture2D(tDiffuse,uv).g,texture2D(tDiffuse,uv-p*fringe).b);
        float grain=fract(sin(dot(floor(vUv*vec2(1536,864)),vec2(12.9898,78.233))+floor(time*24.))*43758.5453)-.5;
        if(filterMode>0){c+=grain*(filterMode==2?.025:.003);c*=1.-.48*pow(length(p),1.6);}
        if(filterMode==1){
          float y=dot(c,vec3(.2126,.7152,.0722));
          c=mix(vec3(y),c,.82)*vec3(1.025,1.012,.972);
          c+=vec3(.009,.015,.017)*(1.-smoothstep(.0,.32,y));
          c=mix(c,sqrt(max(c,vec3(0))),.045);
        }
        if(filterMode==2){c*=.97+.03*sin(vUv.y*1086.*3.14159);c=pow(max(c,vec3(0)),vec3(.94))*vec3(.98,1.02,.97);}
        if(filterMode==3){float y=dot(c,vec3(.2126,.7152,.0722));c=mix(vec3(y),c,.55)*vec3(.78,.96,1.14);}
        float border=smoothstep(0.,.018,min(min(uv.x,uv.y),min(1.-uv.x,1.-uv.y)));
        gl_FragColor=vec4(c*(filterMode==1?border:1.),1.);
      }`
  });composer.addPass(film);
  const keys=new Set<string>();let active=false,disposed=false,last=performance.now(),frames=0,elapsed=0,fps=0,time=0,vct=true,stepDistance=0,caustics=true,dragging=false,charging=false,chargeStart=0;
  // Crosshair action shared by desktop left-click and the mobile look-area tap:
  // grab a prop if one is aimed at, otherwise strike the water surface.
  const tapAction=()=>{
    const picked=props.pick(camera,allColliders);if(picked){props.grab(picked);dragging=true;return;}
    if(props.held)return;
    const direction=camera.getWorldDirection(new T.Vector3());
    const distance=(.28-camera.position.y)/direction.y;
    if(distance>0&&distance<12){const hit=camera.position.clone().addScaledVector(direction,distance);if(!blocked(hit,allSolids)){waterSystem.impact(hit.x,hit.z,.13);const dx=hit.x-camera.position.x,dz=hit.z-camera.position.z,d=Math.hypot(dx,dz);audio.tapWater((dx*Math.cos(camera.rotation.y)-dz*Math.sin(camera.rotation.y))/Math.max(1,d),d);}}
  };
  const strike=(e:MouseEvent)=>{
    if(!active)return;
    if(e.button===2){if(props.held&&!charging){charging=true;chargeStart=performance.now();}return;}
    if(e.button!==0)return;
    tapAction();
  };
  const chargeNow=()=>charging&&props.held?T.MathUtils.clamp((performance.now()-chargeStart)/1100,0,1):0;
  // Held right button charges the throw; releasing it launches the prop with a
  // speed that ramps from a gentle toss to a full-power hurl. Both mouseup
  // handlers filter on their own button - a right-click release must not be
  // mistaken for the end of a left-button drag (which would gently drop the
  // prop before the throw could fire).
  const releaseThrow=(e:MouseEvent)=>{
    if(e.button!==2||!charging)return;charging=false;dragging=false;
    if(props.held&&active){const charge=T.MathUtils.clamp((performance.now()-chargeStart)/1100,0,1);props.release(camera,6+charge*11);}
  };
  const releaseDrag=(e?:MouseEvent)=>{if(dragging&&(!e||e.button===0)){props.release();dragging=false;}};
  const wheel=(e:WheelEvent)=>{if(active&&props.held){e.preventDefault();props.distance=T.MathUtils.clamp(props.distance-e.deltaY*.002,.75,3);}};
  const noContext=(e:MouseEvent)=>{if(active)e.preventDefault();};
  // Grab/drop/climb action shared by the desktop E key and the mobile pad.
  const interactAction=()=>{if(props.held){props.release();charging=false;return;}const picked=props.pick(camera,allColliders);if(picked)props.grab(picked);else player.toggle(camera,allLadders);};
  const interactKey=(e:KeyboardEvent)=>{
    if(e.repeat||document.activeElement?.tagName==='INPUT')return;
    if(e.code==='KeyF'){film.uniforms.filterMode.value=(film.uniforms.filterMode.value+1)%4;return;}
    if(e.code==='KeyE'&&active)interactAction();
  };
  window.addEventListener('mouseup',releaseDrag);window.addEventListener('mouseup',releaseThrow);window.addEventListener('wheel',wheel,{passive:false});window.addEventListener('contextmenu',noContext);window.addEventListener('keydown',interactKey);
  const causticKey=(e:KeyboardEvent)=>{if(e.code==='Escape'&&document.pointerLockElement)document.exitPointerLock();if(e.code==='KeyC'&&!e.repeat&&document.activeElement?.tagName!=='INPUT'){caustics=!caustics;waterSystem.causticUniforms.causticGain.value=caustics?1.5:0;}};
  window.addEventListener('mousedown',strike);window.addEventListener('keydown',causticKey);
  // ---- Mobile touch layer: virtual stick + look/tpad + action pads ----
  const touchLook={x:0,y:0};
  let touchUI:HTMLDivElement|null=null;
  const touchCleanups:(()=>void)[]=[];
  if(touch){
    touchUI=document.createElement('div');
    touchUI.className='vct-touch';
    touchUI.style.display='none';
    touchUI.innerHTML='<div class="vct-touch-look"></div><div class="vct-touch-stick"><span></span></div><div class="vct-touch-pad" data-role="jump">跳</div><div class="vct-touch-pad" data-role="interact">拿起</div><div class="vct-touch-pad" data-role="throw">投掷</div><div class="vct-touch-menu">☰</div>';
    host.appendChild(touchUI);
    const stick=touchUI.querySelector<HTMLElement>('.vct-touch-stick')!;
    const dot=stick.querySelector('span')!;
    const look=touchUI.querySelector<HTMLElement>('.vct-touch-look')!;
    const on=(el:HTMLElement,ev:string,fn:(e:Event)=>void)=>{el.addEventListener(ev,fn,{passive:false});touchCleanups.push(()=>el.removeEventListener(ev,fn));};
    let stickId=-1;const center={x:0,y:0};
    const moveStick=(t:Touch)=>{const dx=(t.clientX-center.x)/52,dy=(t.clientY-center.y)/52,len=Math.hypot(dx,dy),s=len>1?1/len:1,x=dx*s,y=dy*s;stickToKeys(x,y,keys);dot.style.transform=`translate(${x*40}px,${y*40}px)`;};
    on(stick,'touchstart',e=>{e.preventDefault();const t=(e as TouchEvent).changedTouches[0];stickId=t.identifier;const r=stick.getBoundingClientRect();center.x=r.left+r.width/2;center.y=r.top+r.height/2;moveStick(t);});
    on(stick,'touchmove',e=>{e.preventDefault();for(const t of (e as TouchEvent).changedTouches)if(t.identifier===stickId)moveStick(t);});
    const endStick=()=>{stickId=-1;stickToKeys(0,0,keys);dot.style.transform='';};
    on(stick,'touchend',endStick);on(stick,'touchcancel',endStick);
    let lookId=-1;const last={x:0,y:0},start={x:0,y:0};let startT=0;
    on(look,'touchstart',e=>{e.preventDefault();const t=(e as TouchEvent).changedTouches[0];lookId=t.identifier;last.x=start.x=t.clientX;last.y=start.y=t.clientY;startT=performance.now();});
    on(look,'touchmove',e=>{e.preventDefault();for(const t of (e as TouchEvent).changedTouches)if(t.identifier===lookId){touchLook.x+=(t.clientX-last.x)*.0042;touchLook.y+=(t.clientY-last.y)*.0042;last.x=t.clientX;last.y=t.clientY;}});
    const endLook=(e:Event)=>{for(const t of (e as TouchEvent).changedTouches)if(t.identifier===lookId){lookId=-1;if(active&&performance.now()-startT<300&&Math.hypot(t.clientX-start.x,t.clientY-start.y)<12)tapAction();}};
    on(look,'touchend',endLook);on(look,'touchcancel',endLook);
    const pad=(role:string,down:()=>void,up:()=>void)=>{const el=touchUI!.querySelector<HTMLElement>(`[data-role="${role}"]`)!;on(el,'touchstart',e=>{e.preventDefault();down();});on(el,'touchend',up);on(el,'touchcancel',up);};
    pad('jump',()=>keys.add('Space'),()=>keys.delete('Space'));
    pad('interact',()=>{if(active)interactAction();},()=>{});
    pad('throw',()=>{if(active&&props.held&&!charging){charging=true;chargeStart=performance.now();}},()=>{if(charging){charging=false;dragging=false;if(props.held&&active){const charge=T.MathUtils.clamp((performance.now()-chargeStart)/1100,0,1);props.release(camera,6+charge*11);}}});
    const pauseTouch=()=>{active=false;keys.clear();stickToKeys(0,0,keys);releaseDrag();charging=false;touchUI!.style.display='none';};
    on(touchUI.querySelector<HTMLElement>('.vct-touch-menu')!,'touchstart',e=>{e.preventDefault();pauseTouch();});
  }
  const keydown=(e:KeyboardEvent)=>{if(['KeyW','KeyA','KeyS','KeyD','ShiftLeft','Space','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','KeyV','KeyR'].includes(e.code)&&document.activeElement?.tagName!=='INPUT'){e.preventDefault();keys.add(e.code);if(e.code==='KeyV'&&!e.repeat){vct=!vct;field.uniforms.vctStrength.value=vct?1.8:0;}if(e.code==='KeyR'){props.release();charging=false;player.climbing=null;player.vertical=0;camera.position.set(10-originX*ROOM,1.5,12-originZ*ROOM);stream();camera.lookAt(-4,1.9,-10);}}};
  const keyup=(e:KeyboardEvent)=>keys.delete(e.code);
  const mouse=(e:MouseEvent)=>{if(document.pointerLockElement===renderer.domElement){camera.rotation.y-=e.movementX*.0017;camera.rotation.x=T.MathUtils.clamp(camera.rotation.x-e.movementY*.0017,-1.3,1.3);}};
  const lock=()=>{active=document.pointerLockElement===renderer.domElement;keys.clear();if(!active){releaseDrag();charging=false;}};
  const blur=()=>{keys.clear();};
  window.addEventListener('keydown',keydown);window.addEventListener('keyup',keyup);window.addEventListener('mousemove',mouse);window.addEventListener('blur',blur);document.addEventListener('pointerlockchange',lock);
  const resize=()=>{camera.aspect=host.clientWidth/host.clientHeight;camera.updateProjectionMatrix();renderer.setSize(host.clientWidth,host.clientHeight);composer.setSize(host.clientWidth,host.clientHeight);};window.addEventListener('resize',resize);
  renderer.setAnimationLoop(()=>{
    if(disposed)return;const now=performance.now(),dt=Math.min((now-last)/1000,.2);elapsed+=(now-last)/1000;last=now;time+=dt;frames++;
    if(active){const beforeMove=camera.position.clone();player.update(dt,camera,keys,allColliders);
      const travelled=Math.hypot(camera.position.x-beforeMove.x,camera.position.z-beforeMove.z);
      const wading=travelled>.0001&&camera.position.y<1.7&&Math.abs(player.vertical)<1&&!player.climbing;
      if(wading){stepDistance+=travelled;const power=keys.has('ShiftLeft')?.095:.055;
        audio.updateWading(power,.55*dt/travelled,stepDistance/.55);
        if(stepDistance>.55){waterSystem.impact(camera.position.x,camera.position.z,power);stepDistance%=.55;}
      }else if(travelled>.0001&&player.grounded&&Math.abs(player.vertical)<1&&!player.climbing){
        audio.stopWading();
        // Dry ground: hard-soled steps land every stride; sprinting swaps in the
        // heel clip and lengthens the stride with the speed.
        stepDistance+=travelled;const stride=keys.has('ShiftLeft')?1.05:.62;
        if(stepDistance>stride){stepDistance%=stride;audio.stepDry(keys.has('ShiftLeft'));}
      }else{stepDistance=0;audio.stopWading();}
      if(keys.has('ArrowLeft'))camera.rotation.y+=dt;if(keys.has('ArrowRight'))camera.rotation.y-=dt;
    }
    if(touch&&(touchLook.x||touchLook.y)){camera.rotation.y-=touchLook.x;camera.rotation.x=T.MathUtils.clamp(camera.rotation.x-touchLook.y,-1.3,1.3);touchLook.x=touchLook.y=0;}
    stream();water.material.uniforms.time.value=time*.38;
    // Budgeted steps for a pending room transition, ahead of this frame's render.
    // The slice scales with the measured frame time (clamped) so slow machines finish
    // the transition in bounded wall-clock time while fast ones barely notice it.
    if(transition){
      const budget=T.MathUtils.clamp(dt*350,8,24);
      if(!transition.bvhDone)transition.bvhDone=rt.rebuild(collectRtItems(),[...chunks.values()].flatMap(c=>c.lamps));
      else if(!transition.radianceDone)transition.radianceDone=field.stepRadiance(budget);
      else if(!transition.occlusionDone)transition.occlusionDone=waterSystem.stepOcclusion(budget*.5);
    }
    audio.setActive(active&&!document.hidden);
    // Surviving tubes in decayed rooms flicker like failing ballasts: a fast
    // buzz plus slow, occasional deep dropouts; the glass dims in sync.
    for(const c of chunks.values())for(const f of c.flickers){
      const buzz=.9+.08*Math.sin(time*47+f.seed*9)+.04*Math.sin(time*97+f.seed*3);
      const drop=Math.sin(time*.9+f.seed)>1.55-f.amp*.75?.12+.25*Math.abs(Math.sin(time*29+f.seed)):1;
      const v=buzz*drop;
      f.light.intensity=f.base*v;
      f.glow.color.setRGB(3.4*v,3.6*v,3.5*v);
    }
    roomLights.update();
    // Global mood eases toward the current room's decay: denser fog, darker water.
    const mood=Math.min(1,dt*.6),fog=scene.fog as T.FogExp2|null;
    if(fog)fog.density+=(CORRUPT_FOG[currentCorrupt]-fog.density)*mood;
    (scene.background as T.Color).lerp(CORRUPT_BG[currentCorrupt],mood);
    // Tyndall shafts follow the room: lit only under clerestories that have
    // not gone dark, easing in and out as the player crosses doorways.
    const roomNow=roomLayout(cx,cz,seed);
    const shafts=(roomNow.variant===3||roomNow.variant===5||roomNow.variant===6)&&currentCorrupt<2?1:0;
    tyndallLevel+=(shafts-tyndallLevel)*Math.min(1,dt*1.4);
    tyndall.enabled=tyndallLevel>.004;
    if(tyndall.enabled){
      tyndall.uniforms.intensity.value=.05*tyndallLevel;
      tyndall.uniforms.lightPos.value.set(0,(roomNow.variant===3?14:9.2)+1,0);
      tyndall.uniforms.camPos.value.copy(camera.position);
      tyndall.uniforms.camMat.value.copy(camera.matrixWorld);
      tyndall.uniforms.viewMat.value.copy(camera.matrixWorldInverse);
      tyndall.uniforms.proj.value.copy(camera.projectionMatrix);
      tyndall.uniforms.projInv.value.copy(camera.projectionMatrixInverse);
      tyndall.uniforms.time.value=time;
    }
    props.update(dt,camera,allColliders,time,active);
    waterSystem.render(renderer,time);
    field.uniforms.poolTime.value=time;film.uniforms.time.value=time;composer.render();
    if(transition&&transition.occlusionDone){
      if(transition.probeFace<6)captureProbeFace(transition.probeFace++);
      else{finishTransition();transition=null;}
    }
    const charge=chargeNow();
    if(elapsed>.35||(charge>0&&elapsed>.06)){fps=Math.round(frames/elapsed);frames=0;elapsed=0;const aimed=props.pick(camera,allColliders);const ladder=player.nearest(camera,allLadders);const hint=charge>0?(touch?`蓄力 ${'▮'.repeat(1+Math.round(charge*7)).padEnd(8,'▯')} ${Math.round(charge*100)}% · 松开投出`:`右键蓄力 ${'▮'.repeat(1+Math.round(charge*7)).padEnd(8,'▯')} ${Math.round(charge*100)}% · 松开投出`):props.held?(touch?'按住「投掷」蓄力 · 「拿起」放下':'右键按住蓄力投掷 · 滚轮调整距离 · E 放下'):player.climbing?(touch?'摇杆上/下攀爬 · 「拿起」松开':'W / S 攀爬 · E 松开'):aimed?`${aimed.name} · ${touch?'轻点屏幕拿起':'左键拖动 / E 拿起'}`:ladder?(touch?'靠近梯子按「拿起」攀爬':'E 攀爬梯子'):(touch?'轻点水面泛起涟漪':'低头点击水面 · F 切换镜头');report({x:cx,z:cz,rooms:chunks.size,discovered:visited.size,fps,vct,impacts:waterSystem.interactionCount,caustics,hint,filter:film.uniforms.filterMode.value,held:props.held?.name??'',throws:props.throws,grabs:props.grabs,height:camera.position.y,climbing:!!player.climbing,slides:player.slides,charge,paused:!active,corrupt:currentCorrupt});}
  });
  return {
    visitRoom:(x:number,z:number)=>{
      keys.clear();player.climbing=null;player.vertical=0;
      camera.position.set((x-originX)*ROOM,1.5,(z-originZ)*ROOM+11);
      stream();camera.lookAt(0,3,-8);
    },
    setSound:(enabled:boolean)=>audio.setEnabled(enabled),
    setMusic:(enabled:boolean)=>audio.setMusic(enabled),
    enter:()=>{audio.unlock();if(touch){active=true;keys.clear();if(touchUI)touchUI.style.display='';}else renderer.domElement.requestPointerLock();},
    cycleFilter:()=>{film.uniforms.filterMode.value=(film.uniforms.filterMode.value+1)%4;},
    // Local automated physics/visual acceptance only; never exposed by production UI.
    qa:process.env.NODE_ENV!=='production'?{
      inspect:()=>({room:[cx,cz],variant:roomLayout(cx,cz,seed).variant,programs:renderer.info.programs?.length,waterVisible:water.visible,vertical:player.vertical,grounded:player.grounded,impacts:waterSystem.interactionCount,audio:audio.inspect(),position:camera.position.toArray(),time,held:props.held?.name??'',charge:chargeNow(),grabs:props.grabs,throws:props.throws,climbing:!!player.climbing,slides:player.slides,filter:film.uniforms.filterMode.value,environment:!!scene.environment,transition:!!transition,vctReady:field.uniforms.vctReady.value>0,blocks:waterSystem.uniforms.blockCount.value,props:props.bodies.filter(b=>b.position.distanceTo(camera.position)<15).map(b=>({name:b.name,kind:b.kind,position:b.position.toArray(),velocity:b.velocity.toArray(),promoted:b.promoted})),ladders:allLadders.filter(l=>l.base.distanceTo(camera.position)<30).map(l=>({base:l.base.toArray(),top:l.top.toArray(),exit:l.exit.toArray()}))}),
      view:(position:number[],target:number[])=>{player.climbing=null;player.vertical=0;const ox=originX,oz=originZ;camera.position.fromArray(position);stream();camera.lookAt(new T.Vector3(target[0]-(originX-ox)*ROOM,target[1],target[2]-(originZ-oz)*ROOM));},
      simulate:(enabled:boolean)=>{active=enabled;keys.clear();},
      placeProp:(kind:PropKind,position:number[])=>{const body=props.bodies.find(b=>b.kind===kind);if(body){props.grab(body);props.release();body.position.fromArray(position);body.rotation.identity();}},
      water:(x:number,z:number,power:number)=>splash(x,z,power),
      grab:(index=0)=>{const near=props.bodies.filter(b=>b.position.distanceTo(camera.position)<15);if(near[index])props.grab(near[index]);},
      throw:(speed=11)=>{if(props.held)props.release(camera,speed);},
    }:undefined,
    dispose:()=>{disposed=true;audio.dispose();renderer.setAnimationLoop(null);if(document.pointerLockElement===renderer.domElement)document.exitPointerLock();window.removeEventListener('keydown',keydown);window.removeEventListener('keyup',keyup);window.removeEventListener('mousemove',mouse);window.removeEventListener('blur',blur);document.removeEventListener('pointerlockchange',lock);window.removeEventListener('resize',resize);environment?.dispose();probeTarget.dispose();pmrem.dispose();rt.dispose();rtProxy.dispose();window.removeEventListener('mouseup',releaseDrag);window.removeEventListener('mouseup',releaseThrow);window.removeEventListener('wheel',wheel);window.removeEventListener('contextmenu',noContext);window.removeEventListener('keydown',interactKey);waterSystem.dispose();window.removeEventListener('mousedown',strike);window.removeEventListener('keydown',causticKey);field.dispose();scene.traverse(o=>{if(o instanceof T.Mesh)o.geometry.dispose();if(o instanceof T.InstancedMesh)o.dispose();if(o instanceof T.PointLight)o.dispose();});for(const m of materials)m.dispose();for(const t of textures)t.dispose();ballGeometry.dispose();roomLights.dispose();reflectionTarget?.dispose();water.material.dispose();for(const p of composer.passes)p.dispose();composer.dispose();renderer.dispose();renderer.domElement.remove();for(const fn of touchCleanups)fn();touchUI?.remove();},
  };
}
