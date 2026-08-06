---
title: "Prior Art"
description: "The state of Fable III modding as of 2026-08-05, from web research only"
updated: 2026-08-05
confidence: documented
tags:
  - tools
  - prior-art
---

> [!danger] Read this before building anything
> The Anniversary project logged **six** confidently wrong conclusions, and most came from the same
> cause: concluding before surveying prior art. This note exists first, deliberately, and it is
> **[DOCUMENTED] only** - none of it has been checked against a real install yet.

## The landscape

| Thing | What it is | Status |
|---|---|---|
| [Improved Script Injector (aka Console)](https://www.nexusmods.com/fableIII/mods/12) | **Lua script injection with hot reload.** The key tool | Nexus, account-gated download |
| [Keshire/Fable-3-GDB-Tool](https://github.com/Keshire/Fable-3-GDB-Tool) | C#, **MIT**, view and edit `.gdb` files. 25 commits, 6 stars | GitHub, forkable |
| GDB Editor v0.3 | Search/edit/save, re-link and edit parameter nodes | discussed on Fable3Mod forums |
| Save editor, GDB dumper, BNK extractor/injector | assorted, source available | scattered |
| [fable3mod.com](http://fable3mod.com/forums/) | The community hub, with forums for tools and discussion | aging, mirrors on `.net` |
| Killable Children, Augment Rework | example published mods | Nexus |

## How code actually runs  **[DOCUMENTED]**

This is the reason for the whole pivot. Fable III runs **Lua**:

- scripts live in `data\scripts\<YourMod>\`
- they are registered by adding a line to `data\dir.manifest`
- naming appears to drive scheduling: `MyScript01.lua` runs **once per 60 frames** (about a second at
  60fps), `MyScript02.lua` runs **when the screen is fading**
- **script edits apply without relaunching the game**; only the activation file needs a reload

If that holds, the iteration loop is seconds rather than minutes, which is the single biggest
practical difference from Anniversary.

**[UNKNOWN]** what API surface the Lua environment exposes: which engine functions are callable, what
globals exist, whether new entities or UI can be created. **This is the first thing to establish.**

## The GDB  **[DOCUMENTED]**

`globals.gdb` is a custom database holding game data. The community's own description is that it is
"a custom built database that developers still know very little about", which is the same starting
position as `game.bin` was on the Anniversary project - and that one ended fully decoded and verified.

An MIT-licensed C# editor exists, so there is a partial decode to build on rather than starting cold.

## The child system  **[DOCUMENTED]**

- Children grow **once**, baby to child, then stop permanently. They never become adults.
- Community reports place the child age data in `globals.gdb` under an **`AgeComponent`**, with a
  quoted "main children offset" of `101BF01F` and the fix being to set Age above 18.
- A hex-editing route is also described as an alternative to the GDB editor.

**[UNKNOWN]** whether raising that value actually produces an adult NPC or just a scaled-up child
model with broken animation, dialogue and AI. **Assume nothing here** - a working age number is not
the same as a working grown-up character.

## Platform caveats  **[DOCUMENTED]**

- **Fable III was delisted from Steam in October 2025** when Microsoft shut down Games for Windows
  Live. Only prior owners can install it.
- **GFWL is dead.** Single-player needs a stub GFWL DLL. DLC and achievements need further work.
- Nexus 403s automated fetches, so tool downloads have to be done by hand.

## What has NOT been checked

Everything. Specifically:

- No file has been opened. No claim above is **[VERIFIED]**.
- The Lua API surface is entirely unknown.
- The `.gdb` format has not been examined.
- The Fable3Mod forums have not been read, only search-summarised.
- Nothing has been checked for whether the child mod already exists.

## Related

- [[Child System]] · [[Open Questions]]
