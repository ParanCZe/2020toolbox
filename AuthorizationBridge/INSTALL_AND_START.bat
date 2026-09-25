@echo off
setlocal EnableExtensions
chcp 65001 >nul
title 20-20 TOOLBOX - AuthorizationBridge

set "DIR=%LOCALAPPDATA%\20-20-TOOLBOX\AuthorizationBridge"
set "VENV=%DIR%\venv"
set "PAYLOAD_REF=c096794894915d0bfa632f058f4730b9fca4ee63"
set "RAW=https://raw.githubusercontent.com/ParanCZe/2020toolbox/%PAYLOAD_REF%/AuthorizationBridge"
set "STAGE=%TEMP%\20-20-auth-stage-%RANDOM%-%RANDOM%"
set "PYFINDER=%DIR%\find_python.ps1"
set "RESTARTER=%DIR%\restart_bridge.ps1"
set "PYFILE=%TEMP%\2020toolbox_python_path.txt"
set "PY_EXE="

if not exist "%DIR%" mkdir "%DIR%"

echo.
echo 20-20 TOOLBOX - instalace AuthorizationBridge
echo Data certifikatu zustavaji pouze v tomto pocitaci.
echo.

echo [1/6] Stahuji podepsany release AuthorizationBridge 2.1.0...
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%" >nul 2>nul
if errorlevel 1 goto :download_error

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/authorization_bridge.py' -OutFile '%STAGE%\authorization_bridge.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/requirements.txt' -OutFile '%STAGE%\requirements.txt'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/find_python.ps1' -OutFile '%STAGE%\find_python.ps1'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/restart_bridge.ps1' -OutFile '%STAGE%\restart_bridge.ps1'"
if errorlevel 1 goto :download_error

echo Overuji SHA-256 vsech souboru...
call :verify_sha256 "%STAGE%\authorization_bridge.py" "2c2df39ab009f0522306c47c932bbe59abfd92c0fea1f24f510dc71968b1ccee"
if errorlevel 1 goto :integrity_error
call :verify_sha256 "%STAGE%\requirements.txt" "c567e2afd9cdb0930735ff0eb6c3b384bf22bf965d02d9e1ca1981f9875579f3"
if errorlevel 1 goto :integrity_error
call :verify_sha256 "%STAGE%\find_python.ps1" "ea6b7f6334753f7394966e09fda98fa7a12b4a87a34e0c6c95eb0edbae5b39b0"
if errorlevel 1 goto :integrity_error
call :verify_sha256 "%STAGE%\restart_bridge.ps1" "8382fa19af65cee482a1e9333a1ee11157d585dadd412b364ee7c630ec90596e"
if errorlevel 1 goto :integrity_error

copy /y "%STAGE%\authorization_bridge.py" "%DIR%\authorization_bridge.py" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\requirements.txt" "%DIR%\requirements.txt" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\find_python.ps1" "%PYFINDER%" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\restart_bridge.ps1" "%RESTARTER%" >nul
if errorlevel 1 goto :integrity_error
rmdir /s /q "%STAGE%" >nul 2>nul

echo [2/6] Hledam existujici Python 3...
call :verify_sha256
set "VERIFY_FILE=%~1"
set "VERIFY_EXPECTED=%~2"
for /f "usebackq delims=" %%H in (`powershell.exe -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%VERIFY_FILE%').Hash.ToLowerInvariant()"`) do set "VERIFY_ACTUAL=%%H"
if /i not "%VERIFY_ACTUAL%"=="%VERIFY_EXPECTED%" (
  echo.
  echo CHYBA INTEGRITY: SHA-256 nesouhlasi.
  echo Soubor: %VERIFY_FILE%
  echo Ocekavano: %VERIFY_EXPECTED%
  echo Skutecnost: %VERIFY_ACTUAL%
  exit /b 1
)
exit /b 0

:find_python
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
"%VENV%\Scripts\python.exe" -m pip install --disable-pip-version-check --no-cache-dir --upgrade -r "%DIR%\requirements.txt"
if errorlevel 1 goto :pip_error
"%VENV%\Scripts\python.exe" -m pip check
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
echo V Toolboxu musi byt videt verze 2.1.0.
echo Payload commit: %PAYLOAD_REF%
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
echo CHYBA: nepodarilo se stahnout release soubory bridge z GitHubu.
if exist "%STAGE%" rmdir /s /q "%STAGE%" >nul 2>nul
pause
exit /b 1

:integrity_error
echo.
echo BEZPECNOSTNI CHYBA: stazeny AuthorizationBridge neodpovida ocekavanemu SHA-256.
echo Nic z teto aktualizace nebude spusteno.
if exist "%STAGE%" rmdir /s /q "%STAGE%" >nul 2>nul
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
