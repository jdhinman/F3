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

## Housekeeping

- **Fable3Mod forums unread**, only search-summarised.
- **No file in the install has been opened.**
- Licensing not established for any third-party tool we might vendor.
