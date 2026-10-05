@echo off
REM TY_5G clock-in launcher (v5.3.0)
REM Double-click this file: it reads the WiFi name (SSID) you are connected to and
REM opens the attendance page with it, so the system can confirm you are on TY_5G.
REM If no WiFi is detected it tells you why (wired-only PC / WiFi off / wrong network)
REM and still opens the page - since v5.3.0 clock-in may also pass via the company WAN IP.
REM TY_5G-clockin.ps1 must stay in the same folder as this .bat file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TY_5G-clockin.ps1"
