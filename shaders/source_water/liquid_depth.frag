layout(location=0) in vec3 eye;
layout(location=0) out vec4 color;
void main(){color=vec4(-eye.z,0.,0.,1.);}
