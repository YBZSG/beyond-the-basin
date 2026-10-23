/* SPDX-License-Identifier: MIT */
#ifndef SOURCE_WATER_PARTICLE_GATE_CORE_H
#define SOURCE_WATER_PARTICLE_GATE_CORE_H
#include <stdint.h>
#ifndef SW_PARTICLE_LERP
static double sw_particle_lerp_direct(double a, double b, double t) { return a + (b - a) * t; }
#define SW_PARTICLE_LERP sw_particle_lerp_direct
#endif
/* Exact prefix of the existing source-port host particle loop. Return before
 * any surface/depth callback, event, mutation or render packing. The caller
 * either skips an entirely inert patch or runs the original loop unchanged.
 * The experimental sparse caller instead resumes at each returned candidate.
 * Outer arithmetic is strict binary64 without contraction/reassociation or
 * allocation. SW_PARTICLE_LERP intentionally invokes the engine's actual
 * lerpf in the binding, preserving that engine's own interpolation behavior. */
static int64_t sw_next_particle_candidate(const float *data, const float *previous,
        const uint8_t *removed, const uint8_t *emerged, int64_t count,
        int64_t start, double blend, double base, double h) {
    const double reservoir_threshold = base - 0.06;
    for (int64_t i = start; i < count; ++i) {
        const int64_t j = i * 20;
        if (removed[i] != 0 || (double)data[j + 7] < 0.5) continue;
        const double a = (double)previous[j + 1];
        const double b = (double)data[j + 1];
        /* Godot 4.6.3 Math::lerp(double): a + (b - a) * blend. */
        const double y = base + (SW_PARTICLE_LERP(a, b, blend) - 12.0) * h;
        if (y < reservoir_threshold && emerged[i] == 0) continue;
        return i;
    }
    return count;
}
#endif
