#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
BLENDER="${BLENDER:-blender}"
DIR=tools/blender/reference_wing/stair_gallery
"$BLENDER" -b -t 4 --python-exit-code 1 --python "$DIR/build_stair_gallery.py"
python "$DIR/inspect_stair_export.py"
"$BLENDER" -b -t 2 --python-exit-code 1 --python "$DIR/measure_stair_contacts.py"
"$BLENDER" -b -t 2 --python-exit-code 1 --python "$DIR/verify_stair_proxy_clearance.py"
"$BLENDER" -b -t 2 --python-exit-code 1 --python "$DIR/draw_stair_sections.py"
python "$DIR/rasterize_stair_sections.py"
python "$DIR/draw_stair_plan.py"
if [[ "${1:-}" == "--render" ]]; then
  "$BLENDER" -b -t 4 --python-exit-code 1 --python "$DIR/render_stair_preview.py"
fi
