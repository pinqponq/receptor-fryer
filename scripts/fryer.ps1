<#
  receptor-fryer cekirdek kontrol
  Kullanim: fryer.ps1 play | pause | toggle

  - config.enabled false ise hicbir sey yapmaz (ana kapali anahtari).
  - Aktif ANIME'nin secili bolumunu kaldigi saniyeden oynatir.
  - Her anime kendi 'current' (bolum) ve 'pos' (saniye) bilgisini animeState'te tutar.
#>
param(
  [Parameter(Mandatory=$true)][ValidateSet('play','pause','toggle')][string]$Action
)
$ErrorActionPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config.json'
if (-not (Test-Path $configPath)) { exit 0 }
. (Join-Path $PSScriptRoot 'common.ps1')

function Get-Cfg { Get-Content $configPath -Raw | ConvertFrom-Json }
function Save-Cfg($c) { $c | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8 }
function NumStr($n) { ([double]$n).ToString([System.Globalization.CultureInfo]::InvariantCulture) }

$cfg = Get-Cfg
$pipeName = if ($cfg.pipeName) { $cfg.pipeName } else { 'receptor_fryer' }
$pipeFull = "\\.\pipe\$pipeName"

# Aktif anime durum nesnesini getir (yoksa olustur)
function Get-State($c) {
  $name = $c.activeAnime
  if (-not $name) { return $null }
  if (-not $c.PSObject.Properties.Name.Contains('animeState')) {
    $c | Add-Member -NotePropertyName animeState -NotePropertyValue (New-Object PSObject)
  }
  $prop = $c.animeState.PSObject.Properties[$name]
  if (-not $prop) {
    $c.animeState | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{ current=''; pos=0 })
  }
  return $c.animeState.PSObject.Properties[$name].Value
}

# --- IPC ---
function Send-Mpv([string]$json) {
  try {
    $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $p.Connect(400); $sw = New-Object System.IO.StreamWriter($p); $sw.AutoFlush = $true
    $sw.WriteLine($json); Start-Sleep -Milliseconds 40; $p.Dispose(); return $true
  } catch { return $false }
}
function Invoke-Mpv([string]$json, [int]$reqId) {
  try {
    $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $p.Connect(400); $sw = New-Object System.IO.StreamWriter($p); $sw.AutoFlush = $true
    $sr = New-Object System.IO.StreamReader($p); $sw.WriteLine($json)
    for ($i = 0; $i -lt 25; $i++) {
      $line = $sr.ReadLine(); if (-not $line) { break }
      try { $o = $line | ConvertFrom-Json } catch { continue }
      if ($o.request_id -eq $reqId) { $p.Dispose(); return $o }
    }
    $p.Dispose()
  } catch {}
  return $null
}
function Test-MpvAlive { (Invoke-Mpv '{"command":["get_property","idle-active"],"request_id":99}' 99) -ne $null }
function Get-MpvPath   { $r = Invoke-Mpv '{"command":["get_property","path"],"request_id":11}' 11; if ($r) { $r.data } }
function Get-MpvPos    { $r = Invoke-Mpv '{"command":["get_property","time-pos"],"request_id":12}' 12; if ($r -and $r.data -ne $null) { [double]$r.data } else { $null } }

# --- Pencere ---
if (-not ('Fryer.Win' -as [type])) {
  Add-Type @"
using System; using System.Runtime.InteropServices;
namespace Fryer { public static class Win {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
} }
"@
}
function Set-MpvWindow([string]$mode) {
  $p = Get-Process -Name 'mpv' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) { return }
  $h = $p.MainWindowHandle; if ($h -eq [IntPtr]::Zero) { return }
  if ($mode -eq 'front') { [Fryer.Win]::ShowWindow($h, 9) | Out-Null; [Fryer.Win]::SetForegroundWindow($h) | Out-Null }
  elseif ($mode -eq 'min') { [Fryer.Win]::ShowWindow($h, 6) | Out-Null }
}

function Start-Mpv([string]$file, [double]$pos) {
  if (-not (Test-Path $cfg.mpvPath)) { exit 0 }
  if (-not (Test-Path $file)) { exit 0 }
  $args = @("--input-ipc-server=$pipeFull","--save-position-on-quit=no","--force-window=yes","--idle=yes","--keep-open=yes")
  if ($cfg.ontopWhilePlaying) { $args += "--ontop" }
  if ($cfg.volume) { $args += "--volume=$($cfg.volume)" }
  if ($cfg.speed) { $args += "--speed=$(NumStr $cfg.speed)" }
  if ($pos -gt 1) { $args += "--start=$([int]$pos)" }
  $args += "`"$file`""
  Start-Process -FilePath $cfg.mpvPath -ArgumentList $args | Out-Null
  for ($i = 0; $i -lt 25; $i++) { Start-Sleep -Milliseconds 120; if (Test-MpvAlive) { break } }
}

function Save-Pos {
  $pos = Get-MpvPos; if ($pos -eq $null) { return }
  $c = Get-Cfg; $st = Get-State $c
  if ($st) { $st.pos = [math]::Round($pos, 1); Save-Cfg $c }
}

# --- Aktif animenin secili bolumunu coz ---
$st = Get-State $cfg
$wantFile = if ($st) { $st.current } else { $null }
$wantPos  = if ($st -and $st.pos) { [double]$st.pos } else { 0 }

# current bos ise animenin ilk bolumunu sec
if ((-not $wantFile) -or -not (Test-Path $wantFile)) {
  $groups = Get-AnimeGroups $cfg.sourceRoot
  if ($groups.Contains($cfg.activeAnime) -and $groups[$cfg.activeAnime].Count) {
    $wantFile = $groups[$cfg.activeAnime][0].FullName
    if ($st) { $c = Get-Cfg; (Get-State $c).current = $wantFile; Save-Cfg $c }
  }
}

switch ($Action) {
  'play' {
    if (-not $cfg.enabled) { exit 0 }
    if (-not $wantFile -or -not (Test-Path $wantFile)) { exit 0 }
    if (Test-MpvAlive) {
      $loaded = Get-MpvPath
      if ($loaded -and ($loaded -ieq $wantFile)) {
        Send-Mpv '{"command":["set_property","pause",false]}' | Out-Null
      } else {
        Send-Mpv '{"command":["quit"]}' | Out-Null
        for ($i=0;$i -lt 20;$i++){ Start-Sleep -Milliseconds 100; if (-not (Get-Process mpv -ErrorAction SilentlyContinue)){break} }
        Start-Mpv $wantFile $wantPos
      }
    } else { Start-Mpv $wantFile $wantPos }
    if ($cfg.speed) { Send-Mpv "{`"command`":[`"set_property`",`"speed`",$(NumStr $cfg.speed)]}" | Out-Null }
    Set-MpvWindow 'front'
  }
  'pause' {
    if (Test-MpvAlive) {
      Save-Pos
      Send-Mpv '{"command":["set_property","pause",true]}' | Out-Null
      if ($cfg.minimizeOnPause) { Set-MpvWindow 'min' }
    }
  }
  'toggle' {
    if (-not (Test-MpvAlive)) {
      if ($cfg.enabled -and $wantFile) { Start-Mpv $wantFile $wantPos; Set-MpvWindow 'front' }
    } else { Send-Mpv '{"command":["cycle","pause"]}' | Out-Null }
  }
}
exit 0
