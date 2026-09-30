@echo off
setlocal
title 20-20 Toolbox SketchUp Helper
set "DIR=%APPDATA%\2020toolbox\SketchUpPluginInstaller"
set "RAW=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller"

if not exist "%DIR%" mkdir "%DIR%" >nul 2>&1

echo Instaluji 20-20 Toolbox SketchUp Helper...
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -UseBasicParsing -Uri '%RAW%/20-20_BRIDGE_V3.bat' -OutFile '%DIR%\20-20_BRIDGE_V3.bat'; Invoke-WebRequest -UseBasicParsing -Uri '%RAW%/bridge_v3.ps1' -OutFile '%DIR%\bridge_v3.ps1'; Invoke-WebRequest -UseBasicParsing -Uri '%RAW%/register_protocol_v3.ps1' -OutFile '%DIR%\register_protocol_v3.ps1'"
if errorlevel 1 (
  echo CHYBA: helper se nepodarilo stahnout.
  pause
  exit /b 1
)

powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%DIR%\register_protocol_v3.ps1"
if errorlevel 1 (
  echo CHYBA: registrace helperu selhala.
  pause
  exit /b 1
)

echo.
echo HOTOVO. Od ted se Bridge spousti automaticky, skryte a jen na cca 10 sekund po pouziti.
pause
exit /b 0
