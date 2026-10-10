@echo off
setlocal
chcp 65001 >nul 2>&1
title TY Attendance - Clock-in Tool

REM ============================================================
REM  IMPORTANT: keep this file 100 percent ASCII, CRLF line endings.
REM  Chinese characters inside a .bat break cmd.exe (it reads the
REM  file byte-by-byte with the active codepage, so comments turn
REM  into "not recognized as an internal or external command").
REM  All Chinese output is done by the PowerShell script instead.
REM  Build helper: .diag/mk-tools.js  (run it after editing)
REM ============================================================

set "TOOLVER=1.3.0"
set "TY_FROM_BAT=1"
set "PAGEURL=https://tycompnies.github.io/attendance/"
set "PSURL=https://tycompnies.github.io/attendance/tools/TY-clockin-mac.ps1"
set "SIBLING=%~dp0TY-clockin-mac.ps1"
set "CACHED=%TEMP%\TY-clockin-mac.ps1"
set "TESTFLAG="

if /i "%~1"=="/test" set "TESTFLAG=-Test"
if /i "%~1"=="-t"    set "TESTFLAG=-Test"

echo ============================================================
echo   TY Attendance  -  Clock-in Tool   v%TOOLVER%
echo ------------------------------------------------------------
echo   This tool reads the MAC address of the company AP/router
echo   you are connected to, then opens the clock-in page with it.
echo   (A browser cannot read the WiFi MAC, so this tool does it.)
echo ============================================================
echo.

REM ---- 1. always try to fetch the latest PowerShell script ----
echo [1/2] Getting tool script...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{}; try{Invoke-WebRequest -Uri '%PSURL%' -OutFile '%CACHED%' -UseBasicParsing -TimeoutSec 20}catch{}" >nul 2>&1

set "RUN="
if exist "%CACHED%" set "RUN=%CACHED%"
if not defined RUN if exist "%SIBLING%" set "RUN=%SIBLING%"

if defined RUN goto :run

echo.
echo  [X] Tool script not found.
echo.
echo      1. Check that this computer can open this address:
echo         %PSURL%
echo.
echo      2. Or put TY-clockin-mac.ps1 in the SAME folder as this
echo         .bat file, then run this .bat again.
echo.
echo  Phone users do NOT need this tool - just use the device
echo  code shown on the clock-in page and ask the admin to
echo  approve it once.
echo.
pause
exit /b 1

:run
echo [2/2] Detecting your network...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%RUN%" %TESTFLAG%

echo.
echo ============================================================
echo   If it says "(not found)", make sure this computer is on
echo   the COMPANY network, then run this file again.
echo   Phone users do NOT need this tool - use the device code
echo   on the clock-in page and ask the admin to approve it.
echo ============================================================
echo.
pause
endlocal
