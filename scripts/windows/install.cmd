@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\src\windows\install.ps1" %*
exit /b %errorlevel%
