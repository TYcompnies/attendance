@echo off
chcp 65001 >nul
REM ============================================================
REM  TY_5G clock-in launcher (v5.0.0)
REM  連上公司 WiFi 後按兩下本檔，會自動讀出：
REM    - WiFi 名稱 (SSID)
REM    - 公司路由器 MAC (BSSID)   -> v5.0.0 主要認證依據
REM    - 本機網卡 MAC             -> 選配
REM  然後開啟打卡頁並自動帶入，員工直接輸入帳密打卡即可。
REM  TY_5G-clockin.ps1 必須與本 .bat 放在同一個資料夾。
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TY_5G-clockin.ps1"
echo.
echo 若視窗一閃即逝，請確認已連上公司 WiFi 後再執行一次。
timeout /t 6 >nul
