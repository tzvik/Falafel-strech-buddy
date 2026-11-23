# Install: start the tray icon now and at every login (Startup-folder shortcut, no admin needed).
$dir = Split-Path $MyInvocation.MyCommand.Path
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Noodle Reminder.lnk'

$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sc.TargetPath = "$env:WINDIR\System32\wscript.exe"
$sc.Arguments = "`"$dir\launch.vbs`" tray.ps1"
$sc.WorkingDirectory = $dir
$sc.Save()

# older versions used a 20-minute scheduled task; the tray does the timing now
Unregister-ScheduledTask -TaskName 'Rigatoni Posture Reminder' -Confirm:$false -ErrorAction SilentlyContinue

Start-Process wscript.exe -ArgumentList "`"$dir\launch.vbs`" tray.ps1"
"Installed. Look for the rigatoni in your system tray (you may need to click the ^ arrow)."
