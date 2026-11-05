@echo off
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 tools\preview.py
) else if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
  "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" tools\preview.py
) else (
  echo Python 3 with Tcl/Tk is required. Please install Python and try again.
  pause
  exit /b 1
)
if errorlevel 1 pause
