# TY_5G clock-in launcher (v4.0.20)
# Reads the WiFi name (SSID) currently connected via Windows netsh,
# then opens the attendance page with ?ssid=<name>&t=<token> so the system
# can verify the employee is really on TY_5G. Web browsers cannot read SSID
# by themselves, so this helper is required for strict name verification.
$ErrorActionPreference = 'SilentlyContinue'
$page = 'https://tycompnies.github.io/attendance/'

$lines = netsh wlan show interfaces
$line = $lines | Where-Object { $_ -match 'SSID' -and $_ -notmatch 'BSSID' } | Select-Object -First 1

if (-not $line) {
  Start-Process $page
  exit
}

if ($line -match ':\s*(.+?)\s*$') {
  $ssid = $Matches[1].Trim()
} else {
  $ssid = ''
}

if (-not $ssid) {
  Start-Process $page
  exit
}

# day stamp yyyyMMdd
$day = (Get-Date).ToString('yyyyMMdd')
$s = $ssid + '|' + $day
$h = [bigint]0
foreach ($c in $s.ToCharArray()) {
  $h = ($h * 31 + [int][char]$c) % 1000000007
}
$token = [Convert]::ToString([int64]$h, 16).ToLower()

$enc = [uri]::EscapeDataString($ssid)
$url = $page + '?ssid=' + $enc + '&t=' + $token
Start-Process $url
