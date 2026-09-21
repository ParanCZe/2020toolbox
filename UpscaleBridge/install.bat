@echo off
setlocal EnableExtensions
set "TARGET=%LOCALAPPDATA%\20-20-TOOLBOX\UpscaleBridge"
set "BASE=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/UpscaleBridge"

echo ================================================================
echo 20-20 TOOLBOX - VOSR 2.0 BRIDGE INSTALLER
echo Cil: %TARGET%
echo ================================================================

if not exist "%TARGET%" mkdir "%TARGET%"
if errorlevel 1 goto :fail

for %%F in (setup.bat run_bridge.bat server.py download_models.py) do (
  echo Stahuji %%F...
  where curl.exe >nul 2>nul
  if not errorlevel 1 (
    curl.exe -fL "%BASE%/%%F" -o "%TARGET%\%%F"
  ) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/%%F' -OutFile '%TARGET%\%%F'"
  )
  if errorlevel 1 goto :fail
)

echo.
call "%TARGET%\setup.bat"
if errorlevel 1 goto :fail

echo.
echo Spoustim VOSR Bridge...
start "20-20 TOOLBOX VOSR Bridge" "%TARGET%\run_bridge.bat"
exit /b 0

:fail
echo.
echo [CHYBA] VOSR Bridge se nepodarilo nainstalovat.
pause
exit /b 1
