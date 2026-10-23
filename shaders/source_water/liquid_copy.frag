layout(set=0,binding=1) uniform sampler2D image;
layout(location=0) in vec2 vUv;
layout(location=0) out vec4 color;
void main(){color=texture(image,vUv);}
