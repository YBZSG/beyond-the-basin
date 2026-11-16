shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// Image sun u=.742; source yaw=-110deg -> u=.194444. Offset aligns both.
// Explicit room-only daylight authority; original panorama/yaw and global sky unchanged.
const float SCENE_RADIANCE_GAIN = 8.0;
const float SCENE_NEUTRAL_MIX = 0.75;
void sky(){
 vec2 uv=vec2(atan(EYEDIR.x,EYEDIR.z)/6.28318530718+.5+.547556,acos(clamp(EYEDIR.y,-1.,1.))/3.14159265359);
 vec3 sky_color=texture(panorama,uv).rgb;
 float luma=dot(sky_color,vec3(0.2126,0.7152,0.0722));
 COLOR=mix(sky_color,vec3(luma),SCENE_NEUTRAL_MIX) * SCENE_RADIANCE_GAIN;
}
