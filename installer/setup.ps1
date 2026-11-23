# Runs inside StretchBuddy-Setup.exe: unpack app.zip into the user's AppData and start it.
# No admin needed. Upgrades keep the user's settings (state.json) and their own packs.
$ErrorActionPreference = 'Stop'
$target = Join-Path $env:LOCALAPPDATA 'StretchBuddy'

# stop a running copy so files can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*StretchBuddy*tray.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Force $target | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $PSScriptRoot 'app.zip'))
foreach ($e in $zip.Entries) {
  if (-not $e.Name) { continue }
  $out = Join-Path $target $e.FullName
  New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
  [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true)
}
$zip.Dispose()

& (Join-Path $target 'install.ps1') | Out-Null

# text comes from i18n.json (keeps this file ASCII-safe for Windows PowerShell)
$I = Get-Content (Join-Path $target 'i18n.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("$($I.he.ui.installed)`n`n$($I.en.ui.installed)", 'Stretch Buddy') | Out-Null
