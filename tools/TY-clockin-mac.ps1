# 專業出勤系統 打卡小工具 (v5.5.2)
# ---------------------------------------------------------------------------
# 瀏覽器基於安全限制「讀不到」基地台的實體位址（MAC / BSSID），
# 所以由本小工具用 Windows 內建指令讀出後，以
#     ?bssid=<基地台 MAC>&t=<記號>
# 自動帶入打卡頁。員工只要雙擊執行、登入打卡即可。
#
#   bssid = 公司 AP／路由器的實體位址 -> v5.5.0 起的主要認證依據
#   t     = hash31(MAC|密語|當天日期)，**換天自動失效**，所以沒辦法靠手打網址偽造
#
# v5.5.2 兩項重要修正：
#   ① 以前只會抓「WiFi 基地台的 BSSID」，只接網路線的桌上型電腦永遠讀不到 ->
#      新增「路由器閘道 MAC」備援（讀預設閘道 192.168.x.x 的實體位址），有線也能認證
#   ② 以前讀不到時視窗一閃就關，不知道為什麼 -> 現在會印出完整診斷
#      （含「附近所有可見基地台的 BSSID」，要新增 AP 時直接抄這裡的）
#
# 用法：TY-clockin-mac.ps1 必須與 TY-clockin-mac.bat 放在同一個資料夾，
#       請執行 .bat（不要直接對 .ps1 按右鍵）。
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'SilentlyContinue'
$page = 'https://tycompnies.github.io/attendance/'
$secret = 'TY-Attendance-MAC-v5.5'

function Write-Line($t, $c) { if ($c) { Write-Host $t -ForegroundColor $c } else { Write-Host $t } }

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
function Get-DayStamp { return (Get-Date).ToString('yyyyMMdd') }
# 記號：hash31 取模後轉 16 進位（與網頁 hash31()/macToolToken() 完全一致）
function Get-Token($s) {
  $h = [bigint]0
  foreach ($c in $s.ToCharArray()) { $h = ($h * 31 + [int][char]$c) % 1000000007 }
  return ([Convert]::ToString([int64]$h, 16)).ToLower()
}

# ========== 1. 目前連上的 WiFi 基地台 BSSID（netsh） ==========
$lines = & netsh wlan show interfaces 2>$null

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
  # ⚠️ netsh 裡同時有「實體位址」（電腦自己的網卡）與「AP BSSID」（基地台），
  #    只認 BSSID 那一列，避免把電腦自己的網卡 MAC 當成基地台
  $bssidLine = $b | Where-Object { $_ -match 'BSSID' } | Select-Object -First 1
  if (-not $bssidLine) { continue }
  if ($bssidLine -notmatch ':\s*(.+?)\s*$') { continue }
  $m = Get-HexMAC $Matches[1]
  if (-not $m -or $m -eq '000000000000') { continue }
  $thisSsid = ''
  $s = $b | Where-Object { $_ -match 'SSID' -and $_ -notmatch 'BSSID' } | Select-Object -First 1
  if ($s -and $s -match ':\s*(.+?)\s*$') { $thisSsid = $Matches[1].Trim() }
  $joined = ($b -join ' ')
  # 「已連線」的判斷：中英文都認；另外只要有訊號強度（代表確實收得到這個 AP）也算連線，
  # 避免不同語系／編碼下狀態列抓不到時被誤判成沒連
  $isConn = ($joined -match 'connected|已連線|連線|連網') -or
            ($thisSsid -and $joined -match '訊號|信號|Signal')
  if ($isConn) {
    if (-not $connectedMac) { $connectedMac = $m; $ssid = $thisSsid }
  } elseif (-not $idleMac) {
    $idleMac = $m
    if (-not $ssid) { $ssid = $thisSsid }
  }
}
$wifiMacRaw = if ($connectedMac) { $connectedMac } else { $idleMac }

# ========== 2. 路由器閘道 MAC（備援：沒 WiFi／只接網路線的桌上型電腦） ==========
$gwIp = ''
$gwMacRaw = ''
try {
  $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
  if ($route -and $route.NextHop -and $route.NextHop -ne '0.0.0.0') { $gwIp = $route.NextHop }
} catch {}
if (-not $gwIp) {
  foreach ($l in (& ipconfig 2>$null)) {
    if ($l -match '閘道|Gateway' -and $l -match ':\s*(\d+\.\d+\.\d+\.\d+)\s*$') { $gwIp = $Matches[1]; break }
  }
}
if ($gwIp) {
  & ping -n 1 -w 400 $gwIp > $null 2>&1   # 先 ping 一下，arp 快取才會有這筆
  foreach ($l in (& arp -a $gwIp 2>$null)) {
    if ($l -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') {
      $cand = Get-HexMAC $Matches[0]
      if ($cand -and $cand -ne '000000000000' -and $cand -ne 'FFFFFFFFFFFF') { $gwMacRaw = $cand; break }
    }
  }
}

# ========== 3. 附近所有可見的基地台（要新增 AP 時抄這裡的 BSSID） ==========
$apList = New-Object System.Collections.ArrayList
$curSsid = ''
foreach ($l in (& netsh wlan show networks mode=bssid 2>$null)) {
  if ($l -match '^\s*SSID\s*\d*\s*:\s*(.+?)\s*$') { $curSsid = $Matches[1] }
  elseif ($l -match 'BSSID\s*\d*\s*:\s*([0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2})') {
    $bm = Get-HexMAC $Matches[1]
    if ($bm -and $bm -ne '000000000000') {
      [void]$apList.Add([PSCustomObject]@{ SSID = $(if ($curSsid) { $curSsid } else { '(未知)' }); BSSID = (Format-MAC $bm) })
    }
  }
}

# ========== 4. 顯示診斷 ==========
Write-Line '================================================' DarkCyan
Write-Line ' 專業出勤系統 打卡小工具 v5.5.2' Cyan
Write-Line '================================================' DarkCyan
Write-Line ('WiFi 名稱          : ' + $(if ($ssid) { $ssid } else { '(沒連 WiFi)' }))
Write-Line ('基地台 BSSID       : ' + $(if ($wifiMacRaw) { Format-MAC $wifiMacRaw } else { '(讀不到)' }))
Write-Line ('路由器閘道 MAC     : ' + $(if ($gwMacRaw) { (Format-MAC $gwMacRaw) + '   （閘道 ' + $gwIp + '）' } else { '(讀不到)' }))

if ($apList.Count -gt 0) {
  Write-Line '' ''
  Write-Line '[附近可見的基地台] — 要新增／核對公司 AP 時，抄這裡的 BSSID：' Yellow
  foreach ($a in $apList) { Write-Line ('   ' + $a.SSID.PadRight(24) + $a.BSSID) }
}

# ========== 5. 決定要帶入網頁的 MAC（優先用 WiFi 基地台，其次用路由器閘道） ==========
$useRaw = ''
$src = ''
if ($wifiMacRaw) { $useRaw = $wifiMacRaw; $src = 'WiFi 基地台 BSSID' }
elseif ($gwMacRaw) { $useRaw = $gwMacRaw; $src = '路由器閘道 MAC（這台電腦沒連 WiFi，改用有線閘道）' }

Write-Line '' ''
if (-not $useRaw) {
  Write-Line '❌ 讀不到任何基地台／路由器的實體位址，打卡會被擋下。' Red
  Write-Line '' ''
  Write-Line '請依序確認：' Yellow
  Write-Line '  1) 這台電腦有連上網路（WiFi 或網路線皆可）' Yellow
  Write-Line '  2) 連的是「公司」的網路，不是手機熱點或別的地方' Yellow
  Write-Line '  3) 用系統管理員身分執行一次（右鍵 → 以系統管理員身分執行）' Yellow
  Write-Line '' ''
  Write-Line '仍會為您打開打卡頁 — 手機請改用打卡頁上的「裝置代碼」給管理員核准。' Yellow
  Start-Sleep -Seconds 3
  Start-Process $page
  exit
}

$mac = Format-MAC $useRaw
Write-Line ('帶入網頁的 MAC     : ' + $mac + '   ← 來源：' + $src) Green

$t = Get-Token ($mac + '|' + $secret + '|' + (Get-DayStamp))
$url = $page + '?bssid=' + [uri]::EscapeDataString($mac) + '&t=' + $t

Write-Line '' ''
Write-Line ('開啟打卡頁： ' + $url) Cyan
Write-Line '（若打卡頁仍顯示「不在公司清單內」，請把上面那組 MAC 抄給管理員加入清單）' DarkGray
Start-Process $url

Write-Line '' ''
Write-Line '完成！若視窗沒反應請檢查是否已連上公司網路。' DarkGray
