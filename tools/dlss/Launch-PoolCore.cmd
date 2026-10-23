@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if not exist "%~dp0PoolCore.exe" exit /b 2
if not exist "%~dp0PoolCore.pck" exit /b 3
set "DISABLE_VK_LAYER_reshade_1=1"
if defined VK_LOADER_LAYERS_DISABLE (
    set "VK_LOADER_LAYERS_DISABLE=%VK_LOADER_LAYERS_DISABLE%,VK_LAYER_reshade"
) else (
    set "VK_LOADER_LAYERS_DISABLE=VK_LAYER_reshade"
)
start "" /D "%~dp0" "%~dp0PoolCore.exe" --rendering-method forward_plus --rendering-driver vulkan --windowed --resolution 1920x1080 --log-file "%~dp0PoolCore-engine.log" -- --original-world %*
exit /b %ERRORLEVEL%
