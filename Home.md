---
title: "Home"
description: "Entry point for the Fable III modding research vault"
updated: 2026-08-06
tags:
  - moc
---

> [!abstract] What this is
> A research vault and toolchain for **Fable III**, aimed at extending its family and child systems.
> Sibling of the [Fable Anniversary project](https://github.com/jdhinman/fa), which reached a hard
> ceiling: no supported way to run new code. Fable III runs **Lua**, hot-reloadable.

## Start here

| | |
|---|---|
| [[Prior Art]] | What already exists. Read before building anything |
| [[Lua Scripting]] | How new code runs, and why this platform was chosen |
| [[Preservation]] | What is already lost, what is at risk, and what to capture first |
| [[Formats]] | Every file format, and the first verified facts from a real install |
| [[KoreVM]] | **The VM fully specified.** Encoding, all 87 opcodes, chunk and proto layout |
| [[Script Corpus]] | **All 803 scripts extracted.** The AI, lifesim and economy architecture |
| [[Child System]] | The target feature, and why it is harder than one number |
| [[Open Questions]] | The work queue |
| [[Hard Lessons]] | **Read before writing mod code.** Twelve rules, each paid for |
| [[Reference Index]] | Where everything is: artefacts, tools, links |

> [!success] Code runs in the game
> As of 2026-08-06 arbitrary Lua executes in retail Fable III, live-editable with no restart,
> with a working non-modal HUD and an in-game menu. The age system is half solved: raising an
> NPC's age scalar past ~18 flips them to adult and the adult AI follows. The body does not.
> → [[Child System]] · [[Hard Lessons]] · [[Reference Index]]
