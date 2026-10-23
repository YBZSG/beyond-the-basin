shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, fog_disabled;

// Godot copies the opaque HDR color before this transparent pass. We never
// read a texture attached to the target currently being drawn, nor insert this
// material into its own depth prepass / ReflectionProbe capture.
uniform sampler2D opaque_color : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D opaque_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D water_state : filter_linear, repeat_disable;
uniform vec2 room_center = vec2(0.0);
uniform float simulation_resolution = 32.0;
uniform float water_level = 0.32;
uniform float pool_floor = -0.78;
uniform float water_time = 0.0;
uniform vec4 impacts[32]; // world X, world Z, birth time, pressure
uniform int impact_count = 0;
uniform float wave_height : hint_range(0.0, 2.0) = 1.0;
uniform float ripple_gain : hint_range(0.0, 3.0) = 1.0;
uniform float micro_strength : hint_range(0.0, 2.0) = 0.65;
uniform float normal_boost : hint_range(0.5, 2.0) = 1.0;
uniform float refraction_strength : hint_range(0.0, 2.0) = 0.7;
uniform float absorption_strength : hint_range(0.0, 3.0) = 0.7;
uniform float reflection_strength : hint_range(0.0, 1.5) = 1.0;
uniform float caustics_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
uniform float surface_roughness : hint_range(0.01, 0.4) = 0.075;
uniform bool caustics_enabled = true;
uniform bool ssr_enabled = true;
uniform bool refraction_enabled = true;
uniform int trace_steps : hint_range(4, 24) = 14;
uniform int debug_view : hint_range(0, 8) = 0;
varying vec3 water_world;

vec2 state_uv(vec2 p) {
	// Interior texel centres sit a half-cell from room edges. Halo cells use
	// neighbouring rooms, which keeps central differences continuous at doors.
	vec2 cell = (p - room_center + vec2(16.0)) / 32.0 * simulation_resolution + vec2(1.0);
	return cell / (simulation_resolution + 2.0);
}

float ambient_height(vec2 p) {
	return sin(dot(p, vec2(0.71, 0.43)) + water_time * 0.57) * 0.007
		+ sin(dot(p, vec2(-0.35, 1.17)) - water_time * 0.43) * 0.0035
		+ sin(dot(p, vec2(1.8, -0.67)) + water_time * 0.71) * 0.0015;
}

vec3 ripple_field(vec2 p) {
	vec3 result = vec3(0.0); // height, dheight/dx, dheight/dz
	for (int i = 0; i < 32; i++) {
		if (i >= impact_count) { break; }
		vec4 impact = impacts[i];
		float age = water_time - impact.z;
		if (age < 0.0 || age > 5.5) { continue; }
		vec2 offset = p - impact.xy;
		float distance_to_source = length(offset);
		float front = distance_to_source - age * 2.35;
		if (abs(front) > 1.2 || distance_to_source < 0.02) { continue; }
		float envelope = exp(-front * front * 5.8 - age * 0.72) / sqrt(1.0 + distance_to_source);
		float phase = front * 14.0;
		float amp = impact.w * 0.012 * ripple_gain;
		float h = sin(phase) * envelope * amp;
		float derivative = (cos(phase) * 14.0 - sin(phase) * front * 11.6 - sin(phase) * 0.5 / (1.0 + distance_to_source)) * envelope * amp;
		result += vec3(h, offset / distance_to_source * derivative);
	}
	return result;
}

vec2 ambient_slope(vec2 p) {
	return vec2(0.71, 0.43) * cos(dot(p, vec2(0.71, 0.43)) + water_time * 0.57) * 0.007
		+ vec2(-0.35, 1.17) * cos(dot(p, vec2(-0.35, 1.17)) - water_time * 0.43) * 0.0035
		+ vec2(1.8, -0.67) * cos(dot(p, vec2(1.8, -0.67)) + water_time * 0.71) * 0.0015;
}

vec2 micro_slope(vec2 p, float footprint) {
	vec2 k1 = vec2(8.1, 5.7);
	vec2 k2 = vec2(-20.3, 27.1);
	float broad_band = 1.0 - smoothstep(0.7, 2.4, footprint * length(k1));
	float fine_band = 1.0 - smoothstep(0.7, 2.4, footprint * length(k2));
	float phase = sin(dot(p, vec2(0.47, -0.31)) + water_time * 0.024) * 0.35;
	return (k1 * cos(dot(p, k1) + water_time * 0.108 + phase) * 0.0002 * broad_band
		+ k2 * cos(dot(p, k2) - water_time * 0.066) * 0.000045 * fine_band) * micro_strength;
}

// Forward+/Mobile reverse-Z NDC is [0,1]. Compatibility uses [-1,1].
// Never use the old OpenGL depth*2-1 conversion in a Forward+ shader.
bool has_receiver(float raw_depth) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return raw_depth < 0.999999;
#else
	return raw_depth > 0.000001;
#endif
}

vec3 view_position(vec2 uv, float raw_depth, mat4 inverse_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
#endif
	vec4 position = inverse_projection * vec4(ndc, 1.0);
	return position.xyz / position.w;
}

vec2 project_view(vec3 position, mat4 projection) {
	vec4 clip = projection * vec4(position, 1.0);
	return clip.xy / max(clip.w, 0.0001) * 0.5 + 0.5;
}

bool inside_screen(vec2 uv) {
	return all(greaterThan(uv, vec2(0.002))) && all(lessThan(uv, vec2(0.998)));
}

vec3 absorbed(vec3 radiance, float travel) {
	vec3 transmission = exp(-vec3(0.11, 0.033, 0.021) * absorption_strength * travel);
	return radiance * transmission + vec3(0.13, 0.29, 0.30) * (1.0 - transmission) * 0.24;
}

// A finite refracted ray, not merely a normal-driven UV wobble. It only
// accepts opaque receivers below this surface and behind this water fragment.
vec4 trace_transmission(vec3 origin, vec3 direction, mat4 projection, mat4 inverse_projection, mat4 inverse_view, float max_travel) {
	float previous_t = 0.025;
	for (int i = 1; i <= 24; i++) {
		if (i > trace_steps) { break; }
		float t = max_travel * pow(float(i) / float(trace_steps), 1.3);
		vec3 point = origin + direction * t;
		vec2 uv = project_view(point, projection);
		if (!inside_screen(uv)) { break; }
		float raw = textureLod(opaque_depth, uv, 0.0).r;
		vec3 receiver = view_position(uv, raw, inverse_projection);
		if (has_receiver(raw) && point.z <= receiver.z) {
			float lo = previous_t;
			float hi = t;
			for (int j = 0; j < 5; j++) {
				float middle = (lo + hi) * 0.5;
				vec3 probe = origin + direction * middle;
				vec2 probe_uv = project_view(probe, projection);
				vec3 other = view_position(probe_uv, textureLod(opaque_depth, probe_uv, 0.0).r, inverse_projection);
				if (probe.z <= other.z) { hi = middle; } else { lo = middle; }
			}
			float travel = (lo + hi) * 0.5;
			vec3 hit = origin + direction * travel;
			vec2 hit_uv = project_view(hit, projection);
			vec3 scene = view_position(hit_uv, textureLod(opaque_depth, hit_uv, 0.0).r, inverse_projection);
			vec3 world_receiver = (inverse_view * vec4(scene, 1.0)).xyz;
			if (world_receiver.y > water_world.y - 0.005 || scene.z > origin.z - 0.015 || abs(scene.z - hit.z) > 0.24) {
				return vec4(0.0);
			}
			vec2 edge = min(hit_uv, 1.0 - hit_uv);
			float confidence = smoothstep(0.003, 0.045, min(edge.x, edge.y));
			return vec4(hit_uv, travel, confidence);
		}
		previous_t = t;
	}
	return vec4(0.0);
}

vec4 trace_reflection(vec3 origin, vec3 direction, mat4 projection, mat4 inverse_projection, mat4 inverse_view) {
	float previous_t = 0.08;
	for (int i = 1; i <= 16; i++) {
		float t = 0.08 + float(i) * 0.18 + float(i * i) * 0.065;
		vec3 point = origin + direction * t;
		if (point.z > -0.08) { break; }
		vec2 uv = project_view(point, projection);
		if (!inside_screen(uv)) { break; }
		vec3 scene = view_position(uv, textureLod(opaque_depth, uv, 0.0).r, inverse_projection);
		if (point.z <= scene.z) {
			float lo = previous_t;
			float hi = t;
			for (int j = 0; j < 5; j++) {
				float middle = (lo + hi) * 0.5;
				vec3 probe = origin + direction * middle;
				vec2 probe_uv = project_view(probe, projection);
				vec3 other = view_position(probe_uv, textureLod(opaque_depth, probe_uv, 0.0).r, inverse_projection);
				if (probe.z <= other.z) { hi = middle; } else { lo = middle; }
			}
			vec3 hit = origin + direction * (lo + hi) * 0.5;
			uv = project_view(hit, projection);
			scene = view_position(uv, textureLod(opaque_depth, uv, 0.0).r, inverse_projection);
			vec3 world_receiver = (inverse_view * vec4(scene, 1.0)).xyz;
			if (world_receiver.y < water_level + 0.04 || abs(scene.z - hit.z) > 0.35) { return vec4(0.0); }
			vec2 edge = min(uv, 1.0 - uv);
			float confidence = smoothstep(0.005, 0.09, min(edge.x, edge.y)) * (1.0 - smoothstep(12.0, 20.0, t));
			return vec4(textureLod(opaque_color, uv, 0.0).rgb, confidence * 0.80);
		}
		previous_t = t;
	}
	return vec4(0.0);
}

float caustic_focus(vec2 p) {
	vec2 q = p * 2.15;
	float t = water_time * 0.16;
	q += vec2(sin(q.y * 0.91 + t), sin(q.x * 0.83 - t * 0.71)) * 0.47;
	float a = abs(sin(q.x + sin(q.y * 1.13 + t) * 1.25));
	float b = abs(sin(q.y - sin(q.x * 0.93 - t) * 1.19));
	float focus = pow(max(0.0, 1.0 - min(a, b)), 12.0);
	return focus;
}

void vertex() {
	water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height = textureLod(water_state, state_uv(water_world.xz), 0.0).r;
	height += ambient_height(water_world.xz) + ripple_field(water_world.xz).x;
	VERTEX.y += height * wave_height;
	water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = water_world.xz;
	float cell = 32.0 / simulation_resolution;
	vec2 texel = vec2(1.0 / (simulation_resolution + 2.0));
	vec2 uv = state_uv(p);
	vec4 state = texture(water_state, uv);
	vec2 simulation_slope = vec2(texture(water_state, uv + vec2(texel.x, 0.0)).r - texture(water_state, uv - vec2(texel.x, 0.0)).r,
		texture(water_state, uv + vec2(0.0, texel.y)).r - texture(water_state, uv - vec2(0.0, texel.y)).r) / (2.0 * cell);
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float detail_fade = 1.0 - smoothstep(0.08, 0.26, footprint);
	vec2 slopes = (simulation_slope + ambient_slope(p)) * wave_height * normal_boost
		+ ripple_field(p).yz * detail_fade * wave_height
		+ micro_slope(p, footprint);
	vec3 world_normal = normalize(vec3(-slopes.x, 1.0, -slopes.y));
	bool underwater = CAMERA_POSITION_WORLD.y < water_level;
	if (underwater) { world_normal = -world_normal; }
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	NORMAL = view_normal;
	float facing = clamp(dot(view_normal, VIEW), 0.0, 1.0);
	float fresnel = 0.020373 + 0.979627 * pow(1.0 - facing, 5.0);
	float depth = textureLod(opaque_depth, SCREEN_UV, 0.0).r;
	vec3 receiver = view_position(SCREEN_UV, depth, INV_PROJECTION_MATRIX);
	vec3 receiver_world = (INV_VIEW_MATRIX * vec4(receiver, 1.0)).xyz;
	float receiver_depth = clamp(water_world.y - receiver_world.y, 0.0, water_level - pool_floor + 0.5);
	vec3 refracted_view = refract(-VIEW, view_normal, underwater ? 1.333 : 1.0 / 1.333);
	vec3 refracted_world = (INV_VIEW_MATRIX * vec4(refracted_view, 0.0)).xyz;
	float thickness = min(receiver_depth / max(abs(refracted_world.y), 0.2), 6.0);
	vec3 transmitted = absorbed(textureLod(opaque_color, SCREEN_UV, 0.0).rgb, thickness);
	if (refraction_enabled && !underwater && refraction_strength > 0.0) {
		vec3 ray = normalize(mix(-VIEW, refracted_view, refraction_strength));
		vec4 hit = trace_transmission(VERTEX, ray, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, min(6.0, max(1.5, thickness * 2.0)));
		if (hit.w > 0.0) {
			vec3 hit_position = view_position(hit.xy, textureLod(opaque_depth, hit.xy, 0.0).r, INV_PROJECTION_MATRIX);
			receiver_world = mix(receiver_world, (INV_VIEW_MATRIX * vec4(hit_position, 1.0)).xyz, hit.w);
			transmitted = mix(transmitted, absorbed(textureLod(opaque_color, hit.xy, 0.0).rgb, hit.z), hit.w);
			thickness = mix(thickness, hit.z, hit.w);
		}
	}
	float caustics = 0.0;
	if (caustics_enabled && !underwater && receiver_world.y < water_level - 0.06) {
		float submerged = smoothstep(0.05, 0.30, water_level - receiver_world.y);
		float distance_fade = 1.0 - smoothstep(0.08, 0.45, footprint);
		caustics = caustic_focus(receiver_world.xz + slopes * thickness * 0.30) * submerged * distance_fade * caustics_intensity * 0.075;
		// Modulate only already-lit submerged receivers. No emissive wallpaper.
		transmitted += transmitted * vec3(0.68, 0.91, 1.0) * caustics;
	}
	float foam = smoothstep(0.025, 0.36, state.a * foam_strength) * 0.65;
	float contact = 1.0 - smoothstep(0.0, 0.025, thickness);
	transmitted += vec3(0.006, 0.009, 0.009) * contact;
	transmitted = mix(transmitted, vec3(0.48, 0.62, 0.62), foam);
	// Native Godot GGX supplies real local light highlights and box-projected
	// room probe radiance. SPECULAR=.25466 corresponds to dielectric F0=.02037.
	// EMISSION is used for captured transmitted radiance, not a glow effect.
	ALBEDO = vec3(0.0);
	EMISSION = transmitted * (1.0 - fresnel * reflection_strength);
	METALLIC = 0.0;
	SPECULAR = 0.25466 * reflection_strength;
	ROUGHNESS = mix(surface_roughness, 0.28, foam);
	RADIANCE = vec4(0.0);
	if (ssr_enabled && !underwater) {
		vec4 reflected = trace_reflection(VERTEX + view_normal * 0.035, reflect(-VIEW, view_normal), PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		RADIANCE = vec4(reflected.rgb, reflected.a * reflection_strength);
	}
	ALPHA = 1.0;
	if (debug_view > 0) {
		SPECULAR = 0.0;
		if (debug_view == 1) { EMISSION = vec3(0.5 + state.r * 6.0); }
		if (debug_view == 2) { EMISSION = vec3(0.5 + state.gb * 0.5, 0.5); }
		if (debug_view == 3) { EMISSION = world_normal * 0.5 + 0.5; }
		if (debug_view == 4) { EMISSION = vec3(thickness * 0.5); }
		if (debug_view == 5) { EMISSION = vec3(fresnel); }
		if (debug_view == 6) { EMISSION = transmitted; }
		if (debug_view == 7) { EMISSION = vec3(caustics * 4.0); }
		if (debug_view == 8) { EMISSION = vec3(state.a); }
	}
}
