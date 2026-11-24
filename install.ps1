# Install: start the tray icon now and at every login (Startup-folder shortcut, no admin needed),
# add a Start-menu shortcut and an entry in Windows "Apps" so it can be uninstalled normally.
$dir = Split-Path $MyInvocation.MyCommand.Path
$ws  = New-Object -ComObject WScript.Shell

foreach ($lnk in (Join-Path ([Environment]::GetFolderPath('Startup')) 'Noodle Reminder.lnk'),
                 (Join-Path ([Environment]::GetFolderPath('Programs')) 'Stretch Buddy.lnk')) {
  $sc = $ws.CreateShortcut($lnk)
  $sc.TargetPath = "$env:WINDIR\System32\wscript.exe"
  $sc.Arguments = "`"$dir\launch.vbs`" tray.ps1"
  $sc.WorkingDirectory = $dir
  $sc.Save()
}

# Windows "Apps > Installed apps" entry (per-user)
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\StretchBuddy'
New-Item -Force $key | Out-Null
Set-ItemProperty $key DisplayName 'Stretch Buddy'
Set-ItemProperty $key Publisher 'Stretch Buddy'
Set-ItemProperty $key InstallLocation $dir
Set-ItemProperty $key UninstallString "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\uninstall.ps1`""
Set-ItemProperty $key NoModify 1 -Type DWord
Set-ItemProperty $key NoRepair 1 -Type DWord

# older versions used a 20-minute scheduled task; the tray does the timing now
Unregister-ScheduledTask -TaskName 'Rigatoni Posture Reminder' -Confirm:$false -ErrorAction SilentlyContinue

# keep-alive: every 15 min make sure the tray is running (if it already is, the new copy exits at once)
$act = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wscript.exe" -Argument "`"$dir\launch.vbs`" tray.ps1"
$trg = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'Stretch Buddy keep-alive' -Action $act -Trigger $trg -Settings $set -Force | Out-Null

Start-Process wscript.exe -ArgumentList "`"$dir\launch.vbs`" tray.ps1"
"Installed. Look for the rigatoni in your system tray (you may need to click the ^ arrow)."
