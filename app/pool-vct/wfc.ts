// 房间内部的波函数坍缩（WFC）。三种瓦片：E 空水、P 柱、S 平台岛。
// 邻接约束：柱子互不相邻也不贴平台；平台相连成岛；空水与一切相容。
// 门洞走廊（每边中央 8m、内伸两格）预先坍缩为空水，四个入口永远可走。
// 求解只消费传入的 rand 序列——同一 (x,z,seed) 得到同一张图，流式
// 重生成与确定性测试不受影响。这组约束下传播不会掏空任何定义域
// （每个允许掩码都包含空水），重试只是保险，全空水兜底实际不可达。

export type WfcTile='E'|'P'|'S';
export const WFC_SIZE=12;
export const WFC_CELL=2.2;

const ALLOW:Record<WfcTile,number>={E:0b111,P:0b001,S:0b101};
const BITS=[1,2,4] as const;
const TILE:Record<number,WfcTile>={1:'E',2:'P',4:'S'};
const pop=(m:number)=>(m&1)+((m>>1)&1)+((m>>2)&1);

/** 门洞走廊格：四条边中央 8m 开口向内两格，求解前固定为空水。 */
export function doorwayCells(size=WFC_SIZE):[number,number][] {
  const cells:[number,number][]=[];
  const along=(i:number)=>Math.abs((i-(size-1)/2)*WFC_CELL)<=4.4;
  const ring=[0,1,size-2,size-1];
  // ±z 墙的门：j 贴边、i 落在开口范围内；±x 墙对称。两组互不重叠。
  for(const j of ring)for(let i=0;i<size;i++)if(along(i))cells.push([i,j]);
  for(const i of ring)for(let j=0;j<size;j++)if(along(j))cells.push([i,j]);
  return cells;
}

export function collapseInterior(rand:()=>number,size=WFC_SIZE,pillarBoost=1):WfcTile[][] {
  for(let attempt=0;attempt<8;attempt++){const grid=solve(rand,size,pillarBoost);if(grid)return grid;}
  return Array.from({length:size},()=>Array.from({length:size},()=>'E' as WfcTile));
}

function solve(rand:()=>number,size:number,pillarBoost:number):WfcTile[][]|null {
  const n=size*size,domains=new Uint8Array(n).fill(0b111),assigned=new Uint8Array(n);
  // 崩坏房间把柱子权重抬高（pillarBoost>1），坍缩出更密的柱阵；
  // 邻接约束不变，柱子依然互不相邻。
  const weight:Record<WfcTile,number>={E:6,P:1*pillarBoost,S:2.6};
  const neighbours=(i:number)=>{const x=i%size,y=(i/size)|0,out:number[]=[];if(x>0)out.push(i-1);if(x<size-1)out.push(i+1);if(y>0)out.push(i-size);if(y<size-1)out.push(i+size);return out;};
  // AC-3 风格约束传播：邻居只保留与当前格「某个可能值」相容的瓦片。
  const propagate=(from:number):boolean=>{
    const queue=[from];
    while(queue.length){
      const i=queue.pop()!;
      let allowed=0;for(const b of BITS)if(domains[i]&b)allowed|=ALLOW[TILE[b]];
      for(const nb of neighbours(i)){
        const next=domains[nb]&allowed;
        if(next===domains[nb])continue;
        if(next===0)return false;
        domains[nb]=next;queue.push(nb);
      }
    }
    return true;
  };
  const collapse=(i:number,bit:number)=>{domains[i]=bit;assigned[i]=bit;return propagate(i);};
  const doors=doorwayCells(size);
  for(const [i,j] of doors)if(!collapse(j*size+i,1))return null;
  let remaining=n-doors.length;
  while(remaining>0){
    // 熵最低者优先坍缩；平手中随机挑，避免坍缩波永远从左上角出发。
    let best=4;const ties:number[]=[];
    for(let i=0;i<n;i++){if(assigned[i])continue;const count=pop(domains[i]);if(count<best){best=count;ties.length=0;}if(count===best)ties.push(i);}
    if(!ties.length)return null;
    const i=ties[Math.floor(rand()*ties.length)];
    // 加权随机选瓦片；只剩一个选项时不消耗随机数。
    let bit=domains[i];
    if(pop(bit)>1){
      let total=0;for(const b of BITS)if(bit&b)total+=weight[TILE[b]];
      let r=rand()*total;bit=0;
      for(const b of BITS){if(!(domains[i]&b))continue;bit=b;r-=weight[TILE[b]];if(r<=0)break;}
    }
    if(!collapse(i,bit))return null;
    remaining--;
  }
  return Array.from({length:size},(_,y)=>Array.from({length:size},(_,x)=>TILE[assigned[y*size+x]]));
}
