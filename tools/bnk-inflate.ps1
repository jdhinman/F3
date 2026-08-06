<#
.SYNOPSIS
  Fully decompress a Fable III .bnk index or .bnk.dat payload.

.DESCRIPTION
  Banks are stored as a chain of independently compressed blocks, each capped at
  64 KB uncompressed. That is why a single DeflateStream stops at exactly 65,536
  bytes, and why naive header-scanning loses data.

  Block layout:
      byte    flag                       (purpose unknown; varies per block)
      BE32    uncompressed size          (65536, or less for the final block)
      zlib    stream                     (0x78 0xDA ...)

  Verified: guiscripts.bnk declares 14,454 and inflates to exactly 14,454.

  We locate each block by signature rather than by trusting DeflateStream's
  Position, which over-reads because of internal buffering. The signature is
  strong: a BE32 in (0, 65536] immediately followed by a valid zlib header.

  PERF: never slice the byte array - use MemoryStream(buffer, offset, count, $false),
  a view. Slicing made an earlier version quadratic (>6 min on 4.5 MB).

.EXAMPLE
  .\bnk-inflate.ps1 -Path "C:\Games\Fable 3\data\gamescripts.bnk.dat" -Out out.bin
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [string]$Out,
  [switch]$Quiet
)

$sw = [Diagnostics.Stopwatch]::StartNew()
$b = [IO.File]::ReadAllBytes($Path)
$n = $b.Length

function Get-BE32([byte[]]$a, [int]$o) {
  if ($o + 3 -ge $a.Length) { return -1 }
  return ([int]$a[$o] -shl 24) -bor ([int]$a[$o + 1] -shl 16) -bor ([int]$a[$o + 2] -shl 8) -bor [int]$a[$o + 3]
}
function Test-Zlib([byte[]]$a, [int]$o) {
  if ($o + 1 -ge $a.Length -or $a[$o] -ne 0x78) { return $false }
  $f = $a[$o + 1]
  if ($f -ne 0x01 -and $f -ne 0x5E -and $f -ne 0x9C -and $f -ne 0xDA) { return $false }
  return (((([int]$a[$o] * 256) + [int]$f) % 31) -eq 0)
}
# a block header is: [flag][BE32 size in (0,65536]][zlib]
function Test-BlockAt([byte[]]$a, [int]$o) {
  $sz = Get-BE32 $a ($o + 1)
  if ($sz -le 0 -or $sz -gt 65536) { return $false }
  return (Test-Zlib $a ($o + 5))
}

$acc = New-Object IO.MemoryStream
$blocks = 0; $short = 0
$pos = 0
# find the first block header
while ($pos -lt $n - 8 -and -not (Test-BlockAt $b $pos)) { $pos++ }

while ($pos -lt $n - 8) {
  $size = Get-BE32 $b ($pos + 1)
  $dataAt = $pos + 5

  $ms = New-Object IO.MemoryStream($b, ($dataAt + 2), ($n - $dataAt - 2), $false)
  $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
  $buf = New-Object byte[] 65536
  $got = 0
  try {
    while ($got -lt $size) {
      $r = $ds.Read($buf, 0, [Math]::Min($buf.Length, $size - $got))
      if ($r -le 0) { break }
      $acc.Write($buf, 0, $r)
      $got += $r
    }
  } catch { }
  $ds.Dispose(); $ms.Dispose()

  if ($got -gt 0) { $blocks++ }
  if ($got -lt $size) { $short++ }

  # next block: scan forward for the next valid header
  $p2 = $dataAt + 2
  while ($p2 -lt $n - 8 -and -not (Test-BlockAt $b $p2)) { $p2++ }
  if ($p2 -ge $n - 8) { break }
  $pos = $p2
}

$data = $acc.ToArray()
$sw.Stop()
if (-not $Quiet) {
  "{0}" -f (Split-Path $Path -Leaf)
  "  compressed  : {0,12:N0} B" -f $n
  "  inflated    : {0,12:N0} B" -f $data.Length
  "  blocks      : {0} ({1} short)" -f $blocks, $short
  "  elapsed     : {0:N1}s" -f $sw.Elapsed.TotalSeconds
}
if ($Out) { [IO.File]::WriteAllBytes($Out, $data); if (-not $Quiet) { "  wrote       : $Out" } }
