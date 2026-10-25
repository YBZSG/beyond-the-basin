#!/usr/bin/env python3
"""Isolated CPU + official-Godot dummy-renderer validation. Never starts game."""
from pathlib import Path
import argparse
import json
import math
import os
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]


def run():
    parser=argparse.ArgumentParser()
    parser.add_argument('--godot',default='godot')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--blender',help='Optional no-render Blender node contract and parameter parity check')
    parser.add_argument('--candidate-normal',type=Path,help='Optional QA normal used only by the Blender candidate isolation check')
    args=parser.parse_args()
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix='reference-material-contract-'))
    files=[ROOT/'scripts/reference_wing/reference_materials.gd',
           ROOT/'shaders/source_water/caustic_receiver.gdshaderinc',
           ROOT/'scripts/art_pass/art_pass_materials.gd',
           ROOT/'shaders/art_pass_pbr.gdshader',
           ROOT/'tests/reference_wing/material_lab.gd',
           ROOT/'tests/reference_wing/material_contract.gd']
    files+=list((ROOT/'shaders/reference_wing').glob('reference_glaze*'))
    files+=list((ROOT/'assets/materials/reference_wing').glob('*_2k.png*'))
    for source in files:
        destination=stage/source.relative_to(ROOT)
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,destination)
    (stage/'project.godot').write_text('''config_version=5
[application]
config/name="Reference material headless contract"
config/features=PackedStringArray("4.6")
[rendering]
renderer/rendering_method="gl_compatibility"
textures/vram_compression/import_s3tc_bptc=true
''')
    env=os.environ.copy()
    for variable,subdirectory in [('HOME','home'),('XDG_CACHE_HOME','cache'),
                                 ('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config')]:
        env[variable]=str(stage/subdirectory)
        Path(env[variable]).mkdir()
    commands=[['python',str(ROOT/'tests/reference_wing/test_materials.py')],
              [args.godot,'--headless','--path',str(stage),'--editor','--import'],
              [args.godot,'--headless','--path',str(stage),'--check-only','--script','tests/reference_wing/material_lab.gd'],
              [args.godot,'--headless','--path',str(stage),'--quit-after','120','--script','tests/reference_wing/material_contract.gd']]
    if args.blender:
        command=[args.blender,'--background','--factory-startup','-t','2','--python-exit-code','1','--python',str(ROOT/'tests/reference_wing/blender_material_contract.py')]
        if args.candidate_normal: command+=['--','--candidate-normal',str(args.candidate_normal.resolve())]
        commands.append(command)
    records=[]
    for index,command in enumerate(commands):
        try:
            result=subprocess.run(command,cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
        except subprocess.TimeoutExpired as error:
            log=error.stdout or b''
            if isinstance(log,bytes): log=log.decode(errors='replace')
            result=subprocess.CompletedProcess(command,124,stdout=log+'\nERROR: Timed out after 240 seconds.\n')
        (output/f'{index+1}.log').write_text(result.stdout)
        record={'command':command,'returncode':result.returncode,'log':f'{index+1}.log'}
        records.append(record)
        print(result.stdout)
        if result.returncode or any(token in result.stdout for token in ['ERROR:','Parse Error:']):
            break
    success=len(records)==len(commands) and all(item['returncode']==0 for item in records)
    parity_errors=[]
    if success:
        log=(output/'4.log').read_text()
        success='"passed":true' in log.replace(' ','')
        if success and args.blender:
            godot=json.loads(log.split('REFERENCE_MATERIAL_CONTRACT ',1)[1].splitlines()[0])
            blender_log=(output/'5.log').read_text()
            marker='REFERENCE_BLENDER_MATERIAL_CONTRACT '
            if marker not in blender_log:
                parity_errors.append('Missing Blender contract result')
            else:
                blender=json.loads(blender_log.split(marker,1)[1].splitlines()[0])
                if not blender['passed']: parity_errors+=blender['errors']
                gd_roles=godot['stats']['physical_dimensions_by_role'];bl_roles=blender['role_parameters']
                if set(gd_roles)!=set(bl_roles):parity_errors.append('Runtime/Blender role sets differ')
                for role,parameters in bl_roles.items():
                    for key,value in parameters.items():
                        actual=gd_roles.get(role,{}).get(key,-999)
                        equal=(isinstance(actual,list) and len(actual)==len(value) and all(math.isclose(a,b,abs_tol=2e-6) for a,b in zip(actual,value))) if isinstance(value,list) else math.isclose(actual,value,abs_tol=2e-6)
                        if not equal:
                            parity_errors.append(role+'/'+key+' differs between runtime and Blender node contract')
            success=not parity_errors
    report={'passed':success,'stage':str(stage),'steps':records,
            'runtime_blender_parameter_parity':(not parity_errors) if args.blender and success else None,
            'parity_errors':parity_errors,
            'scope':'CPU formulas and official Godot headless dummy-renderer resources/import decoding. No game, GPU execution, visuals, native NVIDIA RT/RR/NR or performance validation.'}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return 0 if success else 1


if __name__=='__main__': raise SystemExit(run())
