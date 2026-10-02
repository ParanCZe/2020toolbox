@echo off
setlocal
set "DIR=%APPDATA%\2020toolbox\SketchUpPluginInstaller"
set "PS1=%DIR%\bridge_v3.ps1"
if not exist "%DIR%" mkdir "%DIR%" >nul 2>&1
rem Use the bridge already installed in AppData. Only download on first run
rem or if the local bridge file was deleted. Reinstall the one-time helper
rem explicitly if you want to update the bridge itself.
if not exist "%PS1%" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $tmp='%PS1%.download'; try { Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/bridge_v3.ps1' -OutFile $tmp; if((Get-Item $tmp).Length -lt 1000){ throw 'Bridge file incomplete' }; Move-Item -LiteralPath $tmp -Destination '%PS1%' -Force } catch { Remove-Item $tmp -ErrorAction SilentlyContinue; exit 2 }"
  if errorlevel 1 exit /b 2
)
if not exist "%PS1%" exit /b 2
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%" "%~1"
exit /b 0
