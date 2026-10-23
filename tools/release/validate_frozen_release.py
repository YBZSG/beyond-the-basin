#!/usr/bin/env python3
"""CPU-only final source + actual PCK cache identity gate, using a Linux host.

No export, import, baking, key access, signing, device launch, or GPU operation.
The actual PCK is copied into an isolated host probe with its source-matching
Linux helper. This does not claim that the Windows DLL executed on Linux.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
# Verification may run from an immutable staged tree; never create local bytecode.
sys.dont_write_bytecode = True
from types import SimpleNamespace
from stage_release import sha
from audit_packages import AuditError, descriptor_libraries, pck_audit, require

def stage_process_bound_validator(original, out):
    """Adapt only argv observation; Godot consumes engine options before OS argv."""
    original, out = Path(original), Path(out)
    text = original.read_text()
    needle = '\tvar arguments := OS.get_cmdline_args()\n'
    require(text.count(needle) == 1, 'Terrain validator argv adapter no longer matches; review explicitly')
    replacement = '''\t# Linux-only release adapter: read this process's real argv, not consumed Godot options.
\tvar arguments: Array[String] = []
\tvar process_arguments := FileAccess.open("/proc/self/cmdline", FileAccess.READ)
\tif process_arguments == null:
\t\terrors.append("Cannot bind actual process command line")
\telse:
\t\tvar argument_bytes: PackedByteArray = []
\t\tfor byte in process_arguments.get_buffer(65536):
\t\t\tif byte == 0:
\t\t\t\tvar value := argument_bytes.get_string_from_utf8()
\t\t\t\tif value == "--": break
\t\t\t\targuments.append(value)
\t\t\t\targument_bytes.clear()
\t\t\telse: argument_bytes.append(byte)
'''
    adapted = out / 'cache-validator-process-argv.gd'
    require(not adapted.exists(), 'Refuse to replace existing validator adapter')
    adapted.write_text(text.replace(needle, replacement))
    proof = {'original_sha256': sha(original), 'adapter_sha256': sha(adapted),
             'only_change': 'Observe /proc/self/cmdline before the user-argument separator; retain all terrain/source/no-fallback guards.',
             'frozen_source_modified': False, 'linux_only': True}
    (out / 'cache-validator-adapter.json').write_text(json.dumps(proof, indent=2) + '\n')
    return adapted

def authored_catalog(source):
    text = (Path(source)/'scripts/world/formal_rooms.gd').read_text()
    match = re.search(r'^const COORDS:[^\n]*=\s*\[(.*)\]\s*$',text,re.M)
    require(match is not None,'Cannot read authored room catalog; update gate for any syntax change')
    coordinates = [(int(x),int(y)) for x,y in re.findall(r'Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)',match.group(1))]
    require(len(coordinates)==5 and len(set(coordinates))==5,'Expected five distinct authored release rooms')
    return coordinates

def check_cache_report(result, seed, sizes, coordinates, expected_pack=None):
    require(result.get('pass') is True and result.get('seed')==seed,'Cache report failed or seed differs')
    require(result.get('errors')==[] and result.get('sizes')==sizes,'Cache report has errors or incomplete quality coverage')
    coords = [f'({x}, {y})' for x,y in coordinates]
    snapshot=result.get('snapshot',{})
    require(snapshot.get('exists') is True and not snapshot.get('reason'),'Exact imported snapshot was not loaded')
    require(snapshot.get('coords')==coords,'Snapshot authored catalog/order differs')
    require(result.get('publication_order')==coords,'World publication order differs from authored catalog')
    entries=result.get('terrain',[])
    expected={(coord,size) for coord in coords for size in sizes}
    actual={(entry.get('coord'),entry.get('size')) for entry in entries}
    require(len(entries)==len(expected) and actual==expected,'Incomplete or duplicate authored terrain coverage')
    require(all(entry.get('valid') is True and re.fullmatch(r'[0-9a-f]{64}',entry.get('sha256','')) for entry in entries),
            'Missing valid exact terrain hashes')
    require(len({entry.get('key') for entry in entries})==len(entries),'Duplicate terrain cache keys')
    signatures=result.get('source_signatures',{})
    require(signatures and all(re.fullmatch(r'[0-9a-f]{64}',value) for value in signatures.values()),'Missing source identities')
    if expected_pack is not None:
        require(Path(result.get('main_pack','')).resolve()==Path(expected_pack).resolve(),'Validator did not report the actual isolated PCK')
    else:
        require(not result.get('main_pack'),'Source validation unexpectedly used a PCK')
    return {entry['key']:entry['sha256'] for entry in entries}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--pck', type=Path, required=True)
    p.add_argument('--package-root', type=Path, required=True, help='Staged Windows package with external DLL')
    p.add_argument('--report-dir', type=Path, required=True, help='New empty isolated report/probe directory')
    p.add_argument('--godot', default='godot')
    p.add_argument('--seed', type=int, default=250821)
    p.add_argument('--all-quality', action='store_true')
    p.add_argument('--all-early-rooms', action='store_true', help='Also verify all five early teleports in both source and actual PCK')
    args = p.parse_args()
    try:
        source = args.source.resolve(); pack = args.pck.resolve(); package = args.package_root.resolve(); out = args.report_dir.resolve()
        require(sys.platform.startswith('linux'), 'This headless gate currently targets Linux x86_64 host, not Windows execution')
        require(not out.exists() or not any(out.iterdir()), 'Report directory must be new or empty')
        out.mkdir(parents=True,exist_ok=True)
        audit = pck_audit(SimpleNamespace(pck=pack,platform='windows',package_root=package,source=source,
                         launcher=package/'Launch-PoolCore.cmd'))
        validator = source/'tools/cache/validate_formal_terrain.gd'
        require(validator.is_file(), 'Read-only terrain validator missing')
        validator = stage_process_bound_validator(validator, out)
        env = os.environ.copy()
        for key,name in [('HOME','home'),('XDG_CACHE_HOME','cache'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data')]:
            env[key]=str(out/name); (out/name).mkdir()
        host = out/'host-pck-probe'; host.mkdir()
        shutil.copy2(pack,host/'actual-release.pck')
        libraries = descriptor_libraries((source/'native/source_water/source_water.gdextension').read_bytes())
        native = host/libraries['linux']; native.parent.mkdir(parents=True); shutil.copy2(source/libraries['linux'],native)
        # Exercise the actual exported production parser twice in separate
        # processes, once with the Linux helper and once with no helper at all.
        # Missing-library load diagnostics are expected only in the second case.
        fallback_host = out/'host-no-helper-probe'; fallback_host.mkdir()
        os.link(host/'actual-release.pck',fallback_host/'actual-release.pck')
        parser_probe = source/'tools/release/verify_pack_native_fallback.gd'
        require(parser_probe.is_file(), 'Actual production native/fallback CPU probe missing')
        parser_reports = {}
        for label,probe_host,missing in [('native',host,False),('fallback',fallback_host,True)]:
            report=out/('pck-parser-'+label+'.json')
            command=[args.godot,'--headless','--path',str(probe_host),'--main-pack',str(probe_host/'actual-release.pck'),
                     '--script',str(parser_probe),'--','--report='+str(report)]
            if missing: command.append('--expect-fallback')
            else: command.append('--expected-helper='+str(native))
            proc=subprocess.run(command,cwd=out,env=env,capture_output=True,text=True,timeout=60)
            (out/('pck-parser-'+label+'.log')).write_text(proc.stdout+proc.stderr)
            require(proc.returncode==0 and report.is_file(),f'Actual PCK {label} parser failed; see pck-parser-{label}.log')
            result=json.loads(report.read_text())
            require(result.get('pass') is True and result.get('expected_fallback')==missing,
                    f'Actual PCK {label} parser report failed')
            expected_mappings=[] if missing else [str(native)]
            require(result.get('loaded_native_libraries')==expected_mappings, 'Native helper mapped from an unexpected directory')
            if not missing:
                require(result.get('mapped_helper_sha256')==sha(native), 'Mapped helper bytes differ from isolated host')
            parser_reports[label]=report.name
        coordinates=authored_catalog(source)
        sizes=[384,768,1152] if args.all_quality else [768]
        cases=[('default',None)]
        if args.all_early_rooms: cases += [(f'early-{i:02d}',coord) for i,coord in enumerate(coordinates)]
        jobs=[(platform,case,early,base) for case,early in cases for platform,base in
              [('source',['--path',source]),('pck',['--path',host,'--main-pack',host/'actual-release.pck'])]]
        results = {}; terrain_sets={}; report_files={}
        for platform,case,early,base in jobs:
            label=platform if case=='default' else platform+'-'+case
            report = out/(label+'-cache.json')
            command = [args.godot,'--headless','--fixed-fps','120',*map(str,base),'--script',str(validator),'--',
                       '--seed='+str(args.seed),'--report='+str(report)]
            if args.all_quality: command.append('--all-quality')
            if early is not None: command.append(f'--early-room={early[0]},{early[1]}')
            if platform == 'pck': command.append('--require-pck')
            proc = subprocess.run(command,cwd=out,env=env,capture_output=True,text=True,timeout=300)
            log = proc.stdout + proc.stderr
            (out/(label+'-cache.log')).write_text(log)
            require(proc.returncode == 0, f'{label} cache validator failed ({proc.returncode}); see {label}-cache.log')
            require(report.is_file(), f'{label} validator did not write report')
            result = json.loads(report.read_text())
            terrain_sets[label]=check_cache_report(result,args.seed,sizes,coordinates,
                host/'actual-release.pck' if platform=='pck' else None)
            expected_early=None if early is None else f'({early[0]}, {early[1]})'
            require(result.get('early_room')==expected_early,f'{label} did not exercise the requested early-room case')
            results[label] = result
            report_files[label]=report.name
        for label,result in results.items():
            require(results['source']['source_signatures']==result['source_signatures'],f'{label} algorithm identities differ')
            require(results['source']['snapshot']==result['snapshot'],f'{label} imported snapshot identity differs')
            require(results['source']['algorithm']==result['algorithm'],f'{label} cache schema identity differs')
            require(terrain_sets['source']==terrain_sets[label],f'{label} exact terrain differs')
        source_entries=terrain_sets['source']
        result = {'status':'PASS','seed':args.seed,'all_quality':args.all_quality,'package_audit':audit,
                  'source_cache_report':'source-cache.json','actual_pck_cache_report':'pck-cache.json',
                  'all_early_rooms':args.all_early_rooms,'case_reports':report_files,'validator_runs':len(jobs),
                  'actual_pck_parser_reports':parser_reports,'native_and_missing_helper_cpu_parser_verified':True,
                  'cache_validator_adapter':'cache-validator-adapter.json',
                  'matching_terrain_entries':len(source_entries),'linux_headless_only':True,
                  'windows_or_android_executed':False,'gpu_or_pixels_verified':False}
        (out/'frozen-release-gate.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps({'status':'PASS','terrain_entries':len(source_entries),'report':str(out/'frozen-release-gate.json')},ensure_ascii=False))
        return 0
    except (AuditError,OSError,ValueError,subprocess.TimeoutExpired) as exc:
        print(f'FROZEN_RELEASE_GATE_FAIL: {exc}',file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
