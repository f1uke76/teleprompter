@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Starting teleprompter local server (loopback only)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
if errorlevel 1 pause
