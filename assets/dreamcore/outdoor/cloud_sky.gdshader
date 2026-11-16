shader_type sky;
uniform vec3 zenith : source_color = vec3(.17,.22,.35);
uniform vec3 horizon : source_color = vec3(.95,.33,.09);
uniform vec3 sun_direction = vec3(-.40,.10,-.91);
uniform float night = 0.0;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void sky(){vec3 d=normalize(EYEDIR);float h=max(d.y,0.);vec3 col=mix(horizon,zenith,pow(h,.42));float sun=max(dot(d,normalize(sun_direction)),0.);col+=vec3(1.,.55,.19)*pow(sun,18.)*.6*(1.-night);col+=vec3(1.,.85,.55)*smoothstep(.99983,.99996,sun)*4.*(1.-night);vec2 uv=d.xz/max(.12,d.y+.15);float n=noise(uv*1.8)*.5+noise(uv*4.1)*.27+noise(uv*9.2)*.13;float cloud=smoothstep(.45,.66,n)*smoothstep(-.02,.2,d.y);col=mix(col,mix(vec3(.38,.38,.43),vec3(.95,.7,.49),pow(sun,6.)),cloud*.65*(1.-night));COLOR=col;}
