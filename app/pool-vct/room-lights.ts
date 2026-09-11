import * as T from 'three';

// Nine resident rooms, each with two tubes and at most one exit lamp. Keeping
// both counts fixed avoids recompiling every lit material when crossing rooms.
export class RoomLights {
  readonly lights=Array.from({length:27},(_,i)=>{
    const light=new T.PointLight(0xffffff,0,36,2);
    light.castShadow=i<2;
    if(light.castShadow){
      light.shadow.mapSize.set(2048,2048);
      light.shadow.camera.near=.3;light.shadow.camera.far=36;
      light.shadow.bias=-.00003;light.shadow.normalBias=.025;
      light.shadow.radius=2;
    }
    return light;
  });
  private sources:(T.PointLight|undefined)[]=[];
  constructor(scene:T.Scene){scene.add(...this.lights);}
  select(current:T.PointLight[],others:T.PointLight[]){
    const tubes=current.filter(l=>l.distance===36);
    this.sources=[tubes[0],tubes[1],...current.filter(l=>l.distance!==36),...others];
    this.update();
  }
  update(){
    this.lights.forEach((light,i)=>{
      const source=this.sources[i];
      light.intensity=source?.intensity??0;
      if(source){light.position.copy(source.position);light.color.copy(source.color);light.distance=source.distance;light.decay=source.decay;}
      else light.position.set(0,7,0);
    });
  }
  dispose(){for(const light of this.lights){light.removeFromParent();light.dispose();}}
}
