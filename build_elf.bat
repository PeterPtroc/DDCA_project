@echo off
setlocal EnableExtensions

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_elf.ps1" %*
set "BuildExitCode=%ERRORLEVEL%"

echo.
if not "%BuildExitCode%"=="0" echo Build failed. Please check the errors above.
pause
exit /b %BuildExitCode%
