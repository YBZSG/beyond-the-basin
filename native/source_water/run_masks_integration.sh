#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")"
root="$(cd ../.. && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/source-native-mask-integration.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_DATA_HOME="$fixture/data" XDG_CACHE_HOME="$fixture/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
"${GODOT:-godot}" --headless --path "$root" --script tests/source_native_masks_integration.gd
"${GODOT:-godot}" --headless --path "$root" --script tests/source_native_masks_integration.gd -- --no-native-water-masks
mkdir -p "$fixture/project/tests/fixtures" "$fixture/project/scripts/water/source_port"
printf 'config_version=5\n[application]\nconfig/name="Native mask missing-library fallback"\n' > "$fixture/project/project.godot"
cp "$root/tests/source_native_masks_integration.gd" "$fixture/project/tests/"
cp "$root/tests/fixtures/source_incoming_mask_old_reference.gd" "$fixture/project/tests/fixtures/"
cp "$root/scripts/water/source_port/source_caustics.gd" "$fixture/project/scripts/water/source_port/"
cp "$root/scripts/water/source_port/source_gpu_timestamps.gd" "$fixture/project/scripts/water/source_port/"
cp "$root/scripts/water/source_port/source_triangle_bvh.gd" "$fixture/project/scripts/water/source_port/"
"${GODOT:-godot}" --headless --path "$fixture/project" --script tests/source_native_masks_integration.gd
