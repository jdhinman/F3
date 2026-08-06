---
title: "Open Questions"
description: "What is unknown, ranked - everything, currently"
updated: 2026-08-05
tags:
  - moc
  - open
---

The game is not installed yet, so **nothing here is answered**. This is the work queue.

## Blocking - answer these first

**What does the Lua environment actually expose?** Which engine functions are callable, what globals
exist, can entities be queried or created, is there any output or logging channel to debug with.
Everything on the script route depends on this and none of it is known. → [[Prior Art]]

**Is the script injector still needed, or does the retail game load `dir.manifest` scripts on its
own?** If the game reads the manifest natively, the whole toolchain gets simpler.

**What is in `globals.gdb`, structurally?** An MIT-licensed C# editor exists, so there is a partial
decode to read rather than starting from bytes. → [[Prior Art]]

**Does the install even run?** GFWL is shut down; a stub DLL is reportedly required for
single-player. Nothing can be tested until the game boots.

## The target feature

**Does raising a child's age produce a working adult or a broken child?** The honest first milestone
is finding out precisely how it breaks. → [[Child System]]

**Has someone already made this mod?** Not yet checked. Doing so before building is the single
cheapest way to avoid repeating the Anniversary project's most common mistake.

**Where is a child entity actually stored** - in the save, in `globals.gdb`, or both?

## Toolchain

**Does the Anniversary composability model transfer?** Fable III Lua mods are text files registered
in a shared `data\dir.manifest`, which is exactly the shape of collision that field-level diff,
conflict detection and load-order merge were built for. Reusing the *method* is likely; reusing the
`.tng` parser is not.

**Is `dir.manifest` a merge point?** If every mod appends to one shared file, two mods installed
naively will fight over it. That is the same problem the Anniversary project solved for `.tng`.

## The decompiler - the community asked for a dev, this is the work

**Write the KoreVM decompiler back end.** Everything it needs now exists: the spec is complete, and
803 scripts with debug symbols are extractable. Order of work: lower the 87 specialised opcodes to
Lua 5.1's core set, build a CFG, structure it into if/while/for/repeat and short-circuit and/or,
rebuild expressions by symbolic execution over registers, then name locals from the debug data.
Validate against `ai/aibase.lua`. -> [[KoreVM]] [[Script Corpus]]

**Start with `miscellaneous/`.** Roughly 258 files, many plain enum tables that should decompile
even with an imperfect back end, and they name everything else in the corpus.

**Does `gamescripts.bnk` (non-`_r`) carry compiler debug data?** It is 1.37 MB larger than the
stripped bank. If yes, decompiled output gets real local names and line numbers, which changes what
the decompiler must reconstruct. **Test before writing any decompiler code.** -> [[KoreVM]]

**Build the decompiler back end.** Decoding is solved: 7-bit opcode, A/C/B/OP field order, 87
opcodes, all specified. What is missing is lowering the specialised opcodes to Lua 5.1 core,
CFG construction, structuring, and expression rebuilding. Not novel research. -> [[KoreVM]]

**Which LuaPlus version is KoreVM derived from?** The struct and specialised opcodes are LuaPlus.
Pinning the version gives reference semantics for every opcode for free.

~~**Finish the BNK index record layout**~~ **CLOSED 2026-08-05.** Recovered by decompiling
BnkBrowser.exe with ilspycmd - it is managed .NET, so its OpenArchive and Extract methods are the
specification. ``tools/bnk-extract.ps1`` extracts **803 of 803 entries from gamescripts.bnk, 0
failed**, matching the 804 files in functions.txt. The decompiler is unblocked. -> [[Formats]]

## Preservation - do this before building

**Mirror fable3mod.com.** 776 topics / 1,542 messages, broken TLS, plain HTTP only. The Formats (28
topics) and Tools (56) sections are irreplaceable. -> [[Preservation]]

**Capture the four forum attachments**: BNKUtils.zip (90 KB), fable3_decompiled_scripts_1.zip
(223 KB), ScriptInjector.zip (6.5 KB), Catspaw GFWL emu v15d. None is mirrored anywhere we control.

**Fork the MIT tools** (Fable3LUADecompiler, Fable-3-GDB-Tool) into third_party/ with licences intact.

**When was Fable III actually delisted?** Two contradictory claims: Steam October 2025, versus GFWL
2013-08-22 and Steam 2013-12-05. -> [[Preservation]]

## Housekeeping

- **Fable3Mod forums unread**, only search-summarised.
- **No file in the install has been opened.**
- Licensing not established for any third-party tool we might vendor.
