# Install the F3 bridge DLL, and optionally DXVK alongside it.
#
#   .\tools\bridge-install.ps1                 # bridge as dinput8.dll (default)
#   .\tools\bridge-install.ps1 -Dxvk <folder>  # also install DXVK as d3d9.dll
#   .\tools\bridge-install.ps1 -Host d3d9      # legacy: bridge as d3d9.dll instead
#   .\tools\bridge-install.ps1 -Remove
#
# The bridge defaults to **dinput8.dll** so that d3d9.dll stays free for DXVK, which ships
# under that name. Fable3.exe imports exactly one symbol from each of dinput8 and d3d9, so
# either is a clean proxy host; the dinput8 build polls input from the per-frame
# IDirectInputDevice8::GetDeviceState instead of Present. Never touches save games.

[CmdletBinding()]
param(
    [string]$Game = "C:\Games\Fable 3",
    [ValidateSet("dinput8", "d3d9")]
    [string]$HostDll = "dinput8",
    [string]$Dxvk,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$data = Join-Path $Game 'data'
if (-not (Test-Path $data)) { throw "not a Fable III install: $Game" }

$bridgeLua = Join-Path $data 'scripts\MyMod\F3Bridge.lua'
$manifest = Join-Path $data 'dir.manifest'
$targets = @((Join-Path $Game 'dinput8.dll'), (Join-Path $Game 'd3d9.dll'))

if ($Remove) {
    foreach ($t in $targets) {
        if (Test-Path $t) { Remove-Item $t -Force; Write-Output "removed $t" }
    }
    foreach ($extra in @('dxgi.dll', 'dxvk.conf')) {
        $p = Join-Path $Game $extra
        if (Test-Path $p) { Remove-Item $p -Force; Write-Output "removed $p" }
    }
    if (Test-Path $bridgeLua) { Remove-Item $bridgeLua -Force; Write-Output "removed F3Bridge.lua" }
    Write-Output "bridge and DXVK removed. The Lua mod and injector are untouched."
    exit 0
}

$src = Join-Path $PSScriptRoot '..\target\i686-pc-windows-msvc\release\bridge.dll'
if (-not (Test-Path $src)) {
    throw "build it first: cargo build --release -p bridge --target i686-pc-windows-msvc"
}
if (Get-Process -Name 'Fable3' -ErrorAction SilentlyContinue) {
    throw "Fable III is running. Quit it first, then rerun."
}

# One host at a time: leaving a stale copy under the other name would load us twice.
$dest = Join-Path $Game "$HostDll.dll"
$other = Join-Path $Game $(if ($HostDll -eq 'dinput8') { 'd3d9.dll' } else { 'dinput8.dll' })
if ((Test-Path $other) -and -not $Dxvk) {
    Remove-Item $other -Force
    Write-Output "removed stale bridge at $other"
}
Copy-Item $src $dest -Force
Write-Output "installed bridge as $dest"

if ($Dxvk) {
    if (-not (Test-Path $Dxvk)) { throw "DXVK folder not found: $Dxvk" }
    if ($HostDll -ne 'dinput8') { throw "DXVK needs d3d9.dll; run with -HostDll dinput8" }
    $copied = 0
    foreach ($f in @('d3d9.dll', 'dxgi.dll')) {
        $p = Join-Path $Dxvk $f
        if (Test-Path $p) { Copy-Item $p (Join-Path $Game $f) -Force; $copied++; Write-Output "installed DXVK $f" }
    }
    # Our tuned config, not the one bundled with the perf mod: that pinned a 170 Hz refresh
    # rate (exclusive-fullscreen only, and implicated in alt-tab breaking) and set dxgi keys
    # that do nothing in a D3D9 game.
    $ourConf = Join-Path $PSScriptRoot 'dxvk.conf'
    if (Test-Path $ourConf) {
        Copy-Item $ourConf (Join-Path $Game 'dxvk.conf') -Force
        Write-Output "installed tuned dxvk.conf (ours, not the mod's)"
    }
    if ($copied -eq 0) { throw "no DXVK files (d3d9.dll/dxgi.dll/dxvk.conf) found in $Dxvk" }
}

# Seed the command file so RunScript never hits a missing path (no pcall in that VM).
$modDir = Split-Path $bridgeLua -Parent
if (-not (Test-Path $modDir)) { New-Item -ItemType Directory -Force $modDir | Out-Null }
Set-Content -Path $bridgeLua -Value 'F3CMD = { id = 0, action = 0 }' -Encoding ascii
Write-Output "seeded $bridgeLua"

# RunScript resolves through dir.manifest, so the file needs an entry.
if ((Get-Content $manifest) -notcontains 'scripts\MyMod\F3Bridge.lua') {
    Add-Content -Path $manifest -Value "scripts\MyMod\F3Bridge.lua" -Encoding ascii
    Write-Output "added F3Bridge.lua to dir.manifest"
}

Write-Output ""
Write-Output "Done. Launch and press F1."
Write-Output "Log: $(Join-Path $Game 'f3bridge.log')  (look for 'dinput: GetDeviceState hook firing')"
