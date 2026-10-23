/* SPDX-License-Identifier: MIT */
#ifndef SOURCE_WATER_READBACK_CORE_H
#define SOURCE_WATER_READBACK_CORE_H
#include <stdint.h>

/* Little-endian RGBA16F, exactly the source GPU texture representation.
 * Outputs are private temporary arrays; a failed parse must not be published.
 * All floating-point arithmetic below requires strict IEEE binary64 semantics:
 * no fast-math, contraction/FMA, reassociation, or parallel reduction. */
static uint16_t sw_read_half(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static float sw_half_to_float(uint16_t h) {
    uint32_t sign = ((uint32_t)h & 0x8000u) << 16;
    uint32_t exponent = ((uint32_t)h >> 10) & 31u;
    uint32_t fraction = (uint32_t)h & 1023u;
    union { uint32_t bits; float value; } result;
    if (exponent == 0) {
        if (fraction == 0) {
            result.bits = sign; /* Preserve negative zero bit-for-bit. */
            return result.value;
        }
        exponent = 113u;
        while ((fraction & 1024u) == 0) {
            fraction <<= 1;
            --exponent;
        }
        fraction &= 1023u;
    } else {
        exponent += 112u;
    }
    result.bits = sign | (exponent << 23) | (fraction << 13);
    return result.value;
}

static int sw_finite_double(double value) {
    union { uint64_t bits; double value; } input;
    input.value = value;
    return (input.bits & UINT64_C(0x7ff0000000000000)) != UINT64_C(0x7ff0000000000000);
}

static int sw_parse_rgba16f(const uint8_t *bytes, int64_t count, double rest_depth,
                          float *eta, float *us, float *vs,
                          double *energy_out, double *peak_out) {
    double total = 0.0;
    double peak = 0.0;
    if (count <= 0 || !sw_finite_double(rest_depth)) return 0;
    for (int64_t i = 0; i < count; ++i) {
        const uint8_t *pixel = bytes + i * 8;
        uint16_t hb = sw_read_half(pixel);
        uint16_t ub = sw_read_half(pixel + 2);
        uint16_t vb = sw_read_half(pixel + 4);
        if (sw_read_half(pixel + 6) != 0x3c00u ||
            (hb & 0x7c00u) == 0x7c00u ||
            (ub & 0x7c00u) == 0x7c00u ||
            (vb & 0x7c00u) == 0x7c00u) return 0;
        eta[i] = sw_half_to_float(hb);
        us[i] = sw_half_to_float(ub);
        vs[i] = sw_half_to_float(vb);
        double h = (double)eta[i];
        double u = (double)us[i];
        double v = (double)vs[i];
        /* Keep this expression and iteration order identical to source_port. */
        total += h * h + (u * u + v * v) * rest_depth / 9.81;
        double ah = __builtin_fabs(h);
        double au = __builtin_fabs(u) * 0.1;
        double av = __builtin_fabs(v) * 0.1;
        double uv_peak = au > av ? au : av;
        double pixel_peak = ah > uv_peak ? ah : uv_peak;
        peak = peak > pixel_peak ? peak : pixel_peak;
    }
    *energy_out = total / (double)count;
    *peak_out = peak;
    return 1;
}
#endif
