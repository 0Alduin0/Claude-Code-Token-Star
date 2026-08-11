@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0token-test.ps1" %*
exit /b %errorlevel%
