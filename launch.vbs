' Runs a .ps1 from this folder with no console flash. Default: the reminder popup.
'   wscript launch.vbs                         -> rigatoni.ps1 (a reminder)
'   wscript launch.vbs tray.ps1                -> tray icon
'   wscript launch.vbs rigatoni.ps1 -Gallery   -> character picker
script = "rigatoni.ps1"
extra = ""
If WScript.Arguments.Count > 0 Then script = WScript.Arguments(0)
For i = 1 To WScript.Arguments.Count - 1
  extra = extra & " " & WScript.Arguments(i)
Next
folder = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & folder & "\" & script & """" & extra, 0, False
