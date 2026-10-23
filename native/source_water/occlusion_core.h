/* SPDX-License-Identifier: MIT */
#ifndef SOURCE_WATER_OCCLUSION_CORE_H
#define SOURCE_WATER_OCCLUSION_CORE_H
#include <stdint.h>

#define SW_MASK_SIZE 256
#define SW_MASK_PIXELS (SW_MASK_SIZE * SW_MASK_SIZE)

/* These inputs are Godot Vector3 components, not newly evaluated bounds.
 * Each six-float box is [position.xyz, end.xyz], where Godot has already
 * performed AABB.end's binary32 addition. Preserve their original order.
 * Vector subtraction is binary32; scalar GDScript arithmetic is binary64.
 * Strict IEEE compilation is mandatory: no fast-math, FMA or reassociation. */
static int sw_mask_finite(float value) {
    union { uint32_t bits; float value; } input;
    input.value = value;
    return (input.bits & UINT32_C(0x7f800000)) != UINT32_C(0x7f800000);
}

static int sw_ray_blocked(const float start[3], const float end[3],
                          const float *boxes, int64_t box_count) {
    /* Assignment deliberately rounds exactly as Vector3::operator-. */
    const float delta[3] = {end[0] - start[0], end[1] - start[1], end[2] - start[2]};
    for (int64_t box_id = 0; box_id < box_count; ++box_id) {
        const float *box = boxes + box_id * 6;
        double near_t = 0.0, far_t = 1.0;
        int outside = 0;
        for (int axis = 0; axis < 3; ++axis) {
            const double d = (double)delta[axis];
            const double s = (double)start[axis];
            const double lo = (double)box[axis];
            const double hi = (double)box[axis + 3];
            if (d > -1.0e-8 && d < 1.0e-8) {
                if (s < lo || s > hi) {
                    outside = 1;
                    break;
                }
            } else {
                const double a = (lo - s) / d;
                const double b = (hi - s) / d;
                const double lesser = a < b ? a : b;
                const double greater = a > b ? a : b;
                near_t = near_t > lesser ? near_t : lesser;
                far_t = far_t < greater ? far_t : greater;
            }
        }
        if (!outside && near_t <= far_t && near_t < .995 && far_t > .005) return 1;
    }
    return 0;
}

/* A malformed/nonfinite input returns 0 before writing either private output.
 * Empty boxes are valid and produce two fully unoccluded masks. Inverted and
 * zero-thickness bounds retain the original kernel's behavior, not a repaired
 * or normalized AABB. The caller owns output buffers of SW_MASK_PIXELS bytes. */
static int sw_build_occlusion_masks(const float *boxes, int64_t box_values,
                                    const float *lamps, int64_t lamp_values,
                                    uint8_t *mask0, uint8_t *mask1) {
    if (box_values < 0 || box_values % 6 != 0 || lamp_values != 6 ||
        (box_values != 0 && !boxes) || !lamps || !mask0 || !mask1) return 0;
    for (int64_t i = 0; i < box_values; ++i) if (!sw_mask_finite(boxes[i])) return 0;
    for (int i = 0; i < 6; ++i) if (!sw_mask_finite(lamps[i])) return 0;
    const int64_t box_count = box_values / 6;
    uint8_t *masks[2] = {mask0, mask1};
    for (int lamp_id = 0; lamp_id < 2; ++lamp_id) {
        for (int row = 0; row < SW_MASK_SIZE; ++row) {
            for (int x = 0; x < SW_MASK_SIZE; ++x) {
                const float start[3] = {
                    (float)(((double)x + .5) / 256.0 * 32.0 - 16.0),
                    (float).31,
                    (float)(((double)row + .5) / 256.0 * 32.0 - 16.0)
                };
                masks[lamp_id][x + row * SW_MASK_SIZE] =
                    sw_ray_blocked(start, lamps + lamp_id * 3, boxes, box_count) ? 0 : 255;
            }
        }
    }
    return 1;
}
#endif
