shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
uniform vec4 pigment : source_color = vec4(.035,.05,.045,1.0);
varying vec3 world_position;
void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    // Match the room's mirror-camera water plane. Underwater joint backing
    // must not appear as dark bars in the above-water planar reflection.
    if ((CAMERA_VISIBLE_LAYERS & 524288u)!=0u && world_position.y<.318) discard;
    ALBEDO=pigment.rgb;
    ROUGHNESS=1.0;
    SPECULAR=0.0;
}
