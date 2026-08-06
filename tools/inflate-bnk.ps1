<#
.SYNOPSIS
  Inflate a Fable III .bnk.dat payload, which is a run of concatenated zlib streams.

.DESCRIPTION
  A single DeflateStream stops at the end of the first stream, which is why a naive
  attempt recovers only ~114 KB of a 4.5 MB bank.

  PERFORMANCE NOTE, learned the hard way: do NOT slice the byte array to feed each
  stream (`$bytes[$i..$end]`). That copies the whole remainder per candidate offset
  and turns this into a quadratic crawl - it ran >6 minutes on a 4.5 MB file before
  being killed. `MemoryStream($bytes, offset, count, $false)` is a view over the same
  buffer and costs nothing.

  NAME NOTE: the accumulator is $acc, not $out - PowerShell variables are
  case-insensitive, so $out silently aliases the -Out parameter and becomes a string.

  Streams start 0x78 followed by 0x01/0x5E/0x9C/0xDA, and the two bytes together must
  be divisible by 31. After each stream we resume from where it actually stopped.

.EXAMPLE
  .\inflate-bnk.ps1 -Path "C:\Games\Fable 3\data\gamescripts.bnk.dat" -Out out.bin
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [string]$Out,
  [switch]$Quiet
)

$sw = [Diagnostics.Stopwatch]::StartNew()
$bytes = [IO.File]::ReadAllBytes($Path)
$n = $bytes.Length
$acc = New-Object IO.MemoryStream
$streams = 0
$truncated = 0
$i = 0

while ($i -lt $n - 1) {
  # cheap header test before doing any work
  if ($bytes[$i] -ne 0x78) { $i++; continue }
  $flg = $bytes[$i + 1]
  if ($flg -ne 0x01 -and $flg -ne 0x5E -and $flg -ne 0x9C -and $flg -ne 0xDA) { $i++; continue }
  if (((([int]$bytes[$i] * 256) + [int]$flg) % 31) -ne 0) { $i++; continue }

  # view, not a copy
  $ms = New-Object IO.MemoryStream($bytes, ($i + 2), ($n - $i - 2), $false)
  $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
  $chunk = New-Object IO.MemoryStream
  $buf = New-Object byte[] 65536
  $clean = $true
  try {
    while ($true) {
      $r = $ds.Read($buf, 0, $buf.Length)
      if ($r -le 0) { break }
      $chunk.Write($buf, 0, $r)
    }
  } catch { $clean = $false }
  $consumed = $ms.Position
  $ds.Dispose(); $ms.Dispose()

  if ($chunk.Length -gt 64) {
    $b2 = $chunk.ToArray()
    $acc.Write($b2, 0, $b2.Length)
    $streams++
    if (-not $clean) { $truncated++ }
    $i += [Math]::Max(2, [int]$consumed)
  } else {
    $i++
  }
  $chunk.Dispose()
}

$data = $acc.ToArray()
$sw.Stop()
if (-not $Quiet) {
  "{0}" -f (Split-Path $Path -Leaf)
  "  compressed : {0,12:N0} B" -f $n
  "  inflated   : {0,12:N0} B" -f $data.Length
  "  streams    : {0} ({1} ended early)" -f $streams, $truncated
  "  elapsed    : {0:N1}s" -f $sw.Elapsed.TotalSeconds
}
if ($Out) { [IO.File]::WriteAllBytes($Out, $data); if (-not $Quiet) { "  wrote      : $Out" } }
