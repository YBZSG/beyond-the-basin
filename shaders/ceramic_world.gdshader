shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Original analytic PBR atlas, NOT a measured scan. Historical uniform names
// remain compatible with the material library. 16 tiles / 1.6 m = 100 mm pitch.
uniform sampler2D scan_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 pigment : source_color = vec4(0.459, 0.678, 0.698, 1.0);
uniform vec4 grout_pigment : source_color = vec4(0.63, 0.68, 0.67, 1.0);
uniform float repeat_metres : hint_range(0.25, 8.0) = 1.6;
uniform float face_roughness : hint_range(0.1, 0.9) = 0.34;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.82;
uniform float coat_strength : hint_range(0.0, 1.0) = 0.20;
uniform float water_exposure : hint_range(0.0, 1.0) = 0.0;
uniform float waterline_metres = 0.32;
uniform bool tile_face_only = false;
// Explicit expanded wet-module opt-in. This is a local roughness / thin-film
// approximation, NOT geometric fluid puddles or a second water simulation.
uniform bool local_wet_finish_enabled = false;
uniform float local_wet_finish_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec2 local_wet_room_origin = vec2(0.0);
uniform float local_wet_deck_y = 0.52;
uniform float local_wet_water_y = 0.32;
// Exact four authored basin bounds: abs(local x/z) in [3, 10] metres.
uniform vec2 local_wet_basin_range = vec2(3.0, 10.0);
// Opt-in PC candidate. Original/source material roles never enable this.
// Exact cardinal normals need one projection, not all three.
uniform bool projection_fast_path = false;
// Live gameplay/reflection materials keep clipping enabled. Native UV2 bake
// instances opt out because a material extraction is not a reflected camera.
uniform bool planar_clip_enabled = true;
uniform bool upper_plaster = false;
uniform float dado_height = 2.9;
uniform vec4 plaster_pigment : source_color = vec4(0.894, 0.890, 0.871, 1.0);

#include "res://shaders/source_water/caustic_receiver.gdshaderinc"
uniform vec2 source_domain_origin=vec2(0.0);
varying vec3 world_position;
varying vec3 geometric_world_normal;

vec3 unpack_normal(vec2 rg) {
    // Godot may use BC5 and discard B. OpenGL +Y; never invert green.
    vec2 xy = rg * 2.0 - 1.0;
    return vec3(xy, sqrt(max(0.0025, 1.0-dot(xy,xy))));
}

// Signed distance to the actual four rectangular basins. No atlas UVs or
// tile-frequency noise: one coherent mask in room-local world metres.
vec2 expanded_local_wet_masks(vec3 point, vec3 normal) {
    vec2 p = point.xz - local_wet_room_origin;
    float center = (local_wet_basin_range.x + local_wet_basin_range.y) * 0.5;
    float half_size = (local_wet_basin_range.y - local_wet_basin_range.x) * 0.5;
    vec2 q = abs(abs(p) - vec2(center)) - vec2(half_size);
    float basin_distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
    // Broad, fixed, non-tile-aligned variation, wavelengths 6-15 metres.
    // Three analytic waves only modulate coverage, never animate normals,
    // illumination, colour fringe or caustics.
    float broad = 0.5 + 0.23 * sin(dot(p, vec2(0.73, 0.39)))
                      + 0.19 * sin(dot(p, vec2(-0.31, 0.81)) + 0.9)
                      + 0.08 * sin(dot(p, vec2(0.47, -0.61)) + 1.7);
    float upright = smoothstep(0.75, 0.98, normal.y);
    float deck_height = 1.0 - smoothstep(0.012, 0.032, abs(point.y - local_wet_deck_y));
    float outside_basin = smoothstep(-0.02, 0.0, basin_distance);
    float width = 0.40 + 0.65 * broad;
    float edge_film = 1.0 - smoothstep(0.06, width, max(basin_distance, 0.0));
    float patches = smoothstep(0.38, 0.68, broad);
    float film = 0.92 * upright * deck_height * outside_basin * edge_film * patches;
    float rim_damp = upright * deck_height * outside_basin
                   * (1.0 - smoothstep(0.10, 1.30, basin_distance));
    float vertical = 1.0 - smoothstep(0.12, 0.40, abs(normal.y));
    // Narrow transition on true basin sides at the existing .32 m waterline.
    float waterline = vertical * (1.0 - smoothstep(0.018, 0.08, abs(basin_distance)))
                    * smoothstep(local_wet_water_y - 0.08, local_wet_water_y - 0.015, point.y)
                    * (1.0 - smoothstep(local_wet_water_y + 0.025, local_wet_water_y + 0.20, point.y));
    // Restrained capillary/splash damp at tiled wall/bench feet, never plaster
    // or an elevated seat. Only within 1.65 m of one of the real basins.
    float foot = vertical * smoothstep(local_wet_deck_y - 0.02, local_wet_deck_y, point.y)
               * (1.0 - smoothstep(local_wet_deck_y + 0.035, local_wet_deck_y + 0.18, point.y))
               * (1.0 - smoothstep(0.75, 1.65, max(basin_distance, 0.0))) * outside_basin;
    return vec2(film, max(0.80 * rim_damp, max(0.65 * waterline, 0.55 * foot)));
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    geometric_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    if(planar_clip_enabled && (CAMERA_VISIBLE_LAYERS & 524288u)!=0u && world_position.y<0.318) discard;
    vec3 n = normalize(geometric_world_normal);
    vec3 weights = pow(abs(n), vec3(8.0));
    weights /= max(dot(weights,vec3(1.0)),0.00001);
    vec3 s = mix(vec3(-1.0),vec3(1.0),step(vec3(0.0),n));
    vec3 p = world_position / max(repeat_metres,0.001);
    vec2 uv_x = p.zy * vec2(-s.x,1.0);
    vec2 uv_y = p.xz * vec2(1.0,-s.y);
    vec2 uv_z = p.xy * vec2(s.z,1.0);

    vec3 color_map;
    vec3 surface;
    vec3 nx;
    vec3 ny;
    vec3 nz;
    if (projection_fast_path) {
        // The material uniform is coherent across a quad. Compute all UV
        // derivatives before any per-fragment cardinal selection; implicit
        // derivatives in a divergent texture branch would be undefined.
        vec2 uv_x_dx = dFdx(uv_x), uv_x_dy = dFdy(uv_x);
        vec2 uv_y_dx = dFdx(uv_y), uv_y_dy = dFdy(uv_y);
        vec2 uv_z_dx = dFdx(uv_z), uv_z_dy = dFdy(uv_z);
        bool cardinal_x = weights.x == 1.0 && weights.y == 0.0 && weights.z == 0.0;
        bool cardinal_y = weights.y == 1.0 && weights.x == 0.0 && weights.z == 0.0;
        bool cardinal_z = weights.z == 1.0 && weights.x == 0.0 && weights.y == 0.0;
        if (cardinal_x || cardinal_y || cardinal_z) {
            vec2 uv = cardinal_x ? uv_x : (cardinal_y ? uv_y : uv_z);
            vec2 dx = cardinal_x ? uv_x_dx : (cardinal_y ? uv_y_dx : uv_z_dx);
            vec2 dy = cardinal_x ? uv_x_dy : (cardinal_y ? uv_y_dy : uv_z_dy);
            color_map = textureGrad(scan_albedo, uv, dx, dy).rgb;
            surface = textureGrad(scan_roughness, uv, dx, dy).rgb;
            vec3 mapped_projection = unpack_normal(textureGrad(scan_normal, uv, dx, dy).rg);
            nx = cardinal_x ? mapped_projection : vec3(0.0, 0.0, 1.0);
            ny = cardinal_y ? mapped_projection : vec3(0.0, 0.0, 1.0);
            nz = cardinal_z ? mapped_projection : vec3(0.0, 0.0, 1.0);
        } else {
            // Every non-cardinal fragment retains the full authored blend,
            // including narrow bevels. No threshold/pop at near-cardinal angles.
            color_map = textureGrad(scan_albedo,uv_x,uv_x_dx,uv_x_dy).rgb*weights.x
                       +textureGrad(scan_albedo,uv_y,uv_y_dx,uv_y_dy).rgb*weights.y
                       +textureGrad(scan_albedo,uv_z,uv_z_dx,uv_z_dy).rgb*weights.z;
            surface = textureGrad(scan_roughness,uv_x,uv_x_dx,uv_x_dy).rgb*weights.x
                      +textureGrad(scan_roughness,uv_y,uv_y_dx,uv_y_dy).rgb*weights.y
                      +textureGrad(scan_roughness,uv_z,uv_z_dx,uv_z_dy).rgb*weights.z;
            nx = unpack_normal(textureGrad(scan_normal,uv_x,uv_x_dx,uv_x_dy).rg);
            ny = unpack_normal(textureGrad(scan_normal,uv_y,uv_y_dx,uv_y_dy).rg);
            nz = unpack_normal(textureGrad(scan_normal,uv_z,uv_z_dx,uv_z_dy).rg);
        }
    } else {
        // Reference route stays byte-for-byte in its texture expressions.
        color_map = texture(scan_albedo,uv_x).rgb*weights.x
                   +texture(scan_albedo,uv_y).rgb*weights.y
                   +texture(scan_albedo,uv_z).rgb*weights.z;
        surface = texture(scan_roughness,uv_x).rgb*weights.x
                  +texture(scan_roughness,uv_y).rgb*weights.y
                  +texture(scan_roughness,uv_z).rgb*weights.z;
        nx=unpack_normal(texture(scan_normal,uv_x).rg);
        ny=unpack_normal(texture(scan_normal,uv_y).rg);
        nz=unpack_normal(texture(scan_normal,uv_z).rg);
    }
    // Coverage is an explicitly authored linear mask. Mip filtering integrates
    // the real 3.6% grout area instead of guessing it from a roughness threshold.
    float face = tile_face_only ? 1.0 : surface.b;
    float grout = 1.0-face;
    float footprint = max(length(dFdx(world_position)),length(dFdy(world_position)));
    float detail = 1.0-smoothstep(0.012,0.060,footprint);
    float wet = (1.0-smoothstep(waterline_metres,waterline_metres+0.23,world_position.y))*water_exposure;
    // sRGB atlas samples arrive in linear space. Decode the two authored
    // reference values the same way before extracting small glaze variation.
    vec3 reference = vec3(mix(0.53824,0.82757,surface.b));
    vec3 modulation = clamp(color_map/max(reference,vec3(0.001)),vec3(0.965),vec3(1.035));
    if (tile_face_only) modulation=vec3(1.0);
    // Uniform-coherent branch: disabled roles retain the original material math.
    vec2 local_wet = vec2(0.0);
    if (local_wet_finish_enabled && local_wet_finish_strength > 0.0) local_wet = expanded_local_wet_masks(world_position, n) * local_wet_finish_strength;
    vec3 ceramic = pigment.rgb*modulation*(1.0-0.025*wet);
    vec3 mortar = grout_pigment.rgb*(1.0-0.055*wet);
    if (local_wet_finish_enabled && local_wet_finish_strength > 0.0) {
        ceramic *= 1.0 - 0.030 * local_wet.y;
        mortar *= 1.0 - 0.100 * local_wet.y;
    }
    float plaster_mask=upper_plaster?smoothstep(dado_height-0.012,dado_height+0.012,world_position.y):0.0;
    ALBEDO=mix(mix(mortar,ceramic,face),plaster_pigment.rgb,plaster_mask);

    float batch=(surface.g-.5)*2.0;
    float glaze=clamp(face_roughness*0.025+0.04+batch*.003-wet*.008,0.04,0.065);
    float rough=mix(glaze,0.82-wet*.12,grout);
    if (local_wet_finish_enabled && local_wet_finish_strength > 0.0) {
        // Porous joints remain substantially rougher than glazed faces.
        float film_roughness = mix(0.06, 0.68, grout);
        float damp_roughness = mix(0.025, 0.075, grout);
        rough = mix(max(rough - damp_roughness * local_wet.y, mix(0.06, 0.65, grout)), film_roughness, local_wet.x);
    }
    vec3 perturbation=vec3(0.0,nx.y,-s.x*nx.x)*weights.x
                     +vec3(ny.x,0.0,-s.y*ny.y)*weights.y
                     +vec3(s.z*nz.x,nz.y,0.0)*weights.z;
    perturbation-=n*dot(n,perturbation);
    // Strong authored joint/bevel normals, quiet glossy tile interiors.
    float bevel_normal=smoothstep(0.025,0.14,length(perturbation));
    perturbation*=normal_strength*mix(0.08,1.0,bevel_normal)*detail*(1.0-plaster_mask)*(tile_face_only?0.0:1.0);
    vec3 mapped=normalize(n+perturbation);
    NORMAL=normalize((VIEW_MATRIX*vec4(mapped,0.0)).xyz);
    // Specular antialiasing only reacts to normal-map variation, not the true
    // curvature of modelled nosings. Distant ceramic retains broad calm gloss.
    vec3 dx=dFdx(mapped)-dFdx(n);
    vec3 dy=dFdy(mapped)-dFdy(n);
    float variance=min(0.00012,0.05*(dot(dx,dx)+dot(dy,dy)));
    ROUGHNESS=mix(clamp(pow(pow(rough,4.0)+variance,0.25),0.04,0.95),0.84,plaster_mask);
    METALLIC=0.0;
    SPECULAR=mix(mix(0.5,0.34,grout),0.32,plaster_mask);
    CLEARCOAT=(coat_strength+wet*.06)*face*(1.0-plaster_mask);
    CLEARCOAT_ROUGHNESS=0.08;
    if (local_wet_finish_enabled && local_wet_finish_strength > 0.0) {
        // Godot 4.6.3: dielectric F0 = .16 * SPECULAR^2. Air/water
        // IOR 1.333 gives F0=.020373; SPECULAR=.356837. Blend in F0,
        // not in IOR. This single-lobe approximation is not layered optics.
        float water_specular = 0.35683669;
        SPECULAR = sqrt(mix(SPECULAR * SPECULAR, water_specular * water_specular, local_wet.x));
        // Do NOT use fixed-IOR clearcoat as a pretend water layer or add energy.
        CLEARCOAT *= 1.0 - local_wet.x;
    }
    // Exact existing receiver: no artificial albedo illumination or baked
    // caustic pattern, and no changes to the source water implementation.
    // Disabled dynamic irradiance is exactly zero. Do not sample unbound
    // caustic inputs and multiply the result by zero during native UV2 baking.
    // Assign rather than accumulate so this channel is defined in every pass.
    EMISSION=vec3(0.0);
    if(causticGain>0.0) {
        EMISSION=ALBEDO*source_caustic_irradiance(world_position-vec3(source_domain_origin.x,0.0,source_domain_origin.y),n)/3.14159265359;
    }
}
