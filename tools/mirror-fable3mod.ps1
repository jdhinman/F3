<#
.SYNOPSIS
  Mirror the fable3mod.com forum, which holds the entire Fable III modding corpus.

.DESCRIPTION
  The site runs FUDforum on plain HTTP with a broken TLS certificate, and its key
  technical threads date from 2013-2015. It is a single point of failure for tools
  and format knowledge that exist nowhere else. See Notes/Preservation.md.

  Saves two forms per topic:
    html/th-<id>.html   raw response, the preservation artifact
    text/th-<id>.txt    tags stripped and entities decoded, for reading and grep

  Retrieval note: WebFetch and Invoke-WebRequest force HTTPS and fail on the bad
  certificate. curl.exe over plain http:// is the working route.

.EXAMPLE
  .\mirror-fable3mod.ps1 -Technical        # 186 topics, everything but General Discussion
  .\mirror-fable3mod.ps1 -All              # all 776 topics
#>
[CmdletBinding()]
param(
  [string]$Base = 'http://fable3mod.com/forums',
  [string]$Out  = "$PSScriptRoot\..\reference\fable3mod",
  [switch]$All,
  [switch]$Technical,
  [int]$DelayMs = 250
)

# frm_id -> name. General Discussion (4) is 590 mostly-spam topics; the rest is the corpus.
$forums = @{ '1' = 'Announcements'; '4' = 'General Discussion'; '5' = 'Modding Discussion'
             '6' = 'Tools'; '7' = 'Formats'; '8' = 'Mods' }
$technicalForums = @('1', '5', '6', '7', '8')

function Get-Page([string]$url) {
  $r = curl.exe -s -L --max-time 40 -A "Mozilla/5.0" $url 2>$null
  if (-not $r) { return '' }
  ($r -join "`n")
}

function ConvertTo-Text([string]$html) {
  $t = [regex]::Replace($html, '(?s)<script.*?</script>', '')
  $t = [regex]::Replace($t, '(?s)<style.*?</style>', '')
  # keep post boundaries readable
  $t = $t -replace '(?i)</(p|div|tr|br)>', "`n"
  $t = [regex]::Replace($t, '<[^>]+>', ' ')
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  ($t -replace '[ \t]{2,}', ' ') -replace '(\r?\n){3,}', "`n`n"
}

$targets = if ($All) { $forums.Keys } elseif ($Technical) { $technicalForums } else { $technicalForums }

New-Item -ItemType Directory -Force "$Out\html", "$Out\text" | Out-Null

# --- enumerate topic ids -------------------------------------------------
# Links are HTML-encoded (&amp;th=123), so match on `th=` rather than `&th=`.
$ids = New-Object 'System.Collections.Generic.HashSet[string]'
$perForum = @{}
foreach ($id in $targets) {
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $start = 0
  while ($start -le 800) {
    $h = Get-Page "$Base/index.php?t=thread&frm_id=$id&start=$start"
    $found = [regex]::Matches($h, 'th=(\d+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '0' }
    $new = 0
    foreach ($f in $found) { if ($seen.Add($f)) { $new++ } }
    if ($new -eq 0) { break }
    $start += 40
    Start-Sleep -Milliseconds $DelayMs
  }
  $perForum[$id] = $seen.Count
  foreach ($s in $seen) { [void]$ids.Add($s) }
  Write-Host ("  {0,-20} frm_id={1,-2} topics={2}" -f $forums[$id], $id, $seen.Count)
}
Write-Host "topics to mirror: $($ids.Count)"

# --- fetch each topic ----------------------------------------------------
$done = 0; $failed = @(); $bytes = 0
foreach ($th in ($ids | Sort-Object { [int]$_ })) {
  $htmlPath = "$Out\html\th-$th.html"
  if (Test-Path $htmlPath) { $done++; continue }   # resumable

  $pages = @()
  $start = 0
  while ($true) {
    $h = Get-Page "$Base/index.php?t=msg&th=$th&start=$start"
    if (-not $h) { break }
    $pages += $h
    # another page exists only if a larger start= is linked for this thread
    $more = [regex]::Matches($h, "th=$th&amp;start=(\d+)") | ForEach-Object { [int]$_.Groups[1].Value } |
            Where-Object { $_ -gt $start } | Sort-Object | Select-Object -First 1
    if (-not $more) { break }
    $start = $more
    Start-Sleep -Milliseconds $DelayMs
  }
  if (-not $pages) { $failed += $th; continue }

  $joined = $pages -join "`n<!-- page break -->`n"
  [IO.File]::WriteAllText($htmlPath, $joined, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText("$Out\text\th-$th.txt", (ConvertTo-Text $joined), [Text.UTF8Encoding]::new($false))
  $bytes += $joined.Length
  $done++
  if ($done % 25 -eq 0) { Write-Host "  $done / $($ids.Count)" }
  Start-Sleep -Milliseconds $DelayMs
}

Write-Host ""
Write-Host ("mirrored : {0} topics, {1:N1} MB" -f $done, ($bytes / 1MB))
if ($failed.Count) { Write-Host "failed   : $($failed.Count) -> $($failed -join ', ')" }
