# Build dist\StretchBuddy-Setup.exe with IExpress (built into Windows - no tools to install).
# IExpress can't hold folders, so the app is zipped and setup.ps1 unpacks it.
$root = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$work = Join-Path $root 'installer\build'; $dist = Join-Path $root 'dist'
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work, $dist | Out-Null

# app files = what git tracks (so personal state.json / private packs never ship), minus dev-only stuff
Push-Location $root
$files = git ls-files | Where-Object { $_ -notmatch '^(installer/|docs/|\.gitignore)' }
Pop-Location
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open((Join-Path $work 'app.zip'), 'Create')
foreach ($f in $files) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $root $f), $f) }
$zip.Dispose()
Copy-Item (Join-Path $root 'installer\setup.ps1') $work

$exe = Join-Path $dist 'StretchBuddy-Setup.exe'
@"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$exe
FriendlyName=Stretch Buddy
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File setup.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="app.zip"
FILE1="setup.ps1"
[SourceFiles]
SourceFiles0=$work\
[SourceFiles0]
%FILE0%=
%FILE1%=
"@ | Set-Content (Join-Path $work 'setup.sed') -Encoding ascii

Start-Process iexpress.exe -ArgumentList '/N', '/Q', (Join-Path $work 'setup.sed') -Wait   # IExpress rejects a quoted path
Remove-Item $work -Recurse -Force
if (Test-Path $exe) { "Built $exe ($([int]((Get-Item $exe).Length/1KB)) KB)" } else { 'Build failed' }
