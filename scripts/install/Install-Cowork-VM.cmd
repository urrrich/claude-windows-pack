@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Cowork-VM.ps1"
if errorlevel 1 (
  echo Cowork VM patch failed. See the error above.
  pause
  exit /b 1
)
pause
