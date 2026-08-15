---
title: "Hard Lessons"
description: "Every mistake this project paid for, and the rule that prevents each one. Read before writing mod code"
updated: 2026-08-15
confidence: verified
tags:
  - method
  - reference
---

Each entry cost at least one wasted session or one broken thing in game. They are written as
rules because that is how they are useful. Rules 20-23 are the native/DLL layer and were paid
for in one long session; 16-18 are the ones that decide whether a format job is safe to build
on, and 18 is the one that would have saved the most time.

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

### 9. A character record is meshes; the skeleton belongs to the creature type

`SetCharacterRecord` swapped an adult body onto a child and produced a short, wrong-proportioned
adult. `GraphicAppearance.SetScale` only stretched it. Proportions, animation and rig come from
the **creature type**, which no call can change - so the entity must be replaced
(`PutEntityInLimbo` + `Debug.CreateEntityAtEntitysPosition`, the game's own idiom in
`ReplaceCollieWithACSCollie`). When an appearance fix looks 90% right, ask which component
actually owns the remaining 10% before patching harder. -> [[Child System]]

### 10. Never hand a nil entity to a native call, and never "tidy" an asymmetric API

Two game-crashing bugs in one session, both from inventing an argument shape:
`PlayerFamily.AdoptWithSpouse(hero, nil, kid)` (native code dereferences the nil) and
`Villager.AddChild(hero, kid)` (the hero has no Villager component - every shipped call
passes a villager, and the hero appears only via `AddParent`). Optional-looking arguments
are not optional, and an API that looks inconsistent usually reflects a real component
split. This is Rule 1 again, for arguments rather than functions. -> [[Child System]]

### 11. An entity's NAME is not its creature type

`entity:GetName()` starts with the type only for world-placed NPCs. Anything spawned with a
custom name (`Debug.CreateEntityAtEntitysPosition(type, "F3Daughter", ...)`) reports that
name instead, so type-name parsing silently fails on exactly the entities you created for
testing. `Creature.GetCreatureType` does not rescue it - it returns a broad enum
(`CREATURE_VILLAGER`). Derive from a real property (sex, age group) where you can.

### 12. Index the corpus, do not grep it reactively

`SearchTools` - a complete entity finder (`StartNewSearch` / `FilterWithinDistanceOfPos` /
`GetSearchResults`) - sat in dozens of shipped scripts for the entire project while problems
were worked around for want of it. It was found by reading someone else's published mod, not
our own 797-file corpus. There are **5,401 distinct API calls across 679 namespaces** in
there; `python tools/api-index.py search <text>` now answers "does a call for this exist"
in one step. Ask the index before assuming a capability is missing.

## Working on the tooling

### 13. Rebuild the binary, not just the library

`cargo test` builds the lib; a stale `bnkpack.exe` wrote unaligned banks while the alignment
test passed.

### 14. Do not batch-patch source with scripted string replacement

A Python patch turned `\n` inside a Lua string into a real newline. Use `Edit` for anything
delicate.

### 15. Read the reference implementation's constants literally

`GDB_Dump.cpp` comments say `0400 = string hash`. That is `0x0400`, not `4`. Reading it as a
small integer made every field type print as unknown while everything else looked fine.

### 16. A reference reader is not the game, and the game is the one you have to satisfy

The BNK index is chunked zlib. BnkBrowser **concatenates every chunk payload and then
inflates once**, so any split whose declared lengths add up reads back perfectly - and
`write_bank` split the compressed bytes proportionally on that basis, with a comment saying
the split was free to be arbitrary. **The game inflates chunk by chunk.** A chunk declaring
65536 that yields 11787 on its own leaves it with a truncated index: black screen, crash on
launch, and nothing in any log, because every one of our own tools read the file back
happily.

The shipped framing says it plainly if you look: `27179, 3885, 3881, 4470` compressed for
four 64 KB blocks. Wildly uneven, because it is one stream sync-flushed at each boundary so
the dictionary carries over. Compressing that way reproduces the game's own packer to
within a byte. There is now a test asserting each chunk decodes to its declared length,
which is the property the reader cannot see.

It hid this long because it only bites indexes over 64 KB. `ScriptInjector.bnk` repacks
byte-identically and has one chunk. **When a format is recovered from someone else's
reader, list the things that reader normalises away - those are exactly where it is silent
about the real constraint.**

### 17. Find EVERY sorted table before you add a row to any of them

`gdbwrite --verify` reproduced `globals.gdb` byte for byte and `--clone` still produced a
record the engine could not find. A round trip only proves you can reproduce what is there;
it says nothing about the rules a **new** entry has to obey.

Adding one GDB record touches **two** sorted tables, and each cost a separate test round
because they were found one at a time:

| Table | Sorted by | Missing it gives you |
|---|---|---|
| object hashes | object hash, 93 of 93 shipped files | the record is unreachable, silently |
| name map | FNV-1 of the name, 140 of 140 shipped files | `GDB.RecordExists` says no, and the record really is there |

The second one is the nastier lesson: the record was present, complete, byte-correct and
verifiably loaded, and the engine's binary search walked straight past it. **Before adding
a row anywhere, audit every parallel array in the format for order, uniqueness and range,
across all shipped files rather than one** - and check them all in one pass, because finding
them one at a time costs a restart each. → [[Formats]]

### 18. Design the test so a NEGATIVE result means something

Five failed in-game attempts on one feature, and most of them taught nothing, because the
test could not distinguish the hypotheses:

- **Patch every model that shares a visual role, or "look at a barrel" is meaningless.**
  Three separate models are "a barrel". Twice a change was shipped on one of them and the
  answer "looks the same" was ambiguous rather than negative.
- **Never ask someone to compare props they cannot reach.** A test spanning a Bowerstone
  model and a Brightwall model is unrunnable by a player standing in Brightwall.
- **A pass condition of "looks like the original" proves nothing.** Rewriting a bank entry
  and seeing a normal barrel is equally consistent with "the write worked" and "the write
  was ignored and the old bytes were read". Make the control differ in a way only a
  *successful* write can produce.
- **Order the tests so each one narrows the next.** Container, then size, then counts, then
  content. Running them out of order means an early failure has four possible causes and the
  result cannot be attributed.

The corollary that cost the most: **fixing a real bug is not evidence you fixed THE bug.**
Winding, bounds, tangents and the compressed-entry flag were all genuine conformance errors,
each measurably wrong against the game's own data, and none of them was the cause. Bisecting
against a known-good control found more in one step than four rounds of fixing.

### 19. Do not install a save someone uploaded because it was broken

`squark`'s save was posted asking for help diagnosing it. Format compatibility is not evidence
of safety. → [[Preservation]]

## Working in native code (the bridge DLL)

### 20. Give native code a log file before anything else

In Lua a failure is visible; in an injected DLL every failure looks identical from in front
of the game. "Not loaded", "hook not firing", "hook fired but drew nothing", and "thread
died" are the same black screen. One `log()` appending to `<game dir>\f3bridge.log` killed
four wrong theories in four runs. This is Rule 3 one layer down. → [[Bridge DLL]]

### 21. In this game, hook to READ, never to DRAW

Rendering anything through the device from an EndScene hook works for exactly one frame,
then the hook is silently bypassed forever while the game keeps animating. A full
`D3DSBT_ALL` state block does not save it. Retail ships `DFA.dll` and `F3Secu.exe`. Poll
input in the hook, and let the game's own HUD (`GUI.SetCounter`) do the drawing.

### 22. Do not add threads or system-wide hooks to this process

`CreateThread` from `Direct3DCreate9` wedges startup (`DLL_THREAD_ATTACH` walks every
loaded DLL, anti-tamper included). Creating it in `DllMain` deadlocks the loader instead.
`SetWindowsHookEx(WH_KEYBOARD_LL)` stops the game launching at all. All three were
unnecessary: polling `GetAsyncKeyState` inside the existing Present hook does the job.

### 23. Check the evidence you already have before theorising

Two rounds were spent on "DirectInput exclusive mode is eating the keyboard", complete with
supporting web research. The first log ever captured already contained `F1 -> menu OPEN`
from the Present hook - the input path had worked from the start, and the real fault was a
thread dying before it polled. Re-read the earliest log before proposing a new mechanism.


## Related

- [[Lua Scripting]] · [[Child System]] · [[Bridge DLL]] · [[Weapon Augments]] · [[Formats]] · [[Reference Index]]
