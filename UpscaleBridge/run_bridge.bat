@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
  echo VOSR 2.0 neni nainstalovany.
  echo Spust znovu hlavni install.bat - Python se nainstaluje automaticky.
  pause
  exit /b 1
)

title 20-20 TOOLBOX - VOSR 2.0 Bridge
".venv\Scripts\python.exe" "%CD%\server.py"
if errorlevel 1 (
  echo.
  echo Bridge skoncil s chybou.
  pause
)
