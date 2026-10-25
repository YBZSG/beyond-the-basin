@echo off
setlocal DisableDelayedExpansion
set "PROJECT=%~1"
if not defined PROJECT (
  echo SOURCE INCREMENTAL UPDATE - not a full project, PCK, or engine.
  echo Drag your existing project folder onto this file, or enter its full path.
  set /p "PROJECT=Project folder: "
)
if not defined PROJECT goto :missingpath
py -3 -c "import sys; sys.exit(sys.version_info.__lt__((3,9)))" >nul 2>&1
if not errorlevel 1 (
  py -3 "%~dp0compact_source_update.py" apply "%PROJECT%"
  goto :result
)
python -c "import sys; sys.exit(sys.version_info.__lt__((3,9)))" >nul 2>&1
if not errorlevel 1 (
  python "%~dp0compact_source_update.py" apply "%PROJECT%"
  goto :result
)
echo Python 3.9 or newer was not found. Install Python from python.org yourself, then retry.
echo No download, installation, or system setting change was attempted.
pause
exit /b 2
:missingpath
echo No project folder provided. Nothing was changed.
pause
exit /b 2
:result
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo Update did not complete. Read the error above. Do not force-copy the payload.
  goto :finish
)
echo SOURCE update complete or already applied. Your existing engine is unchanged.
:finish
pause
exit /b %RESULT%
