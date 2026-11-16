shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Genuine 100mm laminated floor glazing. Only the room's real glass geometry
// uses this material. Glass top and its collider/source-depth proxy coincide.
// Ordinary alpha glass. The room-only source optical derivative bounds water
// path analytically to this exact pane/step structure, independent of copied-depth
// transparent-pass timing. Native sorting still requires target GPU validation.
uniform vec4 clear_tint : source_color = vec4(0.30,0.62,0.54,0.038);
uniform vec3 edge_tint : source_color = vec3(0.10,0.38,0.29);
uniform float pane_thickness = 0.10;
uniform float surface_roughness = 0.018;
varying vec3 world_normal;
varying vec3 receiver_world;
void vertex(){ receiver_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL); }
void fragment(){
 if((CAMERA_VISIBLE_LAYERS & 524288u)!=0u && receiver_world.y<.318)discard;
 float horizontal = abs(world_normal.y);
 float facing = clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0);
 float fresnel = 0.043 + 0.957*pow(1.0-facing,5.0);
 ALBEDO = mix(edge_tint, clear_tint.rgb, smoothstep(0.2,0.8,horizontal));
 ROUGHNESS = surface_roughness;
 METALLIC = 0.0;
 SPECULAR = 0.56;
 // Thick edge views absorb more than direct near-normal viewing through pane.
 ALPHA = mix(0.55, clamp(clear_tint.a + fresnel*0.35,0.038,0.65), smoothstep(0.2,0.8,horizontal));
}
