#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")"
root="$(cd ../.. && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/source-native-test.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_DATA_HOME="$fixture/data" XDG_CACHE_HOME="$fixture/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$fixture/project/.godot"
"${GODOT:-godot}" --headless --path "$root" --script tests/source_native_readback_contract.gd
printf 'config_version=5\n[application]\nconfig/name="Native ABI test"\n' > "$fixture/project/project.godot"
sed "s|res://native/source_water/|$root/native/source_water/|g" source_water.gdextension > "$fixture/project/source_water.gdextension"
printf 'res://source_water.gdextension\n' > "$fixture/project/.godot/extension_list.cfg"
cp "$root/tests/source_native_readback_typed.gd" "$fixture/project/test.gd"
"${GODOT:-godot}" --headless --path "$fixture/project" --script test.gd
