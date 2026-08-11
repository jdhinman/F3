---
title: "Bridge DLL"
description: "The proxy DLL that gives Fable III a real keyboard bind: dinput8 host, DXVK alongside, and the four native approaches that fail in this game"
updated: 2026-08-10
confidence: verified
tags:
  - reference
  - target
---

**Status: working in game.** F1 opens a menu, up/down cycles, Enter runs the action.
`crates/bridge` builds one 32-bit DLL that can be installed as **either** `dinput8.dll`
(the default) **or** `d3d9.dll`; `tools/bridge-install.ps1` installs it. Removing it is
deleting one file.

**dinput8 is the default host** so that `d3d9.dll` stays free for DXVK. Fable3.exe imports
exactly one symbol from each library, so both are clean proxy hosts:

| Host | Forwards | Per-frame polling point |
|---|---|---|
| `dinput8.dll` (default) | `DirectInput8Create` | `IDirectInputDevice8::GetDeviceState` |
| `d3d9.dll` (legacy) | `Direct3DCreate9` | `IDirect3DDevice9::Present` |

Both are verified in game. The dinput8 log line to look for is
`dinput: GetDeviceState hook firing`.

The DLL does exactly one job: **read the keyboard and write a file.** Everything else -
menu state, drawing, all game mutation - stays in Lua, live-editable. Four more ambitious
native designs were tried first and all failed; each is recorded below because each one
looked obviously correct and cost a session.

## The architecture that works

```
dinput8.dll (ours)
  -> forwards DirectInput8Create to the real system dinput8 (the game imports ONE symbol)
  -> hooks IDirectInput8::CreateDevice -> IDirectInputDevice8::GetDeviceState
  -> in GetDeviceState: poll GetAsyncKeyState for F1/up/down/Enter. Draw NOTHING.
  -> on a keypress: write data\scripts\MyMod\F3Bridge.lua  (temp file + MoveFileEx)

MyScript01.lua worker (~15 Hz)
  -> RunScript("scripts\\MyMod\\F3Bridge.lua") every tick
  -> new F3KEY.seq -> update menu state -> GUI.SetCounter draws the menu line
  -> Enter runs the selected action with the proven Lua calls (Money, Stats, Age, ...)
```

Latency is one worker tick, about 70 ms. The bridge file needs a `dir.manifest` entry
(`RunScript` resolves through the manifest) and must always exist - `RunScript` on a
missing path raises a Lua error and there is no `pcall` here, so the installer seeds it.

## What fails, and why  **[VERIFIED in game]**

Every one of these was tested with a log file written from inside the DLL. Symptoms were
misleading in all four cases; the log is what settled each.

### 1. Drawing anything with D3D kills the hook

Draw a menu with `ID3DXFont` + `IDirect3DDevice9::Clear` inside the EndScene hook and it
renders correctly **for exactly one frame**, then our hook is never called again. The
give-away: the game keeps animating perfectly, so it is not a crash and not a freeze.
Stage logging proved the draw ran to completion (`draw: end`), and a state block
(`CreateStateBlock(D3DSBT_ALL)` + Capture/Apply) around it did **not** help.

Something in this game removes or bypasses the vtable hook the moment we render through
the device. `DFA.dll` and `F3Secu.exe` ship with retail and are the obvious suspects. Not
worth fighting: **hook for input, never draw.** The game's own HUD draws our menu instead.

### 2. A worker thread hangs startup

`CreateThread` from inside `Direct3DCreate9` wedges the game: the thread logs its first
loop tick and stops, and the game never reaches its **second** `Direct3DCreate9` call
(a healthy launch makes two). A new thread runs `DLL_THREAD_ATTACH` through every loaded
DLL, anti-tamper included, and startup never recovers. **No extra threads.**

### 3. Starting anything in DllMain deadlocks the loader

Creating the thread in `DllMain` instead deadlocked the game inside `CreateDevice`. Classic
loader-lock rule. `DllMain` now only stashes the module handle; all startup happens lazily
from `Direct3DCreate9`, which the game calls well after loading finishes.

### 4. A low-level keyboard hook hangs the whole game

`SetWindowsHookEx(WH_KEYBOARD_LL)` installs fine and then the game will not launch at all.
The hook routes **all system keyboard input** through our thread; if that thread is not
servicing it promptly, everything stalls. Tempting because the research says it beats
DirectInput exclusive mode - but it is far too blunt here. **Not needed anyway:** polling
`GetAsyncKeyState` from the Present hook works, and always did.

### The false lead that cost the most

`GetAsyncKeyState` was blamed for two rounds ("the game holds the keyboard through
DirectInput8 in exclusive mode"). It was never the problem. The very first log already
contained `F1 -> menu OPEN` from the Present hook. The thread was dying before it ever
polled, so the absence of key events looked like an input-API failure and was not.

## Method note

The single highest-value thing built here was `log()` writing to `<game dir>\f3bridge.log`
from inside the DLL. Every wrong theory above was killed by one line of that file. Without
it the failure modes are indistinguishable: "DLL not loaded", "hook not firing", "hook
firing but drawing invisible", and "thread dead" all look identical from in front of the
game. Same rule as Hard Lesson 3, one layer down. → [[Hard Lessons]]

Useful log markers, in order, for a healthy launch:

```
proxy: calling real Direct3DCreate9
proxy: real returned ok
proxy: CreateDevice hooked
createdevice returned
present hook firing
key vk=112 -> action 1
```

## What the DLL does and does not unlock

It removes the ceiling - anything the CPU runs can be hooked or read - but it does not
auto-expose the game. Every feature is still its own RE job on a stripped 2011 binary, and
iteration is compile-and-relaunch instead of Lua's one-second reload. So the split stays:

- **Lua** (live, ~80% of gameplay modding): AI/behaviour, quests, interactions, stats,
  inventory, appearance, weapon augments, age.
- **GDB** (one restart): definitions, balance, spawn tables. → [[Weapon Augments]]
- **DLL** (this doc): the things Lua genuinely cannot do - an arbitrary keyboard key being
  the proven one. A custom overlay is **not** on this list in this game; see failure 1.

## Recon (retail Fable3.exe)

- Imports exactly **one** symbol from `d3d9.dll`: `Direct3DCreate9`. Also `DINPUT8.dll`,
  `d3dx9_42.dll`, `xlive.dll` (already a community stub).
- Renderer is **Direct3D 9**. EndScene is ~1 call per frame here (measured 122 per 120
  presents), so the multi-pass theory for the one-frame flash was wrong.
- Lua VM is **KoreVM**, custom: no standard `luaL_` entry points, so registering a native
  function into the VM is not available. That is why the bridge is a file and not a call.

## Build and install

```bash
cargo build --release -p bridge --target i686-pc-windows-msvc
```

```bash
pwsh -File tools/bridge-install.ps1
```

Install with DXVK alongside:

```bash
pwsh -File tools/bridge-install.ps1 -Dxvk "<FableIIIUltimatePerf folder>"
```

Must be 32-bit (`Fable3.exe` is PE32) and the host export (`DirectInput8Create` or
`Direct3DCreate9`) must be **undecorated**; both are worth re-checking after any build
change, since a decorated export fails silently at load. `-Remove` uninstalls the bridge and
DXVK; `tools/mod-uninstall.ps1` also deletes them.

**If the game will not launch, delete `C:\Games\Fable 3\dinput8.dll`** (and `d3d9.dll` if
DXVK is installed). Those files are the entire install.

## Why dinput8, and DXVK alongside  **[SOLVED]**

Timeslip's save exporter (Nexus 15, 2011) is a **5 KB `dinput8.dll` proxy** that exports
exactly one symbol, `DirectInput8Create` - the same one-import situation we have with
`Direct3DCreate9` - and uses `GetAsyncKeyState` for its hotkeys plus `Beep` for feedback.

Three things that confirms:

1. **`GetAsyncKeyState` polling from a proxy DLL works in this game**, independently of our
   own finding, and was never blocked by DirectInput exclusive mode. The two rounds spent on
   that theory were wasted twice over.
2. **`dinput8.dll` is an equally good host.** `Fable3.exe` imports exactly one symbol from it.
   Moving the bridge there would free `d3d9.dll` for DXVK and resolve the conflict above with
   no chain-loading trickery.
3. **`Beep` is a zero-UI feedback channel** - useful for confirming a keypress registered
   without drawing anything, which matters in a game where drawing gets the hook killed.

That is now the shipped arrangement: bridge on `dinput8.dll`, DXVK on `d3d9.dll`, installed
together by `bridge-install.ps1 -Dxvk <folder>`.

**DXVK breaks alt-tab until one option is set.** Native D3D9 loses the device when a
fullscreen app loses focus, and Fable III drives its alt-tab handling off exactly that
signal; DXVK does not report device loss by default, so the game never learns it lost focus.

```
d3d9.deviceLossOnFocusLoss = True
```

`tools/dxvk.conf` carries that plus memory caps sized for a 32-bit process
(`d3d9.maxAvailableMemory = 1536`), and deliberately does **not** set
`d3d9.forceRefreshRate` - the config bundled with the perf mod pinned 170 Hz, which applies
only in exclusive fullscreen and is monitor-specific.

## Related

- [[fable3-live-modding]] (Lua layer, 15 Hz tick, proven channels) · [[Hard Lessons]]
- [[Weapon Augments]] · [[Reference Index]]
