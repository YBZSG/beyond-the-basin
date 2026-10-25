// New reference-wing material only. UV1 is actual runtime UV in METRES;
// mesh tangents are required. Do not multiply mesh UVs by 1/repeat again.
// The separate linear bevel data contains no face micro-normal noise.
uniform sampler2D base_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bevel_slope : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm : filter_linear_mipmap_anisotropic, repeat_enable;
// Linear palette/body gains set by the runtime glaze finish.
uniform vec3 face_color_gain = vec3(1.0);
uniform vec3 grout_color_gain = vec3(1.0);
uniform float face_roughness : hint_range(0.035, 0.4) = 0.055;
uniform float grout_roughness : hint_range(0.5, 1.0) = 0.82;
// Uniform geometric material scale, not mesh UV scaling: physical pitch,
// joints, relief and crown all scale together. Default preserves ref-5.
uniform float tile_scale : hint_range(0.5, 3.0) = 1.0;
uniform float face_shape_strength : hint_range(0.0, 2.0) = 1.0;
// Profile1 provides the rounded ceramic face used by the current glaze finish.
uniform int face_profile : hint_range(0, 1) = 0;
uniform float bevel_strength : hint_range(0.0, 1.0) = 1.0;
// Explicit diagnostic/LOD input, default identity. No fake camera-distance
// ray footprint; a future measured tile-footprint policy can drive this.
uniform float resolved_shape_strength : hint_range(0.0, 1.0) = 1.0;
uniform bool planar_clip_enabled = true;
uniform vec2 source_domain_origin = vec2(0.0);
varying vec3 world_position;
varying vec3 world_geometric_normal;

#include "res://shaders/reference_wing/reference_glaze_math.gdshaderinc"
#include "res://shaders/source_water/caustic_receiver.gdshaderinc"

void vertex() {
    world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    world_geometric_normal = normalize(transpose(inverse(mat3(MODEL_MATRIX)))*NORMAL);
}

void fragment() {
    if (planar_clip_enabled && (CAMERA_VISIBLE_LAYERS & 524288u) != 0u && world_position.y < 0.318) discard;
    vec2 material_metres = UV/max(tile_scale,0.001);
    vec2 atlas_uv = material_metres/REFERENCE_REPEAT_METRES;
    vec4 channels = texture(orm,atlas_uv);
    float face = clamp(channels.a,0.0,1.0);
    ALBEDO = texture(base_color,atlas_uv).rgb*mix(grout_color_gain,face_color_gain,face);
    AO = channels.r;
    AO_LIGHT_AFFECT = 0.0;

    // Byte128 is exactly neutral. This is custom LINEAR slope data, NOT a
    // standard encoded normal and must not receive normal-map import conversion.
    vec2 edge_slope = (texture(bevel_slope,atlas_uv).rg*255.0-vec2(128.0))/127.0;
    // H_physical=s*H_base(UV/s), so dH_physical/dUV=dH_base/d(UV/s).
    // Slopes stay identical under uniform metric scaling of all dimensions.
    vec3 face_field = face_profile == 1 ? reference_ref5_crown_face_field(material_metres)
                                      : reference_face_field(material_metres);
    vec2 slope = edge_slope*bevel_strength
               - face_field.xy*face_shape_strength*resolved_shape_strength;
    vec3 tangent_normal = normalize(vec3(slope,1.0));
    NORMAL_MAP = tangent_normal*0.5+0.5;
    NORMAL_MAP_DEPTH = 1.0;

    // Keep the existing linear coverage distinction. No ALPHA/transparency,
    // roughness threshold guesses, microfacet noise or normal-amplitude gate.
    // The G map already contains coverage-weighted face/grout roughness.
    // Offset each region once from the authored .075/.82 map, including
    // anti-aliased edge pixels and the separately finished dry walkways.
    ROUGHNESS = clamp(channels.g + (face_roughness-0.075)*face
                    + (grout_roughness-0.82)*(1.0-face),0.035,1.0);
    METALLIC = 0.0;
    SPECULAR = 0.5;
    // The pinned native RT BRDF does not transport clearcoat. A single finite
    // dielectric lobe keeps both routes meaningful without a hidden dependency.
    CLEARCOAT = 0.0;
    CLEARCOAT_ROUGHNESS = 0.12;
    EMISSION = vec3(0.0);
    if (causticGain > 0.0) {
        vec3 irradiance = source_caustic_irradiance(
            world_position-vec3(source_domain_origin.x,0.0,source_domain_origin.y),
            normalize(world_geometric_normal));
        EMISSION = ALBEDO*irradiance/3.14159265359;
    }
}
