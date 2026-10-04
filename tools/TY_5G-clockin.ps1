# TY_5G clock-in launcher (v5.0.0)
# 瀏覽器讀不到 WiFi 名稱（SSID），也讀不到 MAC 位址，所以由本小工具用 Windows 指令讀出後
# 以 ?ssid=<名稱>&mac=<路由器/AP MAC>&dmac=<本機網卡 MAC>&t=<記號> 帶入打卡頁。
#   mac  = 目前連上的 AP（公司路由器）BSSID  -> 主要認證依據
#   dmac = 本機無線網卡 MAC                  -> 選配（Windows 預設會隨機化 MAC，建議關閉隨機化再啟用）
#   t    = hash(內容 + 當天日期)，換天自動失效，避免人手在網址列亂打
$ErrorActionPreference = 'SilentlyContinue'
$page = 'https://tycompnies.github.io/attendance/'

# 統一轉成「大寫純十六進位」（與網頁 normalizeMAC() 對齊）
function Get-HexMAC($v) {
  if (-not $v) { return '' }
  return (($v.ToString()) -replace '[^0-9A-Fa-f]', '').ToUpper()
}

function Get-DayStamp {
  return (Get-Date).ToString('yyyyMMdd')
}

# 記號：hash31 取模後轉 16 進位（與網頁 ssidToken()/toolToken() 完全一致）
function Get-Token($s) {
  $h = [bigint]0
  foreach ($c in $s.ToCharArray()) {
    $h = ($h * 31 + [int][char]$c) % 1000000007
  }
  return ([Convert]::ToString([int64]$h, 16)).ToLower()
}

function Open-Page($url) {
  Write-Host ''
  Write-Host ('開啟： ' + $url) -ForegroundColor Cyan
  Start-Process $url
}

# ---------- 1. 讀取目前連上的 WiFi ----------
$lines = netsh wlan show interfaces

$ssid = ''
$ssidLine = $lines | Where-Object { $_ -match 'SSID' -and $_ -notmatch 'BSSID' } | Select-Object -First 1
if ($ssidLine -and $ssidLine -match ':\s*(.+?)\s*$') { $ssid = $Matches[1].Trim() }

# 路由器／AP 的 MAC = BSSID（v5.0.0 主要認證依據）
$mac = ''
$bssidLine = $lines | Where-Object { $_ -match 'BSSID' } | Select-Object -First 1
if ($bssidLine -and $bssidLine -match ':\s*(.+?)\s*$') { $mac = Get-HexMAC $Matches[1] }
if (-not $mac) {
  # 中文版 Windows 欄位名稱可能不同，退而求其次：抓整份輸出裡第一個像 MAC 的字串
  foreach ($l in $lines) {
    if ($l -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') {
      $mac = Get-HexMAC $Matches[0]
      if ($mac -and $mac -ne '000000000000') { break }
    }
  }
}
if ($mac -eq '000000000000') { $mac = '' }

# ---------- 2. 讀取本機網卡 MAC（裝置 MAC，選配）----------
$dmac = ''
try {
  $up = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.MacAddress }
  if ($up) {
    # 排除虛擬網卡
    $real = $up | Where-Object { $_.InterfaceDescription -notmatch 'Virtual|VMware|VirtualBox|Hyper-V|TAP-|Bluetooth|Loopback' -and $_.MacAddress -notmatch '^00-00-00' }
    if (-not $real) { $real = $up }
    # 優先無線網卡
    $wifi = $real | Where-Object { $_.MediaType -eq 'Native 802.11' -or $_.PhysicalMediaType -eq 'Native 802.11' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11' } | Select-Object -First 1
    if (-not $wifi) { $wifi = $real | Select-Object -First 1 }
    if ($wifi) { $dmac = Get-HexMAC $wifi.MacAddress }
  }
} catch {}
if (-not $dmac) {
  # 舊系統沒有 Get-NetAdapter 時用 getmac 備援
  $gm = & getmac /fo csv /nh 2>$null
  foreach ($l in $gm) {
    if ($l -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') {
      $cand = Get-HexMAC $Matches[0]
      if ($cand -and $cand -ne '000000000000' -and $cand -notmatch '^0000') { $dmac = $cand; break }
    }
  }
}

# ---------- 3. 顯示偵測結果 ----------
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host ' 專業出勤系統 打卡小工具 v5.0.0' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host ('WiFi 名稱(SSID) : ' + $(if ($ssid) { $ssid } else { '(偵測不到)' }))
Write-Host ('路由器 MAC(BSSID): ' + $(if ($mac) { (($mac -replace '(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})', '$1:$2:$3:$4:$5:$6')) } else { '(偵測不到)' }))
Write-Host ('本機網卡 MAC     : ' + $(if ($dmac) { (($dmac -replace '(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})', '$1:$2:$3:$4:$5:$6')) } else { '(偵測不到)' }))
if (-not $ssid -and -not $mac) {
  Write-Host ''
  Write-Host '偵測不到 WiFi：請確認已連上公司 WiFi（TY_5G）再執行本工具。' -ForegroundColor Yellow
  Start-Sleep -Seconds 3
  Open-Page $page
  exit
}

# ---------- 4. 產生記號並開啟打卡頁 ----------
$day = Get-DayStamp
$payload = $mac + '|' + $dmac + '|' + $ssid + '|' + $day
$t = Get-Token $payload

$enc = [uri]::EscapeDataString($ssid)
$url = $page + '?ssid=' + $enc + '&mac=' + $mac + '&dmac=' + $dmac + '&t=' + $t
Open-Page $url
