@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "LAUNCHER=%SCRIPT_DIR%Launch-Codex-With-Proxy.ps1"

if not exist "%LAUNCHER%" (
  echo Launcher script not found: %LAUNCHER%
  pause
  exit /b 1
)

if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" -ProxyPort "%~1"
)

exit /b %ERRORLEVEL%
