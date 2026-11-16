shader_type spatial;
render_mode cull_disabled;
uniform vec4 deep_color:source_color=vec4(.025,.34,.42,1.);
uniform float surface_roughness=.14;
uniform float emission_scale=.48;
varying vec3 p;
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 float wave=sin(p.x*.36+sin(p.y*.5)+TIME*.12)*sin(p.y*.68+p.x*.2-TIME*.09);
 float caustic=pow(max(0.,1.-abs(wave)*9.),3.);
 float shaft=pow(.5+.5*sin(p.x*.23+sin(p.y*.08)),7.);
 ALBEDO=deep_color.rgb+vec3(.02,.14,.14)*shaft+vec3(.13,.35,.33)*caustic;
 EMISSION=ALBEDO*emission_scale;ROUGHNESS=surface_roughness;METALLIC=.06;
}
