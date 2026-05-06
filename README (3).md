@echo off
setlocal
cd /d "%~dp0"
echo Starting AxMclub.com backend...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
echo.
echo Server stopped.
pause
