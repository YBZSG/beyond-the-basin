@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\release\Open-Source.ps1" -Engine "%~1" -Play
if errorlevel 1 pause
