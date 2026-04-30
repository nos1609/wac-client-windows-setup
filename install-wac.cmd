@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%interactive-installer.ps1"

if not exist "%PS1%" (
  echo Missing script: "%PS1%"
  exit /b 2
)

set "WAC_SETUP_UNBLOCK_DIR=%SCRIPT_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:WAC_SETUP_UNBLOCK_DIR -Recurse -File | Unblock-File -ErrorAction SilentlyContinue"

where pwsh.exe >nul 2>&1
if "%errorlevel%"=="0" (
  set "PSHOST=pwsh.exe"
) else (
  set "PSHOST=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
)

set "WAC_WAIT_ON_EXIT=1"
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %errorlevel%


