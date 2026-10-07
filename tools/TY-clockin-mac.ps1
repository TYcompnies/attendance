# 專業出勤系統 打卡小工具 (v5.5.0)
# ---------------------------------------------------------------------------
# 瀏覽器基於安全限制「讀不到」基地台的實體位址（MAC / BSSID），
# 所以由本小工具用 Windows 內建指令 netsh 讀出後，以
#     ?bssid=<基地台 MAC>&t=<記號>
# 自動帶入打卡頁。員工只要雙擊執行、登入打卡即可。
#
#   bssid = 目前連上的那個 AP（公司路由器）的實體位址 -> v5.5.0 的主要認證依據
#   t     = hash31(MAC|密語|當天日期)，**換天自動失效**，所以沒辦法靠手打網址偽造
#
# 用法：TY-clockin-mac.ps1 必須與 TY-clockin-mac.bat 放在同一個資料夾，
#       請執行 .bat（不要直接對 .ps1 按右鍵）。
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'SilentlyContinue'
$page = 'https://tycompnies.github.io/attendance/'
$secret = 'TY-Attendance-MAC-v5.5'

# 統一轉成「大寫純十六進位」（與網頁 normalizeMAC() 對齊）
function Get-HexMAC($v) {
  if (-not $v) { return '' }
  return (($v.ToString()) -replace '[^0-9A-Fa-f]', '').ToUpper()
}
# 12 碼純十六進位 -> 冒號分隔（A42B8C112233 -> A4:2B:8C:11:22:33）
function Format-MAC($v) {
  if (-not $v -or $v.Length -ne 12) { return '' }
  return ($v -replace '(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})', '$1:$2:$3:$4:$5:$6')
}
function Get-DayStamp {
  return (Get-Date).ToString('yyyyMMdd')
}
# 記號：hash31 取模後轉 16 進位（與網頁 hash31()/macToolToken() 完全一致）
function Get-Token($s) {
  $h = [bigint]0
  foreach ($c in $s.ToCharArray()) {
    $h = ($h * 31 + [int][char]$c) % 1000000007
  }
  return ([Convert]::ToString([int64]$h, 16)).ToLower()
}

# ---------- 1. 讀取目前連上的 WiFi（netsh） ----------
$lines = & netsh wlan show interfaces 2>$null

# netsh 的輸出是一段一段（每張無線網卡一段）→ 切成區塊，避免抓到沒在連線的那張卡的舊資料
$blocks = New-Object System.Collections.ArrayList
$cur = New-Object System.Collections.ArrayList
foreach ($l in $lines) {
  if ($l.Trim() -eq '') {
    if ($cur.Count -gt 0) { [void]$blocks.Add($cur.ToArray()); $cur.Clear() }
  } else { [void]$cur.Add($l) }
}
if ($cur.Count -gt 0) { [void]$blocks.Add($cur.ToArray()) }

$ssid = ''
$connectedMac = ''
$idleMac = ''
foreach ($b in $blocks) {
  $bssidLine = $b | Where-Object { $_ -match 'BSSID' } | Select-Object -First 1
  if (-not $bssidLine) { continue }
  if ($bssidLine -notmatch ':\s*(.+?)\s*$') { continue }
  $m = Get-HexMAC $Matches[1]
  if (-not $m -or $m -eq '000000000000') { continue }
  $joined = ($b -join ' ')
  # 中文 Windows 的欄位名不同 → 中英文都判斷；找不到「已連線」標記時就用第一個有效的 BSSID
  if ($joined -match 'connected|已連線|連線') {
    if (-not $connectedMac) {
      $connectedMac = $m
      $s = $b | Where-Object { $_ -match 'SSID' -and $_ -notmatch 'BSSID' } | Select-Object -First 1
      if ($s -and $s -match ':\s*(.+?)\s*$') { $ssid = $Matches[1].Trim() }
    }
  } elseif (-not $idleMac) { $idleMac = $m }
}
$macRaw = if ($connectedMac) { $connectedMac } else { $idleMac }

# 備援：區塊切法失效時，直接掃整份輸出裡第一個像 MAC 的字串
if (-not $macRaw) {
  foreach ($l in $lines) {
    if ($l -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') {
      $cand = Get-HexMAC $Matches[0]
      if ($cand -and $cand -ne '000000000000') { $macRaw = $cand; break }
    }
  }
}

# ---------- 2. 顯示偵測結果 ----------
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host ' 專業出勤系統 打卡小工具 v5.5.0' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host ('WiFi 名稱        : ' + $(if ($ssid) { $ssid } else { '(讀不到)' }))

if (-not $macRaw) {
  Write-Host ('基地台 MAC(BSSID): (讀不到)') -ForegroundColor Yellow
  Write-Host ''
  Write-Host '讀不到基地台的實體位址。請確認：' -ForegroundColor Yellow
  Write-Host '  1) 這台電腦是用 WiFi 連線（不是只有接網路線）' -ForegroundColor Yellow
  Write-Host '  2) 已連上公司 WiFi' -ForegroundColor Yellow
  Write-Host ''
  Write-Host '仍會為您打開打卡頁，但打卡會被擋下 — 手機請改用「裝置代碼」請管理員核准。' -ForegroundColor Yellow
  Start-Sleep -Seconds 4
  Start-Process $page
  exit
}

$mac = Format-MAC $macRaw
Write-Host ('基地台 MAC(BSSID): ' + $mac) -ForegroundColor Green

# ---------- 3. 產生記號並開啟打卡頁 ----------
$t = Get-Token ($mac + '|' + $secret + '|' + (Get-DayStamp))
$url = $page + '?bssid=' + [uri]::EscapeDataString($mac) + '&t=' + $t

Write-Host ''
Write-Host ('開啟打卡頁： ' + $url) -ForegroundColor Cyan
Write-Host '（若這台電腦不是在公司網路，打卡會被擋下，這是正常的）' -ForegroundColor DarkGray
Start-Process $url
