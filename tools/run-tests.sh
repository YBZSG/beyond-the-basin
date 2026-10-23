#!/bin/sh
# Current CPU/data contracts only. GPU/pixels/timing require separate native runs.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
GODOT_BIN=${GODOT_BIN:-godot}
PYTHON_BIN=${PYTHON_BIN:-python3}
TEST_TIMEOUT_SECONDS=${TEST_TIMEOUT_SECONDS:-120}
IMPORT_TIMEOUT_SECONDS=${IMPORT_TIMEOUT_SECONDS:-180}
ACTIVE_GODOT='world_parity world_room_parity original_geometry_parity original_batch_parity original_prop_parity world_streaming rendering_contract_test source_scene_presentation_contract source_spawn_selection_contract formal_daylight_material_contract formal_walkthrough_test source_coupling_controller source_coupling_test source_held_wheel_dispatch native_gait_audio_test source_wave_contract source_wave_events_test source_static_terrain_test source_terrain_prepare_test source_terrain_cache_test source_field_shift_test source_caustic_contract probe-cache-contract source_liquid_host source_liquid_contacts source_liquid_lifecycle source_splash_schedule_contract source_splash_host_parity source_splash_optical_profile desktop_quality_contract source_wave_readback_contract source_fog_contract mobile_controls_test mobile_multitouch_test mobile_source_contract mobile_lifecycle_test desktop_quality_mobile_guard'
ACTIVE_PYTHON='source_wave_reference formal_architectural_junctions source_fog_reference'
if [ "${1:-}" = '--list' ]; then
  printf 'Active Godot CPU contracts:\n'; for t in $ACTIVE_GODOT; do printf '  tests/%s.gd\n' "$t"; done
  printf 'Active Python CPU references:\n'; for t in $ACTIVE_PYTHON; do printf '  tests/%s.py\n' "$t"; done
  printf '\nHistorical, NOT current acceptance gates:\n  tests/water_contract.gd (retired pool_water/water_field placeholder)\n  tests/integration_native_game.gd (retired water fields, menus, audio counts)\n  tests/player_controller_test.gd (retired water API; replaced by source_coupling_controller)\n  tests/fixtures/rendering_contract_legacy.gd.fixture (old scan/invented-light assumptions)\n\nSeparate native GPU/visual/performance checks are NOT run here.\nSee docs/verification/current-test-suite.md for limits and specialized suites.\n'
  exit 0
fi
SKIP_IMPORT=0
if [ "${1:-}" = '--skip-import' ]; then SKIP_IMPORT=1; shift; fi
if [ "$#" -ne 0 ]; then echo 'Usage: tools/run-tests.sh [--list | --skip-import]' >&2; exit 2; fi
case "$TEST_TIMEOUT_SECONDS:$IMPORT_TIMEOUT_SECONDS" in *[!0-9:]*|0:*|*:0|:*|*:) echo 'Timeouts must be positive integer seconds.' >&2; exit 2;; esac
for binary in "$GODOT_BIN" "$PYTHON_BIN" timeout; do command -v "$binary" >/dev/null || { echo "Missing required command: $binary" >&2; exit 2; }; done
# Every process owns a fresh writable profile. The spawn contract requires this
# explicit sentinel and may safely create/delete settings inside it.
RUN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/poolcore-spawn-contract-suite.XXXXXX")
trap 'rm -rf "$RUN_ROOT"' EXIT HUP INT TERM
RESULTS_DIR=${TEST_RESULTS_DIR:-"$ROOT/docs/verification/current-test-suite-results"}
mkdir -p "$RESULTS_DIR"
RESULTS_DIR=$(cd "$RESULTS_DIR" && pwd)
SUMMARY="$RESULTS_DIR/summary.tsv"
printf 'test\tstatus\texit_code\tseconds\tlog\n' > "$SUMMARY"
FAILED=0
TOTAL=0
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run_case() {
  name=$1; limit=$2; shift 2
  profile="$RUN_ROOT/$name"
  mkdir -p "$profile/home" "$profile/data" "$profile/config" "$profile/cache" "$profile/runtime"
  chmod 700 "$profile/runtime"
  logfile="$RESULTS_DIR/$name.log"
  start=$(date +%s)
  printf '\n=== %s (timeout %ss) ===\n' "$name" "$limit"
  code=0
  HOME="$profile/home" XDG_DATA_HOME="$profile/data" XDG_CONFIG_HOME="$profile/config" XDG_CACHE_HOME="$profile/cache" XDG_RUNTIME_DIR="$profile/runtime" \
    timeout --signal=TERM --kill-after=5s "${limit}s" "$@" > "$logfile" 2>&1 || code=$?
  seconds=$(($(date +%s) - start))
  status=PASS
  if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then status=TIMEOUT
  elif [ "$code" -ne 0 ]; then status=FAIL
  elif grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$logfile"; then status=ERROR_LOG
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); fi
  cat "$logfile"
  printf '%s: %s (exit %s, %ss)\n' "$name" "$status" "$code" "$seconds"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$code" "$seconds" "$name.log" >> "$SUMMARY"
}
if [ "$SKIP_IMPORT" -eq 0 ]; then
  run_case editor_import "$IMPORT_TIMEOUT_SECONDS" "$GODOT_BIN" --headless --path . --editor --import --quit
fi
# Serial execution avoids contaminating native profiling and preserves readable
# per-case logs. A script exception with exit 0 is still a failure above.
if [ "$FAILED" -eq 0 ]; then
  for test in $ACTIVE_GODOT; do
    if [ "$test" = desktop_quality_mobile_guard ]; then
      run_case "$test" "$TEST_TIMEOUT_SECONDS" "$GODOT_BIN" --headless --path . --fixed-fps 120 --script "res://tests/$test.gd" -- --mobile-preview
    else
    run_case "$test" "$TEST_TIMEOUT_SECONDS" "$GODOT_BIN" --headless --path . --fixed-fps 120 --script "res://tests/$test.gd"
    fi
  done
  for test in $ACTIVE_PYTHON; do
    run_case "$test" "$TEST_TIMEOUT_SECONDS" "$PYTHON_BIN" "tests/$test.py"
  done
fi
"$PYTHON_BIN" - "$SUMMARY" "$STARTED" "$SKIP_IMPORT" <<'PY'
import csv, datetime, hashlib, json, pathlib, sys
summary = pathlib.Path(sys.argv[1])
rows = list(csv.DictReader(summary.open(), delimiter='\t'))
for row in rows:
    row['exit_code'] = int(row['exit_code']); row['seconds'] = int(row['seconds'])
files = [pathlib.Path('tools/run-tests.sh'), *sorted(pathlib.Path('scripts').rglob('*.gd')), *sorted(pathlib.Path('shaders').rglob('*'))]
files = [p for p in files if p.is_file() and p.suffix != '.uid']
report = {
    'scope': 'Current CPU/data contracts only; not GPU, visual, subjective audio, real-time performance, or full native integration validation.',
    'started_utc': sys.argv[2], 'finished_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'import_skipped': sys.argv[3] == '1', 'passed': sum(r['status'] == 'PASS' for r in rows),
    'failed': sum(r['status'] != 'PASS' for r in rows), 'results': rows,
    'production_and_runner_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
    'test_inputs_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(pathlib.Path('tests').rglob('*')) if p.is_file() and p.suffix in ('.gd', '.json', '.fixture', '.py')},
}
report['pass'] = report['failed'] == 0
(summary.parent/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
PY
printf '\nCURRENT CPU SUITE: %s processes, %s failed. Results: %s\n' "$TOTAL" "$FAILED" "$RESULTS_DIR"
printf 'GPU/native flow, rendered pixels, performance, and subjective audio are not covered.\n'
[ "$FAILED" -eq 0 ]
