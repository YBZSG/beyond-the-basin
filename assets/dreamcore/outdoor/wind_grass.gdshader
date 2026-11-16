shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 root_color : source_color = vec3(0.18, 0.27, 0.12);
uniform vec3 tip_color : source_color = vec3(0.43, 0.55, 0.28);
uniform float wind_strength : hint_range(0.0, 2.0) = 1.0;
uniform float time_override = -1.0; // deterministic motion regression capture
uniform vec4 trample_stamps[8]; // world x/z, radius and recovering strength
uniform int trample_count = 0;
varying float leaf_height;
varying float variation;

void vertex() {
	float t = time_override >= 0.0 ? time_override : TIME;
	vec3 root = MODEL_MATRIX[3].xyz;
	// The custom RT renderer cannot compile INSTANCE_CUSTOM in its hit shader.
	// Stable world-position seeds retain per-instance wind and colour variation.
	float seed = fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = seed * 6.283185;
	variation = fract(sin(dot(root.xz, vec2(39.34, 11.135))) * 24634.6345);
	leaf_height = UV.y;
	// Gust fronts travel across world space; independent fine motion avoids
	// the synchronized metronome look. Roots remain exactly on dry collision.
	float gust = 0.5 + 0.5 * sin(dot(root.xz, vec2(0.075, 0.043)) - t * 0.85);
	float sway = sin(t * 1.65 + dot(root.xz, vec2(0.34, 0.19)) + phase);
	float flutter = sin(t * 3.8 + phase * 2.1 + root.z * 0.7);
	float bend = UV.y * UV.y * wind_strength;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world.xz += vec2(0.88, 0.47) * (0.035 + gust * 0.08 + sway * 0.035) * bend;
	world.xz += vec2(-0.47, 0.88) * flutter * .015 * bend;
	float flattened = 0.0;
	vec2 push = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= trample_count) { break; }
		vec4 stamp = trample_stamps[i];
		vec2 offset = root.xz - stamp.xy;
		float weight = (1.0 - smoothstep(0.0, max(stamp.z * stamp.z, 0.0001), dot(offset, offset))) * stamp.w;
		flattened = max(flattened, weight);
		push += normalize(offset + vec2(0.0001, 0.0001)) * weight;
	}
	world.xz += push * UV.y * UV.y * .24;
	world.y -= flattened * min(.30, max(0.0, VERTEX.y) * length(MODEL_MATRIX[1].xyz) * .65);
	float fade = 1.0 - smoothstep(52.0, 74.0, distance(root, CAMERA_POSITION_WORLD));
	world = mix(root, world, fade);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec3 tint = mix(root_color, tip_color, pow(leaf_height, .7));
	ALBEDO = tint * mix(.82, 1.13, variation);
	ROUGHNESS = .91;
	SPECULAR = .16;
	// Up-biased front normals match the clockwise upper face. Backfaces use
	// the physically opposite normal; do not claim both faces always point up.
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
