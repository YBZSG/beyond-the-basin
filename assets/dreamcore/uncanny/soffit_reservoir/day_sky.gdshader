shader_type sky;
// Scene-local candidate, same selected LDR panorama and yaw as annex_day_sky.
// Bounded authored sky radiance reaches the room only through real openings.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float radiance_gain : hint_range(1.0,8.0,1.0) = 1.0;
const float NEUTRAL_MIX=0.75;
void sky(){
 vec2 uv=vec2(atan(EYEDIR.x,EYEDIR.z)/6.28318530718+.5+.547556,acos(clamp(EYEDIR.y,-1.,1.))/3.14159265359);
 vec3 radiance=texture(panorama,uv).rgb;
 float luminance=dot(radiance,vec3(.2126,.7152,.0722));
 COLOR=mix(radiance,vec3(luminance),NEUTRAL_MIX)*clamp(radiance_gain,1.0,8.0);
}
