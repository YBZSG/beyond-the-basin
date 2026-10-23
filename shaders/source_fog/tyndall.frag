// Port of beyond-the-basin 66a4543 app/pool-vct/engine.ts:722-773.
// Only framebuffer/depth conventions and additive output are adapted.
layout(set=0,binding=0,std140) uniform SourceFogFrame {
    mat4 proj;
    mat4 projInv;
    mat4 viewMat;
    mat4 camMat;
    vec4 lightIntensity; // xyz: source-local lightPos, w: intensity
    vec4 frame;          // xy: native render size, z: source time, w: native HDR encoding scale
};
layout(set=0,binding=1) uniform sampler2D tDepth;
layout(location=0) in vec2 vUv;
layout(location=0) out vec4 color;
const vec3 SUN=vec3(.274,-.913,.274);
void main() {
    float intensity=lightIntensity.w;
    if(intensity<=.001) { color=vec4(0.0); return; }
    vec3 lightPos=lightIntensity.xyz;
    vec3 camPos=camMat[3].xyz;
    float time=frame.z;
    vec2 ndc=vUv*2.0-1.0;
    // Godot's corrected projection has reverse Z [1 near, 0 far].
    vec4 nearH=projInv*vec4(ndc,1.0,1.0);
    vec4 farH=projInv*vec4(ndc,0.0,1.0);
    vec3 dir=normalize(mat3(camMat)*(farH.xyz/farH.w-nearH.xyz/nearH.w));
    const int STEPS=20;
    float dt=36.0/float(STEPS);
    // WebGL gl_FragCoord is bottom-up. Preserve its static jitter pattern.
    vec2 sourceFragCoord=vec2(gl_FragCoord.x,frame.y-gl_FragCoord.y);
    float jitter=fract(sin(dot(sourceFragCoord,vec2(12.9898,78.233)))*43758.5453);
    vec3 acc=vec3(0.0);
    for(int i=0;i<STEPS;i++) {
        vec3 p=camPos+dir*((float(i)+jitter)*dt);
        if(p.y<.32) break;
        vec4 clip=proj*viewMat*vec4(p,1.0);
        if(clip.w<=0.0) continue;
        vec2 suv=clip.xy/clip.w*.5+.5;
        if(suv.x<0.0||suv.x>1.0||suv.y<0.0||suv.y>1.0) continue;
        // Exact source test mapped to reverse Z: sourceDepth = 1 - nativeDepth.
        if(clip.z/clip.w<texture(tDepth,suv).x-.0015) continue;
        vec3 rel=p-lightPos;
        float along=dot(rel,SUN);
        if(along<0.0) continue;
        vec3 perp=rel-SUN*along;
        float spread=5.4*(1.0+along*.028);
        float radial=length(perp);
        if(radial>spread) continue;
        float edge=1.0-smoothstep(spread*.55,spread,radial);
        float drift=.72+.28*sin(p.x*.9+time*.32+sin(p.z*.7-time*.21)*1.4);
        float mu=max(dot(dir,-SUN),0.0);
        float phase=.16+1.5*pow(mu,5.0);
        acc+=vec3(.62,.78,.84)*edge*drift*phase*dt;
    }
    // RGB ONE+ONE blending gives original base + acc*intensity without a copy
    // of the full HDR image. Scene alpha is kept by the native blend state.
    color=vec4(acc*intensity*frame.w,0.0);
}
