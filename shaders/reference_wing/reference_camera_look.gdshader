shader_type canvas_item;
render_mode unshaded;

// Replaces the existing single camera-look pass, not a second post-process.
// Host: CanvasLayer 0, clean HUD/menu CanvasLayer 1. Hide the rect altogether
// when look_mode == 0 and reference_look_enabled == false (exact clean bypass).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform int look_mode : hint_range(0, 3) = 0;
uniform bool reference_look_enabled = false;
uniform float reference_fringe_px : hint_range(0.0, 8.0, 0.05) = 0.8;
uniform float reference_grain : hint_range(0.0, 0.02, 0.001) = 0.006;
uniform float reference_vignette : hint_range(0.0, 0.45, 0.005) = 0.07;
// QA can hold the sensor grain fixed without touching water simulation time.
uniform bool reference_freeze_grain = false;

vec2 safe_uv(vec2 uv, vec2 pixel_size) {
	vec2 border = pixel_size * 0.5;
	return clamp(uv, border, vec2(1.0) - border);
}

float sensor_noise(vec2 pixel, float frame) {
	return fract(sin(dot(pixel + vec2(frame * 7.13, frame * 3.71), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Original Clean/CCD/VHS/Cold controls remain independent and session-owned.
	if (look_mode == 2 && !reference_look_enabled) uv.x += sin(uv.y * 370.0 + TIME * 8.0) * 0.0006;
	vec3 color = texture(screen_tex, safe_uv(uv, SCREEN_PIXEL_SIZE)).rgb;
	vec2 reference_offset = vec2(0.0);
	if (reference_look_enabled && reference_fringe_px > 0.0) {
		vec2 radial = (SCREEN_UV - vec2(0.5)) * 2.0;
		// A radial 0..8 output-pixel shift, not a resolution-dependent UV smear.
		float edge = smoothstep(0.12, 1.0, length(radial));
		vec2 direction = radial / max(length(radial), 0.0001);
		reference_offset = direction * SCREEN_PIXEL_SIZE * clamp(reference_fringe_px, 0.0, 8.0) * edge;
		color.r = texture(screen_tex, safe_uv(uv + reference_offset, SCREEN_PIXEL_SIZE)).r;
		color.b = texture(screen_tex, safe_uv(uv - reference_offset, SCREEN_PIXEL_SIZE)).b;
	}
	float legacy_grain = fract(sin(dot(FRAGCOORD.xy + TIME * 53.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec2 centered = SCREEN_UV - vec2(0.5);
	if (look_mode == 1 && !reference_look_enabled) {
		color *= 1.0 - dot(centered, centered) * 0.23;
		color += legacy_grain * 0.018;
	} else if (look_mode == 2 && !reference_look_enabled) {
		color.r = texture(screen_tex, safe_uv(uv + vec2(0.0015, 0.0) + reference_offset, SCREEN_PIXEL_SIZE)).r;
		color.b = texture(screen_tex, safe_uv(uv - vec2(0.0015, 0.0) - reference_offset, SCREEN_PIXEL_SIZE)).b;
		color *= 0.98 + sin(FRAGCOORD.y * 3.14) * 0.02;
		color += legacy_grain * 0.025;
	} else if (look_mode == 3 && !reference_look_enabled) {
		float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
		color = mix(vec3(luminance), color, 0.72) * vec3(0.94, 1.01, 1.07);
	}
	if (reference_look_enabled) {
		// Stable lens treatment: straight architecture, highlight-only diffusion.
		vec3 soft_near = textureLod(screen_tex, safe_uv(uv, SCREEN_PIXEL_SIZE), 3.0).rgb;
		vec3 soft_wide = textureLod(screen_tex, safe_uv(uv, SCREEN_PIXEL_SIZE), 5.0).rgb;
		vec3 halo = max(soft_near - vec3(0.42), vec3(0.0)) * 0.58;
		halo += max(soft_wide - vec3(0.34), vec3(0.0)) * 0.42;
		float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		color = max((mix(vec3(luma), color, 0.94) - vec3(0.018)) * 1.055, vec3(0.0));
		color *= mix(vec3(0.90, 1.015, 1.005), vec3(1.0), smoothstep(0.25, 0.85, luma));
		color *= 1.0 + smoothstep(0.35, 0.82, luma) * 0.40;
		color += halo;
		float radius = clamp(length(centered) * 1.41421356, 0.0, 1.0);
		color *= 1.0 - smoothstep(0.25, 1.0, radius) * clamp(reference_vignette, 0.0, 0.45);
		float frame = reference_freeze_grain ? 0.0 : floor(mod(TIME, 1024.0) * 24.0);
		color += sensor_noise(floor(FRAGCOORD.xy), frame) * clamp(reference_grain, 0.0, 0.02);
	}
	// One camera pass. Scene lights, exposure and the HUD remain independent.
	COLOR = vec4(color, 1.0);
}
