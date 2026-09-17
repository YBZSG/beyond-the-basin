import * as T from 'three';

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
   * only rebuilt when something they depend on changes:
   *
   *  - a slot was handed a different source light (lights are stationary
   *    fixtures, so the same source in the same slot means it has not moved);
   *  - a dynamic shadow caster moved (props, beach balls and the egg-boy all
   *    cast shadows and are driven by physics every frame).
   *
   * `invalidate()` is the escape hatch for the second case; the engine calls it
   * when any physics prop within shadow range has actually moved. Rebuilding on
   * *any* propagation would defeat the cache, so callers should only report a
   * real displacement.
   */
  private dirty=true;
  constructor(scene:T.Scene){scene.add(...this.lights);}
  /** Force every shadow slot to rebuild on the next shadow pass. */
  invalidate(){this.dirty=true;}
  select(current:T.PointLight[],others:T.PointLight[]){this.current=current;this.others=others;this.tubes=current.filter(l=>l.distance===36);this.update(this.focus,this.dir);}
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
      if(this.shadowSources[i]!==this.sources[i]){this.dirty=true;break;}
    }
    if(this.dirty){
      this.dirty=false;
      for(let i=0;i<shadowCount;i++){
        this.shadowSources[i]=this.sources[i];
        // Invalidate the slot's cube map so the next shadow pass rebuilds it.
        this.lights[i].shadow.needsUpdate=true;
      }
    }
    this.lights.forEach((light,i)=>{
      const source=this.sources[i];
      light.intensity=source?.intensity??0;
      if(source){light.position.copy(source.position);light.color.copy(source.color);light.distance=source.distance;light.decay=source.decay;}
      else light.position.set(0,7,0);
    });
  }
  dispose(){for(const light of this.lights){light.removeFromParent();light.dispose();}}
}
