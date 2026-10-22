@echo off
rem Check only: GPU, VRAM, disk space and existing ComfyUI. Downloads nothing.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_anima.ps1" -CheckOnly
pause
