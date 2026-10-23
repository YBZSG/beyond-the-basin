// LAB ONLY, finite-proxy planar correction. Never apply without a verified room
// envelope and matching current-frame textureMatrix. No new reflection capture.
// envelopeMaxY is authored ceiling height in WORLD space (mainhall local4.8m).
// This improves angular response but is NOT true depth-traced reflection:
// columns, benches and open roof apertures remain parallax approximation.
vec2 nf_project_reflection(vec3 P,vec3 V,vec3 N,mat4 captureMatrix,
                          vec3 envelopeMin,vec3 envelopeMax,vec2 fallbackUv) {
    vec3 R=reflect(-V,N);
    if(R.y<=.005)return fallbackUv;
    // First positive hit on the verified room bounding envelope, with finite cap.
    float hit=32.0;
    for(int axis=0;axis<3;axis++) {
        if(abs(R[axis])>.0001) {
            float plane=R[axis]>0.0?envelopeMax[axis]:envelopeMin[axis];
            float candidate=(plane-P[axis])/R[axis];
            if(candidate>.02)hit=min(hit,candidate);
        }
    }
    vec4 q=captureMatrix*vec4(P+R*hit,1.0);
    if(q.w<=.001)return fallbackUv;
    return q.xy/q.w;
}
