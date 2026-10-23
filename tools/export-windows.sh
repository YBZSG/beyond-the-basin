#!/bin/sh
# Install matching 4.6.3 export templates from Godot's official template manager first.
set -eu
cd "$(dirname "$0")/.."
mkdir -p output/windows
godot --headless --path . --export-release "Windows Desktop" output/windows/PoolCore-Native.exe
