@echo off
setlocal
set "SCRIPT=%~dp0YovaZipArchiver_v3.ps1"
if not exist "%SCRIPT%" (
  echo Missing script: %SCRIPT%
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%SCRIPT%"
exit /b %ERRORLEVEL%
