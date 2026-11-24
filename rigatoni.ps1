# Noodle stretch reminder - inspired by Claude's "Tony the Rigatoni" demo.
# Flow: "It's time to stretch!" toast -> exercise card where a character acts it out (Start/Snooze) -> countdown (Done/Stop).
# Drag it anywhere (position is remembered). Right-click to change language. Text lives in i18n.json.
#   rigatoni.ps1                          normal reminder (next exercise in the rotation)
#   rigatoni.ps1 -Gallery                 character picker
#   rigatoni.ps1 -Demo drink -Who 2       preview one exercise/character without touching the rotation
#   ... -Snap C:\tmp\shot                 also save PNG frames (shot-0.png ...) and close - for testing
#   rigatoni.ps1 -MakeSounds              (re)build the sounds\*.wav files
#   ... -Finish                           (with -Demo) jump straight to the success celebration, with confetti
#   rigatoni.ps1 -Setup                   first-run welcome wizard (character, reminder types, timing, sound)
param([string]$Demo, [int]$Who = -1, [string]$Lang, [switch]$Gallery, [string]$Snap, [switch]$MakeSounds, [switch]$Finish, [switch]$Setup)
if ($Setup) { $Gallery = [switch]$true }   # the wizard reuses the gallery's character tiles
Add-Type -AssemblyName PresentationFramework

$dir   = Split-Path $MyInvocation.MyCommand.Path
$state = Join-Path $dir 'state.json'
$I     = Get-Content (Join-Path $dir 'i18n.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Rotation (one per popup, popups ~every 2h): mixes stretches with water, eyes and getting up.
# Every card also carries a small posture/water tip. s = countdown seconds, w = toast word.
$exercises = @(
  @{ k='thoracic'; s=40; w='stretch' }, @{ k='drink';   s=20; w='drink' },  @{ k='eyes';      s=20;  w='eyes' },
  @{ k='stand';    s=60; w='stand' },   @{ k='wrists';  s=30; w='stretch' }, @{ k='drink2';    s=20;  w='drink' },
  @{ k='neck';     s=40; w='stretch' }, @{ k='walk';    s=120; w='walk' },  @{ k='twist';     s=30;  w='stretch' },
  @{ k='drink';    s=20; w='drink' },   @{ k='breathe'; s=40; w='breathe' }, @{ k='calves';    s=30;  w='move' },
  @{ k='chin';     s=30; w='stretch' }, @{ k='drink2';  s=20; w='drink' },  @{ k='shoulders'; s=30;  w='stretch' },
  @{ k='shake';    s=15; w='stretch' }, @{ k='neckturn'; s=30; w='stretch' }, @{ k='armsout'; s=15; w='stretch' },
  @{ k='wander';   s=60; w='walk' }
)

# --- state: next exercise, done-today counter, dragged position, language, character ---
$today = (Get-Date).ToString('yyyy-MM-dd')
$st = @{ count=0; idx=0; right=$null; bottom=$null; lang='he' }   # default language: Hebrew
$j = $null
try { $j = Get-Content $state -Raw -ErrorAction Stop | ConvertFrom-Json; $st.idx = [int]$j.idx
      $st.right = $j.right; $st.bottom = $j.bottom; if ($j.lang) { $st.lang = $j.lang }
      if ($j.date -eq $today) { $st.count = [int]$j.count } } catch {}
if ($Lang) { $st.lang = $Lang }
if (-not $I.($st.lang)) { $st.lang = 'en' }
# Reminder types (tray > Reminder types): weight 2 = often, 1 = sometimes, 0 = off.
# Each popup picks a type by weight (never the same type twice in a row if others are on),
# then the next exercise of that type in turn.
$cats = [ordered]@{ stretch = 'thoracic','shake','neckturn','chin','armsout','neck','wrists','twist','shoulders'; water = 'drink','drink2'
                    move = 'stand','wander','walk','calves'; eyes = 'eyes','breathe' }
$weights = @{ stretch = 2; water = 2; move = 1; eyes = 1 }
if ($j -and $j.types) { foreach ($c in @($cats.Keys)) { if ($null -ne $j.types.$c) { $weights[$c] = [int]$j.types.$c } } }
function Select-Exercise {
  $on = @($cats.Keys | ? { $weights[$_] -gt 0 })
  if (-not $on) { return $null }
  $pool = @($on | ? { $_ -ne $j.lastCat }); if (-not $pool) { $pool = $on }
  $bag = foreach ($c in $pool) { ,$c * $weights[$c] }          # weighted lottery
  $cat = Get-Random -InputObject @($bag | % { $_ })
  $n = if ($j -and $null -ne $j."ci_$cat") { [int]$j."ci_$cat" } else { 0 }
  $key = $cats[$cat][$n % $cats[$cat].Count]
  if (-not $Gallery) { Save-State @{ lastCat = $cat; "ci_$cat" = $n + 1 } }
  $exercises | ? { $_.k -eq $key } | Select-Object -First 1
}
# Re-read before writing and touch only the given fields, so the popup/tray/gallery never clobber each other.
function Save-State($changes, [switch]$AddDone) {
  $cur = @{}
  try { (Get-Content $state -Raw -ErrorAction Stop | ConvertFrom-Json).psobject.Properties | ForEach-Object { $cur[$_.Name] = $_.Value } } catch {}
  if ($cur.date -ne $today) { $cur.count = 0 }
  $cur.date = $today
  if ($AddDone) { $cur.count = [int]$cur.count + 1 }
  if ($changes) { foreach ($k in $changes.Keys) { $cur[$k] = $changes[$k] } }
  $cur | ConvertTo-Json | Set-Content $state -Encoding utf8
}
$ex = if ($Demo) { $exercises | ? { $_.k -eq $Demo } | Select-Object -First 1 }
      elseif ($Gallery) { $exercises[0] }
      else { Select-Exercise }
if (-not $ex) { return }   # every reminder type switched off: nothing to show

# ============ SOUNDS ============
# Short, quiet, synthesized (no audio files to license). Built once into sounds\<kind>.wav, then just played.
$SR = 22050
function Add-Note($buf, $t0, $f, $dur, $vol, $f2 = $f, $decay = 7, $harm = 0.2, $att = 0.005) {   # sine (+ pitch glide, attack in s)
  $n0 = [int]($t0 * $SR); $n = [int]($dur * $SR); $ph = 0.0; $na = [math]::Max(1.0, $att * $SR)
  for ($i = 0; $i -lt $n -and ($n0 + $i) -lt $buf.Length; $i++) {
    $ph += 2 * [math]::PI * ($f + ($f2 - $f) * $i / $n) / $SR
    $env = [math]::Exp(-$decay * $i / $SR) * [math]::Min(1, $i / $na) * [math]::Min(1, ($n - $i) / 300.0)
    $buf[$n0 + $i] += $vol * $env * ([math]::Sin($ph) + $harm * [math]::Sin(2 * $ph)) } }
function Add-Splash($buf, $t0, $dur, $vol) {   # soft low-passed noise = a little water splash
  $n0 = [int]($t0 * $SR); $lp = 0.0; $rnd = New-Object Random 7
  for ($i = 0; $i -lt [int]($dur * $SR); $i++) { $lp += 0.07 * ($rnd.NextDouble() - 0.5 - $lp)
    $buf[$n0 + $i] += $vol * $lp * [math]::Exp(-6 * $i / $SR) * [math]::Min(1, $i / 400.0) } }
function Add-Pour($buf, $t0, $dur, $vol, $f0, $f1) {
  # a glass filling: noise through a resonant band-pass whose pitch rises as the "glass" fills, plus a few bubbles
  $n0 = [int]($t0 * $SR); $n = [int]($dur * $SR); $rnd = New-Object Random 3
  $x1 = 0.0; $x2 = 0.0; $y1 = 0.0; $y2 = 0.0
  for ($i = 0; $i -lt $n; $i++) {
    $p = $i / $n; $fc = $f0 * [math]::Pow($f1 / $f0, $p)                       # rising resonance
    $w = 2 * [math]::PI * $fc / $SR; $al = [math]::Sin($w) / (2 * 6.0)          # Q = 6
    $a0 = 1 + $al; $bb0 = $al / $a0; $a1 = -2 * [math]::Cos($w) / $a0; $a2 = (1 - $al) / $a0
    $x = $rnd.NextDouble() - 0.5
    $y = $bb0 * $x - $bb0 * $x2 - $a1 * $y1 - $a2 * $y2
    $x2 = $x1; $x1 = $x; $y2 = $y1; $y1 = $y
    $env = [math]::Min(1, $p * 8) * [math]::Min(1, (1 - $p) * 5)             # soft in, soft out
    $buf[$n0 + $i] += $vol * $env * $y }
  foreach ($k in 1..5) { $tb = $t0 + $dur * (0.15 + 0.15 * $k) + $rnd.NextDouble() * 0.05; $fb = $f0 * (1.6 + 0.5 * $k)
    Add-Note $buf $tb $fb 0.05 ($vol * 0.08) ($fb * 1.6) 40 0 }               # tiny bubbles, higher as it fills
}
function Add-Whoosh($buf, $t0, $dur, $vol) {   # soft airy breath: low-passed noise, cutoff rising, bell-shaped envelope
  $n0 = [int]($t0 * $SR); $n = [int]($dur * $SR); $lp = 0.0; $rnd = New-Object Random 11
  for ($i = 0; $i -lt $n; $i++) { $p = $i / $n; $k = 0.02 + 0.10 * $p
    $lp += $k * ($rnd.NextDouble() - 0.5 - $lp)
    $buf[$n0 + $i] += $vol * $lp * [math]::Sin([math]::PI * $p) } }
$recipes = @{
  water    = { param($b) Add-Pour $b 0 1.3 1.0 380 1500 }                                                           # glass filling up
  stretch  = { param($b) Add-Whoosh $b 0 1.0 1.0; Add-Note $b 0.08 196 0.95 0.25 294 1.8 0.05 0.3 }                   # gentle stretch: breath + slow warm rise
  move     = { param($b) Add-Whoosh $b 0 0.9 1.0; Add-Note $b 0.06 247 0.85 0.25 349 2.0 0.05 0.3 }                   # same family, a little brighter
  calm     = { param($b) Add-Note $b 0 660 1.0 0.10 660 3.5 0; Add-Note $b 0 990 0.9 0.05 990 4 0 }                 # soft bell
  done     = { param($b) Add-Note $b 0 659 0.4 0.12 659 8; Add-Note $b 0.12 880 0.6 0.12 880 6 }
  hanukkah = { param($b) $t = 0; foreach ($nt in @(392,0.16),@(330,0.16),@(392,0.16),@(330,0.16),@(330,0.16),@(330,0.4)) {   # festive "sevivon"-style jingle
                 Add-Note $b $t $nt[0] ($nt[1] + 0.25) 0.12 $nt[0] 7; $t += $nt[1] } }
  thanksgiving = { param($b) $t = 0; foreach ($f in 262, 330, 392, 523) { Add-Note $b $t $f 0.6 0.11 $f 6; $t += 0.11 }   # warm harvest arpeggio
                   Add-Note $b 0.5 1047 0.8 0.05 1047 4 0 }                                                              # + little dinner bell
}
function Get-Sound($kind) {
  $f = Join-Path $dir "sounds\$kind.wav"
  if ($MakeSounds -or -not (Test-Path $f)) {
    New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
    $buf = New-Object double[] ([int]($SR * 1.6)); & $recipes[$kind] $buf
    $last = $buf.Length - 1; while ($last -gt 0 -and [math]::Abs($buf[$last]) -lt 0.0005) { $last-- }   # trim silence
    $bw = New-Object IO.BinaryWriter ([IO.File]::Create($f)); $n = $last + 1
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + 2*$n)); $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$SR); $bw.Write([int](2*$SR)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int](2*$n))
    $peak = ($buf | Measure-Object -Maximum -Minimum); $peak = [math]::Max($peak.Maximum, -$peak.Minimum)
    $gain = if ($peak -gt 0) { 0.4 / $peak } else { 1 }   # same gentle loudness for every sound (~ -8 dB)
    for ($i = 0; $i -lt $n; $i++) {   # note: [int16](x) * k casts FIRST - so compute the sample, then cast
      $smp = [math]::Max(-1.0, [math]::Min(1.0, $buf[$i] * $gain)) * 32000.0
      $bw.Write([int16]$smp) }
    $bw.Close() }
  $f }
$script:muted = [bool]($j -and $j.mute)
function Play-Sound($kind) {
  if ($Snap -or $script:muted) { return }
  try {
    # a real recording (sounds\<kind>.mp3) wins over the synthesized .wav; played quietly and cut short
    $mp3 = Join-Path $dir "sounds\$kind.mp3"
    $file = if (Test-Path $mp3) { $mp3 } else { Get-Sound $kind }
    # per-sound start / length / volume (sounds\sounds.json) - so long recordings play just their best bit
    $cfg = $null; try { $cfg = (Get-Content (Join-Path $dir 'sounds\sounds.json') -Raw | ConvertFrom-Json).$kind } catch {}
    $script:sndLen = if ($cfg.len) { [double]$cfg.len } else { 2.5 }
    $script:sndVol = if ($cfg.vol) { [double]$cfg.vol } else { 0.35 }
    $script:player = New-Object System.Windows.Media.MediaPlayer
    $script:player.Open([Uri]$file); $script:player.Volume = $script:sndVol
    if ($cfg.start) { $script:player.Position = [TimeSpan]::FromSeconds([double]$cfg.start) }
    $script:player.Play()
    $script:fade = New-Object System.Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromMilliseconds(50) }
    $script:fadeT0 = Get-Date
    $script:fade.Add_Tick({ $t = ((Get-Date) - $script:fadeT0).TotalSeconds
      if ($t -gt $script:sndLen) { $script:player.Volume = [math]::Max(0, $script:sndVol * (1 - ($t - $script:sndLen) / 0.4)) }   # 0.4 s fade
      if ($t -gt $script:sndLen + 0.4) { $script:player.Stop(); $script:fade.Stop() } })
    $script:fade.Start()
  } catch {} }
if ($MakeSounds) {
  foreach ($k in $recipes.Keys) {   # build + self-check: a silent file means the writer is broken
    $b = [IO.File]::ReadAllBytes((Get-Sound $k)); $loud = $false
    for ($i = 44; $i -lt $b.Length - 1 -and -not $loud; $i += 2) { if ([math]::Abs([BitConverter]::ToInt16($b, $i)) -gt 3000) { $loud = $true } }
    if ($loud) { "built $k.wav" } else { Write-Warning "$k.wav is SILENT" } }
  return }

# ============ THE CAST ============
# Each body: g = outline geometry (inside ~14..96 x 10..134), c = 3-stop fill gradient, d = surface detail drawn on top
# ({P} in d = this copy's name prefix, for animated details), ax = move shoulders inward for narrow bodies.
# Face, limbs, sticker border and ink outline are shared. Names come from i18n.json "cast" (same order).
# KITS: add a theme (e.g. christmas) = add entries with kit='christmas' + names in i18n "cast" and "kits".
$INK = '#2B2420'
function Dots($pts, $w, $h, $fill) { ($pts | % { "<Ellipse Canvas.Left='$($_[0])' Canvas.Top='$($_[1])' Width='$w' Height='$h' Fill='$fill'/>" }) -join '' }
$cast = @(
  @{ kit='pasta'; c='#E2982F','#F5BE52','#D88A26'   # 0 rigatoni
     g='<RectangleGeometry Rect="22,14,66,114" RadiusX="8" RadiusY="8"/>'
     d=(((33,44,55,66,77) | % { "<Line X1='$_' Y1='22' X2='$_' Y2='122' Stroke='#C77F22' StrokeThickness='2.5' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>" }) -join '') +
       "<Ellipse Canvas.Left='22' Canvas.Top='8' Width='66' Height='13' Fill='#F8CF73' Stroke='$INK' StrokeThickness='3'/><Ellipse Canvas.Left='32' Canvas.Top='11' Width='46' Height='7' Fill='#9A5E16'/>" },
  @{ kit='pasta'; c='#EDB54A','#F8D774','#E2A23C'   # 1 penne
     g='<PathGeometry Figures="M 22,28 L 88,12 L 88,114 L 22,130 Z"/>'
     d=(((33,44,55,66,77) | % { $t = 28 - ($_-22)*16/66; "<Line X1='$_' Y1='$($t+6)' X2='$_' Y2='$($t+96)' Stroke='#D29A35' StrokeThickness='2.5' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>" }) -join '') +
       "<Ellipse Canvas.Left='22' Canvas.Top='13' Width='66' Height='14' Fill='#FBE08F' Stroke='$INK' StrokeThickness='3'><Ellipse.RenderTransform><RotateTransform Angle='-13' CenterX='33' CenterY='7'/></Ellipse.RenderTransform></Ellipse>" +
       "<Ellipse Canvas.Left='33' Canvas.Top='16' Width='44' Height='7' Fill='#9A6416'><Ellipse.RenderTransform><RotateTransform Angle='-13' CenterX='22' CenterY='3.5'/></Ellipse.RenderTransform></Ellipse>" },
  @{ kit='pasta'; c='#F0B94E','#FADD86','#EAAE44'   # 2 farfalle (bow tie)
     g='<PathGeometry Figures="M 12,22 C 34,26 46,36 55,44 C 64,36 76,26 98,22 L 98,124 C 76,120 64,110 55,102 C 46,110 34,120 12,124 Z"/>'
     d='<Line X1="20" Y1="30" X2="20" Y2="116" Stroke="#D9A445" StrokeThickness="4" StrokeDashArray="1 0.8"/>' +
       '<Line X1="90" Y1="30" X2="90" Y2="116" Stroke="#D9A445" StrokeThickness="4" StrokeDashArray="1 0.8"/>' +
       '<Path Data="M 30,42 Q 40,72 30,104 M 80,42 Q 70,72 80,104" Stroke="#D9A445" StrokeThickness="2.5"/>' },
  @{ kit='pasta'; c='#EBB85C','#F8D98F','#E2AA4C'   # 3 ravioli (pillow with crimped edge)
     g='<RectangleGeometry Rect="15,30,80,98" RadiusX="14" RadiusY="14"/>'
     d='<Rectangle Canvas.Left="23" Canvas.Top="38" Width="64" Height="82" RadiusX="9" RadiusY="9" Stroke="#D9A445" StrokeThickness="2.5" StrokeDashArray="2 1.5"/>' },
  @{ kit='pasta'; c='#E6B83A','#F8DC78','#DDA82E'   # 4 spaghetti bundle with a curl on top
     g='<PathGeometry Figures="M 26,42 Q 26,20 55,20 Q 84,20 84,42 L 86,122 Q 86,130 78,130 L 32,130 Q 24,130 24,122 Z"/>'
     d=(((32,42,52,62,72,80) | % { "<Path Data='M $_,28 Q $($_+4),44 $_,60 T $_,92 T $_,124' Stroke='#D3A23E' StrokeThickness='2'/>" }) -join '') +
       "<Path Data='M 55,22 C 54,6 72,4 70,14 C 68,22 58,18 62,12' Stroke='$INK' StrokeThickness='8' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>" +
       "<Path Data='M 55,22 C 54,6 72,4 70,14 C 68,22 58,18 62,12' Stroke='#F0C64E' StrokeThickness='4' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>" },
  @{ kit='pasta'; c='#E9BE62','#F8E0A0','#DFA852'   # 5 lasagna: ruffled sheet, sauce + cheese layers
     g='<PathGeometry Figures="M 12,30 Q 17,22 22,30 T 32,30 T 42,30 T 52,30 T 62,30 T 72,30 T 82,30 T 92,30 Q 95,26 98,30 L 98,122 Q 93,130 88,122 T 78,122 T 68,122 T 58,122 T 48,122 T 38,122 T 28,122 T 18,122 Q 15,127 12,122 Z"/>'
     d='<Rectangle Canvas.Left="14" Canvas.Top="38" Width="82" Height="7" Fill="#C8392B"/><Rectangle Canvas.Left="14" Canvas.Top="45" Width="82" Height="3" Fill="#F7EAD0"/>' +
       '<Rectangle Canvas.Left="14" Canvas.Top="102" Width="82" Height="7" Fill="#C8392B"/><Rectangle Canvas.Left="14" Canvas.Top="109" Width="82" Height="3" Fill="#F7EAD0"/>' },
  @{ kit='streetfood'; c='#9A6430','#C3904C','#8A5626'   # 6 falafel ball: crunchy bits, herbs, sesame
     g='<EllipseGeometry Center="55,82" RadiusX="44" RadiusY="44"/>'
     d=(Dots (@(24,52),@(72,42),@(84,100),@(30,108),@(52,116),@(90,68),@(18,82)) 8 6 '#76461A') +
       (Dots (@(40,46),@(78,112),@(16,98),@(92,86),@(64,106)) 6 4 '#5E8C31') +
       (Dots (@(55,42),@(28,64),@(82,52),@(70,118)) 6 3 '#F3E3B5') },
  @{ kit='streetfood'; c='#E8CC92','#F7E8C2','#E0C080'   # 7 shawarma in laffa, paper wrapper
     g='<RectangleGeometry Rect="22,26,66,104" RadiusX="16" RadiusY="16"/>'
     d='<Path Data="M 24,46 Q 55,54 86,40" Stroke="#D4B377" StrokeThickness="2.5"/>' +
       "<Path Data='M 24,32 Q 28,10 42,22 Q 46,6 58,18 Q 66,4 72,20 Q 86,10 86,32 Z' Fill='#8B4A22' Stroke='$INK' StrokeThickness='2.5'/>" +
       '<Ellipse Canvas.Left="28" Canvas.Top="14" Width="13" Height="9" Fill="#5FA03A"/><Ellipse Canvas.Left="66" Canvas.Top="10" Width="12" Height="9" Fill="#5FA03A"/>' +
       '<Ellipse Canvas.Left="47" Canvas.Top="10" Width="11" Height="10" Fill="#E0453A"/>' +
       '<Path Data="M 30,28 Q 40,22 48,28 T 66,28 T 82,26" Stroke="#F4EBD8" StrokeThickness="3" StrokeEndLineCap="Round" StrokeStartLineCap="Round"/>' +
       "<Path Data='M 20,98 L 27,92 L 34,98 L 41,92 L 48,98 L 55,92 L 62,98 L 69,92 L 76,98 L 83,92 L 90,98 L 90,124 Q 90,132 82,132 L 28,132 Q 20,132 20,124 Z' Fill='#FBFBF8' Stroke='$INK' StrokeThickness='2.5' StrokeLineJoin='Round'/>" +
       '<Rectangle Canvas.Left="21" Canvas.Top="110" Width="68" Height="6" Fill="#D33A2C"/>' },
  @{ kit='hanukkah'; eyes='googly'; hands='glove'; mouth='lips'; c='#D98E3E','#F0B868','#CE8236'   # 8 sufganiya: googly eyes, gloves, sugar, red jam
     g='<EllipseGeometry Center="55,86" RadiusX="46" RadiusY="40"/>'
     d='<Path Data="M 11,92 Q 55,108 99,92 L 99,99 Q 55,115 11,99 Z" Fill="#F7E3BC"/>' +
       '<Path Data="M 18,66 Q 28,46 55,46 Q 82,46 92,66 Q 82,60 72,64 Q 62,58 52,63 Q 42,58 32,64 Q 25,61 18,66 Z" Fill="White" Opacity="0.95"/>' +
       (Dots (@(24,74),@(86,76),@(34,54),@(76,52),@(14,82),@(92,88),@(20,108),@(88,106),@(44,116),@(68,114),@(80,62),@(28,92)) 3.5 3.5 'White') +
       "<Path Data='M 45,42 Q 55,22 65,42 Q 67,50 59,48 Q 56,57 52,48 Q 43,50 45,42 Z' Fill='#C8102E' Stroke='$INK' StrokeThickness='2'/>" +
       '<Ellipse Canvas.Left="51" Canvas.Top="31" Width="5" Height="3.5" Fill="White" Opacity="0.85"/>' },
  @{ kit='hanukkah'; c='#2F6FC0','#6FA6E6','#285FA8'   # 9 dreidel (sevivon) with a gimel
     g='<PathGeometry Figures="M 24,36 L 86,36 L 86,100 Q 86,108 78,114 L 55,134 L 32,114 Q 24,108 24,100 Z"/>'
     d="<Rectangle Canvas.Left='49' Canvas.Top='14' Width='12' Height='24' RadiusX='4' RadiusY='4' Fill='#5A92D8' Stroke='$INK' StrokeThickness='3'/>" +
       '<Path Data="M 26,44 L 84,44" Stroke="#9CC3F0" StrokeThickness="2.5"/>' +
       '<TextBlock Canvas.Left="47" Canvas.Top="88" Text="&#x05D2;" FontSize="20" FontWeight="Bold" Foreground="#F5D36A"/>' },
  @{ kit='hanukkah'; ax=10; c='#C8931F','#F2CF66','#BE8818'   # 10 menorah (hanukkiah) with flickering flames
     g='<PathGeometry Figures="M 32,48 L 78,48 L 72,104 Q 86,110 90,126 L 20,126 Q 24,110 38,104 Z"/>'
     d="<Rectangle Canvas.Left='8' Canvas.Top='38' Width='94' Height='9' RadiusX='4' RadiusY='4' Fill='#E3B640' Stroke='$INK' StrokeThickness='3'/>" +
       (((12,22,32,42,64,74,84,94) | % { "<Rectangle Canvas.Left='$($_-3)' Canvas.Top='24' Width='7' Height='15' Fill='$(if ($_ % 20 -eq 2) {'#4A90D9'} else {'#FFFFFF'})' Stroke='$INK' StrokeThickness='1.5'/>" }) -join '') +
       "<Rectangle Canvas.Left='51.5' Canvas.Top='12' Width='7' Height='27' Fill='#4A90D9' Stroke='$INK' StrokeThickness='1.5'/>" +
       "<Canvas><Canvas.RenderTransform><ScaleTransform x:Name='{P}Flames' CenterY='24'/></Canvas.RenderTransform>" +
       (((12,22,32,42,64,74,84,94) | % { "<Ellipse Canvas.Left='$($_-3)' Canvas.Top='14' Width='7' Height='10' Fill='#FFB020'/><Ellipse Canvas.Left='$($_-1.5)' Canvas.Top='18' Width='4' Height='5' Fill='#FFF1A8'/>" }) -join '') +
       "<Ellipse Canvas.Left='51.5' Canvas.Top='2' Width='7' Height='10' Fill='#FFB020'/><Ellipse Canvas.Left='53' Canvas.Top='6' Width='4' Height='5' Fill='#FFF1A8'/></Canvas>" },
  @{ kit='hanukkah'; ax=8; c='#3E7CC9','#8CC0F0','#3570B8'   # 11 single Hanukkah candle, flickering flame
     g='<RectangleGeometry Rect="32,34,46,98" RadiusX="7" RadiusY="7"/>'
     d=(((44,64,84,104,124) | % { "<Path Data='M 33,$($_) L 77,$($_-14)' Stroke='#F4F8FF' StrokeThickness='5' Opacity='0.85'/>" }) -join '') +
       "<Path Data='M 34,40 Q 34,32 44,32 L 66,32 Q 76,32 76,40 L 76,48 Q 72,54 70,46 Q 66,40 62,50 Q 58,56 56,44 L 40,44 Q 36,52 34,46 Z' Fill='#F4F8FF' Stroke='$INK' StrokeThickness='2'/>" +
       "<Line X1='55' Y1='32' X2='55' Y2='22' Stroke='$INK' StrokeThickness='2.5'/>" +
       "<Canvas><Canvas.RenderTransform><ScaleTransform x:Name='{P}Flames' CenterX='55' CenterY='24'/></Canvas.RenderTransform>" +
       "<Path Data='M 55,2 Q 66,14 60,22 Q 55,27 50,22 Q 44,14 55,2 Z' Fill='#FFB020' Stroke='$INK' StrokeThickness='1.5'/><Path Data='M 55,10 Q 60,16 57,21 Q 55,23 53,21 Q 50,16 55,10 Z' Fill='#FFF1A8'/></Canvas>" },
  @{ kit='thanksgiving'; c='#E06A22','#F79A48','#D25E1C'   # 12 pumpkin: ribs, stem, curly vine
     g='<EllipseGeometry Center="55,88" RadiusX="47" RadiusY="40"/>'
     d='<Path Data="M 36,52 Q 22,88 36,124 M 74,52 Q 88,88 74,124 M 22,62 Q 8,88 22,114 M 88,62 Q 102,88 88,114" Stroke="#C9561A" StrokeThickness="3"/>' +
       "<Path Data='M 50,50 L 52,34 Q 55,30 60,33 L 61,50 Z' Fill='#6B8E23' Stroke='$INK' StrokeThickness='2.5' StrokeLineJoin='Round'/>" +
       "<Path Data='M 60,38 C 70,30 78,40 72,44 C 68,47 66,40 70,39' Stroke='#4F7A1F' StrokeThickness='2.5' StrokeEndLineCap='Round'/>" +
       "<Path Data='M 62,42 Q 76,36 84,44 Q 74,48 62,42 Z' Fill='#7FA83A' Stroke='$INK' StrokeThickness='2'/>" },
  @{ kit='thanksgiving'; c='#8A5530','#B27A4A','#7A4A28'   # 13 turkey: fanned tail feathers behind, red wattle
     back=(((-70,-40,-12,12,40,70) | % { $col = @('#D9452B','#F08A24','#F6C243','#F6C243','#F08A24','#D9452B')[[array]::IndexOf(@(-70,-40,-12,12,40,70), $_)]
            "<Ellipse Canvas.Left='43' Canvas.Top='6' Width='24' Height='70' Fill='$col' Stroke='$INK' StrokeThickness='3'><Ellipse.RenderTransform><RotateTransform Angle='$_' CenterX='12' CenterY='68'/></Ellipse.RenderTransform></Ellipse>" }) -join '')
     g='<EllipseGeometry Center="55,90" RadiusX="38" RadiusY="40"/>'
     mouth='beak'
     d='<Path Data="M 30,100 Q 40,112 55,108 Q 70,112 80,100" Stroke="#6E4224" StrokeThickness="2.5"/>' },
  @{ kit='thanksgiving'; ax=6; c='#E8B820','#F9DE6A','#DCA818'   # 14 corn cob with husk leaves
     back="<Path Data='M 55,130 Q 14,110 22,40 Q 36,90 55,118 Z' Fill='#8DBB4C' Stroke='$INK' StrokeThickness='3' StrokeLineJoin='Round'/><Path Data='M 55,130 Q 96,110 88,40 Q 74,90 55,118 Z' Fill='#7BAA3C' Stroke='$INK' StrokeThickness='3' StrokeLineJoin='Round'/>"
     g='<PathGeometry Figures="M 55,16 C 80,16 82,50 82,80 C 82,112 72,128 55,128 C 38,128 28,112 28,80 C 28,50 30,16 55,16 Z"/>'
     d=(((24,34,44,92,102,112) | % { $y = $_; ((36,46,56,66) | % { "<Ellipse Canvas.Left='$_' Canvas.Top='$y' Width='8' Height='7' Fill='#F6CF45' Stroke='#C99A12' StrokeThickness='1'/>" }) -join '' }) -join '') },
  @{ kit='thanksgiving'; c='#D8752A','#F0A050','#CC6A22'   # 15 pumpkin pie with crust rim and whipped cream
     g='<RectangleGeometry Rect="12,46,86,82" RadiusX="22" RadiusY="22"/>'
     d="<Path Data='M 14,62 Q 20,50 28,58 Q 36,48 44,58 Q 52,48 60,58 Q 68,48 76,58 Q 84,48 90,58 Q 96,52 96,62 L 96,68 L 14,68 Z' Fill='#D9A45C' Stroke='$INK' StrokeThickness='2.5' StrokeLineJoin='Round'/>" +
       "<Rectangle Canvas.Left='14' Canvas.Top='104' Width='82' Height='10' Fill='#D9A45C'/>" +
       "<Path Data='M 40,46 Q 38,34 48,34 Q 50,22 60,28 Q 70,26 70,38 Q 76,44 68,48 L 42,48 Q 36,48 40,46 Z' Fill='White' Stroke='$INK' StrokeThickness='2.5' StrokeLineJoin='Round'/>" },
  @{ kit='streetfood'; ax=6; c='#DE9C3A','#F7CD74','#CF8C2E'   # 16 surprise bourekas: flaky triangle, sesame, filling peeking out
     g='<PathGeometry Figures="M 55,24 Q 61,23 64,30 L 97,116 Q 100,127 89,127 L 21,127 Q 10,127 13,116 L 46,30 Q 49,23 55,24 Z"/>'
     d='<Path Data="M 33,92 Q 55,100 77,92 M 26,108 Q 55,117 84,108" Stroke="#C47E26" StrokeThickness="2.5"/>' +
       '<Ellipse Canvas.Left="44" Canvas.Top="38" Width="14" Height="7" Fill="White" Opacity="0.45"/>' +
       (Dots (@(52,30),@(40,52),@(70,50),@(30,82),@(80,80),@(48,104),@(64,100)) 5 2.6 '#FBF0D0') +
       "<Path Data='M 70,118 Q 78,110 88,114' Stroke='$INK' StrokeThickness='2'/>" +
       '<Ellipse Canvas.Left="74" Canvas.Top="112" Width="5" Height="4" Fill="#5FA03A"/><Ellipse Canvas.Left="79" Canvas.Top="111" Width="5" Height="4" Fill="#F2C94C"/><Ellipse Canvas.Left="84" Canvas.Top="113" Width="4" Height="4" Fill="#E0453A"/>' },
  @{ kit='streetfood'; c='#E8C687','#F8E6BF','#DDB878'   # 17 half portion: half pita stuffed with falafel, salad, tahini
     g='<PathGeometry Figures="M 18,44 L 92,44 L 92,122 Q 92,132 82,132 L 28,132 Q 18,132 18,122 Z"/>'
     d='<Path Data="M 22,104 Q 55,112 88,104" Stroke="#CFA866" StrokeThickness="2"/>' +
       "<Ellipse Canvas.Left='18' Canvas.Top='30' Width='20' Height='18' Fill='#7A4A1C' Stroke='$INK' StrokeThickness='2.5'/>" +
       "<Ellipse Canvas.Left='36' Canvas.Top='22' Width='21' Height='19' Fill='#8A5626' Stroke='$INK' StrokeThickness='2.5'/>" +
       "<Ellipse Canvas.Left='58' Canvas.Top='28' Width='20' Height='18' Fill='#7A4A1C' Stroke='$INK' StrokeThickness='2.5'/>" +
       '<Ellipse Canvas.Left="74" Canvas.Top="32" Width="15" Height="12" Fill="#E0453A"/><Ellipse Canvas.Left="30" Canvas.Top="40" Width="14" Height="8" Fill="#7BB247"/>' +
       '<Ellipse Canvas.Left="52" Canvas.Top="40" Width="12" Height="7" Fill="#9CCB5B"/>' +
       '<Path Data="M 24,38 Q 34,32 44,38 T 64,36 T 84,38" Stroke="#F7EEDC" StrokeThickness="3.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>' },
  @{ kit='streetfood'; c='#E6C07E','#F7E3B8','#DAB06C'   # 18 sabich: round pita, eggplant, egg slices, parsley, amba
     g='<PathGeometry Figures="M 16,72 Q 16,38 55,38 Q 94,38 94,72 Q 94,130 55,130 Q 16,130 16,72 Z"/>'
     d="<Ellipse Canvas.Left='18' Canvas.Top='26' Width='26' Height='18' Fill='#5B2C4A' Stroke='$INK' StrokeThickness='2.5'/><Ellipse Canvas.Left='23' Canvas.Top='30' Width='16' Height='9' Fill='#C9A36A'/>" +
       "<Ellipse Canvas.Left='64' Canvas.Top='26' Width='26' Height='18' Fill='#5B2C4A' Stroke='$INK' StrokeThickness='2.5'/><Ellipse Canvas.Left='69' Canvas.Top='30' Width='16' Height='9' Fill='#C9A36A'/>" +
       "<Ellipse Canvas.Left='40' Canvas.Top='20' Width='22' Height='22' Fill='White' Stroke='$INK' StrokeThickness='2.5'/><Ellipse Canvas.Left='46' Canvas.Top='26' Width='10' Height='10' Fill='#F2B81B'/>" +
       '<Ellipse Canvas.Left="30" Canvas.Top="38" Width="10" Height="7" Fill="#5FA03A"/><Ellipse Canvas.Left="62" Canvas.Top="38" Width="10" Height="7" Fill="#5FA03A"/>' +
       '<Path Data="M 22,44 Q 32,36 42,44 T 62,42 T 86,44" Stroke="#E8A21C" StrokeThickness="3.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>' +
       '<Path Data="M 22,104 Q 55,114 88,104" Stroke="#C9A060" StrokeThickness="2"/>' }
)

# ---- CHARACTER PACKS: every folder in .\packs with a pack.json adds a kit (see packs\README.md) ----
# Packs can come from anyone, and XAML can be abused (e.g. ObjectDataProvider runs code), so everything is checked:
# shapes may only use drawing elements/attributes, no markup extensions; colors are hex; images stay inside the pack.
$okEl   = 'Canvas','Ellipse','Rectangle','Path','Line','Polygon','Polyline','TextBlock','RotateTransform','ScaleTransform','TranslateTransform','TransformGroup',
          'Ellipse.RenderTransform','Rectangle.RenderTransform','Path.RenderTransform','Canvas.RenderTransform','TextBlock.RenderTransform'
$okAttr = 'Canvas.Left','Canvas.Top','Width','Height','Fill','Stroke','StrokeThickness','StrokeDashArray','StrokeLineJoin','StrokeStartLineCap','StrokeEndLineCap',
          'Opacity','Data','Points','X1','Y1','X2','Y2','RadiusX','RadiusY','Angle','CenterX','CenterY','ScaleX','ScaleY','X','Y','Text','FontSize','FontWeight','Foreground'
function Test-SafeXaml($x) {
  if (-not $x) { return $true }
  try { $doc = [xml]"<r>$x</r>" } catch { return $false }
  foreach ($n in $doc.SelectNodes('//*')) { if ($n.Name -eq 'r') { continue }
    if ($n.Name -notin $okEl) { return $false }
    foreach ($a in $n.Attributes) { if ($a.Name -notin $okAttr -or $a.Value -match '\{') { return $false } } }
  $true }
foreach ($pj in Get-ChildItem (Join-Path $dir 'packs') -Filter pack.json -Recurse -ErrorAction SilentlyContinue) {
  try { $pk = Get-Content $pj.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }   # skip broken packs
  $kitId = "$($pk.kit)" -replace '[^A-Za-z0-9_-]', ''
  if (-not $kitId) { continue }
  $n = 0
  foreach ($ch in $pk.characters) {
    $e = @{ kit = $kitId; id = "pack:${kitId}:$n"   # stable id, so adding packs never changes your pick
            kitNames = $pk.names; names = $ch.names; ax = [int]$ch.ax
            eyes = $ch.eyes; hands = $ch.hands; mouth = $ch.mouth; noFace = ($ch.face -eq $false)
            first = [bool]$pk.first }   # "first": true = shown first in the gallery and the default character
    if ("$($ch.limbColor)" -match '^#[0-9A-Fa-f]{6}$') {   # felt-colored arms; edge = same color, darker
      $e.limb = $ch.limbColor
      $rgb = [Convert]::ToInt32($ch.limbColor.Substring(1), 16)
      $e.limbEdge = '#{0:X2}{1:X2}{2:X2}' -f [int](($rgb -shr 16 -band 255) * .75), [int](($rgb -shr 8 -band 255) * .75), [int](($rgb -band 255) * .75) }
    if ($ch.image) {   # sticker PNG/JPG as the body - must live inside the pack folder
      $file = [IO.Path]::GetFullPath((Join-Path $pj.DirectoryName $ch.image))
      if (-not $file.StartsWith($pj.DirectoryName, 'OrdinalIgnoreCase') -or $file -notmatch '\.(png|jpe?g)$' -or -not (Test-Path $file)) { continue }
      $img = [Security.SecurityElement]::Escape(([Uri]$file).AbsoluteUri)
      $e.image = "<Image Source='$img' Canvas.Left='8' Canvas.Top='8' Width='94' Height='126' Stretch='Uniform'/>"
    } else {           # vector body: SVG-style path data + 3 colors + optional XAML detail/back
      $cols = @($ch.colors)
      if ("$($ch.shape)" -notmatch '^[0-9MLHVCSQTAZmlhvcsqtaz ,.\-]+$' -or $cols.Count -ne 3 -or ($cols | ? { $_ -notmatch '^#[0-9A-Fa-f]{6,8}$' })) { continue }
      if (-not (Test-SafeXaml $ch.detail) -or -not (Test-SafeXaml $ch.back)) { continue }
      $e.g = "<PathGeometry Figures='$($ch.shape)'/>"; $e.c = $cols; $e.d = "$($ch.detail)"; $e.back = "$($ch.back)"
    }
    $cast += $e; $n++
  }
}
# display names: built-ins from i18n "cast", pack characters from their own "names"
function Get-Name($i, $L) { $n = $cast[$i].names
  if ($n) { if ($n.($st.lang)) { $n.($st.lang) } else { $n.en } } else { $L.cast[$i] } }
function Get-KitName($kit, $L) { if ($L.kits.$kit) { return $L.kits.$kit }
  $kn = ($cast | ? { $_.kit -eq $kit -and $_.kitNames } | Select-Object -First 1).kitNames
  if ($kn) { if ($kn.($st.lang)) { $kn.($st.lang) } else { $kn.en } } else { $kit } }

# Character setting ("who" in state.json): an index, "kit:<name>" (random from that kit), or "random" (anyone).
# default (nothing picked yet): a pack marked "first", else Israeli street food
$pinned = @($cast | ? { $_.first } | % { $_.kit } | Select-Object -Unique)
$defaultWho = if ($pinned) { ($cast | ? { $_.first } | Select-Object -First 1).id } else { 'kit:streetfood' }
$whoSet = if ($j -and $j.who) { "$($j.who)" } else { $defaultWho }
$whoIdx = if ($Who -ge 0) { $Who % $cast.Count }
          elseif ($whoSet -match '^\d+$') { [int]$whoSet % $cast.Count }
          elseif ($whoSet -like 'pack:*' -and ($hit = @(0..($cast.Count-1) | ? { $cast[$_].id -eq $whoSet }))) { $hit[0] }
          else {   # "rotating": a different character each time (never the same one twice in a row)
            $pool = if ($whoSet -like 'kit:*') { @(0..($cast.Count-1) | ? { $cast[$_].kit -eq $whoSet.Substring(4) }) } else { @() }
            if (-not $pool) { $pool = @(0..($cast.Count-1)) }
            $fresh = @($pool | ? { "$_" -ne "$($j.lastWho)" }); if ($fresh) { $pool = $fresh }
            Get-Random -InputObject $pool }
if (-not $Demo -and -not $Gallery -and -not $Snap) { Save-State @{ lastWho = $whoIdx } }

# ============ THE RIG ============
# Canvas 110x160. Jointed limbs: upper arm rotates at the shoulder, forearm at the elbow; thigh at the hip, shin at the knee.
# Angles: + is clockwise. A hanging left arm at +150 points up-left; the right arm mirrors with negatives.
# Every limb = thick ink line over a wider white line (the sticker border). Names are prefixed per copy (T/C/G0..).
function New-Noodle($p, $who) {
  $ax = [int]$who.ax
  # body: sticker image, or vector outline (white sticker border + ink outline + gradient fill + detail)
  $bodyX = if ($who.image) { $who.image } else {
    "$($who.back)<Path Fill='White' Stroke='White' StrokeThickness='14' StrokeLineJoin='Round'><Path.Data>$($who.g)</Path.Data></Path>
     <Path Stroke='$INK' StrokeThickness='3.5' StrokeLineJoin='Round'><Path.Data>$($who.g)</Path.Data>
      <Path.Fill><LinearGradientBrush StartPoint='0,0' EndPoint='1,0'><GradientStop Color='$($who.c[0])' Offset='0'/><GradientStop Color='$($who.c[1])' Offset='0.35'/><GradientStop Color='$($who.c[2])' Offset='1'/></LinearGradientBrush></Path.Fill></Path>
     $($who.d -replace '\{P\}', $p)" }
  # face styles: eyes = dots (default) | googly ; mouth = smile (default) | lips ; hands = mitt (default) | glove
  $eyesX = if ($who.eyes -eq 'googly') {
    "<Ellipse Canvas.Left='38' Canvas.Top='50' Width='17' Height='21' Fill='White' Stroke='$INK' StrokeThickness='2.5'/><Ellipse Canvas.Left='54' Canvas.Top='48' Width='17' Height='22' Fill='White' Stroke='$INK' StrokeThickness='2.5'/>
     <Ellipse Canvas.Left='46' Canvas.Top='59' Width='7' Height='9' Fill='$INK'/><Ellipse Canvas.Left='56' Canvas.Top='58' Width='7' Height='9' Fill='$INK'/>
     <Ellipse Canvas.Left='48' Canvas.Top='60' Width='2.5' Height='2.5' Fill='White'/><Ellipse Canvas.Left='58' Canvas.Top='59' Width='2.5' Height='2.5' Fill='White'/>" }
    else { "<Ellipse Canvas.Left='43' Canvas.Top='57' Width='9' Height='13' Fill='$INK'/><Ellipse Canvas.Left='46' Canvas.Top='59' Width='3.5' Height='3.5' Fill='White'/>
     <Ellipse Canvas.Left='60' Canvas.Top='57' Width='9' Height='13' Fill='$INK'/><Ellipse Canvas.Left='63' Canvas.Top='59' Width='3.5' Height='3.5' Fill='White'/>" }
  $mouthX = if ($who.mouth -eq 'beak') {   # beak + red wattle
    "<Path Data='M 61,74 Q 67,78 65,88 Q 63,93 59,88 Q 58,80 61,74 Z' Fill='#D7263D' Stroke='$INK' StrokeThickness='1.8'/><Path Data='M 49,73 L 63,73 L 56,82 Z' Fill='#F2A71B' Stroke='$INK' StrokeThickness='2' StrokeLineJoin='Round'/>" }
    elseif ($who.mouth -eq 'lips') {
    "<Path Data='M 44,77 Q 56,90 69,75 Q 66,80 56,81 Q 49,81 44,77 Z' Fill='#D7263D' Stroke='$INK' StrokeThickness='1.8' StrokeLineJoin='Round'/>" }
    else { "<Path Data='M 48,75 L 64,75 Q 63,86 56,86 Q 49,86 48,75 Z' Fill='$INK'/><Path Data='M 51.5,82 Q 56,78.5 60.5,82 Q 58.5,85 56,85 Q 53.5,85 51.5,82 Z' Fill='#E86A6A'/>" }
  $faceVis = if ($who.noFace) { 'Collapsed' } else { 'Visible' }
  $handX = { param($hx) if ($who.hands -eq 'felt') {   # puppet-style felt mitten with a thumb
      $f = if ($who.limb) { $who.limb } else { '#D9A55E' }; $fe = if ($who.limbEdge) { $who.limbEdge } else { '#A87634' }
      "<Ellipse Canvas.Left='$($hx-9)' Canvas.Top='98' Width='18' Height='19' Fill='$f' Stroke='$fe' StrokeThickness='2'/><Ellipse Canvas.Left='$($hx+4)' Canvas.Top='99' Width='8' Height='11' Fill='$f' Stroke='$fe' StrokeThickness='2'/><Line X1='$($hx-4)' Y1='108' X2='$($hx-4)' Y2='114' Stroke='$fe' StrokeThickness='1.3'/><Line X1='$($hx)' Y1='108' X2='$($hx)' Y2='115' Stroke='$fe' StrokeThickness='1.3'/>" }
    elseif ($who.hands -eq 'glove') {
      "<Ellipse Canvas.Left='$($hx-8)' Canvas.Top='99' Width='16' Height='15' Fill='White' Stroke='$INK' StrokeThickness='2.5'/><Line X1='$($hx-5)' Y1='101' X2='$($hx+5)' Y2='101' Stroke='$INK' StrokeThickness='1.5'/>" }
    else { "<Ellipse Canvas.Left='$($hx-6)' Canvas.Top='100' Width='12' Height='12' Fill='$INK'/>" } }
  $seg = { param($x1,$y1,$x2,$y2,$part)   # part: 'w' white underlay, 'i' ink, 'a' arm (ink, or felt if the character has limbColor)
    if ($part -eq 'w') { "<Line X1='$x1' Y1='$y1' X2='$x2' Y2='$y2' Stroke='White' StrokeThickness='17' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>" }
    elseif ($part -eq 'a' -and $who.limb) {   # felt arm: darker edge + color
      "<Line X1='$x1' Y1='$y1' X2='$x2' Y2='$y2' Stroke='$($who.limbEdge)' StrokeThickness='11' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/><Line X1='$x1' Y1='$y1' X2='$x2' Y2='$y2' Stroke='$($who.limb)' StrokeThickness='7.5' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>" }
    else { "<Line X1='$x1' Y1='$y1' X2='$x2' Y2='$y2' Stroke='$INK' StrokeThickness='8' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>" } }
  $arm = { param($s, $sx, $ex, $hx)   # side L/R, shoulder x, elbow x, hand x  (y: 72 -> 89 -> 106)
    $glass = if ($s -eq 'R') { "<Canvas x:Name='${p}Glass' Visibility='Collapsed'><Rectangle Canvas.Left='$($hx-4)' Canvas.Top='96' Width='15' Height='20' RadiusX='2' RadiusY='2' Fill='#E8F6FD' Stroke='$INK' StrokeThickness='2'/><Rectangle Canvas.Left='$($hx-2)' Canvas.Top='104' Width='11' Height='10' Fill='#8FCDEE'/></Canvas>" } else { '' }
    "<Canvas><Canvas.RenderTransform><RotateTransform x:Name='${p}${s}ArmU' CenterX='$sx' CenterY='72'/></Canvas.RenderTransform>
      $(& $seg $sx 72 $ex 89 'w')
      <Canvas><Canvas.RenderTransform><RotateTransform x:Name='${p}${s}ArmF' CenterX='$ex' CenterY='89'/></Canvas.RenderTransform>
        $(& $seg $ex 89 $hx 106 'w') $(& $seg $ex 89 $hx 106 'a')
        $(& $handX $hx)$glass</Canvas>
      $(& $seg $sx 72 $ex 89 'a')</Canvas>" }
  $leg = { param($s, $hx, $kx, $fx, $dir)   # hip x, knee x, foot x; y: 124 -> 138 -> 151 ; dir = shoe points out
    "<Canvas><Canvas.RenderTransform><RotateTransform x:Name='${p}${s}LegU' CenterX='$hx' CenterY='124'/></Canvas.RenderTransform>
      $(& $seg $hx 124 $kx 138 'w')
      <Canvas><Canvas.RenderTransform><RotateTransform x:Name='${p}${s}LegF' CenterX='$kx' CenterY='138'/></Canvas.RenderTransform>
        $(& $seg $kx 138 $fx 151 'w') $(& $seg $kx 138 $fx 151 'i')
        <Ellipse Canvas.Left='$($fx-11+4*$dir)' Canvas.Top='146' Width='22' Height='11' Fill='$INK' Stroke='White' StrokeThickness='2.5'/></Canvas>
      $(& $seg $hx 124 $kx 138 'i')</Canvas>" }
@"
<Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Stretch="Uniform">
 <Canvas Width="110" Height="162">
  <Canvas.Effect><DropShadowEffect Color="#5E544B" BlurRadius="4" ShadowDepth="5" Direction="315" Opacity="0.32"/></Canvas.Effect>
  <Canvas.RenderTransform><TranslateTransform x:Name="${p}RigT"/></Canvas.RenderTransform>
  <Canvas x:Name="${p}Chair" Visibility="Collapsed" Opacity="0.85">
   <Path Data="M 14,90 L 16,142 M 14,140 L 80,140 M 20,140 L 18,162 M 76,140 L 78,162" Stroke="#9C9A96" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
  </Canvas>
  <Canvas><Canvas.RenderTransform><TranslateTransform x:Name="${p}LegsT"/></Canvas.RenderTransform>
   $(& $leg 'L' 44 43 42 -1) $(& $leg 'R' 66 67 68 1)
  </Canvas>
  <Canvas>
   <Canvas.RenderTransform><TransformGroup><ScaleTransform x:Name="${p}UpS" CenterX="55" CenterY="130"/><RotateTransform x:Name="${p}UpR" CenterX="55" CenterY="130"/><TranslateTransform x:Name="${p}UpT"/></TransformGroup></Canvas.RenderTransform>
   $bodyX
   <Canvas Visibility="$faceVis">
    <Canvas.RenderTransform><TransformGroup><ScaleTransform x:Name="${p}FaceS" CenterX="56" CenterY="70"/><TranslateTransform x:Name="${p}FaceT"/></TransformGroup></Canvas.RenderTransform>
    <Ellipse Canvas.Left="33" Canvas.Top="72" Width="13" Height="9" Fill="#F28F84" Opacity="0.85"/>
    <Ellipse Canvas.Left="66" Canvas.Top="72" Width="13" Height="9" Fill="#F28F84" Opacity="0.85"/>
    <Canvas><Canvas.RenderTransform><ScaleTransform x:Name="${p}Eyes" CenterY="62"/></Canvas.RenderTransform>$eyesX</Canvas>
    $mouthX
   </Canvas>
   <Canvas><Canvas.RenderTransform><TranslateTransform x:Name="${p}ArmsT"/></Canvas.RenderTransform>
    $(& $arm 'L' (24+$ax) (22+$ax) (21+$ax)) $(& $arm 'R' (86-$ax) (88-$ax) (89-$ax))
   </Canvas>
  </Canvas>
  <Canvas x:Name="${p}Arrows"/>
 </Canvas>
</Viewbox>
"@
}

# ============ ANIMATION ============
$dp = @{ A=[System.Windows.Media.RotateTransform]::AngleProperty
         X=[System.Windows.Media.TranslateTransform]::XProperty; Y=[System.Windows.Media.TranslateTransform]::YProperty
         SX=[System.Windows.Media.ScaleTransform]::ScaleXProperty; SY=[System.Windows.Media.ScaleTransform]::ScaleYProperty }
# M <element> <property> <keyframe values, evenly spaced> <loop seconds>   (eased, loops forever)
function M($name, $prop, [double[]]$vals, $secs) {
  $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
  $a.Duration = [TimeSpan]::FromSeconds($secs); $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $ease = New-Object System.Windows.Media.Animation.SineEase -Property @{ EasingMode='EaseInOut' }
  for ($i = 0; $i -lt $vals.Count; $i++) {
    $kt = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($secs * $i / ($vals.Count - 1)))
    [void]$a.KeyFrames.Add((New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame -Property @{ Value=$vals[$i]; KeyTime=$kt; EasingFunction=$ease }))
  }
  $script:win.FindName($name).BeginAnimation($dp[$prop], $a)
}
function Alive($p) {   # everyone blinks and breathes
  M "${p}Eyes" SY @(1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0.1,1) 4
  M "${p}UpS" SY @(1,1.015,1) 2.4
  if ($script:win.FindName("${p}Flames")) { M "${p}Flames" SY @(1,1.18,0.9,1.12,0.95,1) .9 } }
function Sit($p) {     # seated on a chair, legs bent toward the viewer's right (like the reference)
  $script:win.FindName("${p}Chair").Visibility = 'Visible'
  M "${p}LLegU" A @(-80,-80) 1; M "${p}LLegF" A @(80,80) 1; M "${p}RLegU" A @(-80,-80) 1; M "${p}RLegF" A @(80,80) 1
  M "${p}UpT" Y @(12,12) 1; M "${p}LegsT" Y @(12,12) 1 }
function Wave($p) { M "${p}RArmU" A @(-140,-140) 1; M "${p}RArmF" A @(-30,15,-30) .9 }
$moves = @{
  thoracic  = { Sit C; M CLArmU A @(150,150) 1; M CLArmF A @(100,100) 1; M CRArmU A @(-150,-150) 1; M CRArmF A @(-100,-100) 1   # hands behind head
                M CUpR A @(0,-12,-12,0) 3; M CFaceT Y @(0,-4,-4,0) 3                                                              # arch back over the chair
                $win.FindName('SideHint').Visibility = 'Visible'; $win.FindName('BackHint').Visibility = 'Visible'
                M HintTorso A @(0,-24,-24,0) 3 }                                                                                  # side view: lean back over the chair top
  drink     = { Sit C; $win.FindName('CGlass').Visibility = 'Visible'
                M CRArmU A @(0,30,30,30,0) 3.5; M CRArmF A @(0,78,78,78,0) 3.5; M CFaceT Y @(0,0,-2,-2,0) 3.5 }                    # glass to mouth, sip
  drink2    = { & $moves.drink }
  chin      = { Sit C; M CFaceS SX @(1,.88,.88,1) 2.5; M CFaceS SY @(1,.88,.88,1) 2.5; M CFaceT Y @(0,3,3,0) 2.5            # face pulls back
                $win.FindName('SideHint').Visibility = 'Visible'; $win.FindName('ChinHint').Visibility = 'Visible'
                M HintHead X @(0,-7,-7,0) 2.5 }                                                                                   # side view: head slides straight back
  neck      = { Sit C; M CUpR A @(0,-16,-16,0,16,16,0) 6
                M CLArmU A @(0,0,0,0,160,160,0) 6; M CLArmF A @(0,0,0,0,70,70,0) 6
                M CRArmU A @(0,-160,-160,0,0,0,0) 6; M CRArmF A @(0,-70,-70,0,0,0,0) 6 }                                        # tilt + hand over head
  stand     = { $win.FindName('CChair').Visibility = 'Visible'
                M CLLegU A @(-80,-80,0,0,-80) 4; M CLLegF A @(80,80,0,0,80) 4; M CRLegU A @(-80,-80,0,0,-80) 4; M CRLegF A @(80,80,0,0,80) 4
                M CUpT Y @(12,12,0,0,12) 4; M CLegsT Y @(12,12,0,0,12) 4
                M CLArmU A @(0,0,160,160,0) 4; M CRArmU A @(0,0,-160,-160,0) 4 }                                                # sit -> stand tall, arms up
  shoulders = { Sit C; M CArmsT Y @(0,-10,-10,0,0) 2; M CUpS SY @(1,1.04,1.04,1,1) 2 }                                          # shrug up, back, down
  walk      = { M CLLegU A @(-22,22,-22) 1; M CLLegF A @(0,28,0) 1; M CRLegU A @(22,-22,22) 1; M CRLegF A @(28,0,28) 1
                M CLArmU A @(20,-20,20) 1; M CRArmU A @(20,-20,20) 1
                M CUpT Y @(0,-3,0) .5; M CRigT X @(-12,12,-12) 5 }                                                                # stroll back and forth
  eyes      = { Sit C; M CRArmU A @(-160,-160) 1; M CRArmF A @(-75,-75) 1                                                       # hand shades the eyes
                M CFaceT X @(0,0,-5,-5,0,5,5,0) 5 }                                                                               # look far left / right
  wrists    = { Sit C; M CLArmU A @(90,90) 1; M CRArmU A @(-90,-90) 1                                                           # arms out
                M CLArmF A @(0,-45,-45,0,40,40,0) 3; M CRArmF A @(0,45,45,0,-40,-40,0) 3 }                                       # hands flex back / down
  twist     = { Sit C; M CUpS SX @(1,.86,.86,1,.86,.86,1) 5; M CFaceT X @(0,-8,-8,0,8,8,0) 5
                M CLArmU A @(0,40,40,0,0,0,0) 5; M CRArmU A @(0,0,0,0,-40,-40,0) 5 }                                             # turn left, then right
  breathe   = { Sit C; M CUpS SX @(1,1.06,1.06,1) 5; M CUpS SY @(1,1.05,1.05,1) 5
                M CLArmU A @(0,25,25,0) 5; M CRArmU A @(0,-25,-25,0) 5 }                                                          # in for 4, out for 6
  neckturn  = { Sit C; M CFaceT X @(0,-9,-9,0,9,9,0) 5; M CFaceS SX @(1,.86,.86,1,.86,.86,1) 5 }                          # look over one shoulder, then the other
  armsout   = { Sit C; M CLArmU A @(90,90) 1; M CRArmU A @(-90,-90) 1                                                       # arms straight out to the sides
                M CArmsT X @(0,0) 1; M CLArmF A @(0,-6,0) 2; M CRArmF A @(0,6,0) 2; M CUpS SX @(1,1.04,1) 2 }                 # reach long, chest opens
  wander    = { M CUpS SX @(1,1,-1,-1,1,1) 6                                                                                  # turn around (and back)
                M CLLegU A @(-20,20,-20) 1; M CLLegF A @(0,25,0) 1; M CRLegU A @(20,-20,20) 1; M CRLegF A @(25,0,25) 1
                M CUpT Y @(0,-3,0) .5; M CRigT X @(-10,10,-10) 6 }                                                            # and stroll a few steps
  shake     = { Sit C; M CLArmU A @(20,20) 1; M CRArmU A @(-20,-20) 1                                                       # arms hang loose
                M CLArmF A @(-22,22,-22) .22; M CRArmF A @(22,-22,22) .22; M CArmsT Y @(0,-2,0) .22 }                         # quick gentle shake
  calves    = { M CRigT Y @(0,-9,-9,0,0) 1.6; M CLLegF A @(0,-8,-8,0,0) 1.6; M CRLegF A @(0,8,8,0,0) 1.6 }                    # up on toes, down
}

# Motion arrows: small orange arrows that pulse in the direction to move. @(x, y, angle) in rig coordinates
# (110x162 box; angle 0 = right, 90 = down, 180 = left, -90 = up).
$arrowsFor = @{
  neck     = @(@(12,20,135), @(98,20,45))             # tilt ear to shoulder, each side
  shoulders = @(@(8,66,-90), @(102,66,-90))            # shrug up
  twist     = @(@(4,92,180), @(106,92,0))              # turn each way
  wrists    = @(@(2,52,90), @(108,52,90))              # hands flex down
  stand     = @(,@(104,100,-90))                       # get up
  calves    = @(,@(100,136,-90))                       # onto your toes
  walk      = @(,@(96,152,0))                          # off you go
  eyes      = @(,@(96,56,0))                           # look far away
  breathe   = @(@(2,96,180), @(108,96,0))              # chest expands
  neckturn  = @(@(14,44,180), @(96,44,0))              # turn head left / right
  armsout   = @(@(2,58,180), @(108,58,0))              # reach out wide
  wander    = @(,@(96,152,0))                          # off you go
}                                                      # (no arrows for drinking: not a body movement)
$showArrows = {
  # one arrow per movement: if a side-view bubble explains it, no arrows on the character
  # (chin and thoracic have bubbles, so they have no entries above)
  $layer = $win.FindName('CArrows'); if (-not $layer) { return }
  if ($win.FindName('SideHint').Visibility -eq 'Visible') { $Card.Width = 510; return }   # make room for the bubble
  foreach ($a in $arrowsFor[$ex.k]) {
    $pth = New-Object System.Windows.Controls.Canvas   # white outline under orange: visible on any character
    foreach ($st2 in @('White', 7.5), @('#E8662A', 3.4)) {
      [void]$pth.Children.Add((New-Object System.Windows.Shapes.Path -Property @{ Stroke = $st2[0]; StrokeThickness = $st2[1]
             StrokeStartLineCap = 'Round'; StrokeEndLineCap = 'Round'; StrokeLineJoin = 'Round'
             Data = [System.Windows.Media.Geometry]::Parse('M -8,0 L 8,0 M 2,-6 L 8,0 L 2,6') })) }
    [System.Windows.Controls.Canvas]::SetLeft($pth, $a[0]); [System.Windows.Controls.Canvas]::SetTop($pth, $a[1])
    $tt = New-Object System.Windows.Media.TranslateTransform
    $tg = New-Object System.Windows.Media.TransformGroup
    $tg.Children.Add((New-Object System.Windows.Media.RotateTransform($a[2]))); $tg.Children.Add($tt); $pth.RenderTransform = $tg
    [void]$layer.Children.Add($pth)
    $rad = $a[2] * [math]::PI / 180
    foreach ($pr in @(@([System.Windows.Media.TranslateTransform]::XProperty, [math]::Cos($rad)), @([System.Windows.Media.TranslateTransform]::YProperty, [math]::Sin($rad)))) {
      $an = New-Object System.Windows.Media.Animation.DoubleAnimation(0, (5 * $pr[1]), [TimeSpan]::FromSeconds(0.6)) -Property @{ AutoReverse = $true
              RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
              EasingFunction = (New-Object System.Windows.Media.Animation.SineEase -Property @{ EasingMode = 'EaseInOut' }) }
      $tt.BeginAnimation($pr[0], $an) }
  }
}

# ============ SNAPSHOTS (testing) ============
function Save-Frame($n) {
  $el = $script:win.Content; $w = $el.ActualWidth; $h = $el.ActualHeight
  # draw through a VisualBrush: rendering a right-to-left element directly comes out mirrored
  $dv = New-Object System.Windows.Media.DrawingVisual; $ctx = $dv.RenderOpen()
  if ($script:win.FlowDirection -eq 'RightToLeft') { $ctx.PushTransform((New-Object System.Windows.Media.ScaleTransform(-1, 1, ($w/2), 0))) }
  $ctx.DrawRectangle((New-Object System.Windows.Media.VisualBrush $el), $null, (New-Object System.Windows.Rect(0, 0, $w, $h))); $ctx.Close()
  $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]($w*1.5)), ([int]($h*1.5)), 144, 144, ([System.Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($dv)
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [IO.File]::Create("$Snap-$n.png"); $enc.Save($fs); $fs.Close() }
function Start-Snaps([double[]]$at) {   # save a frame at each time (s), then close
  $script:snapAt = $at; $script:snapN = 0; $script:snapT0 = Get-Date
  $t = New-Object System.Windows.Threading.DispatcherTimer -Property @{ Interval=[TimeSpan]::FromMilliseconds(50) }
  $t.Add_Tick({ if (((Get-Date) - $script:snapT0).TotalSeconds -ge $script:snapAt[$script:snapN]) {
      Save-Frame $script:snapN; $script:snapN++; if ($script:snapN -ge $script:snapAt.Count) { $script:win.Close() } } })
  $t.Start() }

# ============ GALLERY (character picker) ============
if ($Gallery) {
  $L = $I.($st.lang)
  $script:sel = if ($whoSet) { $whoSet } else { 'random' }
  $esc = { param($s) [Security.SecurityElement]::Escape("$s") }
  $script:nTiles = 0
  function Tile($tag, $art, $name, $w = 122, $h = 170, $ah = 120) { $script:nTiles++
    "<Border x:Name='Tile$($script:nTiles)' Tag='$tag' Width='$w' Height='$h' Margin='4' Padding='5' CornerRadius='16' Background='#F4F1EC' BorderThickness='3' Cursor='Hand'>
      <StackPanel><Border Height='$ah' Padding='4'>$art</Border>
      <TextBlock Text='$(& $esc $name)' TextAlignment='Center' TextWrapping='Wrap' FontSize='12' FontWeight='SemiBold' Foreground='#1A1A1A' Margin='0,3,0,0'/></StackPanel></Border>" }
  # "random" tile art: two chunky crossing shuffle arrows (ink + color), white gap where they cross
  $dice = { param($c) "<Viewbox Margin='10'><Canvas Width='104' Height='84'>
    <Path Data='M 10,64 L 26,64 C 48,64 52,22 74,22 L 82,22' Stroke='$INK' StrokeThickness='11' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>
    <Path Data='M 80,8 L 96,22 L 80,36 Z' Fill='$INK' Stroke='$INK' StrokeThickness='6' StrokeLineJoin='Round'/>
    <Path Data='M 10,22 L 26,22 C 48,22 52,64 74,64 L 82,64' Stroke='White' StrokeThickness='19' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>
    <Path Data='M 10,22 L 26,22 C 48,22 52,64 74,64 L 82,64' Stroke='$c' StrokeThickness='11' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>
    <Path Data='M 80,50 L 96,64 L 80,78 Z' Fill='$c' Stroke='$c' StrokeThickness='6' StrokeLineJoin='Round'/>
  </Canvas></Viewbox>" }
  # one full-width row per section, so every category header lines up
  $section = { param($title, $row)
    $hdr = if ($title) { "<TextBlock Text='$(& $esc $title)' FontSize='15' FontWeight='Bold' Foreground='#1A1A1A' Margin='4,0,0,2'/>" } else { '' }
    "<StackPanel Margin='0,8,0,0'>$hdr<WrapPanel>$row</WrapPanel></StackPanel>" }
  # "feeling lucky" (anyone at all) = two tumbling dice; per-kit random = shuffle arrows
  $pips = { param($pts) ($pts | % { "<Ellipse Canvas.Left='$($_[0]-5)' Canvas.Top='$($_[1]-5)' Width='10' Height='10' Fill='$INK'/>" }) -join '' }
  $lucky = "<Viewbox Margin='8'><Canvas Width='110' Height='110'>
    <Canvas><Canvas.RenderTransform><RotateTransform x:Name='Dice1' Angle='-22' CenterX='34' CenterY='36'/></Canvas.RenderTransform>
      <Rectangle Canvas.Left='8' Canvas.Top='10' Width='52' Height='52' RadiusX='10' RadiusY='10' Fill='#F3F1F7' Stroke='$INK' StrokeThickness='5'/>
      <Rectangle Canvas.Left='34' Canvas.Top='13' Width='23' Height='46' Fill='#C4D5EE'/>
      $(& $pips (@(24,27),@(44,45)))</Canvas>
    <Canvas><Canvas.RenderTransform><RotateTransform x:Name='Dice2' Angle='0' CenterX='74' CenterY='76'/></Canvas.RenderTransform>
      <Rectangle Canvas.Left='48' Canvas.Top='50' Width='52' Height='52' RadiusX='10' RadiusY='10' Fill='#F3F1F7' Stroke='$INK' StrokeThickness='5'/>
      <Rectangle Canvas.Left='74' Canvas.Top='53' Width='23' Height='46' Fill='#C4D5EE'/>
      $(& $pips (@(63,65),@(85,65),@(63,87),@(85,87)))</Canvas>
  </Canvas></Viewbox>"
  $body = & $section '' (Tile 'random' $lucky $L.ui.random)   # "feeling lucky" sits alone on the first row
  $first = @($pinned) + @('streetfood', 'hanukkah', 'thanksgiving')   # packs marked "first", then the built-in order
  $kits = @($first) + @($cast | % { $_.kit } | Select-Object -Unique | ? { $_ -notin $first })
  foreach ($kit in $kits) {     # one section per kit
    $kname = Get-KitName $kit $L
    $row = Tile "kit:$kit" (& $dice '#C2A15A') ($L.ui.randomKit -f $kname)
    for ($i = 0; $i -lt $cast.Count; $i++) { if ($cast[$i].kit -eq $kit) {
      $tag = if ($cast[$i].id) { $cast[$i].id } else { "$i" }   # pack characters are saved by id, built-ins by index
      $row += Tile $tag (New-Noodle "G$i" $cast[$i]) (Get-Name $i $L) } }
    $body += & $section $kname $row
  }
  $tiles = $body

  # ============ FIRST-RUN WIZARD: 1 character -> 2 reminder types -> 3 timing + sound. Skip / X keep the defaults ============
  if ($Setup) {
    $u = $L.ui
    # step 1 shows EVERY character in one compact grid (no section titles), so you can see there are many to choose from
    $wizStart = $script:nTiles + 1
    $grid = Tile 'random' $lucky $u.random 100 152 96
    $nChars = 0
    foreach ($kit in $kits) { for ($i = 0; $i -lt $cast.Count; $i++) { if ($cast[$i].kit -eq $kit) {
      $tag = if ($cast[$i].id) { $cast[$i].id } else { "$i" }
      $grid += Tile $tag (New-Noodle "G$i" $cast[$i]) (Get-Name $i $L) 100 152 96; $nChars++ } } }
    $tiles = "<WrapPanel>$grid</WrapPanel>"
    $catOrder = 'stretch', 'water', 'move', 'eyes'
    $catIcon = @{ stretch = '&#x1F938;'; water = '&#x1F4A7;'; move = '&#x1F6B6;'; eyes = '&#x1F440;' }
    $chk = { param($n) "<Border x:Name='$n' Width='24' Height='24' CornerRadius='12' BorderThickness='2' VerticalAlignment='Center'><TextBlock Text='&#x2713;' Foreground='White' FontWeight='Bold' FontSize='13' HorizontalAlignment='Center' VerticalAlignment='Center'/></Border>" }
    $typeCards = ($catOrder | % { "<Border x:Name='Type_$_' Tag='$_' Margin='6' Padding='14,12' CornerRadius='16' BorderThickness='2' Cursor='Hand'><DockPanel>
        <ContentControl DockPanel.Dock='Right'>$(& $chk "Chk_$_")</ContentControl>
        <TextBlock DockPanel.Dock='Left' Text='$($catIcon[$_])' FontFamily='Segoe UI Emoji' FontSize='26' VerticalAlignment='Center' Margin='0,0,12,0'/>
        <StackPanel><TextBlock Text='$(& $esc $u.cats.$_)' FontSize='16' FontWeight='Bold' Foreground='#1A1A1A'/>
        <TextBlock Text='$(& $esc $u.catDesc.$_)' FontSize='12.5' Foreground='#777' TextWrapping='Wrap'/></StackPanel></DockPanel></Border>" }) -join ''
    $freqOpts = 30, 45, 60, 90, 120
    $freqPills = (0..4 | % { "<Border x:Name='Freq_$($freqOpts[$_])' Tag='$($freqOpts[$_])' Margin='6,3' Padding='16,9' CornerRadius='12' BorderThickness='2' Cursor='Hand'>
        <TextBlock Text='$(& $esc $u.freq[$_])' FontSize='14.5' FontWeight='SemiBold' Foreground='#1A1A1A'/></Border>" }) -join ''
    [xml]$wx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Topmost="True" FontFamily="Segoe UI" Title="Stretch Buddy">
 <Grid Margin="20">
  <Border Background="White" CornerRadius="24" Padding="26,22,26,20">
   <Border.Effect><DropShadowEffect BlurRadius="26" ShadowDepth="3" Opacity="0.22"/></Border.Effect>
   <StackPanel Width="800">
    <DockPanel x:Name="Hdr" Background="Transparent">
     <Border DockPanel.Dock="Left" Width="96" Height="108" Background="#F1EBE2" CornerRadius="18" Padding="6">$(New-Noodle 'H' $cast[$whoIdx])</Border>
     <StackPanel Margin="18,8,30,0" VerticalAlignment="Center">
      <TextBlock Text="$(& $esc $u.setupTitle)" FontSize="27" FontWeight="Bold" Foreground="#1A1A1A"/>
      <TextBlock Text="$(& $esc $u.setupSub)" FontSize="14" Foreground="#6B645D" TextWrapping="Wrap" Margin="0,4,0,0"/>
     </StackPanel>
    </DockPanel>
    <StackPanel Orientation="Horizontal" Margin="0,20,0,2">
     <Ellipse x:Name="Dot1" Width="11" Height="11" Margin="0,0,6,0"/><Ellipse x:Name="Dot2" Width="11" Height="11" Margin="0,0,6,0"/><Ellipse x:Name="Dot3" Width="11" Height="11"/>
     <TextBlock x:Name="StepTitle" FontSize="19" FontWeight="Bold" Foreground="#1A1A1A" Margin="12,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock x:Name="StepSub" FontSize="13" Foreground="#888" Margin="0,2,0,8"/>
    <Grid Height="370">
     <ScrollViewer x:Name="P1" VerticalScrollBarVisibility="Auto"><StackPanel>$tiles</StackPanel></ScrollViewer>
     <UniformGrid x:Name="P2" Columns="2" Visibility="Collapsed" VerticalAlignment="Top">$typeCards</UniformGrid>
     <Grid x:Name="P3" Visibility="Collapsed">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <StackPanel>$freqPills</StackPanel>
      <Border x:Name="SoundT" Grid.Column="1" Margin="18,3,6,0" Padding="16,14" CornerRadius="16" BorderThickness="2" Cursor="Hand" VerticalAlignment="Top"><DockPanel>
        <ContentControl DockPanel.Dock="Right">$(& $chk 'Chk_sound')</ContentControl>
        <TextBlock DockPanel.Dock="Left" Text="&#x1F514;" FontFamily="Segoe UI Emoji" FontSize="26" VerticalAlignment="Center" Margin="0,0,12,0"/>
        <StackPanel><TextBlock Text="$(& $esc $u.sound)" FontSize="16" FontWeight="Bold" Foreground="#1A1A1A"/>
        <TextBlock Text="$(& $esc $u.soundSub)" FontSize="12.5" Foreground="#777" TextWrapping="Wrap"/></StackPanel></DockPanel></Border>
     </Grid>
    </Grid>
    <DockPanel Margin="0,16,0,0">
     <TextBlock x:Name="Skip" DockPanel.Dock="Left" Text="$(& $esc $u.skip)" Foreground="#8A8178" FontSize="14.5" VerticalAlignment="Center" Cursor="Hand" TextDecorations="Underline"/>
     <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Back" Content="$(& $esc $u.back)" Background="#ECEAE6" Foreground="#1A1A1A" FontSize="14.5" FontWeight="SemiBold" Cursor="Hand" Margin="0,0,10,0">
       <Button.Template><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="18" Padding="22,9"><ContentPresenter HorizontalAlignment="Center"/></Border></ControlTemplate></Button.Template></Button>
      <Button x:Name="Next" Background="#1A1A1A" Foreground="White" FontSize="14.5" FontWeight="SemiBold" Cursor="Hand">
       <Button.Template><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="18" Padding="26,9"><ContentPresenter HorizontalAlignment="Center"/></Border></ControlTemplate></Button.Template></Button>
     </StackPanel>
    </DockPanel>
   </StackPanel>
  </Border>
  <Border x:Name="WX" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-9,-9,0" Width="28" Height="28" CornerRadius="14" Background="White" BorderBrush="#E4DED6" BorderThickness="1" Cursor="Hand">
   <Border.Effect><DropShadowEffect BlurRadius="6" ShadowDepth="1" Opacity="0.25"/></Border.Effect>
   <TextBlock Text="&#x2715;" FontSize="12" FontWeight="Bold" Foreground="#8A8178" HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
 </Grid>
</Window>
"@
    $script:win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $wx))
    if ($L.rtl) { $win.FlowDirection = 'RightToLeft' }
    $F = { param($n) $win.FindName($n) }
    $ACC = '#D9541E'; $NOPE = 'Transparent'   # (not $on/$off: PowerShell names ignore case)
    # current choices (start from defaults / existing settings)
    $script:sel = $whoSet
    if ($script:sel -like 'kit:*') { $m = @($cast | ? { $_.kit -eq $script:sel.Substring(4) }); if ($m.Count -eq 1 -and $m[0].id) { $script:sel = $m[0].id } }
    $script:on = @{}; foreach ($c in $catOrder) { $script:on[$c] = ($weights[$c] -gt 0) }
    $script:on.eyes = $true   # first run: everything on, uncheck what you don't want
    $script:every = if ($j -and [int]$j.every -gt 0) { [int]$j.every } else { 45 }
    $script:sound = -not $script:muted
    function Paint-Card($card, $chkName, $isOn) {
      $card.BorderBrush = if ($isOn) { $ACC } else { $NOPE }; $card.Background = if ($isOn) { '#FFF4EC' } else { '#F4F1EC' }
      $c = & $F $chkName; $c.Background = if ($isOn) { '#2EA44F' } else { 'White' }; $c.BorderBrush = if ($isOn) { '#2EA44F' } else { '#CFC7BD' } }
    function Paint-All {
      foreach ($c in $catOrder) { Paint-Card (& $F "Type_$c") "Chk_$c" $script:on[$c] }
      foreach ($m in $freqOpts) { $b = & $F "Freq_$m"; $isOn = ($m -eq $script:every)
        $b.BorderBrush = if ($isOn) { $ACC } else { $NOPE }; $b.Background = if ($isOn) { '#FFF4EC' } else { '#F4F1EC' } }
      Paint-Card (& $F 'SoundT') 'Chk_sound' $script:sound }
    $tileEls = $wizStart..$script:nTiles | % { $win.FindName("Tile$_") }
    function Show-Sel { foreach ($t in $tileEls) { $t.BorderBrush = if ($t.Tag -eq $script:sel) { $ACC } else { $NOPE } } }
    foreach ($t in $tileEls) { $t.Add_MouseLeftButtonUp({ param($s) $script:sel = $s.Tag; Show-Sel }) }
    foreach ($c in $catOrder) { (& $F "Type_$c").Add_MouseLeftButtonUp({ param($s) $script:on[$s.Tag] = -not $script:on[$s.Tag]; Paint-All }) }
    foreach ($m in $freqOpts) { (& $F "Freq_$m").Add_MouseLeftButtonUp({ param($s) $script:every = [int]$s.Tag; Paint-All }) }
    (& $F 'SoundT').Add_MouseLeftButtonUp({ $script:sound = -not $script:sound; Paint-All })
    $script:step = 1
    function Show-Step {
      foreach ($k in 1..3) { (& $F "P$k").Visibility = if ($k -eq $script:step) { 'Visible' } else { 'Collapsed' }
                             (& $F "Dot$k").Fill = if ($k -le $script:step) { $ACC } else { '#E3DCD3' } }
      (& $F 'StepTitle').Text = $u."step$($script:step)"; (& $F 'StepSub').Text = $u."step$($script:step)sub" -f $nChars
      (& $F 'Back').Visibility = if ($script:step -gt 1) { 'Visible' } else { 'Collapsed' }
      (& $F 'Next').Content = if ($script:step -lt 3) { $u.next } else { $u.finish } }
    function Close-Setup($save) {
      if ($save) {
        $t = @{}; foreach ($c in $catOrder) { $t[$c] = if ($script:on[$c]) { @{ stretch = 2; water = 2; move = 1; eyes = 1 }[$c] } else { 0 } }
        Save-State @{ who = $script:sel; types = $t; every = $script:every; mute = (-not $script:sound); setupDone = $true }
      } else { Save-State @{ setupDone = $true } }   # skip: keep the defaults
      $win.Close() }
    (& $F 'Next').Add_Click({ if ($script:step -lt 3) { $script:step++; Show-Step } else { Close-Setup $true } })
    (& $F 'Back').Add_Click({ if ($script:step -gt 1) { $script:step--; Show-Step } })
    (& $F 'Skip').Add_MouseLeftButtonUp({ Close-Setup $false })
    (& $F 'WX').Add_MouseLeftButtonUp({ Close-Setup $false })
    (& $F 'Hdr').Add_MouseLeftButtonDown({ $win.DragMove() })
    Show-Sel; Paint-All; Show-Step
    $win.Add_Loaded({ Alive H; Wave H; for ($i = 0; $i -lt $cast.Count; $i++) { Alive "G$i"; Wave "G$i" }
      M Dice1 A @(-22,-22,-8,-30,-22) 2.6; M Dice2 A @(0,0,12,-6,0) 2.6 })
    if ($Snap) {   # test: one frame per step
      $script:snapStep = 0; $tt = New-Object System.Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(1.2) }
      $tt.Add_Tick({ Save-Frame $script:snapStep; $script:snapStep++
        if ($script:snapStep -ge 3) { $win.Close() } else { $script:step = $script:snapStep + 1; Show-Step } }); $tt.Start() }
    $win.ShowDialog() | Out-Null
    return
  }

  [xml]$gx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$([Security.SecurityElement]::Escape($L.ui.chooseChar))" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Topmost="True" Background="White" FontFamily="Segoe UI">
 <StackPanel Margin="22">
  <TextBlock Text="$([Security.SecurityElement]::Escape($L.ui.castKicker))" FontSize="11" FontWeight="Bold" Foreground="#C2410C"/>
  <TextBlock Text="$([Security.SecurityElement]::Escape($L.ui.castTitle))" FontSize="30" FontWeight="Bold" Foreground="#1A1A1A"/>
  <TextBlock Text="$([Security.SecurityElement]::Escape($L.ui.castSub))" FontSize="13" Foreground="#666" Margin="0,2,0,12"/>
  <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="700"><StackPanel Width="950">$tiles</StackPanel></ScrollViewer>
 </StackPanel>
</Window>
"@
  $script:win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $gx))
  if ($L.rtl) { $win.FlowDirection = 'RightToLeft' }
  $tileEls = 1..$script:nTiles | % { $win.FindName("Tile$_") }
  function Show-Sel { foreach ($t in $tileEls) { $t.BorderBrush = if ($t.Tag -eq $script:sel) { '#D9541E' } else { 'Transparent' } } }
  foreach ($t in $tileEls) { $t.Add_MouseLeftButtonUp({ param($s) $script:sel = $s.Tag; Save-State @{ who = $s.Tag }; Show-Sel }) }
  Show-Sel
  $win.Add_Loaded({ for ($i = 0; $i -lt $cast.Count; $i++) { Alive "G$i"; Wave "G$i" }
    M Dice1 A @(-22,-22,-8,-30,-22) 2.6; M Dice2 A @(0,0,12,-6,0) 2.6 })   # dice give a little shake now and then
  if ($Snap) { Start-Snaps @(1.0) }
  $win.ShowDialog() | Out-Null
  return
}

# ============ REMINDER POPUP ============
$pill = @'
<ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="14" Padding="14,5">
 <ContentPresenter HorizontalAlignment="Center"/></Border></ControlTemplate>
'@

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize" FontFamily="Segoe UI">
 <Grid Margin="14">
  <!-- intro toast -->
  <Border x:Name="Toast" Background="White" CornerRadius="18" Padding="12" Width="370">
   <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="2" Opacity="0.18"/></Border.Effect>
   <StackPanel Orientation="Horizontal">
    <Border Background="#F4F1EC" CornerRadius="12" Width="86" Height="86" Padding="6">$(New-Noodle 'T' $cast[$whoIdx])</Border>
    <StackPanel Margin="16,0,0,0" VerticalAlignment="Center">
     <TextBlock x:Name="TimeTo" FontSize="15" FontWeight="SemiBold" Foreground="#1A1A1A"/>
     <TextBlock x:Name="Word" FontSize="30" FontWeight="Bold" Foreground="#D9541E" Margin="0,-4,0,0"/>
     <Path Data="M 0,3 Q 6,0 12,3 T 24,3 T 36,3 T 48,3 T 60,3 T 72,3 T 84,3 T 96,3" Stroke="#D9541E" StrokeThickness="2" Margin="0,-2,0,2" HorizontalAlignment="Left"/>
     <TextBlock x:Name="Sub" FontSize="12" Foreground="#777" TextWrapping="Wrap" Width="240"/>
    </StackPanel>
   </StackPanel>
  </Border>
  <!-- exercise card -->
  <Border x:Name="Card" Visibility="Collapsed" Background="White" CornerRadius="18" Width="440">
   <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="2" Opacity="0.18"/></Border.Effect>
   <Grid>
    <Grid Margin="12">
     <Grid.ColumnDefinitions><ColumnDefinition Width="120"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
     <Border Background="#F1EBE2" CornerRadius="14" Padding="8" Height="136" VerticalAlignment="Top">$(New-Noodle 'C' $cast[$whoIdx])</Border>
      <!-- side-view hint: small bubble BESIDE the character (never covering it), for moves a front view can't show -->
      <Border x:Name="SideHint" Grid.Column="1" Visibility="Collapsed" Width="64" Height="64" CornerRadius="32" Background="White" BorderBrush="#E0D8CE" BorderThickness="1.5"
              HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="8,0,0,6" ToolTip="Side view">
       <Border.Effect><DropShadowEffect BlurRadius="5" ShadowDepth="1" Opacity="0.2"/></Border.Effect>
       <Viewbox Margin="5"><Grid Width="60" Height="60">
        <Canvas x:Name="ChinHint" Visibility="Collapsed">
         <Path Data="M 12,60 Q 14,46 24,42 L 40,42 Q 50,46 50,60 Z" Fill="#F5BE52" Stroke="$INK" StrokeThickness="2"/>
         <Rectangle Canvas.Left="28" Canvas.Top="30" Width="9" Height="14" Fill="#F5BE52" Stroke="$INK" StrokeThickness="2"/>
         <Ellipse Canvas.Left="23" Canvas.Top="10" Width="24" Height="24" Stroke="#B0A79C" StrokeThickness="1.5" StrokeDashArray="2 2"/>
         <Canvas><Canvas.RenderTransform><TranslateTransform x:Name="HintHead"/></Canvas.RenderTransform>
          <Ellipse Canvas.Left="23" Canvas.Top="10" Width="24" Height="24" Fill="#F5BE52" Stroke="$INK" StrokeThickness="2"/>
          <Ellipse Canvas.Left="44" Canvas.Top="18" Width="6" Height="6" Fill="#F5BE52" Stroke="$INK" StrokeThickness="1.6"/>
          <Ellipse Canvas.Left="38" Canvas.Top="17" Width="3.5" Height="4.5" Fill="$INK"/>
         </Canvas>
         <Path Data="M 46,5 L 24,5 M 30,0 L 24,5 L 30,10" Stroke="White" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
         <Path Data="M 46,5 L 24,5 M 30,0 L 24,5 L 30,10" Stroke="#E8662A" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
        </Canvas>
        <Canvas x:Name="BackHint" Visibility="Collapsed">
         <Path Data="M 12,22 L 12,58 M 12,44 L 42,44 M 40,44 L 40,58" Stroke="#9C9A96" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
         <Path Data="M 22,44 L 40,44 L 42,58" Stroke="$INK" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
         <Canvas><Canvas.RenderTransform><RotateTransform x:Name="HintTorso" CenterX="22" CenterY="44"/></Canvas.RenderTransform>
          <Line X1="22" Y1="44" X2="22" Y2="20" Stroke="#F5BE52" StrokeThickness="9" StrokeStartLineCap="Round"/>
          <Line X1="22" Y1="44" X2="22" Y2="20" Stroke="$INK" StrokeThickness="1.5" Opacity="0.4"/>
          <Ellipse Canvas.Left="14" Canvas.Top="4" Width="16" Height="16" Fill="#F5BE52" Stroke="$INK" StrokeThickness="2"/>
          <Path Data="M 22,24 L 34,16 L 27,8" Stroke="$INK" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
         </Canvas>
         <Path Data="M 44,10 Q 36,0 24,0" Stroke="White" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
         <Path Data="M 44,10 Q 36,0 24,0 M 29,-4 L 24,0 L 29,5" Stroke="#E8662A" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
        </Canvas>
       </Grid></Viewbox>
      </Border>
     <StackPanel Grid.Column="2" Margin="14,2,4,0">
      <DockPanel>
       <TextBlock x:Name="Count" DockPanel.Dock="Right" FontSize="12" Foreground="#888" VerticalAlignment="Center"/>
       <TextBlock x:Name="Title" FontSize="17" FontWeight="Bold" Foreground="#1A1A1A"/>
      </DockPanel>
      <TextBlock x:Name="Desc" FontSize="13" Foreground="#555" TextWrapping="Wrap" Margin="0,3,0,0"/>
      <TextBlock x:Name="Amount" FontSize="13" FontWeight="SemiBold" Foreground="#C2410C" Margin="0,4,0,0"/>
      <TextBlock x:Name="HowText" Visibility="Collapsed" FontSize="12" Foreground="#555" TextWrapping="Wrap" Margin="0,6,0,0"/>
      <TextBlock x:Name="Tip" FontSize="11.5" FontStyle="Italic" Foreground="#8A7F72" TextWrapping="Wrap" Margin="0,6,0,0"/>
      <StackPanel x:Name="Success" Orientation="Horizontal" Visibility="Collapsed" Margin="0,10,0,2">
       <Grid Width="20" Height="20"><Ellipse Fill="#2EA44F"/><Path Data="M 5,10.5 L 8.5,14 L 15,6.5" Stroke="White" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/></Grid>
       <TextBlock x:Name="SuccessText" FontSize="14" FontWeight="SemiBold" Foreground="#1F7A3A" Margin="8,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <DockPanel x:Name="Actions" Margin="0,8,0,0">
       <TextBlock x:Name="How" DockPanel.Dock="Right" FontSize="13" FontWeight="SemiBold" Foreground="#333" VerticalAlignment="Center" Cursor="Hand"/>
       <StackPanel Orientation="Horizontal">
        <Button x:Name="Primary" Background="#1A1A1A" Foreground="White" FontWeight="SemiBold" FontSize="13" Cursor="Hand" BorderThickness="0">
         <Button.Template>$pill</Button.Template></Button>
       </StackPanel>
      </DockPanel>
     </StackPanel>
    </Grid>
    <Border VerticalAlignment="Bottom" Height="4" CornerRadius="0,0,18,18" ClipToBounds="True">
     <Rectangle x:Name="Bar" Fill="#E8662A" HorizontalAlignment="Left" Width="0"/>
    </Border>
   </Grid>
  </Border>
  <!-- confetti layer (on top, never catches clicks) -->
  <Canvas x:Name="Fx" IsHitTestVisible="False" ClipToBounds="True" Margin="-14"/>
  <!-- close (x): round badge over the card's corner above the character (left in English, right in Hebrew - follows FlowDirection) -->
  <Border x:Name="CloseX" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="-9,-9,0,0" Width="24" Height="24" CornerRadius="12"
          Background="White" BorderBrush="#E4DED6" BorderThickness="1" Cursor="Hand" ToolTip="Close">
   <Border.Effect><DropShadowEffect BlurRadius="6" ShadowDepth="1" Opacity="0.25"/></Border.Effect>
   <TextBlock Text="&#x2715;" FontSize="11" FontWeight="Bold" Foreground="#8A8178" HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
 </Grid>
</Window>
"@

$script:win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
'TimeTo','Word','Sub','Toast','Card','Count','Title','Desc','Amount','HowText','Tip','How','Primary','Bar','Success','SuccessText','Actions','Fx' |
  ForEach-Object { Set-Variable -Name $_ -Value $win.FindName($_) }
$tipIdx = Get-Random -Maximum 1000

# --- text (re-applied live when you switch language) ---
$script:doneShown = $false
function Set-Lang($code) {
  $script:L = $I.$code
  $e = $L.ex.($ex.k)
  $win.FlowDirection = if ($L.rtl) { 'RightToLeft' } else { 'LeftToRight' }  $TimeTo.Text = $L.ui.timeTo; $Word.Text = $L.ui.($ex.w)
  $TimeTo.Visibility = if ($ex.w -eq 'eyes') { 'Collapsed' } else { 'Visible' }   # the eye-break title stands on its own
  $Sub.Text = $L.ui.sub -f (Get-Name $whoIdx $L)
  $Title.Text = $e.t; $Desc.Text = $e.d; $Amount.Text = $e.a; $HowText.Text = $e.h; $How.Text = $L.ui.howto
  # tip from the SAME type as this card (one topic per reminder)
  $myCat = @($cats.Keys | ? { $cats[$_] -contains $ex.k })[0]
  $tips = @($L.tips.$myCat)
  $Tip.Text = if ($tips) { $L.ui.tip -f $tips[$tipIdx % $tips.Count] } else { '' }
  $Tip.Visibility = if ($tips) { 'Visible' } else { 'Collapsed' }
  $Count.Text = $L.ui.today -f ($st.count + [int]$script:doneShown)
  $Primary.Content = $L.ui.done
  if ($script:doneShown) { $SuccessText.Text = $L.ui.success -f ($st.count + 1) }
  foreach ($m in $win.ContextMenu.Items) { if ($m -is [System.Windows.Controls.MenuItem]) {
    if ($m.Tag -eq 'mute') { $m.Header = $L.ui.mute; $m.IsChecked = $script:muted } else { $m.IsChecked = ($m.Tag -eq $code) } } }
}

# Right-click -> language menu (every language in i18n.json shows up automatically)
$win.ContextMenu = New-Object System.Windows.Controls.ContextMenu
foreach ($code in $I.psobject.Properties.Name) {
  $mi = New-Object System.Windows.Controls.MenuItem -Property @{ Header=$I.$code.name; Tag=$code }
  $mi.Add_Click({ param($s, $e) $st.lang = $s.Tag; Save-State @{ lang = $s.Tag }; Set-Lang $s.Tag })
  [void]$win.ContextMenu.Items.Add($mi)
}
[void]$win.ContextMenu.Items.Add((New-Object System.Windows.Controls.Separator))
$muteItem = New-Object System.Windows.Controls.MenuItem -Property @{ Tag='mute'; IsCheckable=$true }
$muteItem.Add_Click({ param($s, $e) $script:muted = $s.IsChecked; Save-State @{ mute = $s.IsChecked } })
[void]$win.ContextMenu.Items.Add($muteItem)
Set-Lang $st.lang

# --- position: anchor bottom-right corner where you last dragged it, else bottom-right of main screen.
# If that spot is off every screen now (monitor unplugged), fall back to the main screen.
function Set-Corner { $wa = [System.Windows.SystemParameters]::WorkArea
  $r = $wa.Right; $b = $wa.Bottom
  if ($null -ne $st.right) {
    $vl = [System.Windows.SystemParameters]::VirtualScreenLeft; $vt = [System.Windows.SystemParameters]::VirtualScreenTop
    $vr = $vl + [System.Windows.SystemParameters]::VirtualScreenWidth; $vb = $vt + [System.Windows.SystemParameters]::VirtualScreenHeight
    if ($st.right -gt $vl + 100 -and $st.right -le $vr -and $st.bottom -gt $vt + 100 -and $st.bottom -le $vb) { $r = $st.right; $b = $st.bottom }
  }
  $win.UpdateLayout(); $win.Left = $r - $win.ActualWidth; $win.Top = $b - $win.ActualHeight }
$win.Add_SizeChanged({ Set-Corner })
# Drag anywhere on the popup (buttons still click) - new spot is remembered for next time.
$win.Add_MouseLeftButtonDown({ $win.DragMove()
  $st.right = $win.Left + $win.ActualWidth; $st.bottom = $win.Top + $win.ActualHeight
  Save-State @{ right = $st.right; bottom = $st.bottom } })
# sound when the reminder opens: always matches the reminder (water pouring, gentle stretch, soft bell);
# festive kits play their tune when you FINISH instead of the regular "done" chime
$soundKind = @{ drink='water'; stretch='stretch'; eyes='calm'; breathe='calm' }[$ex.w]
if (-not $soundKind) { $soundKind = 'move' }   # stand / walk / move: the gentle stretch family
$doneKind = if ($cast[$whoIdx].kit -in 'hanukkah', 'thanksgiving') { $cast[$whoIdx].kit } else { 'done' }
$win.Add_Loaded({ Set-Corner; Alive T; Wave T; Play-Sound $soundKind })

# toast -> card after 2.5s (click toast to skip); the card's character starts its demo
$intro = New-Object System.Windows.Threading.DispatcherTimer -Property @{ Interval=[TimeSpan]::FromSeconds(2.5) }
$showCard = { if ($Card.Visibility -eq 'Visible') { return }
  $intro.Stop(); $Toast.Visibility='Collapsed'; $Card.Visibility='Visible'; Alive C; & $moves[$ex.k]
  & $showArrows
  if ($Finish) { $script:fin = New-Object System.Windows.Threading.DispatcherTimer -Property @{ Interval=[TimeSpan]::FromMilliseconds(300) }
                 $script:fin.Add_Tick({ $script:fin.Stop(); Complete-Exercise }); $script:fin.Start() } }
$intro.Add_Tick($showCard); $Toast.Add_MouseLeftButtonDown($showCard); $intro.Start()

# no auto-close: the reminder stays on screen until you click Done or the X
$CloseX = $win.FindName('CloseX')
$CloseX.Add_MouseEnter({ $CloseX.Background = '#F1ECE5' }); $CloseX.Add_MouseLeave({ $CloseX.Background = 'White' })
$CloseX.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $win.Close() })   # Handled: don't start a drag
$How.Add_MouseLeftButtonDown({ $HowText.Visibility = if ($HowText.Visibility -eq 'Visible') {'Collapsed'} else {'Visible'} })

# --- celebration: confetti burst (milestones always, otherwise ~1 in 3) ---
function Start-Confetti {
  $w = $win.ActualWidth; $h = $win.ActualHeight; $rnd = New-Object Random
  $colors = '#E8662A', '#F5BE52', '#2EA44F', '#4A90D9', '#E86A9A', '#9B6ADE', '#F2D24B'
  for ($i = 0; $i -lt 55; $i++) {
    $piece = if ($rnd.Next(3) -eq 0) { New-Object System.Windows.Shapes.Ellipse -Property @{ Width=7; Height=7 } }
             else { New-Object System.Windows.Shapes.Rectangle -Property @{ Width=5 + $rnd.Next(4); Height=9 + $rnd.Next(5); RadiusX=1.5; RadiusY=1.5 } }
    $piece.Fill = $colors[$rnd.Next($colors.Count)]
    [System.Windows.Controls.Canvas]::SetLeft($piece, $rnd.NextDouble() * $w); [System.Windows.Controls.Canvas]::SetTop($piece, -12 - $rnd.Next(40))
    $tt = New-Object System.Windows.Media.TranslateTransform; $rt = New-Object System.Windows.Media.RotateTransform
    $tg = New-Object System.Windows.Media.TransformGroup; $tg.Children.Add($rt); $tg.Children.Add($tt); $piece.RenderTransform = $tg
    [void]$Fx.Children.Add($piece)
    $dur = [TimeSpan]::FromSeconds(1.3 + $rnd.NextDouble() * 1.1); $delay = [TimeSpan]::FromMilliseconds($rnd.Next(350))
    $fall = New-Object System.Windows.Media.Animation.DoubleAnimation(0, ($h + 60), $dur) -Property @{ BeginTime = $delay
              EasingFunction = (New-Object System.Windows.Media.Animation.QuadraticEase -Property @{ EasingMode = 'EaseIn' }) }
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $fall)
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(0, ($rnd.Next(-50, 50)), $dur) -Property @{ BeginTime = $delay }))
    $rt.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(0, ($rnd.Next(-720, 720)), $dur) -Property @{ BeginTime = $delay }))
  }
}
# --- finishing an exercise (Done): green success row, cheer, maybe confetti, then close ---
function Complete-Exercise {
  if ($script:doneShown) { return }
  if (-not $Demo) { Save-State -AddDone }   # previews don't count
  $script:doneShown = $true; Set-Lang $st.lang
  $Actions.Visibility = 'Collapsed'; $Success.Visibility = 'Visible'
  $Bar.Fill = '#2EA44F'; $Bar.Width = $Card.ActualWidth
  Play-Sound $doneKind
  M CLArmU A @(150,175,150) .5; M CRArmU A @(-150,-175,-150) .5; M CLArmF A @(0,0) 1; M CRArmF A @(0,0) 1   # arms up, cheering
  M CRigT Y @(0,-9,0) .5
  $n = $st.count + 1
  if ($Finish -or $n -in 1, 3, 5, 8, 10, 15, 20 -or (Get-Random -Maximum 3) -eq 0) { Start-Confetti }
  $end = New-Object System.Windows.Threading.DispatcherTimer -Property @{ Interval=[TimeSpan]::FromSeconds(3) }
  $end.Add_Tick({ $win.Close() }); $end.Start()
}
$Primary.Add_Click({ Complete-Exercise })   # one call to action: Done

if ($Snap) { Start-Snaps @(1.2, 3.4, 4.2, 5.0) }   # toast, then three card frames
$win.ShowDialog() | Out-Null
