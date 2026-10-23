@echo off
setlocal EnableExtensions DisableDelayedExpansion
title PoolCore - diagnostic launch
rem Resolve a quoted relative engine argument BEFORE changing working directory.
set "ENGINE="
if not "%~1"=="" set "ENGINE=%~f1"
set "ROOT=%~dp0"
pushd "%ROOT%" >nul 2>&1
if errorlevel 1 goto folder_failed
set "ROOT=%CD%"
set "PACK=%ROOT%\PoolCore-Source-Water.pck"
set "COUNT=0"
if not exist "%PACK%" goto missing_pack
if defined ENGINE goto check_engine

rem Prefer the bundled game, then the full tested engine and one unambiguous engine.
if exist "%ROOT%\PoolCore-Source-Water.exe" set "ENGINE=%ROOT%\PoolCore-Source-Water.exe"
if defined ENGINE goto check_engine
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
set "REPORT=%ROOT%\PoolCore-diagnostic-%RUNID%.txt"
set "VERSIONLOG=%ROOT%\PoolCore-version-%RUNID%.txt"
set "GODOTLOG=%ROOT%\PoolCore-engine-%RUNID%.log"
>"%REPORT%" echo PoolCore diagnostic launch
if errorlevel 1 goto log_unwritable
>>"%REPORT%" echo Engine: "%ENGINE%"
>>"%REPORT%" echo Package root: "%ROOT%"
>>"%REPORT%" echo Pack: "%PACK%"
>>"%REPORT%" echo Tested baseline: Godot 4.6.3 Standard, Windows x86_64 artifact.
>>"%REPORT%" echo Actual Windows GPU execution is not validated by the cross-build.
echo Engine: "%ENGINE%"
echo Checking the engine version...
"%ENGINE%" --headless --version >"%VERSIONLOG%" 2>&1
set "VERSION_EXIT=%ERRORLEVEL%"
type "%VERSIONLOG%" >>"%REPORT%"
>>"%REPORT%" echo Version command exit code: %VERSION_EXIT%
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
if not exist "%ROOT%\native\source_water\bin\source_water.windows.x86_64.dll" (
 echo WARNING: Optional exact CPU water helper is missing. The GDScript fallback remains available.
 >>"%REPORT%" echo WARNING: Optional native water DLL is missing from its relative tree.
)
echo Starting the actual PCK in Forward+. No saved settings are reset.
echo First startup may compile shaders. Keep this console open.
echo Diagnostic log: "%REPORT%"
rem Explicit --path also makes external native dependencies work with a separate engine.
rem The final \. avoids a quoted argument ending in a Windows backslash.
"%ENGINE%" --path "%ROOT%\." --main-pack "%PACK%" --rendering-method forward_plus --verbose --log-file "%GODOTLOG%" >>"%REPORT%" 2>&1
set "GODOT_EXIT=%ERRORLEVEL%"
>>"%REPORT%" echo Game exit code: %GODOT_EXIT%
echo.
echo Game process ended with exit code %GODOT_EXIT%.
echo If the game failed, please share these local logs:
echo "%REPORT%"
echo "%GODOTLOG%"
if not exist "%GODOTLOG%" echo No engine log was created; the diagnostic TXT is still useful.
echo Logs may contain local paths and graphics-device details. Nothing is uploaded automatically.
pause
popd
exit /b %GODOT_EXIT%

:version_failed
echo If you selected a console wrapper, keep its paired main EXE beside it with matching names.
echo A freely renamed engine must be the full main Godot EXE, not just its small console wrapper.
echo The engine version command failed. The game was not started.
type "%REPORT%"
echo Please share "%REPORT%".
pause
popd
exit /b %VERSION_EXIT%

:wrong_version
echo This package requires Godot 4.6.x or 4.7.x Standard Windows x86_64.
echo Tested engine: 4.6.3. 4.7.x is allowed with an unverified-version warning.
type "%VERSIONLOG%"
echo No download, installation, or saved-setting change was performed.
pause
popd
exit /b 6

:missing_pack
echo Missing PoolCore-Source-Water.pck beside this script.
echo Fully extract the game ZIP first, including its native folder.
echo Do not run this CMD from a ZIP preview.
pause
popd
exit /b 2

:ambiguous_engine
echo Several engines were found. No engine was started.
echo Drag the intended official Godot 4.6.x or 4.7.x EXE onto this CMD.
echo You can also pass its full quoted path. Its filename may be anything.
pause
popd
exit /b 3

:missing_engine
echo Put the official Godot 4.6.x or 4.7.x Windows x86_64 EXE here, or drag it onto this CMD.
echo The tested baseline is Godot 4.6.3 Standard. No engine is bundled.
echo No download, installation, or security-setting change was performed.
pause
popd
exit /b 4

:log_unwritable
echo Cannot write a diagnostic log here. The game was not started.
echo Fully extract into an ordinary writable folder. Do not change security settings.
pause
popd
exit /b 5

:folder_failed
echo The package folder could not be opened. Extract it into a writable local folder.
pause
exit /b 7
