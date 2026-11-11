@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-Cowork-Service.ps1"
set "repairResult=%errorlevel%"
echo.
pause
exit /b %repairResult%