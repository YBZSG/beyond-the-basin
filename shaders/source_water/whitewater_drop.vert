layout(set=0,binding=1,std430) readonly buffer Vertices {vec4 vertices[];};
layout(set=0,binding=2,std430) readonly buffer Instances {vec4 rows[];};
layout(location=0) out vec3 eye;
layout(location=1) out vec3 eyeNormal;
layout(location=2) out float dropDiameter;
void main(){uint i=uint(gl_InstanceIndex)*3u;vec3 vertex=vertices[gl_VertexIndex].xyz;vec4 p=vec4(vertex,1.);
 vec3 world=vec3(dot(rows[i],p),dot(rows[i+1u],p),dot(rows[i+2u],p));
 mat3 model=transpose(mat3(rows[i].xyz,rows[i+1u].xyz,rows[i+2u].xyz));
 eyeNormal=transpose(inverse(mat3(viewMatrix)*model))*normalize(vertex);
 dropDiameter=length(model[0])*2.;vec4 e=viewMatrix*vec4(world,1.);eye=e.xyz;gl_Position=projection*e;
}
