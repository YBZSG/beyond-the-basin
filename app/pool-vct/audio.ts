// PoolCore soundscape built from the user-supplied water recordings
// (converted to OGG under /assets/sfx/): varied water effects plus a
// long ambience bed that loops behind everything. Helpers stay pure so node
// tests can import this module without a DOM.

export const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

// Random variants without repeating the previous recording. Power controls gain.
export function impactClip(power:number, previous=-1, random=Math.random()) {
  const index=previous<0?Math.min(2,Math.floor(random*3)):(previous+1+Math.min(1,Math.floor(random*2)))%3;
  return {index,name:`drop_${index+1}`,volume:clamp(.35+power*1.2,.35,.85)};
}
const CLIP_GAIN:Record<string,number>={ambience:.16,drop_1:1,drop_2:.65,drop_3:1,step_swish:2.2,step_stir:.65,tap:2.2,step_dry_1:1.1,step_dry_2:1.05,step_run:1.15,duck_pickup:1.05,duck_hit:1,egg_hit:.95};
type Voice={source:AudioBufferSourceNode;gain:GainNode;end:number};

export class PoolAudio {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private clips = new Map<string, AudioBuffer>();
  private ambience: AudioBufferSourceNode | null = null;
  private musicBus: GainNode | null = null;
  private _enabled = true;
  private _music = true;
  private corruption = 0;
  private unlocked = false;
  private previousDrop=-1;
  private voices=new Set<Voice>();
  private wadeLoops=new Map<string,{source:AudioBufferSourceNode;gain:GainNode}>();
  private wading=false;
  private disposed=false;
  private active=false;

  private lastInterval=0;
  private lastDrop='';
  private lastStepDry='';

  private base:string;
  constructor(base='/assets/sfx/'){this.base=base;}

  get enabled() { return this._enabled; }

  /** Create the graph inside a user gesture; failures leave the game silent. */
  async unlock() {
    if (this.unlocked) return;
    this.unlocked = true;
    try {
      const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return;
      const ctx = this.ctx = new Ctor();
      this.master = ctx.createGain();
      this.master.gain.value = this._enabled ? .85 : 0;
      const limiter=ctx.createDynamicsCompressor();
      limiter.threshold.value=-8;limiter.knee.value=6;limiter.ratio.value=8;
      limiter.attack.value=.003;limiter.release.value=.15;
      this.master.connect(limiter).connect(ctx.destination);
      // 环境底噪（背景音乐）走独立总线，可与音效分别开关。
      this.musicBus = ctx.createGain();
      this.musicBus.gain.value = this._music ? 1 : 0;
      this.musicBus.connect(this.master);
      await Promise.allSettled(Object.keys(CLIP_GAIN).map(async name => {
        const res = await fetch(this.base + name + '.ogg');
        if (!res.ok) return;
        const buffer=await ctx.decodeAudioData(await res.arrayBuffer());
        if(!this.disposed)this.clips.set(name,buffer);
      }));
      if(this.disposed)return;
      this.startAmbience();
      if (ctx.state === 'suspended') await ctx.resume();
    } catch {
      this.ctx = null;
    }
  }

  /** The water-room ambience bed; loops seamlessly for the whole session. */
  private startAmbience() {
    const ctx = this.ctx!, buf = this.clips.get('ambience');
    if (!buf || !this.master) return;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    const g = ctx.createGain();
    g.gain.value = CLIP_GAIN.ambience;
    // Deep corruption lowers the ambience pitch a touch: the same room, wrong.
    src.playbackRate.value = 1 - this.corruption * .028;
    src.connect(g).connect(this.musicBus ?? this.master);
    src.start();
    this.ambience = src;
  }

  /** Bounded voices and short envelopes prevent clicks at segment boundaries. */
  private play(name:string,volume:number,rate:number,pan=0,distance=0,offset=0,duration?:number) {
    const ctx=this.ctx,buf=this.clips.get(name);
    if(!ctx||!buf||!this.master||!this._enabled||!this.active||ctx.state!=='running'||this.voices.size>=24||distance>30)return;
    const src=ctx.createBufferSource(),g=ctx.createGain(),p=ctx.createStereoPanner();
    src.buffer=buf;src.playbackRate.value=rate;
    const now=ctx.currentTime,length=Math.min(duration??buf.duration/rate,(buf.duration-offset)/rate);
    if(length<=.02)return;
    const level=volume*(CLIP_GAIN[name]??1)/(1+Math.max(0,distance-1)*.2);
    const fade=Math.min(.04,length*.3);
    g.gain.setValueAtTime(0,now);g.gain.linearRampToValueAtTime(level,now+.015);
    g.gain.setValueAtTime(level,now+length-fade);g.gain.linearRampToValueAtTime(0,now+length);
    p.pan.value=clamp(pan,-1,1)*.7;src.connect(g).connect(p).connect(this.master);
    const voice={source:src,gain:g,end:now+length};this.voices.add(voice);
    src.onended=()=>{this.voices.delete(voice);src.disconnect();g.disconnect();p.disconnect();};
    src.start(now,offset);src.stop(now+length);
  }

  /** Splice the tail into the head once, then let Web Audio loop continuously. */
  private loopBuffer(buffer:AudioBuffer){
    const ctx=this.ctx!,fade=Math.min(Math.floor(buffer.sampleRate*.2),Math.floor(buffer.length/4));
    const loop=ctx.createBuffer(buffer.numberOfChannels,buffer.length-fade,buffer.sampleRate);
    for(let ch=0;ch<buffer.numberOfChannels;ch++){
      const input=buffer.getChannelData(ch),output=loop.getChannelData(ch);
      output.set(input.subarray(fade));
      for(let i=0;i<fade;i++){const t=i/(fade-1);output[output.length-fade+i]=input[buffer.length-fade+i]*(1-t)+input[i]*t;}
    }
    return loop;
  }
  /** Movement adjusts existing loops; it never retriggers a sample on a footstep. */
  updateWading(power:number,interval:number,phase:number){
    const ctx=this.ctx;
    if(!ctx||!this.master||!this._enabled||!this.active||ctx.state!=='running')return;
    this.wading=true;this.lastInterval=clamp(interval,.08,.85);
    for(const name of ['step_swish','step_stir']){
      let loop=this.wadeLoops.get(name);
      if(!loop){const buffer=this.clips.get(name);if(!buffer)continue;
        const source=ctx.createBufferSource(),gain=ctx.createGain();
        source.buffer=this.loopBuffer(buffer);source.loop=true;gain.gain.value=0;
        source.connect(gain).connect(this.master);source.start();
        loop={source,gain};this.wadeLoops.set(name,loop);
      }
      // A shallow swell follows the gait, without audible repeated attacks.
      const swell=1+.04*Math.sin(phase*Math.PI*2);
      const level=(name==='step_swish'?.3:.4)*(power>.08?1.15:1)*CLIP_GAIN[name]*swell;
      loop.gain.gain.setTargetAtTime(level,ctx.currentTime,.12);
      loop.source.playbackRate.setTargetAtTime(clamp(.9+(.21/this.lastInterval-1)*.12,.85,1.15),ctx.currentTime,.25);
    }
  }
  stopWading(){
    if(!this.ctx||!this.wading)return;this.wading=false;
    for(const loop of this.wadeLoops.values())loop.gain.gain.setTargetAtTime(0,this.ctx.currentTime,.07);
  }
  splash(power:number,distance=0,pan=0,step=false){
    if(step)return;
    const clip=impactClip(power,this.previousDrop);this.previousDrop=clip.index;this.lastDrop=clip.name;
    this.play(clip.name,clip.volume,.96+Math.random()*.08,pan,distance);
  }
  tapWater(pan=0,distance=0){this.play('tap',.7,.97+Math.random()*.06,pan,distance);}
  diveIn(){this.splash(.45);}

  /** Dry-ground gait: two tile steps alternate; sprinting swaps in the harder heel clip. */
  stepDry(sprint=false,pan=0,distance=0){
    const name=this.lastStepDry==='step_dry_1'?'step_dry_2':'step_dry_1';
    // Sprinting must not consume the walk alternation, or a sprint sandwiched
    // between steps would repeat the same footfall sound.
    if(!sprint)this.lastStepDry=name;
    this.play(sprint?'step_run':name,.5,.94+Math.random()*.12,pan,distance);
  }
  /** Egg shell against masonry: a short crack scaled by the impact. */
  eggHit(power:number,pan=0,distance=0){this.play('egg_hit',.55+.3*power,.94+Math.random()*.12,pan,distance);}
  /** Rubber duck picked up: one squeak. */
  duckPickup(){this.play('duck_pickup',.8,1,0,0);}
  /** Rubber duck rebounding off a wall, pitched around by the impact. */
  duckHit(power:number,pan=0,distance=0){this.play('duck_hit',.5+.3*power,.85+Math.random()*.3,pan,distance);}
  /** Vinyl beach ball: the light drop lands with a hollow plastic thump. */
  ballHit(power:number,pan=0,distance=0){this.play('drop_light',.38+.3*power,1.02+Math.random()*.22,pan,distance);}
  /** Beach ball picked up: a soft shuffle of the vinyl skin. */
  ballPickup(){this.play('drop_light',.22,.94+Math.random()*.06,0,0);}

  /** UI sound switch; smooth-ramps the master bus. */
  setEnabled(enabled: boolean) {
    this._enabled = enabled;
    if(!enabled)this.stopWading();
    if (this.master && this.ctx) {
      const now = this.ctx.currentTime;
      this.master.gain.cancelScheduledValues(now);
      this.master.gain.setTargetAtTime(enabled ? .85 : 0, now, .15);
    }
  }

  /** Independent music switch; only ramps the ambience bed's own bus. */
  setMusic(enabled: boolean) {
    this._music = enabled;
    if (this.musicBus && this.ctx) {
      const now = this.ctx.currentTime;
      this.musicBus.gain.cancelScheduledValues(now);
      this.musicBus.gain.setTargetAtTime(enabled ? 1 : 0, now, .3);
    }
  }

  /** Exploration-depth corruption detunes the ambience bed, one cent at a time. */
  setCorruption(level: number) {
    this.corruption = Math.max(0, Math.min(3, level | 0));
    if (this.ambience && this.ctx)
      this.ambience.playbackRate.setTargetAtTime(1 - this.corruption * .028, this.ctx.currentTime, 1.5);
  }

  /** Suspend/resume with the game's active state (also saves battery). */
  setActive(active: boolean) {
    this.active=active;
    const ctx = this.ctx;
    if (!ctx) return;
    if(!active)this.stopWading();
    if (!active && ctx.state === 'running') void ctx.suspend().catch(()=>{});
    else if (active && ctx.state === 'suspended') void ctx.resume().catch(()=>{});
  }

  /** Dev-only introspection for the automated QA hook. */
  inspect() {
    return { enabled:this._enabled,music:this._music,ready:!!this.ctx,clips:this.clips.size,state:this.ctx?.state,active:this.active,voices:this.voices.size,wading:this.wading,loopSources:this.wadeLoops.size,interval:this.lastInterval,lastDrop:this.lastDrop,lastStepDry:this.lastStepDry };
  }

  dispose() {
    this.disposed=true;
    for(const voice of this.voices){voice.source.onended=null;voice.source.stop();voice.source.disconnect();voice.gain.disconnect();}
    this.voices.clear();
    for(const loop of this.wadeLoops.values()){loop.source.stop();loop.source.disconnect();loop.gain.disconnect();}
    this.wadeLoops.clear();
    try { this.ambience?.stop(); } catch { /* already stopped */ }
    this.ambience = null;
    this.musicBus?.disconnect();
    this.musicBus = null;
    this.clips.clear();
    void this.ctx?.close().catch(()=>{});
    this.ctx = null;
  }
}
