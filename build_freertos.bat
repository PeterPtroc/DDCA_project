@echo off
setlocal EnableExtensions

rem Resolve the build script relative to this BAT and forward all arguments.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_freertos.ps1" %*
exit /b %ERRORLEVEL%
