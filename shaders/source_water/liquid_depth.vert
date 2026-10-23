layout(set=0,binding=1,std430) readonly buffer Vertices {vec4 vertices[];};
layout(set=0,binding=2,std430) readonly buffer Instances {vec4 rows[];};
layout(location=0) out vec3 eye;
void main(){uint i=uint(gl_InstanceIndex)*3u;vec4 p=vec4(vertices[gl_VertexIndex].xyz,1.);vec3 world=vec3(dot(rows[i],p),dot(rows[i+1u],p),dot(rows[i+2u],p));vec4 e=viewMatrix*vec4(world,1.);eye=e.xyz;gl_Position=projection*e;}
