layout(set=0,binding=1) uniform sampler2D image;
layout(set=0,binding=2) uniform sampler2D depthImage;
layout(location=0) in vec2 vUv;
layout(location=0) out vec4 color;
void main(){color=texture(image,vUv);gl_FragDepth=texture(depthImage,vUv).r;}
