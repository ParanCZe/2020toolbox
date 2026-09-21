@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ================================================================
echo 20-20 TOOLBOX - VOSR 2.0 SETUP
echo ================================================================

where nvidia-smi >nul 2>nul
if errorlevel 1 (
  echo [CHYBA] Nebyla nalezena NVIDIA GPU / nvidia-smi.
  echo VOSR 2.0 v teto integraci vyzaduje NVIDIA GPU.
  pause
  exit /b 1
)

set "PYBASE="
py -3.10 -c "import sys" >nul 2>nul && set "PYBASE=py -3.10"
if not defined PYBASE py -3.11 -c "import sys" >nul 2>nul && set "PYBASE=py -3.11"
if not defined PYBASE py -3.12 -c "import sys" >nul 2>nul && set "PYBASE=py -3.12"
if not defined PYBASE python -c "import sys" >nul 2>nul && set "PYBASE=python"
if not defined PYBASE (
  echo [CHYBA] Python 3.10-3.12 nebyl nalezen.
  echo Nainstaluj 64-bit Python a znovu spust setup.bat.
  pause
  exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
  echo [1/6] Vytvarim Python prostredi...
  %PYBASE% -m venv .venv
  if errorlevel 1 goto :fail
)

set "PY=%CD%\.venv\Scripts\python.exe"
echo [2/6] Aktualizuji pip...
"%PY%" -m pip install -U pip setuptools wheel
if errorlevel 1 goto :fail

where git >nul 2>nul
if errorlevel 1 (
  echo [CHYBA] Git nebyl nalezen. Nainstaluj Git for Windows.
  pause
  exit /b 1
)

if not exist "runtime\VOSR\.git" (
  echo [3/6] Stahuji oficialni VOSR zdrojaky...
  if not exist "runtime" mkdir "runtime"
  git clone --depth 1 https://github.com/cswry/VOSR.git "runtime\VOSR"
  if errorlevel 1 goto :fail
) else (
  echo [3/6] VOSR zdrojaky uz existuji.
)

echo [4/6] Instaluji VOSR CUDA zavislosti...
findstr /V /B /C:"triton==" "runtime\VOSR\requirements.txt" > "runtime\requirements-toolbox-windows.txt"
"%PY%" -m pip install -r "runtime\requirements-toolbox-windows.txt"
if errorlevel 1 goto :fail

rem Oficialni requirements pinuji Triton 3.1 pro Torch 2.5.
rem Na Windows pouzijeme kompatibilni komunitni wheel stejne verze.
"%PY%" -m pip uninstall -y triton >nul 2>nul
"%PY%" -m pip install "triton-windows>=3.1,<3.2"
if errorlevel 1 goto :fail

echo [5/6] Instaluji downloader modelu...
"%PY%" -m pip install -U "huggingface_hub[hf_xet]"
if errorlevel 1 goto :fail

echo [6/6] Stahuji VOSR 2.0 checkpoint, Qwen VAE a DINO cache...
"%PY%" "%CD%\download_models.py"
if errorlevel 1 goto :fail

echo.
echo Overuji CUDA...
"%PY%" -c "import torch; print('PyTorch:', torch.__version__); print('CUDA:', torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NONE'); raise SystemExit(0 if torch.cuda.is_available() else 2)"
if errorlevel 1 (
  echo [CHYBA] PyTorch nevidi CUDA GPU. Aktualizuj NVIDIA ovladac a zkus setup znovu.
  pause
  exit /b 1
)

echo.
echo ================================================================
echo HOTOVO. Ted spust run_bridge.bat a nech okno otevrene.
echo V Toolboxu vyber VOSR 2.0 Scene 2x nebo 4x.
echo ================================================================
pause
exit /b 0

:fail
echo.
echo [CHYBA] Instalace se nepodarila. Viz vypis vyse.
pause
exit /b 1
