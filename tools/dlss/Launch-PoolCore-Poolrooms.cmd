@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Start-PoolCore-Scene.ps1" -World poolrooms -NR on
