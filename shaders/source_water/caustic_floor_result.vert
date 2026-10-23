
struct PhotonResult { vec4 position; vec4 powerCell; };
layout(set=0,binding=9,std430) readonly buffer PhotonResults {
    ivec4 photonResultShape; // floor vertex count, wall vertex count, reserved
    PhotonResult photonResults[];
};
int photonResultOffset() {
    if(passData.z<.5) return int(passData.w)*photonResultShape.x;
    return 2*photonResultShape.x+(int(passData.w)*8+int(wallData.w)*2+int(passData.x))*photonResultShape.y;
}
// The host inserts caustic_uniforms.glslinc, shared_waves.glslinc and caustic_bvh.glslinc.
struct WaveSample { vec4 pointHeight; vec4 normal; };
layout(set=0,binding=8,std430) readonly buffer WaveSamples { WaveSample waveSamples[]; };
layout(location=0) out vec2 sourcePoint;
layout(location=1) out float powerAtSurface;
layout(location=2) out vec2 wallCell;
void main() {
    int segments=int(passData.y);
    int row=gl_VertexIndex/(segments+1), column=gl_VertexIndex%(segments+1);
    // Same indexed PlaneGeometry lattice/diagonal as Three.js, not point splats.
    vec2 p=vec2(float(column),float(row))/float(segments)*32.0-16.0;
    if(passData.z<.5) p.y=-p.y;
    // PC_NEARFIELD_BEGIN
    p=pcNearfieldEmissionPoint(p);
    // PC_NEARFIELD_END
    if(receiverData.y>1.5) {
        PhotonResult cachedPhoton=photonResults[photonResultOffset()+gl_VertexIndex];
        sourcePoint=p;
        powerAtSurface=cachedPhoton.powerCell.x;
        wallCell=cachedPhoton.powerCell.yz;
        gl_Position=cachedPhoton.position;
        return;
    }
    float height;
    vec3 n;
    if(receiverData.y>.5) {
        WaveSample cached=waveSamples[int(receiverData.z)+gl_VertexIndex];
        height=cached.pointHeight.z;
        n=cached.normal.xyz;
    } else {
        height=.32+poolSurfaceHeight(p);
        n=poolNormal(p);
        // PC_NEARFIELD_BEGIN
        if(pcNearfieldPhotonActive()){
            vec3 detail=pcNearfieldPhotonSample(p);
            height+=detail.x;
            n=normalize(vec3(-simulationSlope(p)-detailSlope(p)-detail.yz,1.0).xzy);
        }
        // PC_NEARFIELD_END
    }
    vec3 S=vec3(p.x,height,p.y);
    vec3 incoming=normalize(S-lampPosition);
    vec3 transmitted=passData.x>.5?reflect(incoming,n):refract(incoming,n,1.0/1.333);
    sourcePoint=p;
    float distance2=dot(S-lampPosition,S-lampPosition);
    if(passData.z<.5) {
        float bed=.32-poolRestDepth(p);
        vec2 receiver=p+transmitted.xz*((bed-height)/transmitted.y);
        bed=.32-poolRestDepth(receiver);
        receiver=p+transmitted.xz*((bed-height)/transmitted.y);
        powerAtSurface=lampPower/(distance2+1.0)*max(dot(-incoming,n),0.0)*.98*exp(-.11*max(height-bed,0.0));
        receiver=clamp(receiver,vec2(-16.0),vec2(16.0));
        powerAtSurface*=waterRayVisible(S,transmitted,length(vec3(receiver.x,bed,receiver.y)-S));
        wallCell=vec2(0.0);
        // Vulkan viewport maps -1 to row 0: keeps world -Z at texture v=0.
        gl_Position=vec4(receiver.x/16.0,receiver.y/16.0,0.0,1.0);
    } else {
        vec3 wallNormal=wallData.xyz;
        float denom=dot(transmitted,wallNormal);
        float t=abs(denom)>1e-5?(receiverData.x-dot(S,wallNormal))/denom:-1.0;
        vec3 R=t>0.0&&t<64.0?S+transmitted*t:S;
        float u=((abs(wallNormal.x)>.5?R.z:R.x)+16.0)/32.0;
        float v=(R.y+.75)/15.25;
        wallCell=vec2(u,v);
        float fresnel=.02037+.97963*pow(1.0-max(dot(-incoming,n),0.0),5.0);
        float throughput=passData.x>.5?fresnel:(1.0-fresnel)*exp(-.18*max(t,0.0));
        powerAtSurface=t>0.0&&t<64.0?lampPower/(distance2+1.0)*max(dot(-incoming,n),0.0)*throughput:0.0;
        // Invalid wall intersections have exactly zero transport in the source.
        // Avoid traversing its full BVH for these rays; projection is unchanged.
        if(receiverData.w<.5||(t>0.0&&t<64.0))
            powerAtSurface*=waterRayVisible(S,transmitted,max(t,0.0));
        gl_Position=vec4(u*2.0-1.0,(wallData.w+v)*.5-1.0,0.0,1.0);
    }
}
