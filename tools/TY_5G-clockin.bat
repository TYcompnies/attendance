@echo off
REM TY_5G clock-in launcher (v4.0.20)
REM Double-click this file to open the attendance page with the current WiFi name.
REM TY_5G-clockin.ps1 must stay in the same folder as this .bat file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TY_5G-clockin.ps1"
