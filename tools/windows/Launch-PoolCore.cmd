@echo off
setlocal EnableExtensions DisableDelayedExpansion
title PoolCore - diagnostic launch
cd /d "%~dp0"
set "ROOT=%~dp0"
set "PACK=%ROOT%PoolCore-Source-Water.pck"
set "ENGINE="
set "COUNT=0"
if not exist "%PACK%" goto missing_pack

rem A dropped EXE or an explicit quoted first argument takes priority.
if not "%~1"=="" set "ENGINE=%~f1"
if defined ENGINE goto check_engine
rem Prefer the exact tested Standard engine, then one local Godot candidate.
if exist "%ROOT%Godot_v4.6.3-stable_win64_console.exe" set "ENGINE=%ROOT%Godot_v4.6.3-stable_win64_console.exe"
if defined ENGINE goto check_engine
if exist "%ROOT%Godot_v4.6.3-stable_win64.exe" set "ENGINE=%ROOT%Godot_v4.6.3-stable_win64.exe"
if defined ENGINE goto check_engine
for %%G in ("%ROOT%Godot*_console.exe") do if exist "%%~fG" (
 set /a COUNT+=1 >nul
 set "ENGINE=%%~fG"
)
if %COUNT% GTR 1 goto ambiguous_engine
if defined ENGINE goto check_engine
for %%G in ("%ROOT%Godot*.exe") do if exist "%%~fG" (
 set /a COUNT+=1 >nul
 set "ENGINE=%%~fG"
)
if %COUNT% GTR 1 goto ambiguous_engine
if defined ENGINE goto check_engine
goto missing_engine

:check_engine
if not exist "%ENGINE%" goto missing_engine
for %%G in ("%ENGINE%") do set "ENGINE_EXT=%%~xG"
if /I not "%ENGINE_EXT%"==".exe" goto missing_engine
set "RUNID=%RANDOM%-%RANDOM%"
set "REPORT=%ROOT%PoolCore-diagnostic-%RUNID%.txt"
set "GODOTLOG=%ROOT%PoolCore-engine-%RUNID%.log"
>"%REPORT%" echo PoolCore diagnostic launch
if errorlevel 1 goto log_unwritable
>>"%REPORT%" echo Engine: "%ENGINE%"
>>"%REPORT%" echo Pack: "%PACK%"
>>"%REPORT%" echo Tested baseline: Godot 4.6.3 Standard. Other versions are diagnostic only.
echo Engine: "%ENGINE%"
echo Checking engine version...
"%ENGINE%" --version >>"%REPORT%" 2>&1
set "VERSION_EXIT=%ERRORLEVEL%"
>>"%REPORT%" echo Version command exit code: %VERSION_EXIT%
if not "%VERSION_EXIT%"=="0" goto version_failed
type "%REPORT%"
echo.
echo Starting the actual PCK in Forward+. No settings are reset.
echo First startup may compile shaders. Keep this console open.
echo Logs: "%REPORT%"
"%ENGINE%" --main-pack "%PACK%" --rendering-method forward_plus --verbose --log-file "%GODOTLOG%" >>"%REPORT%" 2>&1
set "GODOT_EXIT=%ERRORLEVEL%"
>>"%REPORT%" echo Game exit code: %GODOT_EXIT%
echo.
echo Game process ended with exit code %GODOT_EXIT%.
echo Please share these two local logs if the game did not open:
echo "%REPORT%"
echo "%GODOTLOG%"
if not exist "%GODOTLOG%" echo The engine log was not created; the diagnostic TXT is still useful.
echo Logs can contain local paths and graphics-device details. Nothing is uploaded automatically.
pause
exit /b %GODOT_EXIT%

:version_failed
echo The engine could not complete its version command. The PCK has not been launched.
type "%REPORT%"
echo Please share "%REPORT%".
pause
exit /b %VERSION_EXIT%

:missing_pack
echo Missing PoolCore-Source-Water.pck beside this script.
echo Extract the game ZIP first. Copy this CMD into the folder containing that PCK.
echo Do not run the CMD directly from a ZIP preview.
pause
exit /b 2

:ambiguous_engine
echo More than one Godot engine was found. No engine was started.
echo Drag the intended official Godot EXE onto this CMD, or pass its quoted full path.
pause
exit /b 3

:missing_engine
echo No suitable local Godot EXE was selected. No download or install was performed.
echo Put the official Godot engine beside this CMD, or drag its EXE onto this CMD.
echo The tested baseline is Godot 4.6.3 Standard Windows x86_64.
echo Other versions may be used to collect diagnostics, but are not validated builds.
pause
exit /b 4

:log_unwritable
echo Cannot create a diagnostic log in this folder. The game was not started.
echo Use an ordinary writable folder. Do not change security settings.
pause
exit /b 5
