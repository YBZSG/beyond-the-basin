// Optional longer optical ripples. The existing source/wind paths are untouched.
// No vertex displacement, depth, solver impulses, or caustic dispatch changes.
// Each mode: (world wave vector x/z, equivalent relief metres, bounded phase).
uniform vec4 referenceWaveModes[3];
uniform float referenceWavesActive = 0.0;

vec2 referenceOpticalSlope(vec2 worldP, float footprint, float depth) {
	if (referenceWavesActive < 0.5) return vec2(0.0);
	vec2 slope = vec2(0.0);
	float shore = smoothstep(0.015, 0.12, depth);
	for (int i = 0; i < 3; i++) {
		vec4 mode = referenceWaveModes[i];
		float fade = 1.0 - smoothstep(0.7, 2.4, max(footprint, 0.0) * length(mode.xy));
		slope += mode.xy * (mode.z * fade * shore) * cos(dot(worldP, mode.xy) + mode.w);
	}
	return slope;
}
