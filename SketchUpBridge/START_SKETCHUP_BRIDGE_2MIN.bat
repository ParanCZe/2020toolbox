@echo off
setlocal
chcp 65001 >nul
set "BRIDGE_DIR=%TEMP%\20-20-SketchUpBridge"
set "BRIDGE_PS1=%BRIDGE_DIR%\20-20-SketchUpBridge-2min.ps1"
set "BRIDGE_URL=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpBridge/20-20-SketchUpBridge-2min.ps1"

if not exist "%BRIDGE_DIR%" mkdir "%BRIDGE_DIR%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Invoke-WebRequest -UseBasicParsing -Uri '%BRIDGE_URL%' -OutFile '%BRIDGE_PS1%'; exit 0 } catch { exit 1 }"

if errorlevel 1 (
  echo Nepodarilo se stahnout 20-20 SketchUpBridge.
  echo Zkontrolujte pripojeni k internetu a zkuste to znovu.
  pause
  exit /b 1
)

start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BRIDGE_PS1%"
exit /b 0
