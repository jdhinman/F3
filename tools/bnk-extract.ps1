<#
.SYNOPSIS
  List or extract a Fable III BNK archive (index .bnk + payload .bnk.dat).

.DESCRIPTION
  Format recovered by decompiling BlackDemon's BnkBrowser.exe (managed .NET) with
  ilspycmd and reading its OpenArchive/Extract methods. See Notes/Formats.md.

  INDEX FILE (.bnk), all integers big-endian:

      BE32   total file size        (ignored)
      BE32   version                (4)
      byte   compressedFlag         non-zero -> entries use the 5-field form
      repeat to EOF:
          BE32  chunkCompressedLen
          BE32  chunkUncompressedLen   (summed to give the total)
          bytes[chunkCompressedLen]

  The chunk payloads CONCATENATE into a single zlib stream. They are not
  independent streams - that mistake caps recovery at the first 64 KB.

  INFLATED INDEX:

      BE32   (ignored)
      BE32   fileCount
      per file, if compressedFlag:
          BE32 hash, BE32 offset, BE32 realSize, BE32 size, BE32 numChunks
          skip numChunks*4
      per file, else:
          BE32 hash, BE32 offset, BE32 size
      then per file:
          BE32 pathLen; bytes[pathLen-1] path; byte 0; 7 x BE32 metadata

  PAYLOAD (.bnk.dat): seek to Offset. Uncompressed entries are Size bytes
  verbatim. Compressed entries hold numChunks zlib streams, each occupying a
  fixed 32768-byte slot in the compressed data.

  Hashes are FNV-1 over the lowercased path (basis 2166136261, prime 16777619).

.EXAMPLE
  .\bnk-extract.ps1 -Bnk "C:\Games\Fable 3\data\gamescripts.bnk" -List
  .\bnk-extract.ps1 -Bnk "C:\Games\Fable 3\data\gamescripts.bnk" -Out .\out
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Bnk,
  [string]$Out,
  [switch]$List,
  [string]$Filter
)

function Get-BE32([byte[]]$a, [int]$o) {
  return ([long]$a[$o] -shl 24) -bor ([long]$a[$o+1] -shl 16) -bor ([long]$a[$o+2] -shl 8) -bor [long]$a[$o+3]
}
# raw zlib stream -> bytes. Skips the 2-byte zlib header; DeflateStream wants raw deflate.
function Expand-Zlib([byte[]]$buf, [int]$off, [int]$len, [int]$expect) {
  $ms = New-Object IO.MemoryStream($buf, ($off + 2), ($len - 2), $false)
  $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
  $o = New-Object IO.MemoryStream
  $tmp = New-Object byte[] 65536
  try {
    while ($true) {
      $r = $ds.Read($tmp, 0, $tmp.Length)
      if ($r -le 0) { break }
      $o.Write($tmp, 0, $r)
      if ($expect -gt 0 -and $o.Length -ge $expect) { break }
    }
  } catch { }
  $ds.Dispose(); $ms.Dispose()
  return $o.ToArray()
}

$idxBytes = [IO.File]::ReadAllBytes($Bnk)
$datPath = "$Bnk.dat"
if (-not (Test-Path $datPath)) { throw "missing payload: $datPath" }

# --- read the index chunk chain -----------------------------------------
$compressedFlag = $idxBytes[8] -ne 0
$p = 9
$parts = New-Object IO.MemoryStream
$totalUnc = 0
while ($p -lt $idxBytes.Length - 8) {
  $cl = [int](Get-BE32 $idxBytes $p); $p += 4
  $ul = [int](Get-BE32 $idxBytes $p); $p += 4
  if ($cl -le 0 -or $p + $cl -gt $idxBytes.Length) { break }
  $parts.Write($idxBytes, $p, $cl)
  $totalUnc += $ul
  $p += $cl
}
$blob = $parts.ToArray()
$idx = Expand-Zlib $blob 0 $blob.Length $totalUnc
if ($idx.Length -eq 0) { throw "index failed to inflate" }

# --- parse entries -------------------------------------------------------
$q = 4
$count = [int](Get-BE32 $idx $q); $q += 4
$files = New-Object 'System.Collections.Generic.List[object]'
for ($i = 0; $i -lt $count; $i++) {
  $hash = Get-BE32 $idx $q; $q += 4
  $off  = Get-BE32 $idx $q; $q += 4
  if ($compressedFlag) {
    $real = [int](Get-BE32 $idx $q); $q += 4
    $size = [int](Get-BE32 $idx $q); $q += 4
    $nch  = [int](Get-BE32 $idx $q); $q += 4
    $q += $nch * 4
    $files.Add([pscustomobject]@{ Hash=$hash; Offset=$off; Size=$size; RealSize=$real; Chunks=$nch; Compressed=$true; Path='' })
  } else {
    $size = [int](Get-BE32 $idx $q); $q += 4
    $files.Add([pscustomobject]@{ Hash=$hash; Offset=$off; Size=$size; RealSize=$size; Chunks=0; Compressed=$false; Path='' })
  }
}
for ($j = 0; $j -lt $count; $j++) {
  $plen = [int](Get-BE32 $idx $q); $q += 4
  $files[$j].Path = [Text.Encoding]::ASCII.GetString($idx, $q, $plen - 1)
  $q += $plen
  $q += 28   # 7 x BE32 metadata
}

"{0}: {1} entries, index inflated to {2:N0} B, compressedFlag={3}" -f (Split-Path $Bnk -Leaf), $count, $idx.Length, $compressedFlag

$sel = if ($Filter) { $files | Where-Object { $_.Path -like "*$Filter*" } } else { $files }
if ($List) {
  $sel | Select-Object -First 40 | ForEach-Object {
    "  {0,10:N0} B {1} {2}" -f $_.RealSize, $(if ($_.Compressed) { 'C' } else { 'U' }), $_.Path }
  "  ({0} shown of {1})" -f ([Math]::Min(40, @($sel).Count)), @($sel).Count
  return
}
if (-not $Out) { return }

# --- extract -------------------------------------------------------------
$dat = [IO.File]::ReadAllBytes($datPath)
New-Item -ItemType Directory -Force $Out | Out-Null
$ok = 0; $bad = 0; $bytes = 0
foreach ($f in $sel) {
  $dest = Join-Path $Out ($f.Path -replace '/', '\')
  $dir = Split-Path $dest -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  try {
    if (-not $f.Compressed) {
      $b = New-Object byte[] $f.Size
      [Array]::Copy($dat, $f.Offset, $b, 0, $f.Size)
      [IO.File]::WriteAllBytes($dest, $b)
    } else {
      $o = New-Object IO.MemoryStream
      $remaining = $f.Size
      for ($c = 0; $c -lt $f.Chunks; $c++) {
        $cOff = [int]$f.Offset + ($c * 32768)
        $cLen = [Math]::Min($remaining, 32768)
        if ($cLen -le 2) { break }
        $part = Expand-Zlib $dat $cOff $cLen 0
        $o.Write($part, 0, $part.Length)
        $remaining -= 32768
      }
      $b = $o.ToArray()
      [IO.File]::WriteAllBytes($dest, $b)
    }
    $bytes += (Get-Item $dest).Length
    $ok++
  } catch { $bad++ }
}
"extracted {0} files ({1:N0} B), {2} failed -> {3}" -f $ok, $bytes, $bad, $Out
