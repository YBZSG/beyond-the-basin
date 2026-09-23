import * as T from 'three';
import type { MovedShadowCaster } from './physics';

// Nine resident rooms, each with two tubes and at most one exit lamp. Keeping
// both counts fixed avoids recompiling every lit material when crossing rooms.
// Four lights cast shadows: the current room's tubes plus two next-door slots
// that follow the view, so the room the player looks into keeps its shadows.
//
// Shadow resolution is deliberately modest. A point light's shadow is a CUBE
// map - 6 faces - so the per-frame rasterization is mapSize^2 * 6 * slots. At
// 2048 for the two nearest slots that was 62.9 Mpx per pass, ~30x the main
// canvas and ~47x the refraction capture, and it landed on whichever stage
// happened to be the frame's shadow producer (the capture). 1024 across all
// four slots is 25.2 Mpx (-60%) and the difference is invisible at this range:
// the light's reach is 36m, so a 1024 face already gives ~3.5cm per texel.
const SHADOW_MAP_SIZE = 1024;
export class RoomLights {
  readonly lights=Array.from({length:27},(_,i)=>{
    const light=new T.PointLight(0xffffff,0,36,2);
    light.castShadow=i<4;
    if(light.castShadow){
      light.shadow.mapSize.set(SHADOW_MAP_SIZE,SHADOW_MAP_SIZE);
      light.shadow.camera.near=.3;light.shadow.camera.far=36;
      light.shadow.bias=-.00003;light.shadow.normalBias=.025;
      light.shadow.radius=2;
      light.shadow.autoUpdate=false;
    }
    return light;
  });
  private current:T.PointLight[]=[];private others:T.PointLight[]=[];private tubes:T.PointLight[]=[];
  private sources:(T.PointLight|undefined)[]=[];
  private focus=new T.Vector3();private dir=new T.Vector3(0,0,-1);private tmp=new T.Vector3();
  /** The source mapped into each shadow slot last update, to detect reassignment. */
  private shadowSources:(T.PointLight|undefined)[]=[];
  /**
   * Shadow cube maps are cached between updates (`shadow.autoUpdate=false`) and
   * only rebuilt when something the slot depends on changes:
   *
   *  - a slot was handed a different source light (lights are stationary
   *    fixtures, so the same source in the same slot means it has not moved);
   *  - a dynamic shadow caster that can actually reach that slot's light moved
   *    (props and beach balls cast shadows and are driven by
   *    physics every frame).
   *
   * Invalidation is tracked PER SLOT: a duck bobbing next to one tube must not
   * re-rasterize the 24 cube faces of the other three shadow lights.
   * `invalidate()` remains the rebuild-everything escape hatch (room
   * transitions, quality changes); `invalidateBodies()` is the precise path
   * the engine feeds with the props that actually moved.
   */
  private shadowDirty=[true,true,true,true];
  constructor(scene:T.Scene){scene.add(...this.lights);}
  /** Force every shadow slot to rebuild on the next shadow pass. */
  invalidate(){for(let i=0;i<4;i++)this.shadowDirty[i]=true;}
  select(current:T.PointLight[],others:T.PointLight[]){this.current=current;this.others=others;this.tubes=current.filter(l=>l.distance===36);this.update(this.focus,this.dir);}
  /**
   * Invalidate only the shadow slots a moved caster can influence. A light at
   * 36m reach sees the caster if the caster's bounding sphere intersects the
   * light sphere either before OR after the move, so a prop crossing the range
   * edge is caught in both directions.
   */
  invalidateBodies(moved:readonly MovedShadowCaster[]){
    if(!moved.length)return;
    for(let i=0;i<4;i++){
      if(!this.shadowDirty[i]){
        const light=this.lights[i];
        for(const caster of moved){
          if(this.affectsLight(caster,light)){this.shadowDirty[i]=true;break;}
        }
      }
    }
  }
  /** Whether the caster's swept volume overlaps the light's reach. */
  private affectsLight(caster:MovedShadowCaster,light:T.PointLight){
    const range=light.distance+caster.radius,rangeSq=range*range;
    const lightX=light.position.x,lightY=light.position.y,lightZ=light.position.z;
    const oldDx=caster.previous.x-lightX,oldDy=caster.previous.y-lightY,oldDz=caster.previous.z-lightZ;
    if(oldDx*oldDx+oldDy*oldDy+oldDz*oldDz<=rangeSq)return true;
    const newDx=caster.current.x-lightX,newDy=caster.current.y-lightY,newDz=caster.current.z-lightZ;
    return newDx*newDx+newDy*newDy+newDz*newDz<=rangeSq;
  }
  update(focus:T.Vector3,direction:T.Vector3){
    this.focus.copy(focus);this.dir.copy(direction).normalize();
    // Rank by how directly a light sits in the view, penalising lights behind
    // the camera: shadows follow where the player is actually looking, not
    // just the nearest room.
    const score=(l:T.PointLight)=>{
      this.tmp.copy(l.position).sub(this.focus);
      const along=this.tmp.dot(this.dir);
      return this.tmp.lengthSq()-along*along+(along<0?2500:0);
    };
    const rest=[...this.current.filter(l=>l.distance!==36),...this.others].sort((a,b)=>score(a)-score(b));
    this.sources=[...this.tubes,...rest];
    // A slot that keeps the same source light has not moved, so its cube map is
    // still valid. Re-ranking shuffles lights between slots as the view turns,
    // which is exactly what used to re-rasterize everything on every frame.
    const shadowCount=this.lights[0]?.castShadow?4:0;
    for(let i=0;i<shadowCount;i++){
      if(this.shadowSources[i]!==this.sources[i])this.shadowDirty[i]=true;
    }
    let updated=0;
    for(let i=0;i<shadowCount;i++){
      if(!this.shadowDirty[i])continue;
      this.shadowSources[i]=this.sources[i];
      // Invalidate the slot's cube map so the next shadow pass rebuilds it.
      this.lights[i].shadow.needsUpdate=true;
      this.shadowDirty[i]=false;updated++;
    }
    this.lastShadowUpdates=updated;
    this.lights.forEach((light,i)=>{
      const source=this.sources[i];
      light.intensity=source?.intensity??0;
      if(source){light.position.copy(source.position);light.color.copy(source.color);light.distance=source.distance;light.decay=source.decay;}
      else light.position.set(0,7,0);
    });
  }
  /** How many shadow slots asked for a rebuild in the last update (0..4). */
  get shadowSlotsUpdated(){return this.lastShadowUpdates;}
  private lastShadowUpdates=0;
  dispose(){for(const light of this.lights){light.removeFromParent();light.dispose();}}
}
