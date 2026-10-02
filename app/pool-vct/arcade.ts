import * as T from 'three';
import type { Solid } from './world';

export const ARCADE_FLOOR=-.72;
export const ARCADE_CEILING=4.6;
const CENTRES=[-10.6,0,10.6];
const RADIUS=4.05,SPRING=2.35,RISE=1.4,DEPTH=1.15;

/** A continuous wall above three elliptical openings, including their reveals. */
export function createArcadeGeometry(){
  const shape=new T.Shape();shape.moveTo(-16,ARCADE_FLOOR);
  for(const centre of CENTRES){
    shape.lineTo(centre-RADIUS,ARCADE_FLOOR);shape.lineTo(centre-RADIUS,SPRING);
    for(let i=1;i<=48;i++){
      const angle=Math.PI*(1-i/48);
      shape.lineTo(centre+Math.cos(angle)*RADIUS,SPRING+Math.sin(angle)*RISE);
    }
    shape.lineTo(centre+RADIUS,ARCADE_FLOOR);
  }
  shape.lineTo(16,ARCADE_FLOOR);shape.lineTo(16,ARCADE_CEILING);
  shape.lineTo(-16,ARCADE_CEILING);shape.closePath();
  return new T.ExtrudeGeometry(shape,{depth:DEPTH,bevelEnabled:false,curveSegments:48});
}

/** Voxel/collision proxies follow each opening; the water can flow through it. */
export function arcadeSolids(x:number,z:number,color:T.Color):Solid[]{
  const rectangles:[number,number,number,number][]=[];
  let edge=-16;
  for(const centre of CENTRES){
    rectangles.push([edge,centre-RADIUS,ARCADE_FLOOR,ARCADE_CEILING]);
    // GI voxels are 75 cm wide; finer proxy slices only duplicate occupancy.
    for(let i=0;i<12;i++){
      const left=centre-RADIUS+i*RADIUS/6,right=left+RADIUS/6;
      const u=((left+right)/2-centre)/RADIUS;
      rectangles.push([left,right,SPRING+RISE*Math.sqrt(Math.max(0,1-u*u)),ARCADE_CEILING]);
    }
    edge=centre+RADIUS;
  }
  rectangles.push([edge,16,ARCADE_FLOOR,ARCADE_CEILING]);
  return rectangles.map(([a,b,lo,hi])=>({
    min:new T.Vector3(x+a,lo,z),
    max:new T.Vector3(x+b,hi,z+DEPTH),color,
  }));
}
