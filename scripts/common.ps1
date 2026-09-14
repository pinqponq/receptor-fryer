<#
  Ortak yardimcilar: kaynak klasordeki videolari anime bazinda gruplar.
  AnimeciX dosyalari duz kaydediyor; anime adini dosya isminden turetiyoruz.
  Ornek: "Koukaku Kidoutai_ Stand Alone Complex S1 B1.mp4" -> anime "Koukaku Kidoutai_ Stand Alone Complex"
#>
$VideoExt = @('.mp4','.mkv','.ts','.avi','.webm','.mov','.m4v')

function Get-Series([string]$base) {
  # "... S1 B1", "... S01 B12", "... B1" gibi bolum ekini at
  if ($base -match '^(.*?)[\s._-]+S\d+[\s._-]*B\d+') { return $Matches[1].Trim() }
  if ($base -match '^(.*?)[\s._-]+B\d+')            { return $Matches[1].Trim() }
  if ($base -match '^(.*?)[\s._-]+S\d+E\d+')        { return $Matches[1].Trim() }
  return $base.Trim()
}

function Get-EpNum([string]$base) {
  $s = 0; $b = 0
  if ($base -match 'S(\d+)') { $s = [int]$Matches[1] }
  if ($base -match 'B(\d+)') { $b = [int]$Matches[1] }
  elseif ($base -match 'E(\d+)') { $b = [int]$Matches[1] }
  return ($s * 10000 + $b)
}

# Kaynak klasoru tarar; anime adi -> siralanmis dosya listesi (hashtable) doner
function Get-AnimeGroups([string]$rootPath) {
  $result = [ordered]@{}
  if (-not $rootPath -or -not (Test-Path $rootPath)) { return $result }
  $files = Get-ChildItem -LiteralPath $rootPath -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $VideoExt -contains $_.Extension.ToLower() }
  $groups = $files | Group-Object { Get-Series $_.BaseName } | Sort-Object Name
  foreach ($g in $groups) {
    $eps = $g.Group | Sort-Object { Get-EpNum $_.BaseName }, Name
    $result[$g.Name] = $eps
  }
  return $result
}
