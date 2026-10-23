#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# CPU/reference tests; this deliberately does not pretend headless can run GPU passes.
for test in source_wave_contract source_static_terrain_test source_wave_events_test source_coupling_test source_coupling_controller source_caustic_contract source_liquid_host source_liquid_contacts source_liquid_lifecycle desktop_quality_contract formal_walkthrough_test; do
 godot --headless --path . --script "res://tests/$test.gd"
done
# Actual GPU tests must run separately without --headless:
# source_wave_gpu_test, source_wave_global_test, source_caustic_gpu,
# source_liquid_gpu, source_liquid_rd_smoke, source_liquid_pixels,
# source_planar_projection_test (all under res://tests).
