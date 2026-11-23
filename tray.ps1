# Tray icon: runs the reminder timer and holds the settings menu. Started at login by install.ps1.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$dir   = Split-Path $MyInvocation.MyCommand.Path
$state = Join-Path $dir 'state.json'
$I     = Get-Content (Join-Path $dir 'i18n.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# one tray per user session
$mutex = New-Object System.Threading.Mutex($false, 'Local\NoodleReminderTray')
if (-not $mutex.WaitOne(0)) { exit }

function Get-State { try { Get-Content $state -Raw -ErrorAction Stop | ConvertFrom-Json } catch { [pscustomobject]@{} } }
function Set-State($changes) {    # same merge-write as the popup, so neither clobbers the other
  $cur = @{}; (Get-State).psobject.Properties | ForEach-Object { $cur[$_.Name] = $_.Value }
  foreach ($k in $changes.Keys) { $cur[$k] = $changes[$k] }
  $cur | ConvertTo-Json | Set-Content $state -Encoding utf8
}
function Get-L { $s = Get-State; $code = if ($s.lang -and $I.($s.lang)) { $s.lang } else { 'en' }; $I.$code }
function Get-Every { $e = [int](Get-State).every; if ($e -gt 0) { $e } else { 120 } }   # minutes; default ~2h
# Random timing: each gap is the chosen interval +/- 25%, so reminders don't feel like a metronome.
function Get-NextTime { (Get-Date).AddMinutes((Get-Every) * (0.75 + (Get-Random -Maximum 1000) / 2000)) }
function Get-PausedUntil { $p = (Get-State).pausedUntil; if ($p) { [datetime]$p } else { [datetime]::MinValue } }

# tray icon: a tiny rigatoni drawn at runtime (no image file needed)
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
$g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(242,184,75))), 7, 2, 18, 28)
$g.DrawRectangle((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(184,118,28)), 2), 7, 2, 18, 28)
foreach ($x in 11, 16, 21) { $g.DrawLine((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(196,127,34)), 1.5), $x, 4, $x, 28) }
$g.FillEllipse([System.Drawing.Brushes]::Black, 11, 13, 4, 5); $g.FillEllipse([System.Drawing.Brushes]::Black, 18, 13, 4, 5)
$g.DrawArc((New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 1.5), 12, 17, 8, 5, 0, 180)

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$ni.Visible = $true

$script:next = Get-NextTime
function Show-Reminder { Start-Process wscript.exe -ArgumentList "`"$dir\launch.vbs`""; $script:next = Get-NextTime }
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
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

  # character: the gallery picks a specific one; here are the random options (default = Hanukkah kit)
  $ch = Add-Item $menu $L.ui.character $null $false $null
  $who = if ($s.who) { "$($s.who)" } else { 'kit:hanukkah' }
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

  $lg = Add-Item $menu $L.ui.language $null $false $null
  foreach ($code in $I.psobject.Properties.Name) {
    Add-Item $lg $I.$code.name $code ($code -eq $(if ($s.lang) { $s.lang } else { 'en' })) { param($o) Set-State @{ lang = $o.Tag }; Update-Tip } | Out-Null
  }

  $ev = Add-Item $menu $L.ui.every $null $false $null
  $opts = 60, 90, 120, 180
  for ($i = 0; $i -lt $opts.Count; $i++) {
    Add-Item $ev $L.ui.freq[$i] $opts[$i] ($opts[$i] -eq (Get-Every)) { param($o) Set-State @{ every = $o.Tag }
      $script:next = Get-NextTime; Update-Tip } | Out-Null
  }

  if ((Get-PausedUntil) -gt (Get-Date)) {
    Add-Item $menu $L.ui.resume $null $false { Set-State @{ pausedUntil = $null }; $script:next = Get-NextTime; Update-Tip } | Out-Null
  } else {
    Add-Item $menu $L.ui.pause $null $false { Set-State @{ pausedUntil = (Get-Date).AddHours(1).ToString('o') }; Update-Tip } | Out-Null
  }
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
  $now = Get-Date
  if ((Get-PausedUntil) -gt $now) { $script:next = (Get-PausedUntil).AddMinutes((Get-Every) * 0.5) }
  elseif ($now -ge $script:next) { Show-Reminder }
  Update-Tip
})
$timer.Start(); Update-Tip

[System.Windows.Forms.Application]::Run()
$ni.Dispose()
