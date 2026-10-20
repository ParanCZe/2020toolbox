@echo off
setlocal EnableExtensions
chcp 65001 >nul
title 20-20 TOOLBOX - AuthorizationBridge

set "DIR=%LOCALAPPDATA%\20-20-TOOLBOX\AuthorizationBridge"
set "VENV=%DIR%\venv"
set "PAYLOAD_REF=560fcb770061ddfbefdaeaacd025012a525bde64"
set "RAW=https://raw.githubusercontent.com/ParanCZe/2020toolbox/%PAYLOAD_REF%/AuthorizationBridge"
set "STAGE=%TEMP%\20-20-auth-stage-%RANDOM%-%RANDOM%"
set "PYFINDER=%DIR%\find_python.ps1"
set "RESTARTER=%DIR%\restart_bridge.ps1"
set "PYFILE=%TEMP%\2020toolbox_python_path.txt"
set "PY_EXE="

if not exist "%DIR%" mkdir "%DIR%"

echo.
echo 20-20 TOOLBOX - AUTORIZACE PDF 2.5.0 s Adobe CMS revokacnimi podklady 
echo Instalace aktualizuje mistni Bridge. Vsechny podpisy pouzivaji soukromy klic pouze ve Windows.
echo Data certifikatu zustavaji pouze v tomto pocitaci.
echo.

echo [1/6] Stahuji pevne pripnuty a SHA-256 overovany AuthorizationBridge 2.5.0 pro Adobe CMS...
if exist "%STAGE%" rmdir /s /q "%STAGE%" >nul 2>nul
mkdir "%STAGE%" >nul 2>nul
if errorlevel 1 goto :download_error

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/authorization_bridge.py' -OutFile '%STAGE%\authorization_bridge.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/pdf_ltv.py' -OutFile '%STAGE%\pdf_ltv.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/pdf_validator_engine.py' -OutFile '%STAGE%\pdf_validator_engine.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/eu_dss_validator.py' -OutFile '%STAGE%\eu_dss_validator.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/INSTALL_EU_DSS.ps1' -OutFile '%STAGE%\INSTALL_EU_DSS.ps1'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/qualified_tsa_check.py' -OutFile '%STAGE%\qualified_tsa_check.py'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/requirements.txt' -OutFile '%STAGE%\requirements.txt'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/find_python.ps1' -OutFile '%STAGE%\find_python.ps1'"
if errorlevel 1 goto :download_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/restart_bridge.ps1' -OutFile '%STAGE%\restart_bridge.ps1'"
if errorlevel 1 goto :download_error

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%RAW%/pdf_signature_inspector.py' -OutFile '%STAGE%\pdf_signature_inspector.py'"
if errorlevel 1 goto :download_error

echo Overuji SHA-256 vsech souboru...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\pdf_ltv.py').Hash.ToLowerInvariant(); if($h -ne '60d42469a34492570b39b9a3b38590f0747bb5e546f84b1b38999e2d7aa919d5'){Write-Error ('SHA-256 nesouhlasi: pdf_ltv.py = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\authorization_bridge.py').Hash.ToLowerInvariant(); if($h -ne 'b8842c322fa3490326760e8b6a8f04b4509389ca47d6c7aaf1744f75d6f21107'){Write-Error ('SHA-256 nesouhlasi: authorization_bridge.py = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\pdf_validator_engine.py').Hash.ToLowerInvariant(); if($h -ne 'bf6cc227db1b9aa03532c1ee181dd5812d24e926a63a1241a38eca93ab4b8b99'){Write-Error ('SHA-256 nesouhlasi: pdf_validator_engine.py = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\eu_dss_validator.py').Hash.ToLowerInvariant(); if($h -ne '8b151b094469b67a493c49c746dcf0dffae5ed8845187dab7a15c7b2d2354ca6'){Write-Error ('SHA-256 nesouhlasi: eu_dss_validator.py = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\INSTALL_EU_DSS.ps1').Hash.ToLowerInvariant(); if($h -ne '4759698c32bf9b5224ff947b355bc68bce1eef7ff111dbdb5ff5ee7ab0aa324a'){Write-Error ('SHA-256 nesouhlasi: INSTALL_EU_DSS.ps1 = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\qualified_tsa_check.py').Hash.ToLowerInvariant(); if($h -ne 'e86522d3f68bbc8d5c0212e28fc443b93cd0284f4387543b04093fa7626d5b89'){Write-Error ('SHA-256 nesouhlasi: qualified_tsa_check.py = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\requirements.txt').Hash.ToLowerInvariant(); if($h -ne 'c567e2afd9cdb0930735ff0eb6c3b384bf22bf965d02d9e1ca1981f9875579f3'){Write-Error ('SHA-256 nesouhlasi: requirements.txt = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\find_python.ps1').Hash.ToLowerInvariant(); if($h -ne 'ea6b7f6334753f7394966e09fda98fa7a12b4a87a34e0c6c95eb0edbae5b39b0'){Write-Error ('SHA-256 nesouhlasi: find_python.ps1 = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\restart_bridge.ps1').Hash.ToLowerInvariant(); if($h -ne '063c20ca5420de26c937efb124aa11beb1c8c18c7b041a1951a05f11fbec493b'){Write-Error ('SHA-256 nesouhlasi: restart_bridge.ps1 = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -Algorithm SHA256 -LiteralPath '%STAGE%\pdf_signature_inspector.py').Hash.ToLowerInvariant(); if($h -ne '54772513262b1c71bba7a6660e9cc7ebdcf7401d3368442b86e7fa1b7fd26c42'){Write-Error ('SHA-256 nesouhlasi: pdf_signature_inspector.py = '+$h); exit 1}"
if errorlevel 1 goto :integrity_error

rem Preserve the previous bridge module once for recovery before updating.
if exist "%DIR%\authorization_bridge.py" if not exist "%DIR%\authorization_bridge.py.before-LT-beta.bak" copy /y "%DIR%\authorization_bridge.py" "%DIR%\authorization_bridge.py.before-LT-beta.bak" >nul
copy /y "%STAGE%\authorization_bridge.py" "%DIR%\authorization_bridge.py" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\pdf_ltv.py" "%DIR%\pdf_ltv.py" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\pdf_validator_engine.py" "%DIR%\pdf_validator_engine.py" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\pdf_signature_inspector.py" "%DIR%\pdf_signature_inspector.py" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\eu_dss_validator.py" "%DIR%\eu_dss_validator.py" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\INSTALL_EU_DSS.ps1" "%DIR%\INSTALL_EU_DSS.ps1" >nul
if errorlevel 1 goto :integrity_error
copy /y "%STAGE%\qualified_tsa_check.py" "%DIR%\qualified_tsa_check.py" >nul
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
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RESTARTER%" -PythonExe "%VENV%\Scripts\python.exe" -BridgeScript "%DIR%\authorization_bridge.py" -LogFile "%DIR%\bridge.log" -ExpectedVersion "2.5.0"
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
echo V Toolboxu musi byt videt verze 2.5.0.
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
