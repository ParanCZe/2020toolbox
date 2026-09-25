@echo off
setlocal EnableExtensions
chcp 65001 >nul
title 20-20 TOOLBOX - AuthorizationBridge

set "DIR=%LOCALAPPDATA%\20-20-TOOLBOX\AuthorizationBridge"
set "VENV=%DIR%\venv"
set "RAW=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/AuthorizationBridge"
set "PYFINDER=%DIR%\find_python.ps1"
set "RESTARTER=%DIR%\restart_bridge.ps1"
set "PYFILE=%TEMP%\2020toolbox_python_path.txt"
set "PY_EXE="

if not exist "%DIR%" mkdir "%DIR%"

echo.
echo 20-20 TOOLBOX - instalace AuthorizationBridge
echo Data certifikatu zustavaji pouze v tomto pocitaci.
echo.

echo [1/6] Stahuji aktualni AuthorizationBridge...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/authorization_bridge.py?cb=15' -OutFile '%DIR%\authorization_bridge.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/requirements.txt?cb=15' -OutFile '%DIR%\requirements.txt'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/find_python.ps1?cb=15' -OutFile '%PYFINDER%'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/restart_bridge.ps1?cb=15' -OutFile '%RESTARTER%'"
if errorlevel 1 goto :download_error

echo [2/6] Hledam existujici Python 3...
call :find_python
if defined PY_EXE goto :python_ready

echo.
echo Python 3 nebyl nalezen. Nainstaluji ho automaticky.
where winget >nul 2>nul
if errorlevel 1 goto :python_auto_install_failed

echo Instaluji Python 3.13 pres Windows Package Manager...
winget install --id Python.Python.3.13 -e --source winget --scope user --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
  echo Python 3.13 se nepodarilo nainstalovat. Zkousim Python 3.12...
  winget install --id Python.Python.3.12 -e --source winget --scope user --silent --accept-package-agreements --accept-source-agreements
)
if errorlevel 1 goto :python_auto_install_failed

echo.
echo Python byl nainstalovan. Overuji standardni instalacni cestu...
if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" set "PY_EXE=%LOCALAPPDATA%\Programs\Python\Python314\python.exe"
if not defined PY_EXE if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "PY_EXE=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if not defined PY_EXE if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY_EXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY_EXE if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PY_EXE=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if not defined PY_EXE call :find_python
if not defined PY_EXE goto :python_auto_install_failed

:python_ready
echo.
echo Nalezen Python:
echo   %PY_EXE%
"%PY_EXE%" --version
if errorlevel 1 goto :python_auto_install_failed

set "RECREATE_VENV=0"
if exist "%VENV%\Scripts\python.exe" (
  "%VENV%\Scripts\python.exe" -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" >nul 2>nul
  if errorlevel 1 set "RECREATE_VENV=1"
) else (
  set "RECREATE_VENV=1"
)

if "%RECREATE_VENV%"=="1" (
  echo [3/6] Vytvarim ciste lokalni Python prostredi...
  if exist "%VENV%" rmdir /s /q "%VENV%"
  "%PY_EXE%" -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" >nul 2>nul
  if errorlevel 1 (
    echo Nalezeny Python je prilis stary. Je potreba Python 3.10 nebo novejsi.
    goto :python_auto_install_failed
  )
  "%PY_EXE%" -m venv "%VENV%"
  if errorlevel 1 goto :python_error
) else (
  echo [3/6] Lokalni Python prostredi je v poradku.
)

echo [4/6] Instaluji / aktualizuji podpisove knihovny...
"%VENV%\Scripts\python.exe" -m pip install --disable-pip-version-check --quiet --upgrade pip setuptools wheel
if errorlevel 1 goto :pip_error
"%VENV%\Scripts\python.exe" -m pip install --disable-pip-version-check --upgrade --upgrade-strategy eager -r "%DIR%\requirements.txt"
if errorlevel 1 goto :pip_error

echo [5/6] Vytvarim spoustec s automatickym restartem...
(
  echo @echo off
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RESTARTER%" -PythonExe "%VENV%\Scripts\python.exe" -BridgeScript "%DIR%\authorization_bridge.py" -LogFile "%DIR%\bridge.log"
) > "%DIR%\start_bridge.cmd"

echo [6/6] Registruji spousteni z Toolboxu...
reg add "HKCU\Software\Classes\twentytwentyauth" /ve /d "URL:20-20 AuthorizationBridge" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth" /v "URL Protocol" /d "" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth\shell\open\command" /ve /d "\"%DIR%\start_bridge.cmd\" \"%%1\"" /f >nul

echo.
echo Restartuji AuthorizationBridge a uvolnuji port 8094...
call "%DIR%\start_bridge.cmd"
if errorlevel 1 goto :bridge_start_error

echo.
echo HOTOVO.
echo AuthorizationBridge byl aktualizovan a restartovan.
echo V Toolboxu musi byt videt verze 1.8.6 nebo novejsi.
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
echo Microsoft Store alias WindowsApps se zamerne ignoruje.
echo Automaticka instalace pouziva oficialni Python balicek pres winget.
echo.
pause
exit /b 1

:download_error
echo.
echo CHYBA: nepodarilo se stahnout aktualni soubory bridge z GitHubu.
pause
exit /b 1

:python_error
echo.
echo CHYBA: nepodarilo se vytvorit Python prostredi.
echo Pouzity Python: %PY_EXE%
pause
exit /b 1

:pip_error
echo.
echo CHYBA: nepodarilo se nainstalovat pyHanko/Flask/cryptography.
echo Pouzity Python: %PY_EXE%
pause
exit /b 1

:bridge_start_error
echo.
echo CHYBA: novy AuthorizationBridge se nepodarilo spustit.
echo.
if exist "%DIR%\bridge.preflight.log" (
  echo ===== BRIDGE PREFLIGHT =====
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%DIR%\bridge.preflight.log' -Tail 80"
  echo.
)
if exist "%DIR%\bridge.error.log" (
  echo ===== BRIDGE ERROR LOG =====
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%DIR%\bridge.error.log' -Tail 100"
  echo.
)
if exist "%DIR%\bridge.log" (
  echo ===== BRIDGE LOG =====
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%DIR%\bridge.log' -Tail 60"
  echo.
)
echo Logy zustavaji v:
echo   %DIR%
echo.
pause
exit /b 1
