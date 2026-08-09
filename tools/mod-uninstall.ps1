# Put the Fable III install back to stock: remove the injector DLC, the loose mod
# scripts, and restore dir.manifest from the backup taken at install time.
#
#   .\tools\mod-uninstall.ps1
#   .\tools\mod-uninstall.ps1 -Game "D:\Games\Fable 3"
#
# Safe to run twice. Never touches save games.

[CmdletBinding()]
param(
    [string]$Game = "C:\Games\Fable 3"
)

$ErrorActionPreference = 'Stop'
$data = Join-Path $Game 'data'

if (-not (Test-Path $data)) { throw "not a Fable III install: $Game" }

$manifest = Join-Path $data 'dir.manifest'
$backup = Join-Path $data 'dir.manifest.stock-backup'
if (Test-Path $backup) {
    Copy-Item $backup $manifest -Force
    Remove-Item $backup -Force
    Write-Output "restored dir.manifest from backup"
} else {
    # No backup, so strip our own lines rather than leave them behind.
    $lines = Get-Content $manifest
    $kept = $lines | Where-Object { $_ -notmatch '^scripts\\MyMod\\' }
    if ($kept.Count -ne $lines.Count) {
        Set-Content -Path $manifest -Value $kept -Encoding ascii
        Write-Output "no backup found; removed $($lines.Count - $kept.Count) MyMod line(s) from dir.manifest"
    } else {
        Write-Output "dir.manifest already clean"
    }
}

foreach ($p in @((Join-Path $Game 'DLC\10_ScriptInjector'), (Join-Path $data 'scripts'), (Join-Path $data 'scripts_r'))) {
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force
        Write-Output "removed $p"
    }
}

$left = @()
foreach ($p in @((Join-Path $Game 'DLC\10_ScriptInjector'), (Join-Path $data 'scripts'))) {
    if (Test-Path $p) { $left += $p }
}
if ($left.Count -gt 0) { throw "still present: $($left -join ', ')" }

Write-Output ""
Write-Output "install is stock. Save games were not touched."
Write-Output "dir.manifest is $((Get-Content $manifest).Count) lines (stock is 530)."
