@echo off
setlocal EnableExtensions DisableDelayedExpansion
title PoolCore - prepare editable project
set "ENGINE="
if not "%~1"=="" set "ENGINE=%~f1"
set "ROOT=%~dp0"
pushd "%ROOT%" >nul 2>&1
if errorlevel 1 goto folder_failed
set "ROOT=%CD%"
set "COUNT=0"
if not exist "%ROOT%\project.godot" goto missing_project
if not exist "%ROOT%\native\source_water\source_water.gdextension" goto missing_project
if defined ENGINE goto check_engine

rem Prefer the full tested engine, then one console wrapper, then one Godot engine.
if exist "%ROOT%\Godot_v4.6.3-stable_win64.exe" set "ENGINE=%ROOT%\Godot_v4.6.3-stable_win64.exe"
if defined ENGINE goto check_engine
if exist "%ROOT%\Godot_v4.6.3-stable_win64_console.exe" set "ENGINE=%ROOT%\Godot_v4.6.3-stable_win64_console.exe"
if defined ENGINE goto check_engine
for %%G in ("%ROOT%\Godot*_console.exe") do if exist "%%~fG" (
 set /a COUNT+=1 >nul
 set "ENGINE=%%~fG"
)
if %COUNT% GTR 1 goto ambiguous_engine
if defined ENGINE goto check_engine
for %%G in ("%ROOT%\Godot*.exe") do if exist "%%~fG" (
 set /a COUNT+=1 >nul
 set "ENGINE=%%~fG"
)
if %COUNT% GTR 1 goto ambiguous_engine
if defined ENGINE goto check_engine
rem A renamed Godot EXE is allowed if it is the only EXE. Its version is checked.
for %%G in ("%ROOT%\*.exe") do if exist "%%~fG" (
 set /a COUNT+=1 >nul
 set "ENGINE=%%~fG"
)
if %COUNT% GTR 1 goto ambiguous_engine
if not defined ENGINE goto missing_engine


:check_engine
if not exist "%ENGINE%" goto missing_engine
if exist "%ENGINE%\" goto missing_engine
for %%G in ("%ENGINE%") do set "ENGINE_EXT=%%~xG"
if /I not "%ENGINE_EXT%"==".exe" goto missing_engine
set "RUNID=%RANDOM%-%RANDOM%"
set "REPORT=%ROOT%\PoolCore-editor-diagnostic-%RUNID%.txt"
set "VERSIONLOG=%ROOT%\PoolCore-editor-version-%RUNID%.txt"
set "GODOTLOG=%ROOT%\PoolCore-editor-engine-%RUNID%.log"
>"%REPORT%" echo PoolCore editable-project preparation
if errorlevel 1 goto write_failed
>>"%REPORT%" echo Engine: "%ENGINE%"
>>"%REPORT%" echo Project root: "%ROOT%"
"%ENGINE%" --headless --version >"%VERSIONLOG%" 2>&1
set "VERSION_EXIT=%ERRORLEVEL%"
type "%VERSIONLOG%" >>"%REPORT%"
if not "%VERSION_EXIT%"=="0" goto version_failed
findstr /R /B /C:"4[.][67][.]" "%VERSIONLOG%" >nul
if errorlevel 1 goto wrong_version
findstr /R /B /C:"4[.]6[.]3[.]" "%VERSIONLOG%" >nul
if not errorlevel 1 goto version_ready
echo WARNING: This engine version is allowed but not the tested 4.6.3 build baseline.
>>"%REPORT%" echo WARNING: Allowed 4.6/4.7 engine differs from tested baseline; compatibility is unverified.
echo Different engine builds may rebuild exact caches and take longer on first startup.
echo No automatic downgrade, download, or settings change will be performed.
:version_ready

rem Bootstrap only the known portable GDExtension path before first editor import.
rem Existing unrelated extension entries are preserved, not overwritten.
if not exist "%ROOT%\.godot" mkdir "%ROOT%\.godot" >nul 2>&1
if not exist "%ROOT%\.godot" goto write_failed
set "REGISTRY=%ROOT%\.godot\extension_list.cfg"
if not exist "%REGISTRY%" goto add_extension
findstr /L /X /C:"res://native/source_water/source_water.gdextension" "%REGISTRY%" >nul
if not errorlevel 1 goto extension_ready
:add_extension
>>"%REGISTRY%" echo.
>>"%REGISTRY%" echo res://native/source_water/source_water.gdextension
if errorlevel 1 goto write_failed
findstr /L /X /C:"res://native/source_water/source_water.gdextension" "%REGISTRY%" >nul
if errorlevel 1 goto write_failed
:extension_ready
>>"%REPORT%" echo Portable native startup registration is present. Other cache files were not copied or removed.
echo Opening the editable project. Allow the first import to finish before pressing Play.
echo This avoids Godot's known first-discovery headless documentation shutdown race.
echo No download, installation, credential, or security-setting change was performed.
"%ENGINE%" --editor --path "%ROOT%\." --verbose --log-file "%GODOTLOG%" >>"%REPORT%" 2>&1
set "GODOT_EXIT=%ERRORLEVEL%"
>>"%REPORT%" echo Editor exit code: %GODOT_EXIT%
echo Editor ended with exit code %GODOT_EXIT%.
echo Local diagnostic: "%REPORT%"
echo Local engine log: "%GODOTLOG%"
echo Logs may contain local paths or graphics-device details. Nothing is uploaded automatically.
pause
popd
exit /b %GODOT_EXIT%

:version_failed
echo If you selected a console wrapper, keep its paired main EXE beside it with matching names.
echo A freely renamed engine must be the full main Godot EXE, not just its small console wrapper.
echo The chosen engine's version check failed. The editor was not started.
type "%REPORT%"
pause
popd
exit /b %VERSION_EXIT%
:wrong_version
echo Please use an official Godot 4.6.x or 4.7.x Standard Windows x86_64 engine. Tested baseline: 4.6.3.
type "%VERSIONLOG%"
pause
popd
exit /b 6
:missing_project
echo Put this script in the fully extracted source root beside project.godot and the native folder.
echo This script opens editable source, not the portable PCK play package.
pause
popd
exit /b 2
:ambiguous_engine
echo Several engines were found. Drag the intended official Godot 4.6.x or 4.7.x EXE onto this script.
pause
popd
exit /b 3
:missing_engine
echo Drag an official Godot 4.6.x or 4.7.x Standard Windows x86_64 EXE onto this script.
echo Its filename may be anything. No engine was downloaded or installed.
pause
popd
exit /b 4
:write_failed
echo Cannot prepare the registry or write logs. The editor was not started.
echo Fully extract into a writable local folder. Do not change security settings.
pause
popd
exit /b 5
:folder_failed
echo Cannot open the source folder. Fully extract the source ZIP first.
pause
exit /b 7
