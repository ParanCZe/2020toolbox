@echo off
setlocal
set "DIR=%APPDATA%\2020toolbox\SketchUpPluginBridge"
set "PS1=%DIR%\bridge.ps1"
if not exist "%DIR%" mkdir "%DIR%" >nul 2>&1
if not exist "%PS1%" exit /b 2
start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%"
exit /b 0