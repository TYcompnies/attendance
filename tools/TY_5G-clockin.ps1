# TY_5G clock-in launcher (v5.3.0)
# Reads the WiFi name (SSID) currently connected via Windows netsh,
# then opens the attendance page with ?ssid=<name>&t=<token>.
#
# v5.3.0 changes:
#   - FIXED "cannot find SSID" on PCs with several wireless adapters: old builds took
#     the FIRST SSID line, which is empty on a disconnected adapter -> no SSID at all.
#     Now we skip empty SSIDs and use the first adapter that is really connected.
#   - Language independent: only matches the English keyword "SSID". Chinese Windows
#     returns netsh output in the local code page, so matching Chinese labels
#     (介面卡名稱 / 狀態) silently failed before.
#   - Shows a clear popup explaining WHY nothing was found (wired only / WiFi off /
#     wrong network) instead of failing silently.
#   - Since v5.3.0 the system can also release via the company WAN IP, so we always
#     open the page and tell the user what still works.

$ErrorActionPreference = 'SilentlyContinue'
$page = 'https://tycompnies.github.io/attendance/'

function Show-Info($msg) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($msg, 'TY_5G 打卡小工具') | Out-Null
  } catch {
    Write-Host $msg
  }
}

$raw = & netsh wlan show interfaces 2>$null

# Pick the first wireless adapter that actually has an SSID (= connected).
# NOTE: only the ASCII keyword "SSID" is matched on purpose, see header.
$ssid = ''
foreach ($line in $raw) {
  if ($line -match 'SSID' -and $line -notmatch 'BSSID') {
    if ($line -match ':\s*(.+)$') {
      $v = $Matches[1].Trim()
      if ($v -ne '') { $ssid = $v; break }
    }
  }
}

if (-not $raw) {
  Show-Info "偵測不到無線網路（這台電腦可能只有有線網路，或網路卡已停用）。`n`n現在仍會直接開啟打卡頁：只要這台電腦在公司網路上，系統會用「網路出口 IP」放行，您依然可以打卡。`n`n若仍無法打卡，請改連公司 WiFi「TY_5G」後再試一次。"
  Start-Process $page
  exit
}

if ($ssid -eq '') {
  Show-Info "WiFi 目前沒有連線，抓不到 WiFi 名稱。`n`n常見原因：`n1) 電腦只插網路線（請改連公司 WiFi TY_5G）`n2) WiFi 被關閉或飛航模式`n3) 公司 WiFi 故障`n`n現在仍會直接開啟打卡頁：只要這台電腦在公司網路上，系統會用「網路出口 IP」放行。"
  Start-Process $page
  exit
}

# day stamp yyyyMMdd -> the ?ssid=&t= link is valid for today only (anti hand-typing)
$day = (Get-Date).ToString('yyyyMMdd')
$s = $ssid + '|' + $day
$h = [bigint]0
foreach ($c in $s.ToCharArray()) {
  $h = ($h * 31 + [int][char]$c) % 1000000007
}
$token = [Convert]::ToString([int64]$h, 16).ToLower()

$enc = [uri]::EscapeDataString($ssid)
$url = $page + '?ssid=' + $enc + '&t=' + $token

if ($ssid -ne 'TY_5G') {
  Show-Info "目前連上的 WiFi 是「$ssid」，不是公司 WiFi「TY_5G」。`n`n打卡頁仍會開啟：若這台電腦剛好在公司網路內（出口 IP 符合），還是可以打卡；否則請改連公司 WiFi「TY_5G」後再雙擊本工具。"
}

Start-Process $url
