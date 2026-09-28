@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "PY=%CD%\.venv\Scripts\python.exe"

echo ================================================================
echo 20-20 TOOLBOX - VOSR PERFORMANCE OPTIMIZER
echo ================================================================
echo.

if not exist "%PY%" (
  echo [CHYBA] VOSR runtime nebyl nalezen.
  echo Nejdriv spust setup.bat.
  pause
  exit /b 1
)

if not exist "%CD%\optimize_runtime.py" (
  echo [CHYBA] Chybi optimize_runtime.py.
  echo Stahni aktualni UpscaleBridge z 2020toolboxu.
  pause
  exit /b 1
)

"%PY%" "%CD%\optimize_runtime.py"
if errorlevel 1 (
  echo.
  echo [CHYBA] Optimalizace selhala.
  pause
  exit /b 1
)

echo.
echo HOTOVO.
echo Restartuj run_bridge.bat a zkus stejny obraz znovu.
pause
