@echo off
setlocal EnableExtensions
chcp 65001 >nul
title 20-20 TOOLBOX - AuthorizationBridge

set "DIR=%LOCALAPPDATA%\20-20-TOOLBOX\AuthorizationBridge"
set "VENV=%DIR%\venv"
set "RAW=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/AuthorizationBridge"
set "PYFINDER=%DIR%\find_python.ps1"
set "PYFILE=%TEMP%\2020toolbox_python_path.txt"

if not exist "%DIR%" mkdir "%DIR%"

echo.
echo 20-20 TOOLBOX - instalace AuthorizationBridge
echo Data certifikatu zustavaji pouze v tomto pocitaci.
echo.

echo [1/6] Stahuji bridge a instalacni soubory...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/authorization_bridge.py' -OutFile '%DIR%\authorization_bridge.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/requirements.txt' -OutFile '%DIR%\requirements.txt'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/find_python.ps1' -OutFile '%PYFINDER%'"
if errorlevel 1 goto :download_error

echo [2/6] Hledam existujici Python 3...
call :find_python
if defined PY_EXE goto :python_ready

echo.
echo Python 3 nebyl nalezen. Zkusim ho automaticky nainstalovat.
where winget >nul 2>nul
if errorlevel 1 goto :python_auto_install_failed

echo Instaluji Python 3.13 pres Windows Package Manager...
winget install --id Python.Python.3.13 -e --source winget --scope user --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
  echo Python 3.13 se nepodarilo nainstalovat. Zkousim Python 3.12...
  winget install --id Python.Python.3.12 -e --source winget --scope user --silent --accept-package-agreements --accept-source-agreements
)
if errorlevel 1 goto :python_auto_install_failed

echo Python byl nainstalovan. Znovu hledam skutecny python.exe...
timeout /t 2 /nobreak >nul
call :find_python
if not defined PY_EXE goto :python_auto_install_failed

:python_ready
echo Nalezen Python:
echo   %PY_EXE%
"%PY_EXE%" --version
if errorlevel 1 goto :python_auto_install_failed

if not exist "%VENV%\Scripts\python.exe" (
  echo [3/6] Vytvarim lokalni Python prostredi...
  "%PY_EXE%" -m venv "%VENV%"
  if errorlevel 1 goto :python_error
) else (
  echo [3/6] Lokalni Python prostredi uz existuje.
)

echo [4/6] Instaluji / aktualizuji podpisove knihovny...
"%VENV%\Scripts\python.exe" -m pip install --disable-pip-version-check --quiet --upgrade -r "%DIR%\requirements.txt"
if errorlevel 1 goto :pip_error

echo [5/6] Vytvarim lokalni spoustec...
(
  echo @echo off
  echo start "" /min cmd /c ""%VENV%\Scripts\python.exe" "%DIR%\authorization_bridge.py" ^>^>"%DIR%\bridge.log" 2^>^&1"
) > "%DIR%\start_bridge.cmd"

echo [6/6] Registruji spousteni z Toolboxu...
reg add "HKCU\Software\Classes\twentytwentyauth" /ve /d "URL:20-20 AuthorizationBridge" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth" /v "URL Protocol" /d "" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth\shell\open\command" /ve /d "\"%DIR%\start_bridge.cmd\" \"%%1\"" /f >nul

call "%DIR%\start_bridge.cmd"

echo.
echo HOTOVO.
echo AuthorizationBridge bezi pouze na 127.0.0.1:8094.
echo Vrat se do 20-20 TOOLBOXu a klikni na "Zkontrolovat".
echo.
pause
exit /b 0

:find_python
set "PY_EXE="
del /q "%PYFILE%" >nul 2>nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PYFINDER%" > "%PYFILE%" 2>nul
if exist "%PYFILE%" set /p "PY_EXE="<"%PYFILE%"
del /q "%PYFILE%" >nul 2>nul
exit /b 0

:python_auto_install_failed
echo.
echo CHYBA: Python 3 se nepodarilo najit ani automaticky nainstalovat.
echo Automaticka instalace pouziva oficialni Python balicek pres winget.
echo Pokud winget na tomto PC neni, nainstaluj Windows App Installer nebo Python rucne.
echo.
pause
exit /b 1

:download_error
echo CHYBA: nepodarilo se stahnout soubory bridge z GitHubu.
pause
exit /b 1

:python_error
echo CHYBA: nepodarilo se vytvorit Python prostredi.
echo Pouzity Python: %PY_EXE%
pause
exit /b 1

:pip_error
echo CHYBA: nepodarilo se nainstalovat pyHanko/Flask.
echo Pouzity Python: %PY_EXE%
echo Zkontroluj internet a log v prikazovem radku.
pause
exit /b 1
