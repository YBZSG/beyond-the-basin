// Three.js FogExp2: fogFactor = 1 - exp(-density*density*vFogDepth*vFogDepth).
// Source engine.ts:66,71,949-952; evaluated on opaque depth before water samples it.
layout(set=0,binding=0,std140) uniform SourceDistanceFogFrame {
    mat4 inverseProjection;
    vec4 fogColorDensity; // RGB linear source #22343d; w density (not native fog density)
    vec4 viewport;        // xy size
};
#ifdef SOURCE_FOG_MSAA
layout(set=0,binding=1) uniform sampler2DMS tDepth;
#else
layout(set=0,binding=1) uniform sampler2D tDepth;
#endif
layout(location=0) in vec2 vUv;
layout(location=0) out vec4 color;
void main() {
#ifdef SOURCE_FOG_MSAA
    ivec2 pixel=ivec2(gl_FragCoord.xy);
    float depth=texelFetch(tDepth,pixel,gl_SampleID).x;
    vec2 uv=(vec2(pixel)+gl_SamplePosition)/viewport.xy;
#else
    float depth=texture(tDepth,vUv).x;
    vec2 uv=vUv;
#endif
    // Original scene.background is not a fog-receiving mesh. Leave it alone.
    if(depth<=0.0) {color=vec4(0.0);return;}
    vec4 p=inverseProjection*vec4(uv*2.0-1.0,depth,1.0);
    float fogDepth=max(0.0,-p.z/p.w);
    float density=fogColorDensity.w;
    float factor=1.0-exp(-density*density*fogDepth*fogDepth);
    // Premultiplied blend implements source mix(base,fogColor,factor), while
    // preserving native scene alpha. No framebuffer feedback/readback/copy.
    color=vec4(fogColorDensity.rgb*factor,factor);
}
