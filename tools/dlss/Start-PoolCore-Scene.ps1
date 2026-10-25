param([ValidateSet('original','formal','expanded','poolrooms','reference','campaign')][string]$World='campaign', [ValidateSet('keep','on','off')][string]$NR='keep')
$ErrorActionPreference='Stop'
$exe=Join-Path $PSScriptRoot 'PoolCore.exe'
if (!(Test-Path -LiteralPath $exe) -or !(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'PoolCore.pck'))) { throw 'Install the complete PoolCore package; EXE and PCK must stay together.' }
$env:APPDATA=Join-Path $PSScriptRoot 'profile'
$configPath=Join-Path $env:APPDATA 'Godot\app_userdata\BEYOND THE BASIN - PoolCore Native\desktop_quality.cfg'
if (!(Test-Path -LiteralPath $configPath)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
    # First-run defaults only; never overwrite a player's existing profile.
    $text="[graphics]`npreset=`"High`"`nmsaa=0`nframe_generation=false`nraytracing=false`nnr=false`n"
} else { $text=[IO.File]::ReadAllText($configPath) }
$values=@{}
if ($NR -ne 'keep') { $values.nr=($NR -eq 'on').ToString().ToLowerInvariant() }
$nrEnabled=if ($NR -eq 'keep') { [regex]::IsMatch($text,'(?m)^nr=true\s*$') } else { $NR -eq 'on' }
if ($nrEnabled) { $values.frame_generation='false'; $values.raytracing='true' }
if ($nrEnabled -or [regex]::IsMatch($text,'(?m)^raytracing=true\s*$')) { $values.msaa='0' }
foreach($key in $values.Keys) {
    $line=$key+'='+$values[$key]
    if([regex]::IsMatch($text,'(?m)^'+$key+'=.*$')) { $text=[regex]::Replace($text,'(?m)^'+$key+'=.*$',$line) }
    else { $text+="`n"+$line+"`n" }
}
[IO.File]::WriteAllText($configPath,$text,[Text.UTF8Encoding]::new($false))
$env:POOLCORE_DLSS_NR=if($nrEnabled){'1'}else{'0'}
$env:POOLCORE_NR_CAPTURE=''
$env:DISABLE_VK_LAYER_reshade_1='1'
$env:VK_LOADER_LAYERS_DISABLE='VK_LAYER_reshade'
$flag=@{original='--original-world';formal='--formal-hall';expanded='--expanded-world';poolrooms='--poolrooms-wing';reference='--reference-wing';campaign='--campaign'}[$World]
$launchArguments=@('--rendering-method','forward_plus','--rendering-driver','vulkan','--windowed','--resolution','1920x1080','--log-file',(Join-Path $env:APPDATA 'PoolCore.log'),'--',$flag)
$env:POOLCORE_RESTART_LAUNCH_V1=@{version=1;executable=$exe;pack=(Join-Path $PSScriptRoot 'PoolCore.pck');args=$launchArguments}|ConvertTo-Json -Compress
# This is the interactive game requested by the user; keep its window visible.
$p=Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot -ArgumentList ($launchArguments|ForEach-Object {'"'+$_+'"'}) -PassThru -Wait
exit $p.ExitCode
