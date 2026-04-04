@echo off
setlocal
set "SCRIPT=%~dp0YovaZipArchiver_plus.ps1"
if not exist "%SCRIPT%" (
  echo Missing script: %SCRIPT%
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%"
echo.
echo Exit code: %ERRORLEVEL%
pause
