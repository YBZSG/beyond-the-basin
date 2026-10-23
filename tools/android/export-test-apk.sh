#!/bin/sh
# Export the CURRENT original-source-water project using an EXISTING test key.
# No key generation, SDK license acceptance, install, Play upload or publication.
set -eu
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
: "${DEBUG_KEYSTORE:?Set DEBUG_KEYSTORE to the existing authorized local Android debug key.}"
: "${ANDROID_SDK_ROOT:?Set ANDROID_SDK_ROOT to the installed official Android SDK.}"
: "${JAVA_HOME:?Set JAVA_HOME to an installed OpenJDK 17 or newer.}"
: "${GODOT_TEMPLATES_DIR:?Set GODOT_TEMPLATES_DIR to the matching Godot export template directory.}"
GODOT_BIN=${GODOT_BIN:-godot}
OUTPUT_APK=${OUTPUT_APK:-$ROOT/output/android/PoolCore-Source-Water-Android-Test.apk}
BUILD_ROOT=${ANDROID_EXPORT_HOME:-$ROOT/output/android/export-user}
[ -f "$DEBUG_KEYSTORE" ] || { echo 'Existing debug key missing. No signing credential will be generated.' >&2; exit 1; }
[ -x "$JAVA_HOME/bin/java" ] || { echo 'Java runtime not found.' >&2; exit 1; }
[ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ] || { echo 'Android platform tools missing.' >&2; exit 1; }
[ -f "$GODOT_TEMPLATES_DIR/android_debug.apk" ] || { echo 'Matching official Android debug template missing.' >&2; exit 1; }
VERSION=$($GODOT_BIN --headless --version | tail -1 | cut -d. -f1-4)
[ "$(cat "$GODOT_TEMPLATES_DIR/version.txt" | tr -d '\r\n')" = "$VERSION" ] || { echo "Export template version must match $VERSION." >&2; exit 1; }
export HOME="$BUILD_ROOT/home" XDG_CACHE_HOME="$BUILD_ROOT/cache" XDG_CONFIG_HOME="$BUILD_ROOT/config" XDG_DATA_HOME="$BUILD_ROOT/data"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME/godot" "$XDG_DATA_HOME/godot/export_templates" "$(dirname "$OUTPUT_APK")"
if [ ! -e "$XDG_DATA_HOME/godot/export_templates/$VERSION" ]; then ln -s "$GODOT_TEMPLATES_DIR" "$XDG_DATA_HOME/godot/export_templates/$VERSION"; fi
export ANDROID_SDK_ROOT JAVA_HOME DEBUG_KEYSTORE
python3 - <<'PY'
import json,os,pathlib
p=pathlib.Path(os.environ['XDG_CONFIG_HOME'])/'godot/editor_settings-4.6.tres'
values={'export/android/android_sdk_path':os.environ['ANDROID_SDK_ROOT'], 'export/android/java_sdk_path':os.environ['JAVA_HOME'], 'export/android/debug_keystore':os.environ['DEBUG_KEYSTORE']}
p.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' + ''.join(k+' = '+json.dumps(v)+'\n' for k,v in values.items()))
PY
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$DEBUG_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${DEBUG_KEY_ALIAS:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${DEBUG_KEY_PASSWORD:-android}"
"$GODOT_BIN" --headless --path "$ROOT" --export-debug Android "$OUTPUT_APK"
printf '\nCurrent-source debug APK exported. No install or publishing was performed.\n'
