@echo off
rem Runs install_anima.ps1 for this process only (system execution policy is not changed).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_anima.ps1" %*
pause
