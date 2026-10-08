@echo off
setlocal EnableExtensions

rem ============================================================
rem PtrocOS - Vivado GUI Launcher
rem
rem This BAT file must be placed in the repository root:
rem
rem DDCA_project\
rem   open_vivado_gui.bat
rem   scripts\
rem   src\
rem   sw\
rem   constraints\
rem ============================================================

set "REQUIRED_VIVADO=2024.2"

rem Repository root = directory containing this BAT file.
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "LOCAL_CONFIG=%ROOT%\scripts\vivado_local.bat"
set "CREATE_TCL=%ROOT%\scripts\create_vivado_project.tcl"
set "OPEN_GUI_TCL=%ROOT%\scripts\open_vivado_project.tcl"
set "PROJECT_FILE=%ROOT%\build\vivado\ptrocos.xpr"

echo ============================================================
echo PtrocOS - Vivado Launcher
echo ============================================================
echo Project root:
echo   %ROOT%
echo.

rem ============================================================
rem 0. Repository sanity check
rem ============================================================

if not exist "%CREATE_TCL%" (
    echo ERROR: Repository file not found:
    echo   %CREATE_TCL%
    echo.
    echo Make sure open_vivado_gui.bat is located in the repository root.
    pause
    exit /b 1
)

if not exist "%OPEN_GUI_TCL%" (
    echo ERROR: Repository file not found:
    echo   %OPEN_GUI_TCL%
    pause
    exit /b 1
)

rem ============================================================
rem 1. If Vivado is already available in PATH, use it.
rem ============================================================

where vivado >nul 2>&1
if not errorlevel 1 goto :vivado_ready

rem ============================================================
rem 2. Load machine-local configuration if it exists.
rem
rem Expected file:
rem   scripts\vivado_local.bat
rem
rem Example:
rem   @echo off
rem   set "VIVADO_HOME=D:\Xilinx\Vivado\2024.2"
rem ============================================================

if exist "%LOCAL_CONFIG%" (
    echo Found local Vivado configuration:
    echo   %LOCAL_CONFIG%
    call "%LOCAL_CONFIG%"
    goto :try_configured_vivado
)

goto :ask_vivado_path


rem ============================================================
rem 3. Try VIVADO_HOME loaded from local configuration.
rem ============================================================

:try_configured_vivado

if not defined VIVADO_HOME (
    echo.
    echo WARNING: Local configuration does not define VIVADO_HOME.
    goto :ask_vivado_path
)

echo.
echo Configured Vivado:
echo   %VIVADO_HOME%

if not exist "%VIVADO_HOME%\settings64.bat" (
    echo.
    echo WARNING: Vivado settings file was not found:
    echo   %VIVADO_HOME%\settings64.bat
    echo.
    echo The saved local path is no longer valid.
    goto :ask_vivado_path
)

call "%VIVADO_HOME%\settings64.bat"

where vivado >nul 2>&1
if errorlevel 1 (
    echo.
    echo WARNING: Vivado environment setup failed for:
    echo   %VIVADO_HOME%
    goto :ask_vivado_path
)

goto :vivado_ready


rem ============================================================
rem 4. Ask for Vivado installation directory.
rem ============================================================

:ask_vivado_path

echo.
echo Vivado was not found automatically.
echo.
echo Please enter your Vivado %REQUIRED_VIVADO% installation directory.
echo Example:
echo   D:\Xilinx\Vivado\%REQUIRED_VIVADO%
echo.

set "VIVADO_HOME="
set /p "VIVADO_HOME=Vivado path: "

if not defined VIVADO_HOME (
    echo.
    echo ERROR: No Vivado path was entered.
    pause
    exit /b 1
)

rem Remove a trailing backslash if the user entered one.
if "%VIVADO_HOME:~-1%"=="\" set "VIVADO_HOME=%VIVADO_HOME:~0,-1%"

if not exist "%VIVADO_HOME%\settings64.bat" (
    echo.
    echo ERROR: Cannot find:
    echo   %VIVADO_HOME%\settings64.bat
    echo.
    echo Please check the Vivado installation directory.
    pause
    exit /b 1
)

echo.
echo Loading Vivado environment...
call "%VIVADO_HOME%\settings64.bat"

where vivado >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: Vivado environment setup failed.
    echo Installation directory:
    echo   %VIVADO_HOME%
    pause
    exit /b 1
)

rem ============================================================
rem 5. Save this machine's Vivado path.
rem
rem scripts\vivado_local.bat should be ignored by Git.
rem ============================================================

> "%LOCAL_CONFIG%" echo @echo off
>> "%LOCAL_CONFIG%" echo set "VIVADO_HOME=%VIVADO_HOME%"

echo.
echo Saved local Vivado configuration:
echo   %LOCAL_CONFIG%

goto :vivado_ready


rem ============================================================
rem 6. Vivado environment is ready.
rem ============================================================

:vivado_ready

where vivado >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: Vivado is still unavailable.
    pause
    exit /b 1
)

echo.
echo Vivado found:
where vivado
echo.

rem ============================================================
rem 7. Open or create the project and refresh firmware configuration.
rem ============================================================

echo.
echo Opening Vivado GUI:
echo   %PROJECT_FILE%
echo.

where python.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python 3 must be available in PATH.
    pause
    exit /b 1
)
python.exe -E "%ROOT%\scripts\build_guard.py" check --kind firmware --file "%ROOT%\build\hex\ptrocos_elf.hex"
if errorlevel 1 (
    echo ERROR: Rebuild the current branch firmware with build_freertos.bat first.
    pause
    exit /b 1
)

pushd "%ROOT%"
call vivado -mode gui -source "%OPEN_GUI_TCL%"
set "VIVADO_EXIT=%ERRORLEVEL%"
popd

if not "%VIVADO_EXIT%"=="0" pause
exit /b %VIVADO_EXIT%
