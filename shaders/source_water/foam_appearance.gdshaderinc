// Transported foam breaks into quiet patches as density decays. Shared by
// original and reference water; no particles or additional texture samples.
float foam_hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx)*.1031);
    q += dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float foam_noise(vec2 p) {
    vec2 cell=floor(p),f=fract(p);
    f=f*f*f*(f*(f*6.0-15.0)+10.0);
    return mix(mix(foam_hash(cell),foam_hash(cell+vec2(1,0)),f.x),
               mix(foam_hash(cell+vec2(0,1)),foam_hash(cell+vec2(1)),f.x),f.y);
}
float foam_coverage(vec2 p,vec2 flow,float density,float footprint,float time) {
    float phase=fract(time*.35),other=fract(phase+.5),weight=abs(phase*2.0-1.0);
    vec2 a=p-flow*phase/ .35,b=p-flow*other/ .35;
    float patch=mix(foam_noise(a*5.0),foam_noise(b*5.0),weight);
    float pore=mix(foam_noise(a*38.0),foam_noise(b*38.0),weight);
    // Fade unresolved bubbles to their mean instead of sparkling/aliasing.
    pore=mix(.5,pore,1.0-smoothstep(.006,.025,footprint));
    float islands=smoothstep(.38,.67,patch+density*.16);
    float bubbles=smoothstep(.25,.7,pore)*.45+.55;
    return smoothstep(.10,.58,density)*islands*bubbles*.72;
}
vec3 foam_lit_color(vec3 transmitted,vec3 reflected) {
    // Use the local scene illumination; foam must not glow in unlit halls.
    float light=dot(mix(transmitted,reflected,.35),vec3(.2126,.7152,.0722));
    return vec3(.72,.79,.76)*clamp(light*1.8,.025,1.0);
}
