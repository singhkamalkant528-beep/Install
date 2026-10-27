@echo off
setlocal EnableExtensions
powershell.exe -NoProfile -Command "$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo Right-click this file and select Run as administrator.
    pause
    exit /b 1
)
if not exist "%~dp0uninstall.ps1" (
    echo ERROR: Keep this batch file and uninstall.ps1 together.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
set "RESULT=%ERRORLEVEL%"
echo(
if not "%RESULT%"=="0" echo Operation stopped. Read the error above.
pause
endlocal & exit /b %RESULT%