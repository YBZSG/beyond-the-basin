// LAB ONLY. Coherent sub-mesh optical height; NOT source-equivalent and NOT SWE.
// CPU oracle: tests/pc_nearfield_reference.py. Units metres / seconds.
// Works in GLSL450 and Godot spatial shader syntax. No textures or RNG.
float nf_sinc(float x) { return abs(x)<.0001 ? 1.0-x*x/6.0 : sin(x)/x; }
float nf_box(vec2 k, vec2 dpdx, vec2 dpdy) {
    vec2 phaseWidth=vec2(dot(k,dpdx),dot(k,dpdy));
    float stop=1.0-smoothstep(2.4,3.141592654,max(abs(phaseWidth.x),abs(phaseWidth.y)));
    return nf_sinc(.5*phaseWidth.x)*nf_sinc(.5*phaseWidth.y)*stop;
}
vec3 nf_mode(vec2 p,float time,vec2 dpdx,vec2 dpdy,vec2 direction,float wavelength,float amplitude,float phase) {
    vec2 k=normalize(direction)*(6.283185307/wavelength);
    float km=length(k);
    // Fixed .44m reference depth avoids a position-dependent temporal phase
    // whose omitted depth derivative would make the reported slope inconsistent.
    float omega=sqrt((9.81*km+.000072*km*km*km)*tanh(km*.44));
    float theta=dot(p,k)-omega*time+phase;
    float a=amplitude*nf_box(k,dpdx,dpdy);
    return vec3(a*sin(theta),a*cos(theta)*k);
}
vec3 nf_height_gradient(vec2 worldXZ,float time,vec2 dpdx,vec2 dpdy) {
    vec3 h=nf_mode(worldXZ,time,dpdx,dpdy,vec2(.817,.577),.72,.0025,.3);
    h+=nf_mode(worldXZ,time,dpdx,dpdy,vec2(-.6,.8),.48,.0018,1.7);
    h+=nf_mode(worldXZ,time,dpdx,dpdy,vec2(.96,-.28),.36,.0012,3.1);
    return h; // x height(m), yz exact derivatives dHeight/dX and dHeight/dZ.
}
// Photon call: nf_height_gradient(p+microOrigin,poolTime,vec2(16.0/256.0,0),vec2(0,12.0/256.0)).
// Surface call: same world position/time; use dFdx(worldXZ), dFdy(worldXZ).
// Add yz to SOURCE simulationSlope+detailSlope. Replace, do not double-count,
// source microSlope. Height and derivative filtering must remain paired.
