@echo off
chcp 65001 >nul
REM ============================================================
REM  專業出勤系統 打卡小工具 (v5.5.0)
REM  連上公司 WiFi 後按兩下本檔，會自動讀出目前連上的
REM  基地台實體位址（MAC / BSSID），然後開啟打卡頁並自動帶入，
REM  員工直接輸入帳密打卡即可。
REM
REM  TY-clockin-mac.ps1 必須與本 .bat 放在同一個資料夾。
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TY-clockin-mac.ps1"
echo.
echo 若視窗一閃即逝或讀不到基地台，請確認已連上公司 WiFi 後再執行一次。
echo 用手機打卡者不需要這個工具：請在打卡頁抄下「裝置代碼」給管理員核准。
timeout /t 8 >nul
