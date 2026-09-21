@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "TOOLBOX_ROOT=%LOCALAPPDATA%\20-20-TOOLBOX"
set "TARGET=%TOOLBOX_ROOT%\UpscaleBridge"
if exist "%~dp0server.py" set "TARGET=%~dp0"
if "%TARGET:~-1%"=="\" set "TARGET=%TARGET:~0,-1%"

set "WAITPID="
set "AUTOMATED=0"
if /I "%~1"=="--wait-pid" (
  set "WAITPID=%~2"
  set "AUTOMATED=1"
)

echo ================================================================
echo 20-20 TOOLBOX - AI STORAGE CLEANUP
echo ================================================================
echo Cil: %TARGET%
echo.

if defined WAITPID (
  echo Cekam na ukonceni VOSR Bridge PID %WAITPID%...
:wait_loop
  tasklist /FI "PID eq %WAITPID%" /NH 2>nul | find "%WAITPID%" >nul
  if not errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto :wait_loop
  )
) else (
  rem Pokud je skript spusten rucne, zkusime ukoncit pouze okno VOSR Bridge.
  taskkill /FI "WINDOWTITLE eq 20-20 TOOLBOX - VOSR 2.0 Bridge*" /T /F >nul 2>nul
  timeout /t 1 /nobreak >nul
)

echo Mazu VOSR modely a runtime...
call :remove_dir "%TARGET%\.venv"
call :remove_dir "%TARGET%\runtime"
if exist "%TARGET%\.portable_runtime_v1" del /q "%TARGET%\.portable_runtime_v1" >nul 2>nul

rem Rezervovane Toolbox-owned AI adresare pro starsi/budouci verze.
call :remove_dir "%TOOLBOX_ROOT%\AIModels"
call :remove_dir "%TOOLBOX_ROOT%\AICache"
call :remove_dir "%TOOLBOX_ROOT%\ModelCache"
call :remove_dir "%TOOLBOX_ROOT%\UpscalerModels"

echo.
echo ================================================================
echo HOTOVO - lokalni AI modely/runtime Toolboxu byly odstraneny.
echo VOSR bude pri dalsim pouziti vyzadovat novou instalaci.
echo ================================================================
if "%AUTOMATED%"=="0" pause
exit /b 0

:remove_dir
set "D=%~1"
if not exist "%D%" exit /b 0
for /L %%N in (1,1,8) do (
  rmdir /s /q "%D%" >nul 2>nul
  if not exist "%D%" exit /b 0
  timeout /t 1 /nobreak >nul
)
echo [VAROVANI] Nepodarilo se uplne smazat: %D%
exit /b 0
