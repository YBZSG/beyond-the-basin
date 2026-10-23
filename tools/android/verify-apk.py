#!/usr/bin/env python3
"""Check a signed current-source APK offline. No install or device connection."""
import hashlib,json,os,pathlib,re,subprocess,sys,zipfile
root=pathlib.Path(__file__).resolve().parents[2]
apk=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else root/'output/android/PoolCore-Source-Water-Android-Test.apk'
sdk=pathlib.Path(os.environ['ANDROID_SDK_ROOT'])
versions=sorted((sdk/'build-tools').iterdir(),key=lambda p:[int(n) for n in re.findall(r'\d+',p.name)])
tools=versions[-1]
def command(*args):
 p=subprocess.run([str(a) for a in args],capture_output=True,text=True)
 if p.returncode:raise RuntimeError(p.stdout+'\n'+p.stderr)
 return p.stdout,p.stderr
signature,signature_warnings=command(tools/'apksigner','verify','--verbose',apk)
assert 'v2): true' in signature and 'v3): true' in signature,signature
alignment,_=command(tools/'zipalign','-c','-P','16','-v','4',apk)
assert 'Verification successful' in alignment
manifest,manifest_warnings=command(tools/'aapt2','dump','badging',apk)
assert "native-code: 'arm64-v8a'" in manifest
assert 'application-debuggable' in manifest
assert "package: name='org.poolcore.beyondthebasin'" in manifest
permissions=[line for line in manifest.splitlines() if line.startswith('uses-permission')]
assert permissions==[],permissions
with zipfile.ZipFile(apk) as z:
 assert z.testzip() is None
 names=z.namelist()
 assert not any(n.lower().endswith(('.keystore','.jks','.pem','.p12')) for n in names)
 assert 'assets/scripts/water/source_water_runtime.gdc' in names
 assert 'assets/scripts/mobile/pool_mobile_capabilities.gdc' in names
 checked=[]
 for p in (root/'shaders').rglob('*'):
  if p.suffix in ['.glslinc','.vert','.frag','.rg16f']:
   entry='assets/'+p.relative_to(root).as_posix()
   assert z.read(entry)==p.read_bytes(),entry
   checked.append(entry)
report={'apk':apk.name,'bytes':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),
 'signature_v2_v3':True,'zipalign_16k':True,'zip_crc':True,'abi':'arm64-v8a','debuggable':True,
 'permissions':permissions,'original_source_runtime':True,'source_assets_byte_exact':checked,
 'private_signing_material_in_apk':False,'device_install_tested':False,'phone_performance_tested':False,
 'manifest':manifest.splitlines(),'warnings':(signature_warnings+'\n'+manifest_warnings).strip()}
path=apk.with_suffix('.verification.json');path.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['source_assets_byte_exact','manifest']},indent=2))
print('Verified raw original-source shader assets:',len(checked))
print('Verification report:',path)
