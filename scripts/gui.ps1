<#
  receptor-fryer kontrol paneli (WinForms)
  - Ana ACIK/KAPALI anahtari (config.enabled)
  - Tek kaynak = AnimeciX klasoru; icindeki videolar anime bazinda gruplanir
  - ANIME sec -> aktif olur; her anime kendi bolum + saniyesini tutar
  Calistir: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gui.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$here       = $PSScriptRoot
$root       = Split-Path -Parent $here
$configPath = Join-Path $root 'config.json'
$fryer      = Join-Path $here 'fryer.ps1'
. (Join-Path $here 'common.ps1')

$script:cfg     = $null
$script:loading = $false
$script:epMap   = @{}

function Load-Cfg {
  $script:cfg = Get-Content $configPath -Raw | ConvertFrom-Json
  # autoDelete anahtari yoksa ekle (varsayilan acik) -> Save-Cfg'de kaybolmasin
  if (-not $script:cfg.PSObject.Properties.Name.Contains('autoDelete')) {
    $script:cfg | Add-Member -NotePropertyName autoDelete -NotePropertyValue $true
  }
}
function Save-Cfg { $script:cfg | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8 }
function Fryer([string]$a) { & powershell -NoProfile -ExecutionPolicy Bypass -File $fryer $a 2>$null | Out-Null }
function NumStr($n) { ([double]$n).ToString([System.Globalization.CultureInfo]::InvariantCulture) }

function Get-State {
  $name = $script:cfg.activeAnime
  if (-not $name) { return $null }
  if (-not $script:cfg.PSObject.Properties.Name.Contains('animeState')) {
    $script:cfg | Add-Member -NotePropertyName animeState -NotePropertyValue (New-Object PSObject)
  }
  if (-not $script:cfg.animeState.PSObject.Properties[$name]) {
    $script:cfg.animeState | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{ current=''; pos=0 })
  }
  return $script:cfg.animeState.PSObject.Properties[$name].Value
}

function Mpv-Get([string]$prop) {
  $name = if ($script:cfg.pipeName) { $script:cfg.pipeName } else { 'receptor_fryer' }
  try {
    $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', $name, [System.IO.Pipes.PipeDirection]::InOut)
    $p.Connect(200); $sw = New-Object System.IO.StreamWriter($p); $sw.AutoFlush = $true
    $sr = New-Object System.IO.StreamReader($p)
    $sw.WriteLine("{`"command`":[`"get_property`",`"$prop`"],`"request_id`":7}")
    for ($i=0; $i -lt 20; $i++) {
      $l = $sr.ReadLine(); if (-not $l) { break }
      try { $o = $l | ConvertFrom-Json } catch { continue }
      if ($o.request_id -eq 7) { $p.Dispose(); return $o }
    }
    $p.Dispose()
  } catch {}
  return $null
}

function Mpv-Send([string]$json) {
  $name = if ($script:cfg.pipeName) { $script:cfg.pipeName } else { 'receptor_fryer' }
  try {
    $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', $name, [System.IO.Pipes.PipeDirection]::InOut)
    $p.Connect(200); $sw = New-Object System.IO.StreamWriter($p); $sw.AutoFlush = $true
    $sw.WriteLine($json); Start-Sleep -Milliseconds 30; $p.Dispose()
  } catch {}
}

function Fmt-Time([double]$s) { if ($s -lt 0) { $s = 0 }; "{0:mm\:ss}" -f [TimeSpan]::FromSeconds([int]$s) }

Load-Cfg

# ---------------- Form ----------------
$form = New-Object Windows.Forms.Form
$form.Text = "receptor-fryer"
$form.Size = New-Object Drawing.Size(440, 535)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.BackColor = [Drawing.Color]::FromArgb(24,24,28)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font("Segoe UI", 9)

$toggle = New-Object Windows.Forms.Button
$toggle.Size = New-Object Drawing.Size(400, 52); $toggle.Location = New-Object Drawing.Point(12, 12)
$toggle.FlatStyle = 'Flat'; $toggle.Font = New-Object Drawing.Font("Segoe UI", 13, [Drawing.FontStyle]::Bold)
$form.Controls.Add($toggle)

$lblA = New-Object Windows.Forms.Label
$lblA.Text = "Anime sec (aktif):"; $lblA.Location = New-Object Drawing.Point(12, 80); $lblA.AutoSize = $true
$form.Controls.Add($lblA)

$cmb = New-Object Windows.Forms.ComboBox
$cmb.DropDownStyle = 'DropDownList'; $cmb.Size = New-Object Drawing.Size(366, 26)
$cmb.Location = New-Object Drawing.Point(12, 102)
$cmb.BackColor = [Drawing.Color]::FromArgb(40,40,46); $cmb.ForeColor = [Drawing.Color]::White; $cmb.FlatStyle = 'Flat'
$form.Controls.Add($cmb)

$btnRef = New-Object Windows.Forms.Button
$btnRef.Text = [char]0x21BB   # yenile simgesi
$btnRef.Size = New-Object Drawing.Size(36, 26); $btnRef.Location = New-Object Drawing.Point(382, 101)
$btnRef.FlatStyle = 'Flat'; $btnRef.BackColor = [Drawing.Color]::FromArgb(55,55,62); $btnRef.ForeColor = [Drawing.Color]::White
$btnRef.Font = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
$tt = New-Object Windows.Forms.ToolTip; $tt.SetToolTip($btnRef, "Listeyi yenile (yeni indirilenleri tara)")
$form.Controls.Add($btnRef)

$lblE = New-Object Windows.Forms.Label
$lblE.Text = "Bolumler (tikla = aktif bolum):"; $lblE.Location = New-Object Drawing.Point(12, 140); $lblE.AutoSize = $true
$form.Controls.Add($lblE)

$lst = New-Object Windows.Forms.ListBox
$lst.Size = New-Object Drawing.Size(406, 170); $lst.Location = New-Object Drawing.Point(12, 162)
$lst.BackColor = [Drawing.Color]::FromArgb(40,40,46); $lst.ForeColor = [Drawing.Color]::White; $lst.BorderStyle = 'FixedSingle'
$form.Controls.Add($lst)

$lblS = New-Object Windows.Forms.Label
$lblS.Text = "Oynatma hizi:"; $lblS.Location = New-Object Drawing.Point(12, 344); $lblS.AutoSize = $true
$form.Controls.Add($lblS)

$cmbSpeed = New-Object Windows.Forms.ComboBox
$cmbSpeed.DropDownStyle = 'DropDownList'; $cmbSpeed.Size = New-Object Drawing.Size(90, 26)
$cmbSpeed.Location = New-Object Drawing.Point(100, 340)
$cmbSpeed.BackColor = [Drawing.Color]::FromArgb(40,40,46); $cmbSpeed.ForeColor = [Drawing.Color]::White; $cmbSpeed.FlatStyle = 'Flat'
'0.75','1.0','1.25','1.5','1.75','2.0' | ForEach-Object { [void]$cmbSpeed.Items.Add($_) }
$form.Controls.Add($cmbSpeed)

$chkDel = New-Object Windows.Forms.CheckBox
$chkDel.Text = "Izleneni sil (onceki bolum kalir)"
$chkDel.Location = New-Object Drawing.Point(202, 344); $chkDel.AutoSize = $true
$chkDel.ForeColor = [Drawing.Color]::FromArgb(210,210,215)
$form.Controls.Add($chkDel)

$btnPlay = New-Object Windows.Forms.Button
$btnPlay.Text = "> Oynat"; $btnPlay.Size = New-Object Drawing.Size(198, 40); $btnPlay.Location = New-Object Drawing.Point(12, 380)
$btnPlay.FlatStyle = 'Flat'; $btnPlay.BackColor = [Drawing.Color]::FromArgb(45,90,160)
$btnPlay.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($btnPlay)

$btnPause = New-Object Windows.Forms.Button
$btnPause.Text = "|| Duraklat"; $btnPause.Size = New-Object Drawing.Size(198, 40); $btnPause.Location = New-Object Drawing.Point(220, 380)
$btnPause.FlatStyle = 'Flat'; $btnPause.BackColor = [Drawing.Color]::FromArgb(70,70,80)
$btnPause.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($btnPause)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(12, 428); $status.Size = New-Object Drawing.Size(406, 44)
$status.ForeColor = [Drawing.Color]::FromArgb(180,180,190)
$form.Controls.Add($status)

# ---------------- Doldurma ----------------
function Refresh-Toggle {
  if ($script:cfg.enabled) { $toggle.Text = "SISTEM: ACIK"; $toggle.BackColor = [Drawing.Color]::FromArgb(34,139,84) }
  else { $toggle.Text = "SISTEM: KAPALI"; $toggle.BackColor = [Drawing.Color]::FromArgb(120,40,40) }
  $toggle.ForeColor = [Drawing.Color]::White
}

function Refresh-Animes {
  $script:loading = $true
  $cmb.Items.Clear()
  $script:groups = Get-AnimeGroups $script:cfg.sourceRoot
  foreach ($k in $script:groups.Keys) { [void]$cmb.Items.Add($k) }
  $idx = $cmb.Items.IndexOf($script:cfg.activeAnime)
  if ($idx -lt 0 -and $cmb.Items.Count) { $idx = 0; $script:cfg.activeAnime = $cmb.Items[0] }
  if ($idx -ge 0) { $cmb.SelectedIndex = $idx }
  $script:loading = $false
}

function Refresh-Eps {
  $script:loading = $true
  $lst.Items.Clear(); $script:epMap = @{}
  $anime = $script:cfg.activeAnime
  if ($script:groups.Contains($anime)) {
    foreach ($f in $script:groups[$anime]) {
      [void]$lst.Items.Add($f.BaseName); $script:epMap[$f.BaseName] = $f.FullName
    }
    $st = Get-State
    if ($st.current) {
      $curName = [IO.Path]::GetFileNameWithoutExtension($st.current)
      $ci = $lst.Items.IndexOf($curName); if ($ci -ge 0) { $lst.SelectedIndex = $ci }
    }
  }
  $script:loading = $false
}

function Refresh-Status([double]$livePos = -1) {
  $st = Get-State
  if (-not $st) { $status.Text = "Anime yok."; return }
  $name = if ($st.current) { [IO.Path]::GetFileNameWithoutExtension($st.current) } else { "(bolum secili degil)" }
  $pos  = if ($livePos -ge 0) { $livePos } elseif ($st.pos) { [double]$st.pos } else { 0 }
  $status.Text = "[$($script:cfg.activeAnime)]`n$name  -  Konum: $(Fmt-Time $pos)"
}

# ---------------- Olaylar ----------------
$toggle.Add_Click({
  $script:cfg.enabled = -not $script:cfg.enabled; Save-Cfg; Refresh-Toggle
  if (-not $script:cfg.enabled) { Fryer 'pause' }
})

$cmb.Add_SelectedIndexChanged({
  if ($script:loading) { return }
  Fryer 'pause'                          # eski animenin saniyesini kaydet
  Load-Cfg
  $script:cfg.activeAnime = $cmb.SelectedItem
  Save-Cfg
  Refresh-Eps; Refresh-Status
})

$lst.Add_SelectedIndexChanged({
  if ($script:loading) { return }
  $sel = $lst.SelectedItem; if (-not $sel) { return }
  $full = $script:epMap[$sel]; $st = Get-State
  if ($st.current -ne $full) {
    $st.current = $full; $st.pos = 0; Save-Cfg
    # mpv calisiyorsa secilen bolume hemen atla
    if ($script:cfg.enabled -and (Get-Process mpv -ErrorAction SilentlyContinue)) {
      Get-Process mpv -ErrorAction SilentlyContinue | Stop-Process -Force
      Start-Sleep -Milliseconds 300
      Fryer 'play'
    }
  }
  Refresh-Status
})

$btnRef.Add_Click({
  $sel = $cmb.SelectedItem
  Refresh-Animes
  if ($sel -and $cmb.Items.Contains($sel)) { $script:loading=$true; $cmb.SelectedItem = $sel; $script:loading=$false }
  Refresh-Eps; Refresh-Status
})

$btnPlay.Add_Click({
  if (-not $script:cfg.enabled) { $script:cfg.enabled = $true; Save-Cfg; Refresh-Toggle }
  Fryer 'play'
})
$btnPause.Add_Click({ Fryer 'pause'; Load-Cfg; Refresh-Status })

function Select-Speed {
  $script:loading = $true
  $cur = if ($script:cfg.speed) { [double]$script:cfg.speed } else { 1.0 }
  for ($i=0; $i -lt $cmbSpeed.Items.Count; $i++) {
    if ([double]$cmbSpeed.Items[$i] -eq $cur) { $cmbSpeed.SelectedIndex = $i; break }
  }
  $script:loading = $false
}

$cmbSpeed.Add_SelectedIndexChanged({
  if ($script:loading) { return }
  $v = [double]$cmbSpeed.SelectedItem
  $script:cfg.speed = $v; Save-Cfg
  Mpv-Send "{`"command`":[`"set_property`",`"speed`",$(NumStr $v)]}"   # calisan mpv'ye canli uygula
})

$chkDel.Add_CheckedChanged({
  if ($script:loading) { return }
  $script:cfg.autoDelete = $chkDel.Checked; Save-Cfg
})

$script:tick = 0
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
  $pause = Mpv-Get 'pause'; $tp = Mpv-Get 'time-pos'; $pathObj = Mpv-Get 'path'
  if ($tp -and $tp.data -ne $null) {
    $pos = [double]$tp.data; Refresh-Status $pos
    if (-not ($pause -and $pause.data -eq $true)) {
      $st = Get-State
      if ($st) {
        $st.pos = [math]::Round($pos, 1)
        # otomatik gecis olduysa gercekte oynanan bolumu yakala
        if ($pathObj -and $pathObj.data -and ($st.current -ne $pathObj.data)) {
          $st.current = $pathObj.data
          $script:loading = $true
          $curName = [IO.Path]::GetFileNameWithoutExtension($st.current)
          $ci = $lst.Items.IndexOf($curName); if ($ci -ge 0) { $lst.SelectedIndex = $ci }
          $script:loading = $false
        }
        $script:tick++; if ($script:tick % 3 -eq 0) { Save-Cfg }
      }
    }
  }
})

Refresh-Toggle; Refresh-Animes; Refresh-Eps; Select-Speed; Refresh-Status
$script:loading = $true; $chkDel.Checked = [bool]$script:cfg.autoDelete; $script:loading = $false
Save-Cfg   # autoDelete (ve eksik anahtarlar) diske yazilsin
$timer.Start()
[void]$form.ShowDialog()
$timer.Stop()
