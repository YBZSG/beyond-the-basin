shader_type sky;
// Original AI-generated sky-only LDR panorama, not geometry or HDR capture.
// Explicit mapping makes the measured sun alignment reproducible in CPU previews.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float longitude_offset = -0.393173;
void sky(){vec3 d=normalize(EYEDIR);vec2 uv=vec2(atan(d.x,-d.z)/6.28318530718+.5+longitude_offset/6.28318530718,acos(clamp(d.y,-1.,1.))/3.14159265359);uv.x=fract(uv.x);float half_texel=.5/float(textureSize(panorama,0).y);uv.y=clamp(uv.y,half_texel,1.-half_texel);vec3 col=texture(panorama,uv).rgb;float edge=min(uv.x,1.-uv.x);float blend=.5*(1.-smoothstep(0.,.012,edge));col=mix(col,texture(panorama,vec2(1.-uv.x,uv.y)).rgb,blend);COLOR=col;}
