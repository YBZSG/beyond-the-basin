param([ValidateSet('original','formal','expanded','poolrooms')][string]$World='original', [ValidateSet('on','off')][string]$NR='on')
$ErrorActionPreference='Stop'
$env:APPDATA=Join-Path $PSScriptRoot 'profile'
$configPath=Join-Path $env:APPDATA 'Godot\app_userdata\BEYOND THE BASIN - PoolCore Native\desktop_quality.cfg'
$text=[IO.File]::ReadAllText($configPath)
$values=@{nr=($NR -eq 'on').ToString().ToLowerInvariant()}
if($NR -eq 'on') { $values.frame_generation='false' }
foreach($key in $values.Keys) {
    $line=$key+'='+$values[$key]
    if([regex]::IsMatch($text,'(?m)^'+$key+'=.*$')) { $text=[regex]::Replace($text,'(?m)^'+$key+'=.*$',$line) }
    else { $text+="`n"+$line+"`n" }
}
[IO.File]::WriteAllText($configPath,$text,[Text.UTF8Encoding]::new($false))
$env:POOLCORE_DLSS_NR=if($NR -eq 'on'){'1'}else{'0'}
$env:POOLCORE_NR_CAPTURE=''
$env:DISABLE_VK_LAYER_reshade_1='1'
$env:VK_LOADER_LAYERS_DISABLE='VK_LAYER_reshade'
$exe=Join-Path $PSScriptRoot 'PoolCore.exe'
$flag=@{original='--original-world';formal='--formal-hall';expanded='--expanded-world';poolrooms='--poolrooms-wing'}[$World]
$launchArguments=@('--rendering-method','forward_plus','--rendering-driver','vulkan','--windowed','--resolution','1920x1080','--log-file',(Join-Path $PSScriptRoot 'PoolCore-NR.log'),'--',$flag)
$env:POOLCORE_RESTART_LAUNCH_V1=@{version=1;executable=$exe;pack=(Join-Path $PSScriptRoot 'PoolCore.pck');args=$launchArguments}|ConvertTo-Json -Compress
# This is the interactive game requested by the user; keep its window visible.
Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot -ArgumentList ($launchArguments|ForEach-Object {'"'+$_+'"'}) -Wait
