@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "VOSR_COMMIT=516f292b99cf23c76fdc33351e86dc4f97711fe8"
set "RUNTIME=%CD%\runtime"
set "UV_DIR=%RUNTIME%\uv"
set "UV=%UV_DIR%\uv.exe"
set "UV_PYTHON_INSTALL_DIR=%RUNTIME%\python"
set "UV_CACHE_DIR=%RUNTIME%\uv-cache"
set "UV_MANAGED_PYTHON=1"
set "UV_NO_MODIFY_PATH=1"
set "VOSR_DIR=%RUNTIME%\VOSR"
set "VOSR_ZIP=%RUNTIME%\VOSR-%VOSR_COMMIT%.zip"
set "VOSR_TMP=%RUNTIME%\_vosr_extract"

echo ================================================================
echo 20-20 TOOLBOX - VOSR 2.0 ONE-CLICK SETUP
echo Python ani Git neni potreba instalovat do Windows.
echo ================================================================

where nvidia-smi >nul 2>nul
if errorlevel 1 (
  echo [CHYBA] Nebyla nalezena NVIDIA GPU / nvidia-smi.
  echo VOSR 2.0 vyzaduje NVIDIA GPU a aktualni NVIDIA ovladac.
  goto :fail
)

if not exist "%RUNTIME%" mkdir "%RUNTIME%"
if errorlevel 1 goto :fail

if not exist "%UV%" (
  echo [1/7] Stahuji portable instalacni runtime uv...
  if not exist "%UV_DIR%" mkdir "%UV_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $env:UV_UNMANAGED_INSTALL='%UV_DIR%'; $env:UV_NO_MODIFY_PATH='1'; irm https://astral.sh/uv/install.ps1 | iex"
  if errorlevel 1 goto :fail
)
if not exist "%UV%" (
  echo [CHYBA] Portable uv.exe nebyl po instalaci nalezen.
  goto :fail
)

echo [2/7] Stahuji vlastni Python 3.10 runtime...
"%UV%" python install 3.10 --managed-python
if errorlevel 1 goto :fail

if not exist ".venv\Scripts\python.exe" (
  echo [3/7] Vytvarim izolovane Python prostredi...
  "%UV%" venv ".venv" --python 3.10 --managed-python
  if errorlevel 1 goto :fail
) else (
  echo [3/7] Izolovane Python prostredi uz existuje.
)

set "PY=%CD%\.venv\Scripts\python.exe"
"%PY%" -c "import sys; raise SystemExit(0 if sys.version_info[:2] == (3,10) else 3)" >nul 2>nul
if errorlevel 1 (
  echo Stare Python prostredi neni kompatibilni, vytvarim nove...
  rmdir /s /q ".venv"
  "%UV%" venv ".venv" --python 3.10 --managed-python
  if errorlevel 1 goto :fail
)

if not exist "%VOSR_DIR%\inference_vosr_onestep.py" (
  echo [4/7] Stahuji pinned VOSR 2.0 zdrojaky...
  if exist "%VOSR_DIR%" rmdir /s /q "%VOSR_DIR%"
  if exist "%VOSR_TMP%" rmdir /s /q "%VOSR_TMP%"
  if exist "%VOSR_ZIP%" del /q "%VOSR_ZIP%"

  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/cswry/VOSR/archive/%VOSR_COMMIT%.zip' -OutFile '%VOSR_ZIP%'; Expand-Archive -LiteralPath '%VOSR_ZIP%' -DestinationPath '%VOSR_TMP%' -Force; $d=Get-ChildItem -LiteralPath '%VOSR_TMP%' -Directory | Select-Object -First 1; if(-not $d){throw 'VOSR ZIP neobsahuje slozku'}; Move-Item -LiteralPath $d.FullName -Destination '%VOSR_DIR%'"
  if errorlevel 1 goto :fail

  if exist "%VOSR_ZIP%" del /q "%VOSR_ZIP%"
  if exist "%VOSR_TMP%" rmdir /s /q "%VOSR_TMP%"
) else (
  echo [4/7] Pinned VOSR zdrojaky uz existuji.
)

echo [5/7] Instaluji PyTorch CUDA a VOSR zavislosti...
findstr /V /B /C:"triton==" "%VOSR_DIR%\requirements.txt" > "%RUNTIME%\requirements-toolbox-windows.txt"
if errorlevel 1 goto :fail

"%UV%" pip install --python "%PY%" -r "%RUNTIME%\requirements-toolbox-windows.txt"
if errorlevel 1 goto :fail

rem Oficialni VOSR pinuje Triton 3.1. Na Windows pouzijeme kompatibilni triton-windows 3.1.x.
"%UV%" pip install --python "%PY%" "triton-windows>=3.1,<3.2"
if errorlevel 1 goto :fail

"%UV%" pip install --python "%PY%" -U "huggingface_hub[hf_xet]"
if errorlevel 1 goto :fail

echo [6/7] Stahuji VOSR2 checkpoint, Qwen VAE a DINO cache...
"%PY%" "%CD%\download_models.py"
if errorlevel 1 goto :fail

echo [7/7] Overuji NVIDIA CUDA...
"%PY%" -c "import torch; print('PyTorch:', torch.__version__); print('CUDA:', torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NONE'); raise SystemExit(0 if torch.cuda.is_available() else 2)"
if errorlevel 1 (
  echo [CHYBA] PyTorch nevidi CUDA GPU.
  echo Aktualizuj NVIDIA ovladac a spust instalator znovu.
  goto :fail
)

echo Cistim instalacni cache...
"%UV%" cache clean >nul 2>nul

> "%CD%\.portable_runtime_v1" echo VOSR portable runtime installed
echo.
echo ================================================================
echo HOTOVO.
echo Python, Git ani CUDA toolkit neni potreba instalovat rucne.
echo Vsechny runtime soubory jsou uvnitr:
echo %CD%
echo ================================================================
exit /b 0

:fail
echo.
echo [CHYBA] Instalace VOSR Bridge se nepodarila. Viz vypis vyse.
exit /b 1
