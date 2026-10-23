#!/usr/bin/env python3
"""Reproduce native dependency export/launch behavior in a tiny isolated project.

CPU/headless only. Never exports or imports the real project and never signs,
installs, downloads, publishes, or creates a key. Requires an EXISTING authorized
keystore path only to prevent Godot editor's automatic default-key generation.
The key contents are never opened by this script; the APK preset is unsigned.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace
from audit_packages import AuditError, require, descriptor_libraries, pck_audit, apk_audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New/empty isolated output directory')
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--existing-debug-keystore', type=Path, required=True)
    parser.add_argument('--pre-register', action='store_true', default=True, help='Startup-register helper (default, verified upstream engine-race workaround)')
    parser.add_argument('--discover-extension', action='store_false', dest='pre_register', help='Diagnostic only: reproduce known first-discovery shutdown race instead of using bootstrap')
    parser.add_argument('--android-template', type=Path)
    parser.add_argument('--android-sdk', type=Path)
    parser.add_argument('--java-home', type=Path)
    parser.add_argument('--build-tools', type=Path)
    args = parser.parse_args()
    root = args.source.resolve(); out = args.output.resolve(); key = args.existing_debug_keystore.resolve()
    try:
        require(key.is_file(), 'Existing authorized key is required; no key will be generated')
        require(not out.exists() or not any(out.iterdir()), 'Probe output must be empty')
        require(key != out and out not in key.parents, 'Signing key must remain outside the probe output')
        android = args.android_template is not None
        if android:
            require(all((args.android_sdk, args.java_home, args.build_tools)), 'Android requires SDK, Java, build-tools paths')
            require(args.android_template.is_file(), 'Android template missing')
        out.mkdir(parents=True, exist_ok=True)
        project = out/'fixture'; project.mkdir()
        source_native = root/'native/source_water'
        native = project/'native/source_water'; native.mkdir(parents=True)
        shutil.copytree(source_native/'bin', native/'bin')
        shutil.copy2(source_native/'source_water.gdextension', native/'source_water.gdextension')
        libraries = descriptor_libraries((native/'source_water.gdextension').read_bytes())
        if args.pre_register:
            (project/'.godot').mkdir()
            (project/'.godot/extension_list.cfg').write_text('res://native/source_water/source_water.gdextension\n')
        (project/'project.godot').write_text('''config_version=5
[application]
config/name="Native export probe"
run/main_scene="res://probe.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
''')
        (project/'probe.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="Probe" type="Node"]
script = ExtResource("1")
''')
        (project/'probe.gd').write_text('''extends Node
func _ready() -> void:
\tvar exists := ClassDB.class_exists("SourceWaterReadback")
\tvar expect_fallback := "--expect-fallback" in OS.get_cmdline_user_args()
\tprint("NATIVE_EXPORT_PROBE class_exists=", exists, " executable=", OS.get_executable_path())
\tif not exists:
\t\t# A missing optional helper must not hard-crash or prevent ordinary script execution.
\t\tprint("NATIVE_EXPORT_PROBE interpreted_fallback_reached=true")
\t\tget_tree().quit(0 if expect_fallback else 3)
\t\treturn
\tif expect_fallback:
\t\tget_tree().quit(4)
\t\treturn
\tvar helper: Object = ClassDB.instantiate("SourceWaterReadback")
\tvar fixture := Image.create(1, 1, false, Image.FORMAT_RGBAH)
\tfixture.fill(Color(0.03125, -0.125, 0.0625, 1.0))
\tvar parsed: Array = helper.parse_rgba16f(fixture.get_data(), 1, 0.32 - (-0.72))
\tvar ok: bool = parsed.size() == 5 and parsed[0][0] == 0.03125
\tprint("NATIVE_EXPORT_PROBE exact_parse=", ok)
\tget_tree().quit(0 if ok else 2)
''')
        presets = ''
        for index, platform in enumerate(('Windows Desktop', 'Linux')):
            presets += f'''[preset.{index}]
name="{platform}"
platform="{platform}"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
script_export_mode=0
[preset.{index}.options]
binary_format/architecture="x86_64"
'''
        if android:
            presets += f'''[preset.2]
name="Android"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
script_export_mode=0
[preset.2.options]
custom_template/debug={json.dumps(str(args.android_template.resolve()))}
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
package/unique_name="org.poolcore.exportprobe"
package/name="Native Export Probe"
package/signed=false
'''
        (project/'export_presets.cfg').write_text(presets)
        env = os.environ.copy()
        for name, directory in [('HOME','home'), ('XDG_CACHE_HOME','cache'), ('XDG_CONFIG_HOME','config'), ('XDG_DATA_HOME','data')]:
            env[name] = str(out/directory); (out/directory).mkdir()
        config = out/'config/godot'; config.mkdir()
        values = {'export/android/debug_keystore': str(key)}
        if android:
            values.update({'export/android/android_sdk_path': str(args.android_sdk.resolve()),
                           'export/android/java_sdk_path': str(args.java_home.resolve())})
        (config/'editor_settings-4.6.tres').write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
            ''.join(k+' = '+json.dumps(v)+'\n' for k,v in values.items()))
        commands = []
        def run(label, arguments, expected=0):
            command = [args.godot, '--headless', *map(str, arguments)]
            proc = subprocess.run(command, cwd=out, env=env, capture_output=True, text=True, timeout=150)
            text = proc.stdout + proc.stderr
            (out/(label+'.log')).write_text(text)
            commands.append({'label':label, 'exit_code':proc.returncode, 'expected':expected, 'log':label+'.log'})
            require(proc.returncode == expected, f'{label}: exit {proc.returncode}, expected {expected}; see isolated log')
            return text
        for platform, preset in [('windows','Windows Desktop'),('linux','Linux')]:
            folder = out/platform; folder.mkdir()
            run(platform+'-export', ['--path',project,'--export-pack',preset,folder/'probe.pck'])
            require(list(folder.iterdir()) == [folder/'probe.pck'], '--export-pack changed dependency-copy behavior; inspect before staging')
        require((project/'.godot/extension_list.cfg').is_file(), 'Export editor scan did not register the extension')
        linux = out/'linux'; pack = linux/'probe.pck'
        run('missing-native', ['--path',linux,'--main-pack',pack], 3)
        run('missing-native-fallback', ['--path',linux,'--main-pack',pack,'--','--expect-fallback'])
        for platform in ('linux','windows'):
            path = out/platform/libraries[platform]; path.parent.mkdir(parents=True)
            shutil.copy2(root/libraries[platform], path)
        run('separate-engine-without-path', ['--main-pack',pack], 3)
        run('separate-engine-with-path', ['--path',linux,'--main-pack',pack])
        moved = out/'Package with spaces 池核 !'; shutil.copytree(linux,moved)
        run('unicode-relocated-package', ['--path',moved,'--main-pack',moved/'probe.pck'])
        audits = {}
        for platform in ('linux','windows'):
            audits[platform] = pck_audit(SimpleNamespace(pck=out/platform/'probe.pck', platform=platform,
                package_root=out/platform, source=None, launcher=None))
        if android:
            folder = out/'android'; folder.mkdir(); apk = folder/'probe-unsigned.apk'
            run('android-unsigned-export', ['--path',project,'--export-debug','Android',apk])
            audits['android'] = apk_audit(SimpleNamespace(apk=apk, source=None, build_tools=args.build_tools,
                package_id='org.poolcore.exportprobe', require_signature=False))
        require(not list(out.rglob('*.keystore')) and not list(out.rglob('*.jks')), 'Unexpected generated key in probe output; do not distribute')
        report = {'status':'PASS', 'commands':commands, 'audits':audits,
                  'findings':{'export_pack_copies_native_libraries':False, 'explicit_package_path_loads_native':True,
                              'missing_native_keeps_interpreted_execution':True, 'unicode_and_space_path_linux_tested':True,
                              'windows_executed':False, 'android_executed':False, 'probe_apk_signed':False, 'registration_preseeded':args.pre_register}}
        (out/'native-export-probe.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps({'status':'PASS','report':str(out/'native-export-probe.json'),'checks':len(commands)},ensure_ascii=False))
        return 0
    except (AuditError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f'NATIVE_EXPORT_PROBE_FAIL: {exc}',file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
