@echo off
setlocal
set "HELPER_DIR=%APPDATA%\2020toolbox\SketchUpPluginInstaller"
set "PS1=%HELPER_DIR%\install_plugin.ps1"
set "PS1_URL=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/install_plugin.ps1"

if not exist "%HELPER_DIR%" mkdir "%HELPER_DIR%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Invoke-WebRequest -UseBasicParsing -Uri '%PS1_URL%' -OutFile '%PS1%'; exit 0 } catch { if (Test-Path '%PS1%') { exit 0 } else { exit 1 } }"

if errorlevel 1 exit /b 2

start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%" "%~1"
exit /b 0
