import * as T from 'three';

export type Collider = { center:T.Vector3; half:T.Vector3; rotation?:T.Quaternion; radius?:number; slide?:boolean };
export type Ladder = { base:T.Vector3; top:T.Vector3; exit:T.Vector3 };
export type Contact = { normal:T.Vector3; depth:number };

export function sphereContact(p:T.Vector3,r:number,c:Collider):Contact|null {
  const q=p.clone().sub(c.center);if(c.rotation)q.applyQuaternion(c.rotation.clone().invert());
  let normal:T.Vector3,depth:number;
  if(c.radius!==undefined){
    const horizontal=Math.hypot(q.x,q.z),outsideSide=horizontal-c.radius,outsideY=Math.abs(q.y)-c.half.y;
    if(outsideSide>=r||outsideY>=r)return null;
    if(outsideSide>0&&outsideY>0){const distance=Math.hypot(outsideSide,outsideY);if(distance>=r)return null;normal=new T.Vector3(q.x/horizontal*outsideSide,Math.sign(q.y)*outsideY,q.z/horizontal*outsideSide).normalize();depth=r-distance;}
    else if(outsideSide>outsideY){normal=new T.Vector3(q.x/(horizontal||1),0,q.z/(horizontal||1));if(horizontal===0)normal.set(1,0,0);depth=r-outsideSide;}
    else {normal=new T.Vector3(0,Math.sign(q.y)||1,0);depth=r-outsideY;}
  }else{
    const closest=q.clone().clamp(c.half.clone().negate(),c.half),delta=q.clone().sub(closest),distance=delta.length();
    if(distance>=r)return null;
    if(distance>1e-8){normal=delta.divideScalar(distance);depth=r-distance;}
    else {const gaps=c.half.clone().sub(new T.Vector3(Math.abs(q.x),Math.abs(q.y),Math.abs(q.z)));const axis=gaps.x<gaps.y&&gaps.x<gaps.z?'x':gaps.y<gaps.z?'y':'z';normal=new T.Vector3();normal[axis]=Math.sign(q[axis])||1;depth=r+gaps[axis];}
  }
  if(c.rotation)normal.applyQuaternion(c.rotation);return {normal,depth};
}

export function resolveSphere(p:T.Vector3,v:T.Vector3,r:number,colliders:Collider[],bounce=.24){
  let grounded=false;
  for(let pass=0;pass<2;pass++)for(const c of colliders){
    // Cheap broad phase; rotated box extent uses its bounding sphere.
    const reach=c.rotation?c.half.length():Math.max(c.half.x,c.half.z,c.radius??0);
    if(Math.abs(p.x-c.center.x)>reach+r||Math.abs(p.z-c.center.z)>reach+r)continue;
    const contact=sphereContact(p,r,c);if(!contact)continue;
    p.addScaledVector(contact.normal,contact.depth+.0001);const speed=v.dot(contact.normal);
    if(speed<0)v.addScaledVector(contact.normal,-(1+bounce)*speed);
    if(contact.normal.y>.5)grounded=true;
  }
  return grounded;
}

export function rayOccluded(origin:T.Vector3,target:T.Vector3,colliders:Collider[],radius=.015){
  const direction=target.clone().sub(origin),distance=direction.length();direction.normalize();
  // Exact OBB slab query; cylindrical blockers use a conservative box for targeting.
  for(const c of colliders){const p=origin.clone().sub(c.center),d=direction.clone();if(c.rotation){const inv=c.rotation.clone().invert();p.applyQuaternion(inv);d.applyQuaternion(inv);}
    const h=c.half.clone().addScalar(radius);const hit=new T.Ray(p,d).intersectBox(new T.Box3(h.clone().negate(),h),new T.Vector3());
    if(hit&&hit.distanceTo(p)<distance-.05)return true;
  }return false;
}

export type PropKind = 'egg' | 'duck' | 'ball';
export type PropBody = {
  position:T.Vector3;velocity:T.Vector3;rotation:T.Quaternion;radius:number;floatBias:number;name:string;kind:PropKind;
  visual:T.Group;parts:{mesh:T.InstancedMesh;index:number;local:T.Matrix4}[];
  promoted:boolean;splashCooldown:number;hitCooldown:number;wakeTimer?:number;wakeX?:number;wakeZ?:number;
  /** Per-kind buoyancy tuning (PROP_SPEC): spring stiffness, damping ratio, a
   * cap on the spring acceleration (slow deep refloat vs quick pop), horizontal
   * drag rate while submerged (light bodies ride waves farther), and a splash
   * power multiplier for hard entries. */
  buoyK?:number;buoyZeta?:number;buoyMax?:number;flowRate?:number;splashBoost?:number;
};

export type PropEvents = { impact?: (b: PropBody, strength: number) => void; grab?: (b: PropBody) => void };

export class PropPhysics {
  bodies:PropBody[]=[];held:PropBody|null=null;distance=1.7;throws=0;grabs=0;
  private accumulator=0;
  private scene:T.Scene;
  private splash:(x:number,z:number,power:number,direction?:{u:number;v:number;vertical?:number;radius?:number})=>void;
  private surface:(x:number,z:number,time:number)=>number;
  private flow?:(x:number,z:number)=>{u:number;v:number};
  private slope?:(x:number,z:number,r:number)=>{ax:number;az:number;ux:number;uz:number};
  private wave?:(x:number,z:number,ix:number,iz:number,sigma:number,dirX:number,dirZ:number,speed:number)=>void;
  private impactEvent?:PropEvents['impact'];private grabEvent?:PropEvents['grab'];
  constructor(scene:T.Scene,splash:(x:number,z:number,power:number,direction?:{u:number;v:number;vertical?:number;radius?:number})=>void,surface=(x:number,z:number,time:number)=>.32+.018*Math.sin(time*1.3+x*.6+z),events?:PropEvents,flow?:(x:number,z:number)=>{u:number;v:number},wave?:(x:number,z:number,ix:number,iz:number,sigma:number,dirX:number,dirZ:number,speed:number)=>void,slope?:(x:number,z:number,r:number)=>{ax:number;az:number;ux:number;uz:number}){this.scene=scene;this.splash=splash;this.surface=surface;this.flow=flow;this.slope=slope;this.wave=wave;this.impactEvent=events?.impact;this.grabEvent=events?.grab;}
  add(body:PropBody){body.hitCooldown=0;this.bodies.push(body);}
  remove(bodies:PropBody[]){const removed=new Set(bodies.filter(b=>!b.promoted));this.bodies=this.bodies.filter(b=>!removed.has(b));}
  pick(camera:T.Camera,colliders:Collider[]){
    const ray=new T.Ray(camera.position.clone(),camera.getWorldDirection(new T.Vector3()));let result:PropBody|null=null,nearest=3.6;
    for(const b of this.bodies){const hit=ray.intersectSphere(new T.Sphere(b.position,b.radius+.07),new T.Vector3());if(hit){const d=hit.distanceTo(camera.position);if(d<nearest&&!rayOccluded(camera.position,b.position,colliders)){nearest=d;result=b;}}}return result;
  }
  grab(b:PropBody){
    if(!b.promoted){const zero=new T.Matrix4().makeScale(0,0,0);for(const p of b.parts){p.mesh.setMatrixAt(p.index,zero);p.mesh.instanceMatrix.needsUpdate=true;}b.promoted=true;this.scene.add(b.visual);}
    this.held=b;this.distance=1.7;this.grabs++;b.velocity.set(0,0,0);
    this.grabEvent?.(b);
  }
  release(camera?:T.Camera,speed=11){if(!this.held)return;this.held.velocity.set(0,0,0);if(camera){this.held.velocity.copy(camera.getWorldDirection(new T.Vector3())).multiplyScalar(speed);this.held.velocity.y+=1.2;this.throws++;}this.held=null;}
  rebase(shift:T.Vector3){for(const b of this.bodies)b.position.sub(shift);}
  update(dt:number,camera:T.Camera,colliders:Collider[],time:number,enabled=true){
    if(enabled)this.accumulator+=Math.min(dt,.2);
    const h=1/120;
    while(this.accumulator>=h){this.accumulator-=h;
      const nearby=this.bodies.filter(b=>b.position.distanceToSquared(camera.position)<24*24||b===this.held);
      for(const b of nearby){
        const before=b.position.y;b.splashCooldown=Math.max(0,b.splashCooldown-h);
        if(b===this.held){
          const target=camera.position.clone().addScaledVector(camera.getWorldDirection(new T.Vector3()),this.distance);target.y-=.1;
          b.velocity.copy(target.sub(b.position)).multiplyScalar(16).clampLength(0,12);
        }else{
          // floatBias lifts the buoyancy target so props whose visual sits below the
          // collider centre (ducks) keep their tuned waterline while resting dry.
          const water=this.surface(b.position.x,b.position.z,time)+b.floatBias;
          // Buoyancy ramps in with submerged fraction and stays soft: entry
          // momentum carries a body deep underwater for a beat before it floats
          // back up. Per-kind density reshapes the dive: dense eggs bottom out
          // and refloat slowly, light ducks and balls pop straight back up.
          // The waterline equilibrium itself stays on the tuned bias target.
          if(b.position.y<water+b.radius){
            const buoyK=b.buoyK??64,submRest=(b.floatBias+b.radius)/(2*b.radius);
            const ramp=Math.min(1,(water+b.radius-b.position.y)/(2*b.radius)/submRest);
            const spring=T.MathUtils.clamp((water-b.position.y)*buoyK*ramp,-(b.buoyMax??1e9),b.buoyMax??1e9);
            b.velocity.y+=(spring-b.velocity.y*2*(b.buoyZeta??.44)*Math.sqrt(buoyK)*ramp)*h;
          }
          else b.velocity.y-=9.81*h;
          b.velocity.clampLength(0,18);
        }
        // Drag is relative to the local flow. Feed a small share of the body's
        // lost momentum back into the larger water footprint; no extra position
        // drift or recurring height pulse can manufacture energy here.
        const surface=this.surface(b.position.x,b.position.z,time);
        const subm=T.MathUtils.clamp((surface+b.floatBias+b.radius-b.position.y)/(2*b.radius),0,1);
        if(subm>0){
          const f=this.flow?.(b.position.x,b.position.z)??{u:0,v:0};
          // The drag chases the local current plus the Stokes drift the wave
          // train carries, so props glide along with passing waves instead of
          // only bobbing; the slope push rocks them over long wave faces.
          let targetU=f.u,targetV=f.v;
          if(b!==this.held){const w=this.slope?.(b.position.x,b.position.z,.38);
            if(w){const s=subm*h;b.velocity.x+=w.ax*s;b.velocity.z+=w.az*s;targetU+=w.ux;targetV+=w.uz;}}
          const ru=b.velocity.x-targetU,rv=b.velocity.z-targetV;
          // Fast attack, soft release: a passing wave grabs the hull within a
          // fraction of a second (the ring only shelters a spot briefly), then
          // the per-kind low drag lets it glide out over its own inertia.
          const overtaken=targetU*targetU+targetV*targetV>b.velocity.x*b.velocity.x+b.velocity.z*b.velocity.z;
          const k=1-Math.exp(-(overtaken?10:(b.flowRate??8))*subm*h);
          b.velocity.x-=ru*k;b.velocity.z-=rv*k;
          if(this.wave&&Math.hypot(ru,rv)>.08){
            b.wakeTimer=(b.wakeTimer??0)+h;
            // Form drag on the water grows with hull speed SQUARED: a slow
            // nudge leaves a hairline ripple, a fast drag throws a real bow
            // wave. The source stays hull-sized, so the mark is narrow and the
            // solver's own dispersion does the widening downstream.
            const wk=1-Math.exp(-8*subm*h);
            const share=(b===this.held?.8:1)*.09;
            b.wakeX=(b.wakeX??0)+ru*Math.hypot(ru,rv)*wk*share;
            b.wakeZ=(b.wakeZ??0)+rv*Math.hypot(ru,rv)*wk*share;
            if(b.wakeTimer>=.05){
              const rel=Math.hypot(ru,rv);
              this.wave(b.position.x,b.position.z,b.wakeX,b.wakeZ,b.radius*.6+.06,ru/rel,rv/rel,rel);
              b.wakeTimer=0;b.wakeX=0;b.wakeZ=0;
            }
          }else{b.wakeTimer=0;b.wakeX=0;b.wakeZ=0;}
        }else{b.wakeTimer=0;b.wakeX=0;b.wakeZ=0;}
        b.position.addScaledVector(b.velocity,h);
        const beforeHit=b.velocity.clone();
        // Beach balls are the only bouncy kind: a light vinyl shell rebounds at
        // over half the impact speed while eggs and ducks just thud.
        resolveSphere(b.position,b.velocity,b.radius,colliders,b===this.held?0:(b.kind==='ball'?.62:.3));
        // Collision impulses above a threshold become impact sounds; the cooldown
        // keeps a resting contact from machine-gunning events every substep.
        const hit=b.velocity.clone().sub(beforeHit).length();
        if(b!==this.held&&b.hitCooldown<=0&&hit>1.15){b.hitCooldown=.18;this.impactEvent?.(b,hit);}
        b.hitCooldown=Math.max(0,b.hitCooldown-h);
        if(b!==this.held){const playerVolume={center:camera.position.clone().add(new T.Vector3(0,-.82,0)),half:new T.Vector3(.32,.82,.32),radius:.32};const contact=sphereContact(b.position,b.radius,playerVolume);if(contact){b.position.addScaledVector(contact.normal,contact.depth+.001);b.velocity.addScaledVector(contact.normal,.08);}}
        if(before>surface&&b.position.y<=this.surface(b.position.x,b.position.z,time)&&b.velocity.length()>1&&b.splashCooldown===0){
          // Dense bodies (eggs) announce the entry: a boosted splash power
          // scales the particle burst, water impact and audio together.
          const boost=b.splashBoost??1;
          this.splash(b.position.x,b.position.z,Math.min(.5*boost,(.06+b.velocity.length()*.028)*boost),{u:b.velocity.x,v:b.velocity.z,vertical:b.velocity.y,radius:b.radius});
          b.splashCooldown=.7;
        }
        if(b!==this.held&&subm>0&&b.kind!=='ball'){
          const r=b.radius;
          const nx=(this.surface(b.position.x-r,b.position.z,time)-this.surface(b.position.x+r,b.position.z,time))/(2*r);
          const nz=(this.surface(b.position.x,b.position.z-r,time)-this.surface(b.position.x,b.position.z+r,time))/(2*r);
          const normal=new T.Vector3(nx,1,nz).normalize(),yaw=new T.Euler().setFromQuaternion(b.rotation,'YXZ').y;
          const tilt=new T.Quaternion().setFromUnitVectors(new T.Vector3(0,1,0),normal).multiply(new T.Quaternion().setFromAxisAngle(new T.Vector3(0,1,0),yaw));
          b.rotation.slerp(tilt,1-Math.exp(-12*h));
        }else if(b!==this.held&&b.velocity.lengthSq()>.04){const spin=new T.Quaternion().setFromAxisAngle(new T.Vector3(b.velocity.z,0,-b.velocity.x).normalize(),Math.min(b.velocity.length(),6)*h);b.rotation.premultiply(spin);}
      }
      // Spatial buckets avoid an all-pairs pass over the streamed population.
      const buckets=new Map<string,PropBody[]>();for(const b of nearby){const key=`${Math.floor(b.position.x)},${Math.floor(b.position.z)}`;if(!buckets.has(key))buckets.set(key,[]);buckets.get(key)!.push(b);}
      const ids=new Map(nearby.map((b,i)=>[b,i]));
      for(const a of nearby)for(let x=-1;x<=1;x++)for(let z=-1;z<=1;z++)for(const b of buckets.get(`${Math.floor(a.position.x)+x},${Math.floor(a.position.z)+z}`)??[]){
        if(ids.get(a)!>=ids.get(b)!)continue;const delta=b.position.clone().sub(a.position),length=delta.length(),sum=a.radius+b.radius;if(length>=sum||length<1e-6)continue;
        const n=delta.divideScalar(length),depth=sum-length;a.position.addScaledVector(n,-depth*.5);b.position.addScaledVector(n,depth*.5);
        const speed=b.velocity.clone().sub(a.velocity).dot(n);if(speed<0){a.velocity.addScaledVector(n,speed*.65);b.velocity.addScaledVector(n,-speed*.65);
          if(speed<-1.15){const strength=-speed;for(const body of [a,b])if(body!==this.held&&body.hitCooldown<=0){body.hitCooldown=.18;this.impactEvent?.(body,strength);}}}
      }
    }
    for(const b of this.bodies){
      if(b.promoted){b.visual.position.copy(b.position);b.visual.quaternion.copy(b.rotation);}
      else for(const part of b.parts){const root=new T.Matrix4().compose(b.position.clone().sub(part.mesh.position),b.rotation,new T.Vector3(1,1,1));part.mesh.setMatrixAt(part.index,root.multiply(part.local));part.mesh.instanceMatrix.needsUpdate=true;}
    }
    this.bodies=this.bodies.filter(b=>{if(b.promoted&&b!==this.held&&b.position.distanceTo(camera.position)>80){this.scene.remove(b.visual);return false;}return true;});
  }
}

export class PlayerPhysics {
  vertical=0;grounded=false;climbing:Ladder|null=null;climbProgress=0;slides=0;
  private accumulator=0;
  private jumpHeld=false;
  private jumpBuffer=0;
  private splashCooldown=0;
  private waterImpact?: (x:number,z:number,power:number)=>void;
  private waterHeight: (x:number,z:number)=>number;
  constructor(waterImpact?:(x:number,z:number,power:number)=>void,waterHeight:(x:number,z:number)=>number=()=>.32){this.waterImpact=waterImpact;this.waterHeight=waterHeight;}
  nearest(camera:T.Camera,ladders:Ladder[]){return ladders.find(l=>Math.min(...[l.base,l.top,l.exit].map(p=>Math.hypot(camera.position.x-p.x,camera.position.z-p.z)))<1.25&&camera.position.y>l.base.y-.5&&camera.position.y<l.top.y+2.3)??null;}
  toggle(camera:T.Camera,ladders:Ladder[]){if(this.climbing){this.climbing=null;return;}this.climbing=this.nearest(camera,ladders);if(this.climbing){this.climbProgress=T.MathUtils.clamp(camera.position.y-1.65-this.climbing.base.y,0,this.climbing.top.y-this.climbing.base.y);this.vertical=0;}}
  update(dt:number,camera:T.Camera,keys:Set<string>,colliders:Collider[]){
    if(keys.has('Space')&&!this.jumpHeld)this.jumpBuffer=.12;this.jumpHeld=keys.has('Space');
    this.accumulator+=Math.min(dt,.2);const h=1/120;
    while(this.accumulator>=h){this.accumulator-=h;
      this.splashCooldown=Math.max(0,this.splashCooldown-h);
      this.jumpBuffer=Math.max(0,this.jumpBuffer-h);
      if(this.climbing){const l=this.climbing,height=l.top.y-l.base.y;this.climbProgress+=(Number(keys.has('KeyW'))-Number(keys.has('KeyS')))*1.8*h;
        const t=T.MathUtils.clamp(this.climbProgress/height,0,1);camera.position.copy(l.base).lerp(l.top,t);camera.position.y+=1.65;
        if(this.climbProgress>=height){camera.position.copy(l.exit);camera.position.y+=1.65;this.climbing=null;this.grounded=true;}
        else if(this.climbProgress<0){this.climbing=null;camera.position.y=1.5;}continue;
      }
      const move=new T.Vector3(Number(keys.has('KeyD'))-Number(keys.has('KeyA')),0,Number(keys.has('KeyS'))-Number(keys.has('KeyW'))).normalize().applyAxisAngle(new T.Vector3(0,1,0),camera.rotation.y).multiplyScalar(keys.has('ShiftLeft')?5.2:2.6);
      const water=this.waterHeight(camera.position.x,camera.position.z),beforeFeet=camera.position.y-1.64;
      const swimming=camera.position.y<water+1.3&&this.vertical<1&&this.vertical>-1.5;
      this.vertical-=9.81*h;
      if(camera.position.y<water+1.18&&this.vertical<0){this.vertical+=(water+1.18-camera.position.y)*50*h-this.vertical*7*h;}
      if(this.jumpBuffer>0&&(this.grounded||swimming)){
        this.jumpBuffer=0;this.vertical=swimming?3.8:5.0;this.grounded=false;
        if(swimming){this.waterImpact?.(camera.position.x,camera.position.z,.14);this.splashCooldown=.3;}
      }
      const v=new T.Vector3(move.x,this.vertical,move.z);camera.position.addScaledVector(v,h);this.grounded=false;
      for(let pass=0;pass<2;pass++)for(const c of colliders){
        const reach=c.rotation?c.half.length():Math.max(c.half.x,c.half.z,c.radius??0);if(Math.abs(camera.position.x-c.center.x)>reach+.4||Math.abs(camera.position.z-c.center.z)>reach+.4)continue;
        for(const down of [1.32,.83,.34]){const p=camera.position.clone();p.y-=down;const contact=sphereContact(p,.32,c);if(!contact)continue;camera.position.addScaledVector(contact.normal,contact.depth+.0001);const speed=v.dot(contact.normal);if(speed<0)v.addScaledVector(contact.normal,-speed);
          if(contact.normal.y>.5){this.grounded=true;if(c.slide){const gravity=new T.Vector3(0,-9.81,0);gravity.addScaledVector(contact.normal,-gravity.dot(contact.normal));camera.position.addScaledVector(gravity,h*.55);this.slides++;}}
        }
      }this.vertical=v.y;
      // Detect crossing the actual surface, independently of touching the pool
      // floor: buoyancy normally arrests a dive before grounded becomes true.
      const afterWater=this.waterHeight(camera.position.x,camera.position.z);
      if(beforeFeet>water&&camera.position.y-1.64<=afterWater&&this.vertical<-1&&this.splashCooldown===0){
        this.waterImpact?.(camera.position.x,camera.position.z,T.MathUtils.clamp(.09+Math.abs(this.vertical)*.035,.14,.48));
        this.splashCooldown=.4;
      }
    }
  }
}
