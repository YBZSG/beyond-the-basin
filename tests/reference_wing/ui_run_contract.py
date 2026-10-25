#!/usr/bin/env python3
"""Isolated headless UI/settings/restart review. Never imports/runs the main game.

Copies the real optical modules and extracts exact main.gd methods into a small
host with explicitly inert world/quit hooks. Real ConfigFile save/load happens in
a throwaway HOME and all XDG directories. No editor, GPU, extension or restart.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
METHODS = ["_load_settings", "_save_settings", "_change_reference_setting", "_apply_reference_settings", "_set_filter", "_build_water_panel", "_water_value_text", "_add_water_slider", "_reset_wind_settings", "_button", "_add_check", "_apply_live_water", "_set_source_fog", "parse_seed_input", "_read_seed_input", "_choose_spawn", "_restart_into_selected_world"]
FILES = ["scripts/reference_wing/reference_look_settings.gd", "scripts/reference_wing/reference_controls.gd", "scripts/reference_wing/reference_catalog.gd", "scripts/water/source_port/source_water_settings.gd", "scripts/app/world_restart.gd", "scripts/rendering/pc_mainhall_lightmap_preview.gd", "shaders/reference_wing/reference_camera_look.gdshader", "tests/reference_wing/ui_contract.gd"]

def method(source, name):
    match = re.search(r"^(?:static )?func " + re.escape(name) + r"\(.*?(?=^(?:static )?func |\Z)", source, re.M | re.S)
    if not match:
        raise RuntimeError(f"Missing production method {name}")
    return match.group().rstrip() + "\n"

def make_host(source):
    header = '''extends Node3D
const ReferenceLook=preload("res://scripts/reference_wing/reference_look_settings.gd")
const ReferenceControls=preload("res://scripts/reference_wing/reference_controls.gd")
const WaterSettingsScript=preload("res://scripts/water/source_port/source_water_settings.gd")
const MainhallPreview=preload("res://scripts/rendering/pc_mainhall_lightmap_preview.gd")
'''
    var_names = ["_reference_settings", "_world_restart", "_spawn_mode", "world_seed", "_avatar_enabled", "_avatar_fabric_enabled", "_facility_enabled", "_depth_wading_enabled", "_quality", "_audio_on", "_ambience_on", "_gi_on", "_caustics_on", "_fog_on", "_water_settings", "_water_visible", "_pc_preview_return_spawn", "_pc_mainhall_preview", "_ccd_on", "_filter_mode", "_film_rect", "_advanced", "_menu", "_wind_controls", "water", "source_fog", "_retiring_world", "_switching_spawn", "_booted", "_spawn_select", "_seed_edit", "_seed_input_status", "_world_restart_status", "_world_restart_button"]
    header += re.search(r"^const SPAWN_MODES.*$", source, re.M).group() + "\n"
    for name in var_names:
        header += re.search(r"^var " + re.escape(name) + r"(?:\s|:|=).*$", source, re.M).group() + "\n"
    header += '''var regeneration_calls: Array=[]
var preview_calls: Array=[]
func regenerate(seed_value: int)->void: regeneration_calls.append({"mode":_spawn_mode,"seed":seed_value})
func _set_pc_mainhall_preview(enabled:bool,target_spawn:String="")->void: preview_calls.append([enabled,target_spawn])
func _safe_quit()->void: push_error("Test must never quit/relaunch the game")
func set_menu(_value:bool)->void: pass
'''
    interface = method(source, "_build_interface")
    film = interface[interface.index("\tvar film_layer:="):interface.index("\t_build_water_panel(ui)")]
    options = interface[interface.index("\t_spawn_select=OptionButton.new()"):interface.index("\tspawn_row.add_child(_spawn_select)")]
    header += "\nfunc build_camera_fixture()->void:\n" + film
    header += "\nfunc build_world_options_fixture()->void:\n" + options
    header += "\n" + "\n".join(method(source, name) for name in METHODS)
    return header

def source_contracts(source):
    old_modes = '["original", "formal", "expanded", "poolrooms", "reference"]'
    ready = method(source, "_ready")
    create = method(source, "_create_world")
    qa = method(source, "_run_qa_capture")
    return {
        "five_modes_append_preserves_legacy_indices": f"const SPAWN_MODES := {old_modes}" in source,
        "reference_cli_is_explicit": 'if "--reference-wing" in OS.get_cmdline_user_args(): _spawn_mode="reference"' in ready,
        "original_cli_override_still_after_reference": ready.index('"--reference-wing"') < ready.index('"--legacy-world"'),
        "new_world_is_selected_only_by_reference_mode": 'world = ReferenceWorld.new() if _spawn_mode == "reference" else WorldScript.new()' in create,
        "reference_water_split_not_solver_replacement_for_old_world": 'water = ReferenceSceneWater.new() if _spawn_mode == "reference" else (ReferenceWater.new() if MainhallPreview.desktop_allowed() else WaterScript.new())' in create,
        "new_water_receives_saved_optical_intent": 'water.set_reference_wave_settings(_reference_settings)' in create,
        "reference_destinations_are_exact_five": 'for coord: Vector2i in ReferenceCatalog.COORDS:' in method(source, "_rebuild_destinations"),
        "qa_uses_catalog_fixed_camera": all(s in qa for s in ['ReferenceCatalog.camera(index)', 'player.warp_to(view.position-Vector3.UP*PlayerScript.EYE_HEIGHT,view.target)', 'player.camera.fov=view.fov']),
        "focus_follow_is_guarded_desktop_only": "scroll.follow_focus=MainhallPreview.desktop_allowed()" in method(source, "_build_water_panel"),
        "hud_remains_above_film_by_default": '_overlay = CanvasLayer.new()' in source and '_overlay.layer' not in source and 'film_layer.layer=0 if MainhallPreview.desktop_allowed() else 2' in source,
    }

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--godot',default='godot');parser.add_argument('--report',type=Path);args=parser.parse_args()
    source=(ROOT/'scripts/main.gd').read_text()
    with tempfile.TemporaryDirectory(prefix='poolcore-reference-ui-', dir='/tmp') as name:
        fixture=Path(name)
        for relative in FILES + [str(p.relative_to(ROOT)) for p in (ROOT/'assets/models/reference_wing').glob('*.geometry.json')]:
            target=fixture/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/relative,target)
        (fixture/'tests/reference_wing/ui_host.gd').write_text(make_host(source))
        desktop=(ROOT/'scripts/rendering/desktop_quality_panel.gd').read_text()
        (fixture/'tests/reference_wing/ui_desktop_settings.gd').write_text('extends Node\nvar settings:Dictionary={}\nvar preset:=\"High\"\nvar settings_path:=\"user://desktop_quality.cfg\"\nvar _status:Label\n' + method(desktop,'save_settings'))
        (fixture/'tests/reference_wing/ui_sources.json').write_text(json.dumps(source_contracts(source)))
        (fixture/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Reference UI isolated contract"\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n')
        env=dict(os.environ)
        for variable,name in [('HOME','home'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
            path=fixture/name;path.mkdir();env[variable]=str(path)
        env.pop('POOLCORE_RESTART_LAUNCH_V1',None)
        result=subprocess.run([args.godot,'--headless','--path',str(fixture),'--script','res://tests/reference_wing/ui_contract.gd'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90,check=False)
        print(result.stdout,end='')
        prefix='REFERENCE_UI_CONTRACT '
        reports=[json.loads(line[len(prefix):]) for line in result.stdout.splitlines() if line.startswith(prefix)]
        bad=any('SCRIPT ERROR' in line or line.startswith('ERROR:') for line in result.stdout.splitlines())
        report=reports[-1] if reports else {'passed':False,'error':'No completed contract report'}
        reload_result=subprocess.run([args.godot,'--headless','--path',str(fixture),'--script','res://tests/reference_wing/ui_contract.gd','--','--reload-verification'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60,check=False)
        print(reload_result.stdout,end='')
        reload_reports=[json.loads(line[len(prefix):]) for line in reload_result.stdout.splitlines() if line.startswith(prefix)]
        report['separate_process_reload']=reload_reports[-1] if reload_reports else {'passed':False,'error':'No reload report'}
        bad=bad or any('SCRIPT ERROR' in line or line.startswith('ERROR:') for line in reload_result.stdout.splitlines())
        report['passed']=report.get('passed',False) and report['separate_process_reload'].get('passed',False) and reload_result.returncode==0
        report['main_sha256']=hashlib.sha256(source.encode()).hexdigest()
        report['production_source_sha256']={relative:hashlib.sha256((fixture/relative).read_bytes()).hexdigest() for relative in FILES if relative.startswith(('scripts/','shaders/'))}
        report['camera_contract_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (fixture/'assets/models/reference_wing').glob('*.geometry.json')}
        report['desktop_quality_source_sha256']=hashlib.sha256(desktop.encode()).hexdigest()
        report['extracted_production_methods']=METHODS
        report['isolated_home_and_all_xdg']=True
        report['process_exit']=result.returncode
        report['engine_error']=bad
        if args.report:
            args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        return 0 if report.get('passed') and not bad and result.returncode==0 else 2
if __name__=='__main__':raise SystemExit(main())
