@echo off
setlocal EnableExtensions
chcp 65001 >nul
title 20-20 TOOLBOX - AuthorizationBridge

set "DIR=%LOCALAPPDATA%\20-20-TOOLBOX\AuthorizationBridge"
set "VENV=%DIR%\venv"
set "PAYLOAD_REF=a0c7b987b22e2a3c7eb259f1d144657a82607e3f"
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

echo [1/6] Stahuji pevne pripnuty a SHA-256 overovany AuthorizationBridge 2.1.8...
if exist "%STAGE%" rmdir /s /q "%STAGE%" >nul 2>nul
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\authorization_bridge.py').Hash.ToLowerInvariant(); if($h -ne '950fbd040b71ba8f46df7771531d6534a47e9080ed3ad410a7ce5e94bae0125d'){Write-Error ('SHA-256 nesouhlasi: authorization_bridge.py = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\requirements.txt').Hash.ToLowerInvariant(); if($h -ne 'c567e2afd9cdb0930735ff0eb6c3b384bf22bf965d02d9e1ca1981f9875579f3'){Write-Error ('SHA-256 nesouhlasi: requirements.txt = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\find_python.ps1').Hash.ToLowerInvariant(); if($h -ne 'ea6b7f6334753f7394966e09fda98fa7a12b4a87a34e0c6c95eb0edbae5b39b0'){Write-Error ('SHA-256 nesouhlasi: find_python.ps1 = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\restart_bridge.ps1').Hash.ToLowerInvariant(); if($h -ne 'c9b57d36511a287a15bdd7692fb9a6bdf265d47e1c805c5e4e137f276e183e96'){Write-Error ('SHA-256 nesouhlasi: restart_bridge.ps1 = '+$h); exit 1}"
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
  if errorlevel 1 goto :python_auto_install_failed
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
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RESTARTER%" -PythonExe "%VENV%\Scripts\python.exe" -BridgeScript "%DIR%\authorization_bridge.py" -LogFile "%DIR%\bridge.log" -ExpectedVersion "2.1.8"
) > "%DIR%\start_bridge.cmd"

echo [6/6] Registruji spousteni z Toolboxu...
reg add "HKCU\Software\Classes\twentytwentyauth" /ve /d "URL:20-20 AuthorizationBridge" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth" /v "URL Protocol" /d "" /f >nul
reg add "HKCU\Software\Classes\twentytwentyauth\shell\open\command" /ve /d "\"%DIR%\start_bridge.cmd\" \"%%1\"" /f >nul

echo.
echo Restartuji AuthorizationBridge...
call "%DIR%\start_bridge.cmd"
if errorlevel 1 goto :bridge_start_error

echo.
echo HOTOVO.
echo AuthorizationBridge byl aktualizovan a restartovan.
echo V Toolboxu musi byt videt verze 2.1.8.
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
echo.
pause
exit /b 1

:download_error
echo.
echo CHYBA: nepodarilo se stahnout pripnute soubory bridge z GitHubu.
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
echo.
pause
exit /b 1

:pip_error
echo.
echo CHYBA: nepodarilo se nainstalovat podpisove knihovny.
echo.
pause
exit /b 1

:bridge_start_error
echo.
echo CHYBA: AuthorizationBridge se nepodarilo spustit.
if exist "%DIR%\bridge.preflight.log" (
  echo ===== BRIDGE PREFLIGHT =====
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%DIR%\bridge.preflight.log' -Tail 80"
)
if exist "%DIR%\bridge.error.log" (
  echo ===== BRIDGE ERROR LOG =====
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%DIR%\bridge.error.log' -Tail 100"
)
if exist "%DIR%\bridge.log" (
  echo ===== BRIDGE LOG =====
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%DIR%\bridge.log' -Tail 60"
)
pause
exit /b 1
