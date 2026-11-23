# Uninstall: stop the tray icon and remove it from login. Your files and settings stay in this folder.
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'Noodle Reminder.lnk') -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*tray.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName 'Rigatoni Posture Reminder' -Confirm:$false -ErrorAction SilentlyContinue
"Uninstalled."
