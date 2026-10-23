// Analytic optical wind layer. Physical source solver fields remain untouched.
// Each mode is (wavevector.x, wavevector.z, relief metres, integrated phase).
// Default-off shader guarantees legacy resources without a controller stay exact.
uniform vec4 windModes[3];
uniform float windOpticsActive = 0.0;
vec2 windOpticalSlope(vec2 worldP, float footprint, float depth){
    if(windOpticsActive<.5)return vec2(0.0);
    vec2 slope=vec2(0.0);
    float shore=smoothstep(.015,.12,depth);
    for(int i=0;i<3;i++){
        vec4 mode=windModes[i];
        float fade=1.0-smoothstep(.7,2.4,max(footprint,0.0)*length(mode.xy));
        slope+=mode.xy*(mode.z*fade*shore)*cos(dot(worldP,mode.xy)+mode.w);
    }
    return slope;
}
