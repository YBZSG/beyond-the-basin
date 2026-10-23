#!/bin/sh
# CPU input/contract tests by default. GPU validation must be requested explicitly.
set -eu
cd "$(dirname "$0")/../.."
for test in tests/mobile_controls_test.gd tests/mobile_multitouch_test.gd tests/mobile_source_contract.gd tests/mobile_lifecycle_test.gd; do
  godot --headless --path . --script "$test"
done
if [ "${1:-}" = "--gpu" ]; then
  # Requires an actual Vulkan window/display; headless is NOT an RD test.
  godot --rendering-method mobile --path . --script tests/mobile_source_gpu_smoke.gd -- --mobile-preview
fi
