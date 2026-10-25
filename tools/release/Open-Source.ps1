param([string]$Engine='', [switch]$Play)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (!$Engine) { $Engine=Join-Path $env:LOCALAPPDATA 'Programs\PoolCore\PoolCoreEditor.exe' }
$Engine=[IO.Path]::GetFullPath($Engine)
if (!(Test-Path -LiteralPath $Engine)) { throw 'Install PoolCore PC 0.6.13 first, or drag its PoolCoreEditor.exe onto Open-Editor.cmd.' }
if (!(Test-Path -LiteralPath (Join-Path $project 'project.godot'))) { throw 'The source project is incomplete.' }
if (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($Engine,'.pck'))) { throw 'Use PoolCoreEditor.exe, not PoolCore.exe beside a game PCK; the PCK would hide your source edits.' }
$env:APPDATA=Join-Path $env:LOCALAPPDATA 'PoolCore\SourceProfile'
$config=Join-Path $env:APPDATA 'Godot\app_userdata\BEYOND THE BASIN - PoolCore Native\desktop_quality.cfg'
if (!(Test-Path -LiteralPath $config)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null
    [IO.File]::WriteAllText($config,"[graphics]`npreset=`"High`"`nmsaa=0`nframe_generation=false`nraytracing=false`nnr=false`n",[Text.UTF8Encoding]::new($false))
}
$env:POOLCORE_DLSS_NR='0'
$env:DISABLE_VK_LAYER_reshade_1='1'
$env:VK_LOADER_LAYERS_DISABLE='VK_LAYER_reshade'
$parameters=@('--path',$project,'--rendering-method','forward_plus','--rendering-driver','vulkan')
if (!$Play) { $parameters+=@('--editor') }
# The user explicitly requested an interactive editor/game window.
$p=Start-Process -FilePath $Engine -WorkingDirectory (Split-Path -Parent $Engine) -ArgumentList ($parameters|ForEach-Object {'"'+$_+'"'}) -PassThru -Wait
exit $p.ExitCode
