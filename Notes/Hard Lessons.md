---
title: "Hard Lessons"
description: "Every mistake this project paid for, and the rule that prevents each one. Read before writing mod code"
updated: 2026-08-06
confidence: verified
tags:
  - method
  - reference
---

Each entry cost at least one wasted session or one broken thing in game. They are written as
rules because that is how they are useful.

## Working in game

### 1. Never call a GUI function whose argument shape you have not seen in shipped code

**The single highest-value rule in this project.** Most Fable III GUI calls resolve a
localisation id and render nothing for a raw string. A few take raw strings. The only way to
tell is to find a shipped call site passing a literal.

| Verified by a shipped literal | Works |
|---|---|
| `GUI.DisplayMessageBox("...")` | yes |
| `GUI.SetCounter("id", "label %1", n)` - from QMP010 `"P1 Score: %1"` | yes |
| `GUI.AskYesNoQuestion("...")` - from the barman subgame | yes |
| `GUI.AskForAmount` - shape from the qv020 chicken bet | yes |
| **No shipped literal** | **Dead** |
| `GUI.ShowTopBoxMessage` | renders nothing |
| `GUI.DisplayInfoBoxParams` | renders nothing, even with a real id and `TargetHero` |

The same rule broke the body swap: `GraphicAppearanceMorph.SetCharacterRecord` is real and
works, but it was passed a **creature type name** where every shipped call passes a
**character record name**. The entity lost its body. → [[Child System]]

```
grep -rhoE 'GUI\.TheCall\([^)]*\)' work/decompiled/scripts | sort -u
```

### 2. Add exactly ONE unproven call per push

There is **no `pcall`** in this environment. An error inside the worker kills its coroutine
silently, and `GeneralScriptManager` re-raises it. A push with five new calls that goes quiet
tells you nothing. v15 did that and cost a session; v16 bisected the same ground in one run by
reporting after each added call.

### 3. Make silence mean exactly one thing

A diagnostic that produces nothing must distinguish "the thing under test failed" from "the
code never ran". Add a liveness counter that reports regardless. The v17 message
`no expression detected, worker alive (frames=5592)` is what finally killed the expression
trigger as a theory; three earlier rounds of silence had proved nothing.

### 4. Version-key every piece of persistent state

Globals survive live edits, which is the feature that makes iteration pleasant and also the
thing that hides failures:

- `if F3MOD_HUD == nil` skipped re-registration because v4 had already set it, leaving a dead
  worker in place and producing exactly the silence of a broken channel.
- A fresh `seen = {}` per worker re-reported every NPC on every push.

Use `if F3MOD.version ~= VERSION`, never a nil check.

### 5. Make workers self-retiring, never trust a handshake

Set the loop condition to `while F3MOD ~= nil and F3MOD.worker == self`. Retiring the old
worker by setting a flag on it fails whenever the retirement path does not run, and two live
workers double every popup and race each other for dialog replies through a shared watermark.

### 6. Syntax-check BEFORE copying to the game, and read the result

`python tools/syntax-check.py mods/injector` must pass before the `cp`. A broken file can take
the injector down until a restart. Chaining check-and-push in one command and not reading the
output defeats the check entirely; that shipped a file with an unterminated string.

### 7. Scripts only run while the world ticks

Paused, in a menu, in a load screen, and often in cutscenes, nothing runs at all. Several
"it did not work" rounds were "it never ran". Gate anything the player must witness on
`GUI.IsScreenFading()` and `GUI.IsAnyMenuOpen()`, and set the done-flag **after** the work, so
a bad moment retries instead of being consumed.

### 8. `Debug.SetUseFreeCamera(true)` is a trap

It captures all keyboard input, including the yes/no box's own keys, and the camera is driven
by the debug key system which does not work in retail. There is no way to fly and no way to
leave. `MyScript01.lua` now force-disables it on every run, before the version check.

## Working on the tooling

### 9. Rebuild the binary, not just the library

`cargo test` builds the lib; a stale `bnkpack.exe` wrote unaligned banks while the alignment
test passed.

### 10. Do not batch-patch source with scripted string replacement

A Python patch turned `\n` inside a Lua string into a real newline. Use `Edit` for anything
delicate.

### 11. Read the reference implementation's constants literally

`GDB_Dump.cpp` comments say `0400 = string hash`. That is `0x0400`, not `4`. Reading it as a
small integer made every field type print as unknown while everything else looked fine.

### 12. Do not install a save someone uploaded because it was broken

`squark`'s save was posted asking for help diagnosing it. Format compatibility is not evidence
of safety. → [[Preservation]]

## Related

- [[Lua Scripting]] · [[Child System]] · [[Formats]] · [[Reference Index]]
