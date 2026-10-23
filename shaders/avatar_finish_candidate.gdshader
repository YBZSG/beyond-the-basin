shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Isolated, optional cloth candidate. Same lit PBR path, no custom light(),
// fabricated shine, emission boost, wetness guess, or extra geometry.
// Keep the original glTF PBR surface while sharing the architecture's planar
// water clip marker. Ordinary main views never set the marker and retain legs.
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo_texture = false;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_roughness_texture = false;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_metallic_texture = false;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool normal_enabled = false;
uniform float normal_scale = 1.0;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool ao_enabled = false;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform sampler2D emission_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_emission_texture = false;
uniform bool emission_enabled = false;
uniform bool emission_multiply = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool vertex_color_albedo = false;
uniform bool texture_repeat_enabled = true;
uniform int source_cull_mode = 2; // BaseMaterial3D: back=0, front=1, disabled=2.
uniform bool alpha_scissor_enabled = false;
uniform float alpha_scissor_threshold = 0.5;
// UV2 is authored in metres in avatar_finish_candidate.glb only. UV0 stays
// untouched for the original albedo. Tangents were calculated from this UV2.
uniform bool fabric_enabled = false;
uniform vec2 fabric_uv_repeat = vec2(44.6428571429);
uniform sampler2D fabric_normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fabric_normal_strength : hint_range(0.0, 1.5) = 1.0;
uniform float fabric_specular : hint_range(0.0, 1.0) = 0.30;
varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    UV = UV * uv_scale + uv_offset;
}

void fragment() {
    // Exact marker and water plane used by source_architecture.gdshader.
    if ((CAMERA_VISIBLE_LAYERS & 524288u) != 0u && world_position.y < 0.318) discard;
    if (source_cull_mode == 0 && !FRONT_FACING) discard;
    if (source_cull_mode == 1 && FRONT_FACING) discard;
    if (source_cull_mode == 2 && !FRONT_FACING) NORMAL = -NORMAL;
    vec2 surface_uv = texture_repeat_enabled ? UV : clamp(UV, vec2(0.0), vec2(1.0));
    vec4 base_color = albedo_color;
    if (has_albedo_texture) base_color *= texture(albedo_texture, surface_uv);
    if (vertex_color_albedo) base_color *= COLOR;
    if (alpha_scissor_enabled && base_color.a < alpha_scissor_threshold) discard;
    ALBEDO = base_color.rgb;
    ROUGHNESS = roughness_value;
    if (has_roughness_texture) ROUGHNESS *= dot(texture(roughness_texture, surface_uv), roughness_channel);
    METALLIC = metallic_value;
    if (has_metallic_texture) METALLIC *= dot(texture(metallic_texture, surface_uv), metallic_channel);
    SPECULAR = specular_value;
    if (normal_enabled) {
        NORMAL_MAP = texture(normal_texture, surface_uv).rgb;
        NORMAL_MAP_DEPTH = normal_scale;
    }
    if (fabric_enabled) {
        vec2 fabric_uv = UV2 * fabric_uv_repeat;
        // Scale in Blender's metre UV space, then apply the glTF V flip once.
        // This offset preserves the editable source's phase, not just density.
        fabric_uv.y += 1.0 - fabric_uv_repeat.y;
        NORMAL_MAP = texture(fabric_normal_texture, fabric_uv).rgb;
        NORMAL_MAP_DEPTH = fabric_normal_strength;
        ROUGHNESS = texture(fabric_roughness_texture, fabric_uv).r;
        SPECULAR = fabric_specular;
    }
    if (ao_enabled) {
        AO = dot(texture(ao_texture, surface_uv), ao_channel);
        AO_LIGHT_AFFECT = ao_light_affect;
    }
    if (emission_enabled) {
        vec3 emitted = emission_color;
        if (has_emission_texture) {
            vec3 mapped_emission = texture(emission_texture, surface_uv).rgb;
            emitted = emission_multiply ? emitted * mapped_emission : emitted + mapped_emission;
        }
        EMISSION = emitted * emission_energy;
    }
}
