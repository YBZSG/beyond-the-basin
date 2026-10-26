// RT opaque color is still noisy at the transparent pass (before DLSS RR).
// Use a deterministic raster capture instead of blurring those random samples.
// Ordinary raster rendering keeps the original screen-color transmission.
uniform sampler2D rasterTransmission : filter_linear, repeat_disable;
uniform float rasterTransmissionOn = 0.0;
uniform float rasterTransmissionReady = 0.0;
vec3 water_reflection(vec2 uv) {
    // The viewport texture has no mip chain. Integrate the warped reflection
    // footprint so subpixel lamp/railing images do not blink as the eye moves.
    vec2 pixel = 1.0 / vec2(textureSize(mirrorSampler, 0));
    vec2 dx = clamp(dFdx(uv) * 0.5, -pixel * 6.0, pixel * 6.0);
    vec2 dy = clamp(dFdy(uv) * 0.5, -pixel * 6.0, pixel * 6.0);
    dx = length(dx) < pixel.x * 0.5 ? vec2(pixel.x * 0.5, 0.0) : dx;
    dy = length(dy) < pixel.y * 0.5 ? vec2(0.0, pixel.y * 0.5) : dy;
    return (texture(mirrorSampler, uv - dx - dy).rgb
          + texture(mirrorSampler, uv + dx - dy).rgb
          + texture(mirrorSampler, uv - dx + dy).rgb
          + texture(mirrorSampler, uv + dx + dy).rgb) * 0.25;
}
vec3 water_transmission(vec2 uv, float water_z, mat4 inverse_projection) {
    if (rasterTransmissionOn > 0.5) {
        if (rasterTransmissionReady < 0.5) return waterColor * 0.25;
        return texture(rasterTransmission, uv).rgb;
    }
    return texture(sceneColor, uv).rgb;
}
