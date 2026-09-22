@echo off
setlocal
set "DIR=%APPDATA%\2020toolbox\SketchUpPluginInstaller"
set "PS1=%DIR%\bridge_v3.ps1"
set "URL=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/bridge_v3.ps1"
if not exist "%DIR%" mkdir "%DIR%" >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%PS1%' } catch {}"
if not exist "%PS1%" exit /b 2
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%" "%~1"
exit /b 0