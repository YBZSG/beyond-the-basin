import * as T from 'three';

// Nine resident rooms, each with two tubes and at most one exit lamp. Keeping
// both counts fixed avoids recompiling every lit material when crossing rooms.
// Four lights cast shadows: the current room's tubes at full resolution plus
// two next-door slots that follow the view, so the room the player looks into
// keeps its shadows.
export class RoomLights {
  readonly lights=Array.from({length:27},(_,i)=>{
    const light=new T.PointLight(0xffffff,0,36,2);
    light.castShadow=i<4;
    if(light.castShadow){
      light.shadow.mapSize.set(i<2?2048:1024,i<2?2048:1024);
      light.shadow.camera.near=.3;light.shadow.camera.far=36;
      light.shadow.bias=-.00003;light.shadow.normalBias=.025;
      light.shadow.radius=2;
    }
    return light;
  });
  private current:T.PointLight[]=[];private others:T.PointLight[]=[];private tubes:T.PointLight[]=[];
  private sources:(T.PointLight|undefined)[]=[];
  private focus=new T.Vector3();private dir=new T.Vector3(0,0,-1);private tmp=new T.Vector3();
  constructor(scene:T.Scene){scene.add(...this.lights);}
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
    this.lights.forEach((light,i)=>{
      const source=this.sources[i];
      light.intensity=source?.intensity??0;
      if(source){light.position.copy(source.position);light.color.copy(source.color);light.distance=source.distance;light.decay=source.decay;}
      else light.position.set(0,7,0);
    });
  }
  dispose(){for(const light of this.lights){light.removeFromParent();light.dispose();}}
}
