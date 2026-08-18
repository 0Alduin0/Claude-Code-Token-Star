@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\src\windows\uninstall.ps1" %*
exit /b %errorlevel%
