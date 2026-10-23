// Original attachReceiver irradiance mapping, water-system.ts lines 312-344.
// Supply position and normal in the same local/floating-origin coordinates as the solver.
uniform sampler2D poolCaustics : filter_linear_mipmap, repeat_disable;
uniform sampler2D poolCausticsWalls : filter_linear_mipmap, repeat_disable;
uniform float causticGain = 1.5;
// PC_NEARFIELD_BEGIN
uniform float pcNearfieldFloorMipBias = 1.15;
// PC_NEARFIELD_END
// Optional authored-room half-extents, X then Z. Defaults preserve source ±15.7.
uniform vec2 reflectedWallExtents = vec2(15.7);
uniform vec2 transmittedWallExtents = vec2(15.7);
vec3 source_caustic_irradiance(vec3 p, vec3 wnr) {
    // Disabled during material/lightmap extraction: never sample unavailable
    // HDR targets and rely on 0*NaN. Every nonzero-gain path remains unchanged.
    if(causticGain==0.0) return vec3(0.0);
    vec3 irradiance=vec3(0.0);
    if(wnr.y>.5) {
        vec2 causticUv=p.xz/32.0+.5;
        if(p.y<.25&&p.y>-.8&&all(greaterThan(causticUv,vec2(0.0)))&&all(lessThan(causticUv,vec2(1.0)))) {
            float edgeFade=smoothstep(0.0,.04,min(min(causticUv.x,causticUv.y),min(1.0-causticUv.x,1.0-causticUv.y)));
            irradiance+=texture(poolCaustics,causticUv,pcNearfieldFloorMipBias).rgb*causticGain*max(wnr.y,0.0)*edgeFade;
        }
    } else if(abs(wnr.y)<.45&&p.y>-.75&&p.y<14.5) {
        // Preserve the original source expression exactly when using defaults.
        float ex=abs(15.7-abs(p.x)),ez=abs(15.7-abs(p.z));
        // A submerged receiver belongs to the basin; a receiver above the
        // water plane belongs to the outer room. Columns/other walls away
        // from these specific planes retain zero caustic membership.
        vec2 extents=p.y<.32?transmittedWallExtents:reflectedWallExtents;
        if(any(notEqual(extents,vec2(15.7)))) {
            ex=abs(extents.x-abs(p.x));ez=abs(extents.y-abs(p.z));
        }
        float wallId=ex<ez?(p.x>0.0?0.0:1.0):(p.z>0.0?2.0:3.0);
        float nearWall=1.0-smoothstep(.02,.08,ex<ez?ex:ez);
        float u=((ex<ez?p.z:p.x)+16.0)/32.0;
        float v=clamp((p.y+.75)/15.25,0.0,1.0);
        float uEdge=smoothstep(0.0,.025,u)*(1.0-smoothstep(.975,1.0,u));
        float vEdge=smoothstep(0.0,.002,v)*(1.0-smoothstep(.998,1.0,v));
        irradiance+=texture(poolCausticsWalls,vec2(u,(wallId+v)*.25),1.15).rgb*causticGain*nearWall*uEdge*vEdge;
    }
    return irradiance;
}
