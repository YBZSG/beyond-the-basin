// Exact source LiquidSurfacePass narrow-range filter, four alternating passes.
layout(set=0,binding=1) uniform sampler2D source;
layout(push_constant,std430) uniform FilterDirection {vec4 direction;};
layout(location=0) in vec2 vUv;
layout(location=0) out vec4 color;
void main(){float centre=texture(source,vUv).r;if(centre>9000.){color=vec4(10000.,0.,0.,1.);return;}
 float radius=clamp(viewport.z*.018/centre,1.,6.),sum=centre,weight=1.;
 for(int side=-1;side<=1;side+=2){float lo=centre-.035,hi=centre+.035;
  for(int k=1;k<=6;k++){if(float(k)>radius)break;
   float d=texture(source,vUv+direction.xy/viewport.xy*float(k*side)).r;
   if(d<lo)break;float w=exp(-float(k*k)/(radius*radius*.5));
   if(d>hi){d=centre+.012;}else{lo=min(lo,d-.035);hi=max(hi,d+.035);}
   sum+=w*d;weight+=w;
  }
 }color=vec4(sum/weight,0.,0.,1.);
}
