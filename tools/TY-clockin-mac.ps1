param([switch]$Test, [string]$ReportPath)
# ===========================================================================
#  TY Attendance - Windows clock-in tool   v1.3.0   (TY-clockin-mac.ps1)
# ===========================================================================
#  瀏覽器基於安全限制「讀不到」基地台的實體位址（MAC / BSSID），所以由本小工具
#  用 Windows 內建指令讀出後，以下列網址自動帶入打卡頁：
#      ?bssid=<基地台 MAC>&t=<記號>
#  員工只要雙擊 TY-clockin-mac.bat、登入打卡即可。
#
#    bssid = 公司 AP／路由器的實體位址 -> 主要認證依據
#    t     = hash31(MAC|密語|當天日期)，換天自動失效，無法靠手打網址偽造
#
#  v1.3.0 修正（「一直偵測不到」的元凶）：
#    ① .bat 檔原本含有中文註解 -> cmd.exe 讀檔時以系統編碼逐位元組解析，中文
#       全變亂碼並被當成指令執行（就是視窗裡那串「不是內部或外部命令」）。
#       現在 .bat 改成純 ASCII，中文訊息一律由本 .ps1 輸出。
#    ② .bat 原本是 LF 換行（Unix 格式）-> 改成 CRLF。
#    ③ 「已中斷連線」含有「連線」二字，舊版會誤判成已連線 -> 已排除。
#    ④ 新增 /test 模式（只顯示、不開瀏覽器）與完整診斷報告檔。
#
#  用法：雙擊 TY-clockin-mac.bat（不要直接對 .ps1 按右鍵）
#        命令列除錯：TY-clockin-mac.bat /test
#  報告：每次執行都會存一份 UTF-8 報告（預設在桌面），讀不到時會自動開啟。
# ===========================================================================
$ErrorActionPreference = 'SilentlyContinue'
$TOOL_VER = '1.3.0'
$page   = 'https://tycompnies.github.io/attendance/'
$secret = 'TY-Attendance-MAC-v5.5'

# 所有輸出（主控台 ＋ 報告檔）都走同一個出口，確保兩邊內容與編碼一致
$report = New-Object System.Collections.ArrayList
function Add-R($t) { [void]$script:report.Add([string]$t) }
function Write-Line($t, $c) {
  Add-R $t
  try { if ($c) { Write-Host $t -ForegroundColor $c } else { Write-Host $t } }
  catch { Write-Host $t }
}
function Write-OK($t)   { Write-Line $t Green }
function Write-Bad($t)  { Write-Line $t Red }
function Write-Note($t) { Write-Line $t DarkGray }

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
# ---------------------------------------------------------------------------
# Windows 各指令的輸出編碼並不統一（實測：netsh 吐 UTF-8、arp 吐系統代碼頁 950），
# 直接用 & 呼叫再由 PowerShell 解碼，一定會有一邊變亂碼。所以改成：
#   導向暫存檔 -> 讀原始位元組 -> 先當 UTF-8 解，若出現 U+FFFD（代表不是合法 UTF-8）
#   就改用系統 OEM 代碼頁解。這樣中英文標籤在任何機器上都是可讀的。
# ---------------------------------------------------------------------------
function Invoke-Capture($cmdline) {
  $out = @()
  $tmp = ''
  try { $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'ty_' + [Guid]::NewGuid().ToString('N') + '.txt') } catch {}
  if (-not $tmp) { return $out }
  try { & cmd.exe /c ($cmdline + ' > "' + $tmp + '" 2>&1') | Out-Null } catch {}
  $bytes = $null
  try { if (Test-Path -LiteralPath $tmp) { $bytes = [IO.File]::ReadAllBytes($tmp) } } catch {}
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  if (-not $bytes -or $bytes.Length -eq 0) { return $out }
  $txt = [Text.Encoding]::UTF8.GetString($bytes)
  if ($txt.IndexOf([char]0xFFFD) -ge 0) {
    $oem = 950
    try { $oem = [int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').OEMCP } catch {}
    try { $txt = [Text.Encoding]::GetEncoding($oem).GetString($bytes) } catch {}
  }
  if ($txt.Length -gt 0 -and [int]$txt[0] -eq 0xFEFF) { $txt = $txt.Substring(1) }
  return ($txt -split "`r?`n")
}

$lines = @(Invoke-Capture 'netsh wlan show interfaces')
# 保險：若暫存檔寫不進去或指令被攔，仍退回直接呼叫（BSSID／SSID／Rssi 都是 ASCII，解碼不影響判斷）
if ($lines.Count -eq 0) { $lines = @(& netsh wlan show interfaces 2>$null) }

$blocks = New-Object System.Collections.ArrayList
$cur = New-Object System.Collections.ArrayList
foreach ($l in $lines) {
  if ($l.Trim() -eq '') {
    if ($cur.Count -gt 0) { [void]$blocks.Add($cur.ToArray()); $cur.Clear() }
  } else { [void]$cur.Add($l) }
}
if ($cur.Count -gt 0) { [void]$blocks.Add($cur.ToArray()) }

$ssid = ''
$idleMac = ''
$adapterCount = 0
$adapterLog = New-Object System.Collections.ArrayList
$cand = New-Object System.Collections.ArrayList   # 每個有 BSSID 的介面各是一個候選
foreach ($b in $blocks) {
  # ⚠️ netsh 區塊裡同時有「實體位址」（= 這台電腦自己的網卡）與「AP BSSID」（= 基地台），
  #    只認 BSSID 那一列，否則會把電腦自己的網卡 MAC 誤當成基地台（v5.5.1 就是這樣出錯）
  $bssidLine = $b | Where-Object { $_ -match 'BSSID' } | Select-Object -First 1
  if (-not $bssidLine) { continue }
  if ($bssidLine -notmatch ':\s*(.+?)\s*$') { continue }
  $m = Get-HexMAC $Matches[1]
  if (-not $m -or $m -eq '000000000000') { continue }
  $adapterCount++
  $thisSsid = ''
  $s = $b | Where-Object { $_ -match 'SSID' -and $_ -notmatch 'BSSID' } | Select-Object -First 1
  if ($s -and $s -match ':\s*(.+?)\s*$') { $thisSsid = $Matches[1].Trim() }
  $joined = ($b -join ' ')

  # ⚠️ 絕對不要靠中文標籤判斷連線狀態！netsh 的中文在不同主控台編碼下會變亂碼
  #    （實測「狀態 : 已連線」整列變成「? : ???」），比對中文一定失敗。
  #    改用「結構性 + ASCII 錨點」判斷：
  #      · 已中斷連線：netsh 根本不會印 BSSID 那一列（上面已經 continue 掉了）
  #      · 已連線    ：一定會印 SSID，以及訊號（Rssi / Signal）或速率（Mbps）
  #      · 另外「已中斷連線」含「連線」二字，要先排除，否則會把斷線誤判成連線
  $isDisconn = ($joined -match '中斷|斷線|disconnected|未連線|未連接|not connected')
  $hasSignal = ($joined -match 'Rssi|Signal|訊號|信號')
  $hasRate   = ($joined -match '\d+(\.\d+)?\s*Mbps')
  $isConn    = (-not $isDisconn)
  $strong    = ($thisSsid -ne '') -or $hasSignal -or $hasRate

  [void]$adapterLog.Add('adapter #' + $adapterCount + '  bssid=' + (Format-MAC $m) +
                        "  ssid='" + $thisSsid + "'  conn=" + $isConn + '  signal=' + $hasSignal + '  rate=' + $hasRate)
  if ($isConn) {
    [void]$cand.Add([PSCustomObject]@{ MAC = $m; SSID = $thisSsid; Strong = $strong })
  } elseif (-not $idleMac) {
    $idleMac = $m
    if (-not $ssid) { $ssid = $thisSsid }
  }
}
# 多張無線網卡時：優先挑「有 SSID 或有訊號」的那個，避免挑錯介面
$pick = $cand | Where-Object { $_.Strong } | Select-Object -First 1
if (-not $pick) { $pick = $cand | Select-Object -First 1 }
$wifiMacRaw = ''
if ($pick) { $wifiMacRaw = $pick.MAC; $ssid = $pick.SSID }

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
  & ping -n 1 -w 500 $gwIp > $null 2>&1   # 先 ping 一下，arp 快取才會有這筆
  $arpLines = @(Invoke-Capture ('arp -a ' + $gwIp))
  if ($arpLines.Count -eq 0) { $arpLines = @(& arp -a $gwIp 2>$null) }
  foreach ($l in $arpLines) {
    if ($l -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') {
      $cand = Get-HexMAC $Matches[0]
      if ($cand -and $cand -ne '000000000000' -and $cand -ne 'FFFFFFFFFFFF') { $gwMacRaw = $cand; break }
    }
  }
}

# ========== 3. 附近所有可見的基地台（要新增 AP 時抄這裡的 BSSID） ==========
$apList = New-Object System.Collections.ArrayList
$curSsid = ''
# 這裡刻意「直接呼叫」不要導向檔案：netsh 掃描在輸出被重導時回傳的 AP 會少很多
# （實測 9 台 -> 1 台）。本清單只取 ASCII 的 SSID／BSSID 欄位，不受中文標籤編碼影響。
$netLines = @(& netsh wlan show networks mode=bssid 2>$null)
if ($netLines.Count -eq 0) { $netLines = @(Invoke-Capture 'netsh wlan show networks mode=bssid') }
foreach ($l in $netLines) {
  if ($l -match '^\s*SSID\s*\d*\s*:\s*(.+?)\s*$') { $curSsid = $Matches[1] }
  elseif ($l -match 'BSSID\s*\d*\s*:\s*([0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2})') {
    $bm = Get-HexMAC $Matches[1]
    if ($bm -and $bm -ne '000000000000' -and (Format-MAC $bm)) {
      [void]$apList.Add([PSCustomObject]@{ SSID = $(if ($curSsid) { $curSsid } else { '(hidden/unknown)' }); BSSID = (Format-MAC $bm) })
    }
  }
}

# ========== 4. 決定要帶入網頁的 MAC ==========
$useRaw = ''
$src = ''
$srcZh = ''
if ($wifiMacRaw) { $useRaw = $wifiMacRaw; $src = 'Wi-Fi AP BSSID';                 $srcZh = 'WiFi 基地台 BSSID' }
elseif ($gwMacRaw) { $useRaw = $gwMacRaw; $src = 'Router gateway MAC (wired LAN)'; $srcZh = '路由器閘道 MAC（這台沒連 WiFi，改用有線閘道）' }

# ========== 5. 顯示（關鍵資料一律用純 ASCII 標籤，任何字型／編碼都讀得到） ==========
Write-Line '================================================' DarkCyan
Write-Line ('  TY Attendance - Clock-in Tool   v' + $TOOL_VER) Cyan
Write-Line '================================================' DarkCyan
Write-Line ('[NET] Computer        : ' + $env:COMPUTERNAME + '   (' + $env:USERNAME + ')')
Write-Line ('[NET] Time            : ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
Write-Line ('[NET] WiFi SSID       : ' + $(if ($ssid) { $ssid } else { '(not on Wi-Fi)' }))
if ($wifiMacRaw) { Write-Line ('[NET] AP BSSID        : ' + (Format-MAC $wifiMacRaw)) Cyan }
else             { Write-Line '[NET] AP BSSID        : (not found)' DarkGray }
if ($gwMacRaw) { Write-Line ('[NET] Router GW MAC   : ' + (Format-MAC $gwMacRaw) + '   (gw ' + $gwIp + ')') }
else           { Write-Line '[NET] Router GW MAC   : (not found)' DarkGray }
Write-Line ('[NET] Visible APs     : ' + $apList.Count)
Write-Line '------------------------------------------------' DarkGray

if ($apList.Count -gt 0) {
  Write-Line '  Visible SSID                 BSSID' DarkGray
  foreach ($a in $apList) { Write-Line ('    ' + $a.SSID.PadRight(26) + $a.BSSID) DarkGray }
  Write-Line '------------------------------------------------' DarkGray
}

if (-not $useRaw) {
  Write-Bad '  [X] NO MAC FOUND - clock-in will be blocked.'
  Write-Line ''
  Write-Line '[ 讀不到任何基地台／路由器的實體位址 ]' Yellow
  Write-Line '請依序確認：' Yellow
  Write-Line '  1) 這台電腦有連上網路（WiFi 或網路線都可以）' Yellow
  Write-Line '  2) 連的是「公司」的網路，不是手機熱點或別的地方' Yellow
  Write-Line '  3) 用系統管理員身分再執行一次（右鍵 -> 以系統管理員身分執行）' Yellow
  Write-Line '  4) 防毒軟體沒有攔阻 netsh / arp / ping 指令' Yellow
  Write-Line ''
  Write-Line '  [i] 完整診斷報告已開啟，請把報告內容拍給管理員。' DarkGray
} else {
  $mac = Format-MAC $useRaw
  Write-Line ('[USE] MAC to clock-in : ' + $mac) Green
  Write-Line ('[USE] Source          : ' + $src) Green
  Write-Line ('                            ' + $srcZh) DarkGray

  $t = Get-Token ($mac + '|' + $secret + '|' + (Get-DayStamp))
  $url = $page + '?bssid=' + [uri]::EscapeDataString($mac) + '&t=' + $t
  Write-Line '================================================' DarkCyan
  Write-Line ('[URL] ' + $url) Cyan
  Write-Line '================================================' DarkCyan
  Write-Line ''
  Write-Line '  [i] 若打卡頁仍顯示「不在公司清單內」，請把上面 [USE] 那組 MAC 抄給管理員加入清單。' DarkGray
  Write-Line '  [i] 記號每天自動失效，所以請用本工具帶入，不要自己手打網址。' DarkGray
}

# ========== 6. 報告檔附錄（原始診斷資料） ==========
Add-R ''
Add-R '================ DIAGNOSTIC DETAIL ================'
Add-R ('tool        : v' + $TOOL_VER)
Add-R ('scripthost  : PowerShell ' + $PSVersionTable.PSVersion.ToString() + '  (64-bit=' + [Environment]::Is64BitProcess + ')')
Add-R ('config      : test=' + [bool]$Test + '  fromBat=' + ($env:TY_FROM_BAT -eq '1') + '  consoleCP=' + [Console]::OutputEncoding.CodePage)
Add-R ('net adapters with BSSID : ' + $adapterCount)
Add-R ('gateway ip  : ' + $(if ($gwIp) { $gwIp } else { '(none)' }))
Add-R ('RESULT      : ' + $(if ($useRaw) { 'mac=' + (Format-MAC $useRaw) + '  source=' + $src } else { 'NO MAC FOUND' }))
Add-R ''
Add-R '--- adapter analysis ---'
foreach ($a in $adapterLog) { Add-R $a }
Add-R ''
Add-R '--- raw: netsh wlan show interfaces ---'
foreach ($l in $lines) { Add-R $l }
Add-R ''
Add-R '--- raw: arp -a <gateway> ---'
foreach ($l in $arpLines) { Add-R $l }

# ========== 7. 寫報告檔（UTF-8 with BOM -> 記事本一定讀得正確） ==========
$rp = $ReportPath
if (-not $rp) { $rp = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TY-clockin-report.txt' }
try {
  $enc = New-Object System.Text.UTF8Encoding($true)
  [IO.File]::WriteAllText($rp, (($report -join "`r`n") + "`r`n"), $enc)
} catch {
  try {
    $rp = Join-Path ([IO.Path]::GetTempPath()) 'TY-clockin-report.txt'
    $enc = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($rp, (($report -join "`r`n") + "`r`n"), $enc)
  } catch { $rp = '' }
}
if ($rp -and -not $Test) { Write-Note ('  [i] Report: ' + $rp) }

# ========== 8. 開瀏覽器 / 收尾 ==========
if (-not $useRaw) {
  if ($rp -and -not $Test) { try { Start-Process notepad.exe $rp } catch {} }
  if (-not $Test) { Start-Sleep -Seconds 2; Start-Process $page }
  if ($Test) { Write-Line '' ; Write-Line '  [TEST MODE] browser not opened.' Magenta }
  if ($env:TY_FROM_BAT -ne '1') { Write-Line ''; Write-Line 'Press Enter to close...' DarkGray; $null = Read-Host }
  exit 1
}

if ($Test) {
  Write-Line ''
  Write-Line '  [TEST MODE] browser not opened.' Magenta
} else {
  Write-Line ''
  Write-Line '  Opening clock-in page...' Green
  Start-Process $url
}
if ($env:TY_FROM_BAT -ne '1') { Write-Line ''; Write-Line 'Press Enter to close...' DarkGray; $null = Read-Host }
