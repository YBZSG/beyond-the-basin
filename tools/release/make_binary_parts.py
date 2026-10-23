#!/usr/bin/env python3
"""Lossless bounded delivery ZIPs for an already-validated PC ZIP or signed APK.

Never exports, signs, installs, executes a game, downloads or publishes. Every
delivery ZIP is independently extractable, but its binary part is NOT playable
or installable until all parts are verified and reassembled locally.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
# Verification may run from an immutable staged tree; never create local bytecode.
sys.dont_write_bytecode = True
import zipfile
from audit_packages import AuditError, require
from stage_release import sha


PYTHON_REBUILD = r'''import hashlib,json,pathlib,tempfile,os
base=pathlib.Path(__file__).resolve().parent
raw=(base/'__MANIFEST__').read_bytes()
if hashlib.sha256(raw).hexdigest()!='__MANIFEST_HASH__':raise RuntimeError('Manifest mismatch. Use matching delivery parts.')
m=json.loads(raw)
target=base/m['file']
def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
if target.exists():
 if target.is_file() and target.stat().st_size==m['bytes'] and sha(target)==m['sha256']:print('Existing file verified. No changes.');raise SystemExit(0)
 raise RuntimeError('A different target already exists. Refusing overwrite.')
fd,temporary=tempfile.mkstemp(prefix='.PoolCore-',suffix='.partial',dir=base)
temporary=pathlib.Path(temporary)
try:
 with os.fdopen(fd,'wb') as output:
  for part in m['parts']:
   path=base/part['file']
   if path.stat().st_size!=part['bytes'] or sha(path)!=part['sha256']:raise RuntimeError('Part verification failed: '+part['file'])
   with path.open('rb') as stream:
    for chunk in iter(lambda:stream.read(1024*1024),b''):output.write(chunk)
 if temporary.stat().st_size!=m['bytes'] or sha(temporary)!=m['sha256']:raise RuntimeError('Reconstructed file hash mismatch.')
 # A same-filesystem hard link creates the final path atomically without ever
 # replacing a file that appeared after the initial check.
 os.link(temporary,target)
 print('SHA-256 verified: '+m['file'])
 print('No installation, game launch, network operation or security change was performed.')
finally:
 if temporary.exists():temporary.unlink()
'''


POWERSHELL_REBUILD = r'''$ErrorActionPreference='Stop'
$Base=$env:POOLCORE_REBUILD_BASE
if ([string]::IsNullOrWhiteSpace($Base)) { $Base=$PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($Base)) { throw 'Run the provided CMD or this script from its extracted folder.' }
$Manifest=Join-Path $Base '__MANIFEST__'
if ((Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne '__MANIFEST_HASH__') { throw 'Manifest mismatch. Use matching delivery parts.' }
$M=Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$Target=Join-Path $Base $M.file
if (Test-Path -LiteralPath $Target) {
 if ((Get-Item -LiteralPath $Target).Length -eq $M.bytes -and (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $M.sha256) { Write-Host 'Existing file verified. No changes.'; exit 0 }
 throw 'A different target already exists. Refusing overwrite.'
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
 if ((Get-Item -LiteralPath $Temporary).Length -ne $M.bytes -or (Get-FileHash -LiteralPath $Temporary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $M.sha256) { throw 'Reconstructed file hash mismatch.' }
 [System.IO.File]::Move($Temporary,$Target)
 Write-Host ('SHA-256 verified: '+$M.file)
 Write-Host 'No installation, game launch, network operation or security change was performed.'
} finally { if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary } }
'''


def make_parts(source, output, label, part_bytes=14_000_000, maximum_zip_bytes=16_000_000, artifact_kind=None):
    source, output = Path(source).resolve(), Path(output).resolve()
    require(source.is_file() and source.suffix.lower() in {'.zip', '.apk'}, 'Input must be a completed PC ZIP or signed test APK')
    artifact_kind = artifact_kind or ('android-apk' if source.suffix.lower() == '.apk' else 'pc-archive')
    require(artifact_kind in {'pc-archive', 'android-apk', 'android-archive'}, 'Unknown transport artifact kind')
    require((artifact_kind == 'android-apk') == (source.suffix.lower() == '.apk'), 'Artifact kind differs from input extension')
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]+', source.name), 'Input filename must be portable ASCII')
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]+', label), 'Delivery label must be portable ASCII')
    require(256_000 <= part_bytes < maximum_zip_bytes - 65_536, 'Part size must leave ZIP/script overhead')
    require(not output.exists() or not any(output.iterdir()), 'Output must be new or empty')
    require(output not in source.parents, 'Input must be outside the delivery output')
    output.mkdir(parents=True, exist_ok=True)
    working = output / 'rebuild-files'; working.mkdir()
    before_size, before_hash = source.stat().st_size, sha(source)
    require(before_size > 0, 'Input is empty')
    parts, combined = [], hashlib.sha256()
    with source.open('rb') as stream:
        index = 0
        while body := stream.read(part_bytes):
            index += 1
            name = f'{source.name}.part{index:02d}'
            (working / name).write_bytes(body)
            combined.update(body)
            parts.append({'file': name, 'bytes': len(body), 'sha256': hashlib.sha256(body).hexdigest()})
    require(source.stat().st_size == before_size and sha(source) == before_hash == combined.hexdigest(),
            'Input changed while splitting; partial delivery is invalid')
    manifest_name = label + '-BINARY-PARTS.json'
    manifest = {'format': 1, 'file': source.name, 'bytes': before_size, 'sha256': before_hash, 'artifact_kind': artifact_kind,
                'parts': parts, 'all_parts_required': True, 'lossless_reconstruction_verified': True,
                'scope': 'Byte transport only; this manifest does not establish game/device validation.'}
    manifest_raw = (json.dumps(manifest, ensure_ascii=True, indent=2) + '\n').encode()
    (working / manifest_name).write_bytes(manifest_raw)
    manifest_hash = hashlib.sha256(manifest_raw).hexdigest()
    stem = {'android-apk':'Rebuild-APK', 'android-archive':'Rebuild-Android-Package', 'pc-archive':'Rebuild-PC-Package'}[artifact_kind]
    replacements = {'__MANIFEST__': manifest_name, '__MANIFEST_HASH__': manifest_hash}
    python, powershell = PYTHON_REBUILD, POWERSHELL_REBUILD
    for token, value in replacements.items():
        python, powershell = python.replace(token, value), powershell.replace(token, value)
    (working / (stem + '.py')).write_text(python)
    (working / (stem + '.ps1')).write_text(powershell, encoding='utf-8-sig')
    inline = '; '.join(line for line in powershell.splitlines() if line.strip())
    # Pass the Unicode directory only as environment DATA, never interpolate it
    # into PowerShell source. Inline the reviewed readable program, not -File.
    # No execution-policy bypass,
    # encoded command, downloaded script or credential is used.
    command = ('@echo off\r\nsetlocal EnableExtensions DisableDelayedExpansion\r\n'
               'set "POOLCORE_REBUILD_BASE=%~dp0"\r\n'
               'if not exist "%POOLCORE_REBUILD_BASE%." goto folder_failed\r\n'
               'powershell.exe -NoProfile -Command "' + inline + '"\r\n'
               'set "RESULT=%ERRORLEVEL%"\r\necho.\r\n'
               'if not "%RESULT%"=="0" echo Reconstruction failed. No incomplete final file was accepted.\r\n'
               'pause\r\nexit /b %RESULT%\r\n:folder_failed\r\n'
               'echo Cannot open the extracted folder. Fully extract every matching ZIP first.\r\n'
               'pause\r\nexit /b 2\r\n')
    require(len(command.encode('ascii')) < 8000, 'Windows command exceeds portable CMD limit')
    (working / (stem + '.cmd')).write_bytes(command.encode('ascii'))
    next_step = {
        'android-apk': 'The reconstructed APK is the complete signed test installer. Decide on installation yourself; no phone execution or performance pass is implied.',
        'android-archive': 'The reconstructed file is the complete ANDROID ZIP. Extract it to obtain the original signed APK and its hash. Nothing is installed automatically; phone execution/performance is unverified.',
        'pc-archive': 'The reconstructed file is the COMPLETE PC ZIP. Extract it into a new folder, keep the native subdirectories, then use Launch-PoolCore.cmd. Do not launch a PCK from a ZIP preview.',
    }[artifact_kind]
    readme = (f'PoolCore lossless delivery: {len(parts)} independently extractable ZIPs\n\n'
              f'Extract ALL matching {label} ZIPs into one new folder. Never mix releases.\n'
              f'Windows: double-click {stem}.cmd. Python 3: run python {stem}.py.\n'
              'The tool checks the manifest, each part and the entire final file using SHA-256.\n'
              'A different existing destination is never overwritten. Errors leave no accepted partial file.\n'
              'It does not download, install, upload, launch the game or change security/execution policy.\n'
              'If PowerShell is blocked by your policy, do not weaken it; use the Python alternative.\n'
              f'Output: {source.name}\nBytes: {before_size}\nSHA-256: {before_hash}\n\n{next_step}\n\n'
              '每个 ZIP 都可独立解压，但其中的二进制分块不能单独运行或安装。\n'
              '全部解压到同一文件夹后，运行对应 Rebuild CMD 或 Python 脚本，校验并合并。\n'
              '工具不联网、不安装、不启动游戏、不修改系统安全设置。请勿混用不同版本分块。\n')
    readme_name = label + '-RESTORE.txt'; (working / readme_name).write_text(readme, encoding='utf-8-sig')
    common = [manifest_name, readme_name] + [stem + suffix for suffix in ('.py', '.ps1', '.cmd')]
    archives = []
    for index, part in enumerate(parts, 1):
        name = f'{label}-Part{index:02d}-of-{len(parts):02d}.zip'; destination = output / name
        with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for filename in [part['file'], *common]:
                info = zipfile.ZipInfo(filename, (2026, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                archive.writestr(info, (working / filename).read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)
        require(destination.stat().st_size < maximum_zip_bytes, f'Delivery ZIP exceeds size bound: {name}')
        with zipfile.ZipFile(destination) as archive:
            require(archive.testzip() is None, f'CRC failure: {name}')
            require(hashlib.sha256(archive.read(part['file'])).hexdigest() == part['sha256'], f'Part bytes mismatch: {name}')
            for filename in common:
                require(archive.read(filename) == (working / filename).read_bytes(), f'Common file mismatch: {filename}')
        archives.append({'filename': name, 'bytes': destination.stat().st_size, 'sha256': sha(destination)})
    result = {'status': 'PASS', 'input': manifest, 'archives': archives, 'maximum_zip_bytes': maximum_zip_bytes,
              'rebuild_script': stem, 'windows_cmd_executed': False, 'phone_or_game_executed': False}
    (output / (label + '-DELIVERY.json')).write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--part-bytes', type=int, default=14_000_000)
    parser.add_argument('--max-zip-bytes', type=int, default=16_000_000)
    parser.add_argument('--kind', choices=('pc-archive', 'android-apk', 'android-archive'))
    args = parser.parse_args()
    try:
        print(json.dumps(make_parts(args.input, args.output, args.label, args.part_bytes, args.max_zip_bytes, args.kind), indent=2))
        return 0
    except (AuditError, OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f'BINARY_PARTS_FAIL: {exc}. Partial output is NOT a delivery.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
