shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Original authored material set. UV1 is metric and follows each modelled
// surface; normal mapping uses the actual exported tangent basis, not a
// screen-space emboss or a world projection across curved architectural trims.
uniform sampler2D base_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float repeat_metres = 0.8;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float dielectric_specular : hint_range(0.0, 1.0) = 0.5;
uniform bool mapped = true;
uniform vec4 constant_color : source_color = vec4(1.0);
uniform float constant_roughness = 0.85;
uniform bool planar_clip_enabled = true;
uniform vec2 source_domain_origin = vec2(0.0);
varying vec3 world_position;
varying vec3 world_geometric_normal;

#include "res://shaders/source_water/caustic_receiver.gdshaderinc"

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_geometric_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    // Same reflected-view clipping contract as existing authored receivers.
    // Water depth, collision, dynamics and capture ownership are not changed.
    if (planar_clip_enabled && (CAMERA_VISIBLE_LAYERS & 524288u) != 0u && world_position.y < 0.318) discard;
    vec2 uv = UV / max(repeat_metres, 0.001);
    vec3 channels = mapped ? texture(orm, uv).rgb : vec3(1.0, constant_roughness, 0.0);
    ALBEDO = mapped ? texture(base_color, uv).rgb : constant_color.rgb;
    NORMAL_MAP = mapped ? texture(normal_gl, uv).rgb : vec3(0.5, 0.5, 1.0);
    NORMAL_MAP_DEPTH = normal_strength;
    AO = channels.r;
    // AO is local material relief, not a baked lightmap or an albedo stain.
    AO_LIGHT_AFFECT = 0.0;
    ROUGHNESS = clamp(channels.g, 0.12, 1.0);
    METALLIC = channels.b;
    SPECULAR = dielectric_specular;
    CLEARCOAT = 0.0;
    EMISSION = vec3(0.0);
    if (causticGain > 0.0) {
        vec3 irradiance = source_caustic_irradiance(
            world_position - vec3(source_domain_origin.x, 0.0, source_domain_origin.y),
            normalize(world_geometric_normal));
        EMISSION = ALBEDO * (1.0 - METALLIC) * irradiance / 3.14159265359;
    }
}
