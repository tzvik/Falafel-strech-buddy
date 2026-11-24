# Tray icon: runs the reminder timer and holds the settings menu. Started at login by install.ps1.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$dir   = Split-Path $MyInvocation.MyCommand.Path
$state = Join-Path $dir 'state.json'
$I     = Get-Content (Join-Path $dir 'i18n.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# one tray per user session (the keep-alive task also starts us; if we're already running it just exits)
$mutex = New-Object System.Threading.Mutex($false, 'Local\NoodleReminderTray')
if (-not $mutex.WaitOne(0)) { exit }

# never die silently: errors go to tray.log and the tray keeps running
$log = Join-Path $dir 'tray.log'
function Write-Log($msg) { try { Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) } catch {} }
[System.Windows.Forms.Application]::SetUnhandledExceptionMode('CatchException')
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) Write-Log "ERROR: $($e.Exception.Message)" })
Write-Log 'tray started'

function Get-State { try { Get-Content $state -Raw -ErrorAction Stop | ConvertFrom-Json } catch { [pscustomobject]@{} } }
function Set-State($changes) {    # same merge-write as the popup, so neither clobbers the other
  $cur = @{}; (Get-State).psobject.Properties | ForEach-Object { $cur[$_.Name] = $_.Value }
  foreach ($k in $changes.Keys) { $cur[$k] = $changes[$k] }
  $cur | ConvertTo-Json | Set-Content $state -Encoding utf8
}
function Get-L { $s = Get-State; $code = if ($s.lang -and $I.($s.lang)) { $s.lang } else { 'he' }; $I.$code }   # default Hebrew
# Default ~30 min: move every 30-60 min of sitting, drink a glass every 60-90 min.
# Popups alternate: water when an hour has passed since the last one, otherwise stretch / move (rigatoni.ps1).
function Get-Every { $e = [int](Get-State).every; if ($e -gt 0) { $e } else { 30 } }   # minutes
# Gentle randomness: each gap is the chosen interval +/- 15%, so it doesn't feel like a metronome.
function Get-NextTime { (Get-Date).AddMinutes((Get-Every) * (0.85 + (Get-Random -Maximum 1000) / 3333)) }
function Get-PausedUntil { $p = (Get-State).pausedUntil; if ($p) { [datetime]$p } else { [datetime]::MinValue } }

# tray icon: a tiny shawarma (laffa wrap, fillings on top, paper wrapper), drawn at runtime - no image file needed
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
$C = { param($r, $gg, $b) [System.Drawing.Color]::FromArgb($r, $gg, $b) }
$ink = New-Object System.Drawing.Pen ((& $C 43 36 32), 1.6)
$wrap = New-Object System.Drawing.Drawing2D.GraphicsPath; $wrap.AddArc(7, 7, 8, 8, 180, 90); $wrap.AddArc(17, 7, 8, 8, 270, 90)
$wrap.AddLine(25, 11, 25, 30); $wrap.AddLine(25, 30, 7, 30); $wrap.CloseFigure()
$g.FillPath((New-Object System.Drawing.SolidBrush (& $C 236 208 150)), $wrap); $g.DrawPath($ink, $wrap)          # laffa
$g.FillEllipse((New-Object System.Drawing.SolidBrush (& $C 139 74 34)), 7, 2, 18, 9); $g.DrawEllipse($ink, 7, 2, 18, 9)   # meat
$g.FillEllipse((New-Object System.Drawing.SolidBrush (& $C 95 160 58)), 8, 3, 5, 4)                                  # parsley
$g.FillEllipse((New-Object System.Drawing.SolidBrush (& $C 95 160 58)), 19, 2, 5, 4)
$g.FillEllipse((New-Object System.Drawing.SolidBrush (& $C 224 69 58)), 13, 1, 5, 4)                                 # tomato
$paper = [System.Drawing.Point[]]@((New-Object System.Drawing.Point 7,21),(New-Object System.Drawing.Point 10,19),(New-Object System.Drawing.Point 13,21),(New-Object System.Drawing.Point 16,19),(New-Object System.Drawing.Point 19,21),(New-Object System.Drawing.Point 22,19),(New-Object System.Drawing.Point 25,21),(New-Object System.Drawing.Point 25,30),(New-Object System.Drawing.Point 7,30))
$g.FillPolygon([System.Drawing.Brushes]::White, $paper); $g.DrawPolygon($ink, $paper)                               # paper wrapper
$g.FillRectangle((New-Object System.Drawing.SolidBrush (& $C 211 58 44)), 8, 24, 17, 2)                              # red stripe
$g.FillEllipse([System.Drawing.Brushes]::Black, 11, 12, 3, 4); $g.FillEllipse([System.Drawing.Brushes]::Black, 18, 12, 3, 4)   # eyes
$g.DrawArc((New-Object System.Drawing.Pen ((& $C 43 36 32), 1.3)), 13, 14, 6, 4, 10, 160)                           # smile

# your own icon: drop a tray-icon.png in this folder (kept out of git) and it replaces the shawarma
$custom = Join-Path $dir 'tray-icon.png'
if (Test-Path $custom) {
  try { $src = [System.Drawing.Image]::FromFile($custom)
        $k = [math]::Min(32 / $src.Width, 32 / $src.Height); $w = [int]($src.Width * $k); $h = [int]($src.Height * $k)
        $g.Clear([System.Drawing.Color]::Transparent); $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($src, [int]((32 - $w) / 2), [int]((32 - $h) / 2), $w, $h); $src.Dispose() }
  catch { Write-Log "tray-icon.png unreadable: $($_.Exception.Message)" } }

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$ni.Visible = $true

$script:next = Get-NextTime
function Show-Reminder { Start-Process wscript.exe -ArgumentList "`"$dir\launch.vbs`""; $script:next = Get-NextTime }
# Install a character pack from a .zip (a folder containing pack.json). Entries are checked so nothing lands outside packs\.
function Add-Pack {
  $L = Get-L
  $dlg = New-Object System.Windows.Forms.OpenFileDialog -Property @{ Filter = 'Character pack (*.zip)|*.zip'; Title = $L.ui.addPack }
  if ($dlg.ShowDialog() -ne 'OK') { return }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $name = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName) -replace '[^A-Za-z0-9_-]', '_'
  $dest = [IO.Path]::GetFullPath((Join-Path $dir "packs\$name"))
  try {
    $zip = [IO.Compression.ZipFile]::OpenRead($dlg.FileName)
    if (-not ($zip.Entries | ? { $_.Name -eq 'pack.json' })) { throw $L.ui.packBad }
    foreach ($en in $zip.Entries) {
      $out = [IO.Path]::GetFullPath((Join-Path $dest $en.FullName))
      if (-not $out.StartsWith($dest, 'OrdinalIgnoreCase')) { throw $L.ui.packBad }   # zip-slip guard
      if ($en.Name) { New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null; [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $out, $true) }
    }
    $zip.Dispose()
    $ni.ShowBalloonTip(4000, 'Stretch Buddy', $L.ui.packOk, 'Info'); Show-Gallery
  } catch { if ($zip) { $zip.Dispose() }; [System.Windows.Forms.MessageBox]::Show("$($L.ui.packBad)`n$($_.Exception.Message)") | Out-Null }
}
function Show-Setup { Start-Process wscript.exe -ArgumentList "`"$dir\launch.vbs`" rigatoni.ps1 -Setup" }
function Show-Gallery  { Start-Process wscript.exe -ArgumentList "`"$dir\launch.vbs`" rigatoni.ps1 -Gallery" }
function Update-Tip { $L = Get-L
  $ni.Text = if ((Get-PausedUntil) -gt (Get-Date)) { $L.ui.tipPaused }
             else { $L.ui.tipNext -f [math]::Max(0, [math]::Ceiling(($script:next - (Get-Date)).TotalMinutes)) } }

# menu is rebuilt every time it opens, so it always shows current settings + language
$menu = New-Object System.Windows.Forms.ContextMenuStrip
function Add-Item($parent, $text, $tag, $checked, $onClick) {
  $it = New-Object System.Windows.Forms.ToolStripMenuItem $text
  $it.Tag = $tag; $it.Checked = [bool]$checked
  if ($onClick) { $it.Add_Click($onClick) }
  if ($parent -is [System.Windows.Forms.ContextMenuStrip]) { [void]$parent.Items.Add($it) } else { [void]$parent.DropDownItems.Add($it) }
  $it
}
$menu.Add_Opening({
  $s = Get-State; $L = Get-L; $menu.Items.Clear()
  $menu.RightToLeft = if ($L.rtl) { 'Yes' } else { 'No' }
  Add-Item $menu $L.ui.remindNow $null $false { Show-Reminder; Update-Tip } | Out-Null
  Add-Item $menu $L.ui.setupAgain $null $false { Show-Setup } | Out-Null
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

  # character: the gallery picks a specific one; here are the random options (default = Hanukkah kit)
  $ch = Add-Item $menu $L.ui.character $null $false $null
  $who = if ($s.who) { "$($s.who)" } else { 'kit:streetfood' }   # (a pack marked "first" is the popup's default)
  Add-Item $ch $L.ui.chooseChar $null $false { Show-Gallery } | Out-Null
  [void]$ch.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  Add-Item $ch $L.ui.random 'random' ($who -eq 'random') { param($o) Set-State @{ who = 'random' } } | Out-Null
  $kits = [ordered]@{}
  foreach ($k in $L.kits.psobject.Properties.Name) { $kits[$k] = $L.kits.$k }
  foreach ($pj in Get-ChildItem (Join-Path $dir 'packs') -Filter pack.json -Recurse -ErrorAction SilentlyContinue) {   # character packs
    try { $pk = Get-Content $pj.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
          $kits["$($pk.kit)"] = if ($pk.names.($s.lang)) { $pk.names.($s.lang) } elseif ($pk.names.en) { $pk.names.en } else { $pk.kit } } catch {}
  }
  foreach ($kit in $kits.Keys) {
    Add-Item $ch ($L.ui.randomKit -f $kits[$kit]) "kit:$kit" ($who -eq "kit:$kit") { param($o) Set-State @{ who = $o.Tag } } | Out-Null
  }
  if ($who -match '^\d+$' -and [int]$who -lt $L.cast.Count) { Add-Item $ch $L.cast[[int]$who] $who $true { Show-Gallery } | Out-Null }
  [void]$ch.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  Add-Item $ch $L.ui.addPack $null $false { Add-Pack } | Out-Null

  $lg = Add-Item $menu $L.ui.language $null $false $null
  foreach ($code in $I.psobject.Properties.Name) {
    Add-Item $lg $I.$code.name $code ($code -eq $(if ($s.lang) { $s.lang } else { 'he' })) { param($o) Set-State @{ lang = $o.Tag }; Update-Tip } | Out-Null
  }

  # reminder types: Often / Sometimes / Off for each kind (defaults match rigatoni.ps1)
  $ty = Add-Item $menu $L.ui.types $null $false $null
  $defaults = @{ stretch = 2; water = 2; move = 1; eyes = 1 }
  foreach ($cat in 'stretch', 'water', 'move', 'eyes') {
    $cur = if ($s.types -and $null -ne $s.types.$cat) { [int]$s.types.$cat } else { $defaults[$cat] }
    $sub = Add-Item $ty $L.ui.cats.$cat $null $false $null
    foreach ($lv in @(2, 'often'), @(1, 'sometimes'), @(0, 'off')) {
      Add-Item $sub $L.ui.($lv[1]) "${cat}:$($lv[0])" ($cur -eq $lv[0]) { param($o)
        $c, $v = $o.Tag -split ':'
        $t = @{}; $old = (Get-State).types; if ($old) { $old.psobject.Properties | % { $t[$_.Name] = $_.Value } }
        $t[$c] = [int]$v; Set-State @{ types = $t } } | Out-Null
    }
  }
  $ev = Add-Item $menu $L.ui.every $null $false $null
  $opts = 20, 30, 45, 60, 90   # labels in i18n ui.freq, same order
  for ($i = 0; $i -lt $opts.Count; $i++) {
    Add-Item $ev $L.ui.freq[$i] $opts[$i] ($opts[$i] -eq (Get-Every)) { param($o) Set-State @{ every = $o.Tag }
      $script:next = Get-NextTime; Update-Tip } | Out-Null
  }

  if ((Get-PausedUntil) -gt (Get-Date)) {
    Add-Item $menu $L.ui.resume $null $false { Set-State @{ pausedUntil = $null }; $script:next = Get-NextTime; Update-Tip } | Out-Null
  } else {
    Add-Item $menu $L.ui.pause $null $false { Set-State @{ pausedUntil = (Get-Date).AddHours(1).ToString('o') }; Update-Tip } | Out-Null
  }
  Add-Item $menu $L.ui.mute $null ([bool]$s.mute) { Set-State @{ mute = -not [bool](Get-State).mute } } | Out-Null
  Add-Item $menu $L.ui.resetPos $null $false { Set-State @{ right = $null; bottom = $null } } | Out-Null
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  Add-Item $menu $L.ui.exit $null $false { $ni.Visible = $false; [System.Windows.Forms.Application]::Exit() } | Out-Null
})
$menu.Items.Add('...') | Out-Null    # placeholder so the first Opening fires
$ni.ContextMenuStrip = $menu
$ni.Add_MouseDoubleClick({ Show-Reminder; Update-Tip })

# tick every 30s: fire when due (unless paused); pause expiring restarts the countdown
$timer = New-Object System.Windows.Forms.Timer -Property @{ Interval = 30000 }
$timer.Add_Tick({
  try {
    $now = Get-Date
    if ((Get-PausedUntil) -gt $now) { $script:next = (Get-PausedUntil).AddMinutes((Get-Every) * 0.5) }
    elseif ($now -ge $script:next) { Write-Log 'reminder shown'; Show-Reminder }
    Update-Tip
  } catch { Write-Log "ERROR in timer: $($_.Exception.Message)" }
})
$timer.Start(); Update-Tip

# first run: open the welcome wizard once (marked right away, so restarts never open it twice)
if (-not (Get-State).setupDone) { Set-State @{ setupDone = $true }; Write-Log 'first run: setup wizard'; Show-Setup }

[System.Windows.Forms.Application]::Run()
$ni.Dispose()
