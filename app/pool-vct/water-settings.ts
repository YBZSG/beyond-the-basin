export const WATER_QUALITY={
  Low:{simulation:384,surface:96,ripple:192,caustics:256,photons:64,wallPhotons:24,reflection:256,refraction:0},
  Medium:{simulation:384,surface:192,ripple:384,caustics:768,photons:192,wallPhotons:48,reflection:384,refraction:.65},
  High:{simulation:768,surface:384,ripple:768,caustics:1024,photons:256,wallPhotons:96,reflection:768,refraction:.8},
  Ultra:{simulation:1152,surface:512,ripple:1152,caustics:2048,photons:384,wallPhotons:192,reflection:1536,refraction:1},
} as const;
export type WaterQuality=keyof typeof WATER_QUALITY;
export const WATER_DEBUG=['完整水面','浅水高度','速度场','模拟法线','细波纹','最终法线','水深','Fresnel','折射','焦散','反射','浮沫'] as const;
export const WATER_LAYERS={simulation:'浅水表面',ripples:'交互细波纹',microNormals:'微表面法线',refraction:'屏幕折射',absorption:'深度吸收',caustics:'动态焦散',reflection:'平面反射',fresnel:'Fresnel',waterline:'接触水线',foam:'表面浮沫'} as const;
export const WATER_SLIDERS=[
  {key:'waveHeight',label:'波浪起伏',min:0,max:2,step:.01,def:1},
  {key:'waveSpeed',label:'波速',min:.3,max:3,step:.05,def:1},
  {key:'damping',label:'波浪阻尼',min:.05,max:2,step:.01,def:.28},
  {key:'viscosity',label:'黏性扩散',min:0,max:.012,step:.0005,def:.0015},
  {key:'wallLoss',label:'池壁耗散',min:0,max:4,step:.05,def:1.1},
  {key:'rippleGain',label:'细波强度',min:0,max:3,step:.01,def:1},
  {key:'rippleFrequency',label:'细波频率',min:10,max:32,step:1,def:22},
  {key:'microStrength',label:'微法线强度',min:0,max:2,step:.01,def:.65},
  {key:'environmentalStrength',label:'环境微扰',min:0,max:1,step:.01,def:.08},
  {key:'normalBoost',label:'波浪反光',min:.5,max:2,step:.05,def:1},
  {key:'distortion',label:'倒影偏移',min:0,max:1.5,step:.01,def:.4},
  {key:'refractionStrength',label:'折射强度',min:0,max:2,step:.01,def:.7},
  {key:'fresnelStrength',label:'Fresnel 强度',min:0,max:1.5,step:.01,def:1},
  {key:'absorptionStrength',label:'水体吸收',min:0,max:3,step:.01,def:.7},
  {key:'causticsIntensity',label:'焦散亮度',min:0,max:3,step:.05,def:1.5},
  {key:'causticsScale',label:'焦散细节尺度',min:.5,max:2,step:.05,def:1},
  {key:'causticsSpeed',label:'焦散微动速度',min:0,max:2,step:.05,def:.6},
  {key:'causticsRefresh',label:'焦散更新间隔',min:0,max:6,step:1,def:2},
  {key:'solverSteps',label:'求解子步上限',min:1,max:8,step:1,def:8},
  {key:'refractionRefresh',label:'折射抓帧间隔',min:0,max:4,step:1,def:1},
  {key:'foamStrength',label:'泡沫浓度',min:0,max:2,step:.01,def:1},
  {key:'foamLife',label:'泡沫存留',min:.5,max:12,step:.1,def:2},
  {key:'impact',label:'交互强度',min:.2,max:3,step:.05,def:1},
  {key:'spray',label:'浪尖飞沫',min:0,max:2,step:.05,def:1},
  {key:'ringWaves',label:'物理波频率',min:6,max:20,step:1,def:10},
  {key:'wavePush',label:'随波推力',min:0,max:2,step:.05,def:1},
] as const;
export type WaterSettings=Record<typeof WATER_SLIDERS[number]['key'],number>&Record<keyof typeof WATER_LAYERS,boolean>&{quality:WaterQuality;debugView:number};
export const WATER_SETTINGS_DEFAULT:WaterSettings={
  ...Object.fromEntries(WATER_SLIDERS.map(s=>[s.key,s.def])),
  ...Object.fromEntries(Object.keys(WATER_LAYERS).map(k=>[k,true])),quality:'High',debugView:0,
} as WaterSettings;
/** Validate persisted/QA values too: a bad localStorage value cannot destabilise a shader. */
export function sanitizeWaterSettings(input:Partial<WaterSettings>,base=WATER_SETTINGS_DEFAULT):WaterSettings{
  const s={...base};
  for(const range of WATER_SLIDERS){const value=input[range.key];if(typeof value==='number'&&Number.isFinite(value))s[range.key]=Math.max(range.min,Math.min(range.max,value));}
  for(const key of Object.keys(WATER_LAYERS) as (keyof typeof WATER_LAYERS)[])if(typeof input[key]==='boolean')s[key]=input[key];
  if(input.quality&&Object.hasOwn(WATER_QUALITY,input.quality))s.quality=input.quality;
  if(Number.isInteger(input.debugView))s.debugView=Math.max(0,Math.min(WATER_DEBUG.length-1,input.debugView!));
  return s;
}
