@echo off
setlocal EnableExtensions
chcp 65001 >nul
title 20-20 TOOLBOX - AuthorizationBridge

set "DIR=%LOCALAPPDATA%\20-20-TOOLBOX\AuthorizationBridge"
set "VENV=%DIR%\venv"
set "RAW=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/AuthorizationBridge"

if not exist "%DIR%" mkdir "%DIR%"

echo.
echo 20-20 TOOLBOX - instalace AuthorizationBridge
echo Data certifikatu zustavaji pouze v tomto pocitaci.
echo.

where py >nul 2>nul
if %errorlevel%==0 (
  set "PY=py -3"
) else (
  where python >nul 2>nul
  if %errorlevel%==0 (
    set "PY=python"
  ) else (
    echo CHYBA: Python 3 nebyl nalezen.
    echo Nainstaluj Python 3 z https://www.python.org/downloads/windows/
    echo Pri instalaci zaskrtni "Add python.exe to PATH".
    pause
    exit /b 1
  )
)

echo [1/5] Stahuji bridge...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/authorization_bridge.py' -OutFile '%DIR%\authorization_bridge.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/requirements.txt' -OutFile '%DIR%\requirements.txt'"
if errorlevel 1 goto :download_error

if not exist "%VENV%\Scripts\python.exe" (
  echo [2/5] Vytvarim lokalni Python prostredi...
  %PY% -m venv "%VENV%"
  if errorlevel 1 goto :python_error
) else (
  echo [2/5] Lokalni Python prostredi uz existuje.
)

echo [3/5] Instaluji / aktualizuji podpisove knihovny...
"%VENV%\Scripts\python.exe" -m pip install --disable-pip-version-check --quiet --upgrade -r "%DIR%\requirements.txt"
if errorlevel 1 goto :pip_error

echo [4/5] Vytvarim lokalni spoustec...
(
  echo @echo off
  echo start "" /min cmd /c ""%VENV%\Scripts\python.exe" "%DIR%\authorization_bridge.py" ^>^>"%DIR%\bridge.log" 2^>^&1"
) > "%DIR%\start_bridge.cmd"

echo [5/5] Registruji jednorazove spousteni z Toolboxu...
reg add "HKCU\Software\Classes\twentytwentyauth" /ve /d "URL:20-20 AuthorizationBridge" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth" /v "URL Protocol" /d "" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth\shell\open\command" /ve /d ""%DIR%\start_bridge.cmd" "%%1"" /f >nul

call "%DIR%\start_bridge.cmd"

echo.
echo HOTOVO.
echo AuthorizationBridge bezi pouze na 127.0.0.1:8094.
echo Vrat se do 20-20 TOOLBOXu a klikni na "Zkontrolovat".
echo.
pause
exit /b 0

:download_error
echo CHYBA: nepodarilo se stahnout soubory bridge z GitHubu.
pause
exit /b 1

:python_error
echo CHYBA: nepodarilo se vytvorit Python prostredi.
pause
exit /b 1

:pip_error
echo CHYBA: nepodarilo se nainstalovat pyHanko/Flask.
echo Zkontroluj internet a log v prikazovem radku.
pause
exit /b 1
