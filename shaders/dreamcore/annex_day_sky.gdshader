shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// Image sun u=.742; source yaw=-110deg -> u=.194444. Offset aligns both.
void sky(){
 vec2 uv=vec2(atan(EYEDIR.x,EYEDIR.z)/6.28318530718+.5+.547556,acos(clamp(EYEDIR.y,-1.,1.))/3.14159265359);
 COLOR=texture(panorama,uv).rgb;
}
