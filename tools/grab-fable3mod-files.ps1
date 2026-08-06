<#
.SYNOPSIS
  Download every attachment referenced by the mirrored fable3mod.com threads.

.DESCRIPTION
  The forum's attachments are the only copies of most Fable III tooling: BNKUtils,
  the script injector, the GDB editor, the KoreVM opcode notes, the decompiled
  scripts. None of it is mirrored anywhere else. See Notes/Preservation.md.

  Run mirror-fable3mod.ps1 first; this reads the saved HTML rather than re-crawling.

  Files are named "<attachment id>-<original name>" so duplicates posted in several
  threads stay distinguishable and nothing silently overwrites anything else.

.EXAMPLE
  .\grab-fable3mod-files.ps1
#>
[CmdletBinding()]
param(
  [string]$Base = 'http://fable3mod.com',
  [string]$Mirror = "$PSScriptRoot\..\reference\fable3mod",
  [int]$DelayMs = 250
)

$outDir = "$Mirror\files"
New-Item -ItemType Directory -Force $outDir | Out-Null

# Collect (id -> name) from every mirrored thread. Links are HTML-encoded.
$att = @{}
foreach ($f in (Get-ChildItem "$Mirror\html" -Filter *.html)) {
  $h = [IO.File]::ReadAllText($f.FullName)
  foreach ($m in [regex]::Matches($h, 'href="([^"]*t=getfile[^"]*)"[^>]*>([^<]*)</a>')) {
    $url = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
    $name = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value).Trim()
    $id = [regex]::Match($url, 'id=(\d+)').Groups[1].Value
    if (-not $id) { continue }
    # "here" and similar link text is useless as a filename; fall back to the id
    if (-not $name -or $name -eq 'here' -or $name.Length -gt 80) { $name = "attachment-$id" }
    if (-not $att.ContainsKey($id)) { $att[$id] = @{ Name = $name; Thread = $f.BaseName } }
  }
}
Write-Host "distinct attachments: $($att.Count)"

$ok = 0; $skip = 0; $fail = @(); $bytes = 0
foreach ($id in ($att.Keys | Sort-Object { [int]$_ })) {
  $safe = ($att[$id].Name -replace '[<>:"/\\|?*]', '_')
  $dest = Join-Path $outDir ("{0}-{1}" -f $id, $safe)
  if (Test-Path $dest) { $skip++; continue }

  curl.exe -s -L --max-time 120 -A "Mozilla/5.0" -o $dest "$Base/forums/index.php?t=getfile&id=$id" 2>$null | Out-Null

  if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0) {
    # A expired/blocked download returns an HTML error page rather than the file.
    $head = [IO.File]::ReadAllBytes($dest)[0..([Math]::Min(200, (Get-Item $dest).Length - 1))]
    $txt = [Text.Encoding]::ASCII.GetString($head)
    if ($txt -match '(?i)<html|<!doctype|Invalid Input') {
      Remove-Item -LiteralPath $dest -Force
      $fail += "$id ($($att[$id].Name)) - got HTML, not a file"
    } else {
      $bytes += (Get-Item $dest).Length
      $ok++
    }
  } else {
    if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Force }
    $fail += "$id ($($att[$id].Name)) - empty"
  }
  Start-Sleep -Milliseconds $DelayMs
}

Write-Host ""
Write-Host ("downloaded : {0}  ({1:N1} MB)" -f $ok, ($bytes / 1MB))
Write-Host ("skipped    : {0} (already present)" -f $skip)
if ($fail.Count) {
  Write-Host "failed     : $($fail.Count)"
  $fail | Select-Object -First 15 | ForEach-Object { Write-Host "   $_" }
}
