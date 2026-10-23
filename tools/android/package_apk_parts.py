#!/usr/bin/env python3
"""Losslessly split the CURRENT signed APK. Never installs or publishes it."""
import hashlib, json, pathlib, sys, zipfile
root = pathlib.Path(__file__).resolve().parents[2]
apk = pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else root/'output/android/PoolCore-Source-Water-Android-Test.apk'
out = apk.parent/'parts-current-source'
out.mkdir(parents=True, exist_ok=True)
data = apk.read_bytes()
expected = hashlib.sha256(data).hexdigest()
parts = []
for i, start in enumerate(range(0,len(data),14_000_000),1):
    name = f'APK.part{i:02d}'
    body = data[start:start+14_000_000]
    (out/name).write_bytes(body)
    parts.append({'file':name,'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest()})
assert b''.join((out/p['file']).read_bytes() for p in parts) == data
manifest = {'apk':apk.name,'bytes':len(data),'sha256':expected,'parts':parts,'lossless_reconstruction_verified':True}
(out/'SHA256.json').write_text(json.dumps(manifest,indent=2)+'\n')
readme = f'''原仓库水体 Android 测试 APK：无损 {len(parts)} 分卷
将全部 ZIP 解压到同一目录，双击 Rebuild-APK.cmd，或运行 python Rebuild-APK.py。
工具只读取本地分块、核对每块 SHA-256、合并并核对完整 APK。它不联网、不安装、不改执行策略。
完整 APK 文件名：{apk.name}
字节数：{len(data)}
SHA-256：{expected}
分块不能独立安装。请在 Android 手机上自行决定是否安装核对后的完整 APK。
这是 CURRENT 原仓库水体（SWE/APIC-MPM/光子焦散）的 Godot Android 64位 ARM 调试签名包，不是旧近似水体包。
API24+ 是模板最低系统门槛，不是完整 Vulkan 驱动兼容性保证。手机具体帧率与发热未实测。
不要与任何旧包的分块混合；已有不同同名 APK 时工具拒绝覆盖。
'''
(out/'README-Android.txt').write_text(readme,encoding='utf-8-sig')
python = r'''import hashlib,json,pathlib,tempfile,os
base=pathlib.Path(__file__).resolve().parent
m=json.loads((base/'SHA256.json').read_text())
expected='__HASH__'
if m['sha256']!=expected:raise RuntimeError('Unexpected manifest. Use matching parts.')
target=base/m['apk']
if target.exists():
 if hashlib.sha256(target.read_bytes()).hexdigest()==expected:print('Existing APK verified. No change.');raise SystemExit(0)
 raise RuntimeError('Different existing APK. Refusing overwrite.')
payload=b''
for p in m['parts']:
 body=(base/p['file']).read_bytes()
 if len(body)!=p['bytes'] or hashlib.sha256(body).hexdigest()!=p['sha256']:raise RuntimeError('Part verification failed: '+p['file'])
 payload+=body
if len(payload)!=m['bytes'] or hashlib.sha256(payload).hexdigest()!=expected:raise RuntimeError('APK verification failed.')
with target.open('xb') as f:f.write(payload)
print('SHA-256 verified. APK created. No installation performed.')
'''.replace('__HASH__',expected)
(out/'Rebuild-APK.py').write_text(python)
ps = r'''$ErrorActionPreference='Stop'
$Base=(Get-Location).Path
$M=Get-Content -LiteralPath (Join-Path $Base 'SHA256.json') -Raw | ConvertFrom-Json
$Expected='__HASH__'
if ($M.sha256 -ne $Expected) { throw 'Unexpected manifest. Use matching parts.' }
$Target=Join-Path $Base $M.apk
if (Test-Path -LiteralPath $Target) {
 if ((Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Expected) { Write-Host 'Existing APK verified. No change.'; exit 0 }
 throw 'Different existing APK. Refusing overwrite.'
}
$Temporary=Join-Path $Base ('.PoolCore-'+[Guid]::NewGuid().ToString('N')+'.partial')
try {
 $Output=[System.IO.File]::Open($Temporary,[System.IO.FileMode]::CreateNew)
 try {
  foreach ($P in $M.parts) {
   $Path=Join-Path $Base $P.file
   if ((Get-Item -LiteralPath $Path).Length -ne $P.bytes -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $P.sha256) { throw ('Part verification failed: '+$P.file) }
   $Input=[System.IO.File]::OpenRead($Path)
   try { $Input.CopyTo($Output) } finally { $Input.Dispose() }
  }
 } finally { $Output.Dispose() }
 if ((Get-Item -LiteralPath $Temporary).Length -ne $M.bytes -or (Get-FileHash -LiteralPath $Temporary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) { throw 'APK verification failed.' }
 [System.IO.File]::Move($Temporary,$Target)
 Write-Host 'SHA-256 verified. APK created. No installation performed.'
} finally { if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary } }
'''.replace('__HASH__',expected)
(out/'Rebuild-APK.ps1').write_text(ps,encoding='utf-8-sig')
# Inline literal code means no execution-policy change and no unsigned PS1 load.
command = '@echo off\r\ncd /d "%~dp0"\r\npowershell -NoProfile -Command "'+ps.replace('\n','; ').replace('"','\\"')+'"\r\npause\r\n'
(out/'Rebuild-APK.cmd').write_bytes(command.encode('ascii'))
for i,p in enumerate(parts,1):
    name=apk.parent/f'PoolCore-Source-Water-Android-Part{i}-of-{len(parts)}.zip'
    with zipfile.ZipFile(name,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        z.write(out/p['file'],p['file'])
        for common in ['README-Android.txt','SHA256.json','Rebuild-APK.py','Rebuild-APK.ps1','Rebuild-APK.cmd']:
            z.write(out/common,common)
    assert name.stat().st_size<15_000_000
    print(name.name,name.stat().st_size)
print(json.dumps(manifest,indent=2))
