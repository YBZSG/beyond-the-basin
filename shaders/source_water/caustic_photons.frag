// Source water-system.ts fragment derivative area Jacobian, not a fake wave pattern.
layout(location=0) in vec2 sourcePoint;
layout(location=1) in float powerAtSurface;
layout(location=2) in vec2 wallCell;
layout(location=0) out vec4 fragColor;
void main() {
    bool wall=passData.z>.5;
    if(wall&&(wallCell.x<.015||wallCell.x>.985||wallCell.y<.001||wallCell.y>.999)) discard;
    vec2 dx=dFdx(sourcePoint),dy=dFdy(sourcePoint);
    float sourceArea=abs(dx.x*dy.y-dx.y*dy.x);
    float receiverArea=wall?32.0*15.25/(causticResolution*causticResolution*.25):32.0*32.0/(causticResolution*causticResolution);
    float focus=clamp(sourceArea/receiverArea,0.0,9.0);
    float visibility=passData.w<.5?texture(visibilityMap0,sourcePoint/32.0+.5).r:texture(visibilityMap1,sourcePoint/32.0+.5).r;
    float fade=1.0;
    if(wall) fade=smoothstep(0.0,.03,wallCell.x)*(1.0-smoothstep(.97,1.0,wallCell.x))*smoothstep(0.0,.002,wallCell.y)*(1.0-smoothstep(.998,1.0,wallCell.y));
    float light=focus*powerAtSurface*visibility*fade;
    fragColor=vec4(vec3(light)*vec3(.73,.91,1.0),1.0);
}
