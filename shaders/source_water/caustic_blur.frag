layout(set=0,binding=0) uniform sampler2D source;
layout(push_constant,std430) uniform BlurPass { vec4 blurData; }; // step xy, strips, mip-copy
layout(location=0) in vec2 vUv;
layout(location=0) out vec4 fragColor;
vec3 sampleLight(vec2 uv) {
    float lo=floor(vUv.y*blurData.z)/blurData.z;
    uv.y=clamp(uv.y,lo+.00025,lo+1.0/blurData.z-.00025);
    return textureLod(source,uv,0.0).rgb;
}
void main() {
    if(blurData.w>.5) { fragColor=textureLod(source,vUv,0.0); return; }
    vec3 c=sampleLight(vUv)*.227027;
    c+=(sampleLight(vUv+blurData.xy*1.384615)+sampleLight(vUv-blurData.xy*1.384615))*.316216;
    c+=(sampleLight(vUv+blurData.xy*3.230769)+sampleLight(vUv-blurData.xy*3.230769))*.070270;
    fragColor=vec4(c,1.0);
}
