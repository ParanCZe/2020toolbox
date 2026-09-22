@echo off
setlocal
set "HELPER_DIR=%APPDATA%\2020toolbox\SketchUpPluginInstaller"
set "PS1=%HELPER_DIR%\install_plugin.ps1"
if not exist "%PS1%" exit /b 2
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%" "%~1"
exit /b 0
