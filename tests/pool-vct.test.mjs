import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { randomFor, roomLayout, blocked, VoxelField, corruptionLevel } from '../app/pool-vct/world.ts';
import { rayBlocked, InteractiveWater } from '../app/pool-vct/water-system.ts';
import { stickToKeys } from '../app/pool-vct/touch.ts';
import { PropPhysics } from '../app/pool-vct/physics.ts';
import { collapseInterior, doorwayCells, WFC_SIZE } from '../app/pool-vct/wfc.ts';

test('floor and wall caustics retrace while the shallow-water field moves, then settle into a cache',()=>{
  const water=new InteractiveWater();let draws=0,target=null;
  water.applySettings({microStrength:0,environmentalStrength:0});
  const renderer={getRenderTarget:()=>target,setRenderTarget:t=>{target=t;},
    getClearColor:c=>c.set(0),getClearAlpha:()=>1,setClearColor:()=>{},clear:()=>{},render:()=>{draws++;}};
  water.render(renderer,0);const boot=draws;
  assert.ok(boot>=6); // initial flatten pass plus the six caustics draws
  water.render(renderer,.008);assert.equal(draws,boot); // settled: no redraws
  water.impact(0,0,.1);
  let moving=0;
  for(let i=1;i<=3;i++){const before=draws;water.render(renderer,i*.008);if(draws>before)moving++;}
  assert.ok(moving>0);
  // Let the simulation settle using its own elapsed-time clock.
  for(let i=1;i<=24*30;i++)water.render(renderer,.024+i/30);
  const settled=draws;water.render(renderer,25);assert.equal(draws,settled);assert.equal(target,null);
  assert.equal(water.heightAt(.4,0),0); // the flattened pool reads exactly level
  water.dispose();
});

test('virtual stick maps analog input onto the desktop key set',()=>{
  const keys=new Set(['Space']);
  stickToKeys(0,0,keys);assert.deepEqual([...keys],['Space']);
  stickToKeys(.5,0,keys);assert.deepEqual([...keys].sort(),['KeyD','Space']);
  stickToKeys(-.5,-.5,keys);assert.ok(keys.has('KeyA')&&keys.has('KeyW')&&!keys.has('ShiftLeft'));
  stickToKeys(0,.95,keys);assert.ok(keys.has('KeyS')&&keys.has('ShiftLeft'));
  stickToKeys(0,0,keys);assert.ok(!keys.has('KeyS')&&!keys.has('ShiftLeft')&&!keys.has('KeyW')&&!keys.has('KeyA')&&!keys.has('KeyD'));
});

test('positive and negative chunks regenerate deterministically',()=>{
  for(const [x,z] of [[0,0],[-123,482],[100000,-100000]]){
    const a=randomFor(x,z,250821),b=randomFor(x,z,250821);
    assert.deepEqual(Array.from({length:50},a),Array.from({length:50},b));
    assert.deepEqual(roomLayout(x,z,250821),roomLayout(x,z,250821));
  }
  assert.notDeepEqual(roomLayout(4,8,1),roomLayout(4,8,2));
});
test('collision respects player radius but does not block submerged floor',()=>{
  const wall={min:new T.Vector3(0,0,0),max:new T.Vector3(1,5,1),color:new T.Color('white')};
  assert.equal(blocked(new T.Vector3(-.2,1,.5),[wall]),true);
  assert.equal(blocked(new T.Vector3(-.4,1,.5),[wall]),false);
  assert.equal(blocked(new T.Vector3(.5,1,.5),[{...wall,max:new T.Vector3(1,.1,1)}]),false);
});
test('radiance injection creates four correctly sized nonempty voxel levels',()=>{
  const field=new VoxelField();
  const floor={min:new T.Vector3(-4,-.5,-4),max:new T.Vector3(4,0,4),color:new T.Color('#8299a5')};
  field.rebuild([floor],[],0,0);
  const sum=()=>field.textures[0].image.data.reduce((s,v,i)=>s+(i%4===3?0:v),0);
  const dark=sum();
  field.rebuild([floor],[{position:new T.Vector3(0,4,0),color:new T.Color('white'),power:20}],0,0);
  assert.ok(sum()>dark);
  assert.deepEqual(field.textures.map(t=>[t.image.width,t.image.height,t.image.depth]),[[128,32,128],[64,16,64],[32,8,32],[16,4,16]]);
  for(const t of field.textures)assert.ok(t.image.data.some(v=>v>0));
  field.dispose();assert.equal(field.textures.length,0);
});
test('8×DDA shadow march catches a one-voxel-thin wall',()=>{
  const field=new VoxelField();
  const floor={min:new T.Vector3(-6,-.6,-6),max:new T.Vector3(6,0,6),color:new T.Color('#8299a5')};
  const lamp={position:new T.Vector3(0,4,0),color:new T.Color('white'),power:40};
  const lit=(x,z)=>{const t=field.textures[0].image.data;const ix=Math.floor((x+48)/.75),iy=Math.floor((0+1.5)/.75),iz=Math.floor((z+48)/.75);const i=(ix+128*(iy+32*iz))*4;return t[i]+t[i+1]+t[i+2];};
  field.rebuild([floor],[lamp],0,0);
  const bright=lit(4,0);
  // A .15m wall (one voxel when rasterised) between lamp and receiver.
  const thin={min:new T.Vector3(1.05,-.5,-6),max:new T.Vector3(1.2,4,6),color:new T.Color('#111')};
  field.rebuild([floor,thin],[lamp],0,0);
  assert.ok(lit(4,0)<bright*.6);
  field.dispose();
});
test('caustic light visibility rejects occluders but accepts parallel clear rays',()=>{
  const pillar={min:new T.Vector3(-1,1,-1),max:new T.Vector3(1,3,1),color:new T.Color('white')};
  assert.equal(rayBlocked(new T.Vector3(0,.3,0),new T.Vector3(0,7,0),[pillar]),true);
  assert.equal(rayBlocked(new T.Vector3(3,.3,0),new T.Vector3(3,7,0),[pillar]),false);
  assert.equal(rayBlocked(new T.Vector3(0,4,0),new T.Vector3(0,7,0),[pillar]),false);
});
test('splash queue preserves simultaneous events and follows floating-origin rebases',()=>{
  const water=new InteractiveWater();
  for(let i=0;i<20;i++)water.impact(i*.1,4,.1);
  assert.equal(water.interactionCount,20);
  const swe=water.swe;
  assert.equal(swe.pendingSplats.length,20*4);
  for(let i=0;i<80;i++)water.impact(i*.1,4,.1);
  assert.equal(swe.pendingSplats.length,100*4);
  const before=swe.pendingSplats.slice();
  water.rebase(new T.Vector3(32,0,-32));
  swe.pendingSplats.forEach((v,i)=>{
    if(i%4===0)assert.equal(v,before[i]-32);
    else if(i%4===1)assert.equal(v,before[i]+32);
    else assert.equal(v,before[i]);
  });
  water.dispose();
});

test('buoyancy reads the readback grid and an undisturbed pool stays flat',()=>{
  const water=new InteractiveWater();
  // The buoyancy grid starts zeroed: an undisturbed pool reads perfectly level.
  assert.equal(water.heightAt(3,-2),0);
  // Simulate a GPU readback landing: seed the physics grid the way the async
  // pixel copy would and confirm heightAt interpolates it bilinearly.
  const swe=water.swe;
  for(const row of [191,192]){swe.physicsEta[191+row*384]=.1;swe.physicsEta[192+row*384]=.3;}
  const h=water.heightAt(0,0);
  assert.ok(h>.15&&h<.25,`expected a bilinear mix, got ${h}`);
  assert.equal(water.heightAt(500,0),0);
  water.dispose();
});

test('three distinct bright rooms and a dark bath are reachable next to the original',()=>{
  for(const seed of [1,250821,999]){
    assert.equal(roomLayout(0,0,seed).variant,0);
    assert.deepEqual([[0,-1],[-1,0],[1,0]].map(([x,z])=>roomLayout(x,z,seed).variant),[3,6,5]);
    assert.equal(roomLayout(0,1,seed).variant,4);
    // 柱阵水厅固定用 WFC 变体，主菜单入口始终指向它。
    assert.equal(roomLayout(1,1,seed).variant,7);
  }
});
test('WFC interiors respect adjacency, keep doorways open and stay deterministic',()=>{
  const mulberry32=(a)=>()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};
  // Four centre cells per wall × four walls, and the two wall groups never overlap.
  const doors=doorwayCells();
  assert.equal(doors.length,32);
  assert.ok(doors.every(([i,j])=>i>=0&&j>=0&&i<WFC_SIZE&&j<WFC_SIZE));
  let pillars=0,platforms=0;
  for(const seed of [1,250821,999]){
    const grid=collapseInterior(mulberry32(seed));
    assert.equal(grid.length,WFC_SIZE);
    assert.ok(grid.every(row=>row.length===WFC_SIZE&&row.every(t=>'EPS'.includes(t))));
    for(let j=0;j<WFC_SIZE;j++)for(let i=0;i<WFC_SIZE;i++){
      if(grid[j][i]==='P')pillars++;
      if(grid[j][i]==='S')platforms++;
      // Pillars never touch pillars or platforms in the 4-neighbourhood.
      if(grid[j][i]!=='P')continue;
      for(const [di,dj] of [[1,0],[-1,0],[0,1],[0,-1]]){
        const ni=i+di,nj=j+dj;
        if(ni<0||nj<0||ni>=WFC_SIZE||nj>=WFC_SIZE)continue;
        assert.equal(grid[nj][ni],'E');
      }
    }
    // Doorway corridors stay open water so all four entrances remain walkable.
    for(const [i,j] of doors)assert.equal(grid[j][i],'E');
    // Same seed, same interior — streamed regeneration never drifts.
    assert.deepEqual(collapseInterior(mulberry32(seed)),grid);
  }
  // The solver actually places structure; it never degrades to all-empty water.
  assert.ok(pillars>0&&platforms>0);
});
test('corruption deepens with exploration distance and stays deterministic',()=>{
  // Boundaries of the Chebyshev distance bands.
  assert.deepEqual([[0,0],[1,1],[-1,2],[2,-3],[3,3],[-4,4],[6,-6],[7,0],[0,-7],[100,100]].map(([x,z])=>corruptionLevel(x,z)),[0,0,1,1,1,2,2,3,3,3]);
  // The spawn area stays pristine; the diagonal decay rooms are level 2 and 3.
  for(const seed of [1,250821,999]){
    assert.deepEqual([[0,0],[1,1],[-4,-4],[7,7]].map(([x,z])=>roomLayout(x,z,seed).corrupt),[0,0,2,3]);
    assert.deepEqual(roomLayout(5,5,seed),roomLayout(5,5,seed));
  }
});
test('pillar boost densifies WFC pillar fields without breaking adjacency',()=>{
  const mulberry32=(a)=>()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};
  const count=(grid,tile)=>grid.flat().filter(t=>t===tile).length;
  const adjacencyOk=(grid)=>{
    for(let j=0;j<WFC_SIZE;j++)for(let i=0;i<WFC_SIZE;i++){
      if(grid[j][i]!=='P')continue;
      for(const [di,dj] of [[1,0],[-1,0],[0,1],[0,-1]]){
        const ni=i+di,nj=j+dj;
        if(ni<0||nj<0||ni>=WFC_SIZE||nj>=WFC_SIZE)continue;
        if(grid[nj][ni]!=='E')return false;
      }
    }
    return true;
  };
  let normal=0,boosted=0;
  for(const s of [1,7,42,250821,999,12345,777,31415]){
    const a=collapseInterior(mulberry32(s)),b=collapseInterior(mulberry32(s),WFC_SIZE,3.2);
    normal+=count(a,'P');boosted+=count(b,'P');
    assert.ok(adjacencyOk(b));
    for(const [i,j] of doorwayCells())assert.equal(b[j][i],'E');
  }
  // A 3.2× pillar weight must land meaningfully more pillars across seeds.
  assert.ok(boosted>normal*1.5,`expected boost, got ${boosted} vs ${normal}`);
});
test('beach balls rebound higher than eggs from the same dry drop',()=>{
  // Dry room (surface far below): pure restitution comparison. Both props fall
  // from the same height onto the same floor; the vinyl ball's higher bounce
  // must lift it visibly higher after the first impact.
  const scene=new T.Scene(),camera=new T.PerspectiveCamera();camera.position.set(10,10,10);
  const mk=(kind)=>({position:new T.Vector3(0,.6,0),velocity:new T.Vector3(0,-3,0),rotation:new T.Quaternion(),radius:kind==='ball'?.21:.17,floatBias:0,name:kind,kind,visual:new T.Group(),parts:[],promoted:false,splashCooldown:0,hitCooldown:0});
  const run=(kind)=>{
    const props=new PropPhysics(scene,()=>{},()=>-100);
    props.add(mk(kind));
    const floor={center:new T.Vector3(0,-.5,0),half:new T.Vector3(8,.5,8)};
    let peak=-Infinity;
    for(let i=0;i<240;i++){props.update(1/120,camera,[floor],i/120,true);if(i>=24)peak=Math.max(peak,props.bodies[0].position.y);}
    return peak;
  };
  const egg=run('egg'),ball=run('ball');
  assert.ok(ball>egg+.08,`expected the ball to rebound higher, got ball ${ball.toFixed(3)} vs egg ${egg.toFixed(3)}`);
});
test('beach balls ride the waterline while eggs settle lower',()=>{
  const scene=new T.Scene(),camera=new T.PerspectiveCamera();camera.position.set(10,10,10);
  const settle=(kind,floatBias)=>{
    const props=new PropPhysics(scene,()=>{},()=>.32);
    props.add({position:new T.Vector3(0,1.2,0),velocity:new T.Vector3(),rotation:new T.Quaternion(),radius:kind==='ball'?.21:.17,floatBias,name:kind,kind,visual:new T.Group(),parts:[],promoted:false,splashCooldown:0,hitCooldown:0});
    for(let i=0;i<600;i++)props.update(1/30,camera,[],i/30,true);
    return props.bodies[0].position.y;
  };
  const ball=settle('ball',.05),egg=settle('egg',0);
  // Buoyancy target = surface + floatBias: the ball bobs at .37, the egg at .32.
  assert.ok(Math.abs(ball-.37)<.02,`ball settled at ${ball.toFixed(3)}`);
  assert.ok(Math.abs(egg-.32)<.02,`egg settled at ${egg.toFixed(3)}`);
});
test('budgeted voxel phases match the synchronous rebuild',()=>{
  const solids=[{min:new T.Vector3(-4,-.5,-4),max:new T.Vector3(4,0,4),color:new T.Color('#8299a5')},
    {min:new T.Vector3(-1,0,-1),max:new T.Vector3(1,3,1),color:new T.Color('#ccbbaa')}];
  const lamps=[{position:new T.Vector3(2,4,-2),color:new T.Color('white'),power:20},
    {position:new T.Vector3(-6,3,5),color:new T.Color('#a9d8ed'),power:20}];
  const sync=new VoxelField();sync.rebuild(solids,lamps,0,0);
  const phased=new VoxelField();
  phased.begin(solids,lamps,0,0);
  let guard=0;while(!phased.stepRadiance(0)&&guard++<5000);
  phased.finish();
  const sum=f=>f.textures.reduce((s,t)=>s+t.image.data.reduce((a,v,i)=>a+(i%4===3?0:v),0),0);
  assert.equal(sum(phased),sum(sync));
  assert.deepEqual(phased.textures.map(t=>[t.image.width,t.image.height,t.image.depth]),[[128,32,128],[64,16,64],[32,8,32],[16,4,16]]);
  sync.dispose();phased.dispose();
});
test('sliced caustic occlusion matches the synchronous fill and skips distant blocks',()=>{
  const solids=[{min:new T.Vector3(-1,1,-1),max:new T.Vector3(1,3,1),color:new T.Color('white')},
    {min:new T.Vector3(4,-1,4),max:new T.Vector3(6,9,6),color:new T.Color('white')}];
  const direct=new InteractiveWater();direct.rebuildOcclusion(solids);
  const sliced=new InteractiveWater();sliced.beginOcclusion(solids);
  let guard=0;while(!sliced.stepOcclusion(0)&&guard++<2000);
  for(const l of [0,1])assert.deepEqual(Array.from(sliced.masks[l].image.data),Array.from(direct.masks[l].image.data));
  const far=[...solids,{min:new T.Vector3(100,0,100),max:new T.Vector3(110,8,110),color:new T.Color('white')}];
  const distant=new InteractiveWater();distant.rebuildOcclusion(far);
  assert.deepEqual(Array.from(distant.masks[0].image.data),Array.from(direct.masks[0].image.data));
  direct.dispose();sliced.dispose();distant.dispose();
});
