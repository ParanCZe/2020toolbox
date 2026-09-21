@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "TARGET=%LOCALAPPDATA%\20-20-TOOLBOX\UpscaleBridge"
set "BASE=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/UpscaleBridge"
set "SERVER_REF=47a411ee8ad1d814a1db132306d62d32a54b5923"
set "SERVER_URL=https://raw.githubusercontent.com/ParanCZe/2020toolbox/%SERVER_REF%/UpscaleBridge/server.py"

echo ================================================================
echo 20-20 TOOLBOX - VOSR 2.0 ONE-CLICK INSTALLER
echo.
echo Neni potreba mit nainstalovany Python ani Git.
echo Instalator si stahne vlastni izolovany runtime automaticky.
echo Potreba je pouze NVIDIA GPU + aktualni NVIDIA ovladac.
echo.
echo Cil: %TARGET%
echo Pocitej priblizne s 14-18 GB po instalaci.
echo Behem instalace muze byt docasne potreba 20+ GB.
echo ================================================================
echo.

if not exist "%TARGET%" mkdir "%TARGET%"
if errorlevel 1 goto :fail

for %%F in (setup.bat run_bridge.bat cleanup_ai.bat download_models.py) do (
  echo Stahuji %%F...
  set "CACHEBUST=%RANDOM%%RANDOM%%RANDOM%"
  where curl.exe >nul 2>nul
  if not errorlevel 1 (
    curl.exe -fL -H "Cache-Control: no-cache" "%BASE%/%%F?cb=!CACHEBUST!" -o "%TARGET%\%%F"
  ) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Headers @{'Cache-Control'='no-cache'} -Uri '%BASE%/%%F?cb=!CACHEBUST!' -OutFile '%TARGET%\%%F'"
  )
  if errorlevel 1 goto :fail
)

echo Stahuji server.py z overene immutable verze...
where curl.exe >nul 2>nul
if not errorlevel 1 (
  curl.exe -fL "%SERVER_URL%" -o "%TARGET%\server.py"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%SERVER_URL%' -OutFile '%TARGET%\server.py'"
)
if errorlevel 1 goto :fail

echo.
echo Spoustim automatickou instalaci VOSR 2.0...
call "%TARGET%\setup.bat"
if errorlevel 1 goto :fail

echo.
echo Kontroluji syntax VOSR Bridge...
"%TARGET%\.venv\Scripts\python.exe" -m py_compile "%TARGET%\server.py"
if errorlevel 1 (
  echo [VAROVANI] server.py neprosel syntax kontrolou. Stahuji ho znovu bez cache...
  where curl.exe >nul 2>nul
  if not errorlevel 1 (
    curl.exe -fL "%SERVER_URL%" -o "%TARGET%\server.py"
  ) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%SERVER_URL%' -OutFile '%TARGET%\server.py'"
  )
  if errorlevel 1 goto :fail
  "%TARGET%\.venv\Scripts\python.exe" -m py_compile "%TARGET%\server.py"
  if errorlevel 1 goto :fail
)

echo.
echo Spoustim VOSR Bridge...
start "20-20 TOOLBOX VOSR Bridge" "%TARGET%\run_bridge.bat"

echo.
echo ================================================================
echo HOTOVO - VOSR Bridge je nainstalovany a spousti se.
echo V Toolboxu muzes zvolit VOSR 2.0 Scene 2x nebo 4x.
echo ================================================================
pause
exit /b 0

:fail
echo.
echo [CHYBA] VOSR Bridge se nepodarilo nainstalovat.
echo Python ani Git neinstaluj rucne - pokud chyba zustane,
echo posli vypis z tohoto okna.
pause
exit /b 1
