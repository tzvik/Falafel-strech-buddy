# Uninstall: stop the tray, remove shortcuts and the Apps entry.
# If installed by the .exe (in AppData\Local\StretchBuddy), also delete the app folder.
$dir = Split-Path $MyInvocation.MyCommand.Path
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'Noodle Reminder.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'Stretch Buddy.lnk') -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*tray.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName 'Rigatoni Posture Reminder' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\StretchBuddy' -ErrorAction SilentlyContinue

if ($dir -eq (Join-Path $env:LOCALAPPDATA 'StretchBuddy')) {   # never deletes a dev checkout
  Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c timeout /t 2 >nul & rmdir /s /q `"$dir`""
}
"Uninstalled."
