---
title: "Preservation"
description: "Fable III is delisted, its DLC is unobtainable even to owners, and its entire modding corpus sits on one aging forum behind a broken certificate"
updated: 2026-08-05
confidence: documented
tags:
  - meta
  - preservation
---

> [!danger] This is the strongest argument for the project
> Fable III is delisted. Its online service is dead. **Its DLC cannot be obtained by anyone, including
> people who paid for it.** Its entire modding toolchain exists as forum attachments on one site with
> a broken TLS certificate. Every tool we might build on is a single point of failure.

All **[DOCUMENTED]**, retrieved 2026-08-05.

## The DLC is effectively lost

This is the sharpest finding. Fable III's Steam "DLC" entries **were never downloadable content** -
they were Games for Windows Live keys. With GFWL shut down and Marketplace purchase-retrieval broken,
**there is no route to redownload them.**

From the fable3mod forums, a 2022 thread from someone who owned everything:

> *"I've been a long time fan of Fable games, and have bought every copy of Fable over the years...
> My issue now is getting working versions of the Fable 3 DLC... I've reached out to Steam and
> Microsoft for help, but they weren't able to assist."*

The reply pointed at a guide; the answer came back that the DLC links in it are dead. By 2023 the
thread was still unresolved.

The two DLCs are **`01_Understone`** and **`02_TraitorsKeep`**.

**This is not a side issue for us.** [[Lua Scripting|The script injection method requires a DLC folder
present]], and [[Child System|the child-age offsets are quoted as being "for latest DLC"]]. Whatever
we build has to state its DLC assumptions explicitly, and may need a no-DLC path.

> [!success] We have them
> This project's install includes **both DLCs**. That removes the blocker outright: the script
> injection method's DLC-folder requirement is satisfied, and the child-age offsets quoted as being
> "for latest DLC" can be checked against the version they were written for.
>
> It also means this machine holds a **complete reference copy** of a configuration that, per the
> threads above, paying customers can no longer assemble. Treat it accordingly: `backup/` is
> git-ignored, and the DLC content is copyrighted game data that is **never** committed or
> redistributed. What we publish is knowledge about it, not the thing itself.

### What *is* recoverable

The `content.xbx` manifest that marks a DLC folder as valid is **documented verbatim** on the forums
and can be reconstructed by hand - `TitleID=0x4D53090A`, `ContentPackageType`, `ContentID`, and so on,
with the expected layout:

```
..\Fable 3\DLC\01_Understone\content\*.*
..\Fable 3\DLC\01_Understone\content.xbx
..\Fable 3\DLC\02_TraitorsKeep\content\*.*
..\Fable 3\DLC\02_TraitorsKeep\content.xbx
```

So the *packaging* is recoverable. The *content* is not, unless you already have it.

## The corpus is small, finite, and fragile

[fable3mod.com](http://fable3mod.com/forums/) - FUDforum 3.0.9, **broken TLS certificate, plain HTTP
only**. Mirrors respond on `.net`, `w.`, and `ww.` prefixes.

| Forum | Topics | Messages | Last activity |
|---|---|---|---|
| General Discussion | 628 | 590 | Jul 2026 |
| **Modding Discussion** | **697** | **148** | Jul 2026 |
| Mods | 132 | 17 | Oct 2025 |
| **Tools** | **56** | **10** | Oct 2025 |
| **Formats** *(file format discussions)* | **28** | **10** | Feb 2022 |
| Announcements | 1 | 1 | Aug 2013 |

**Total: 1,542 messages across 776 topics.** 6,136 registered users.

That is small enough to mirror in full - comparable to the 49-page fabletlcmod wiki the Anniversary
project captured, which proved its worth repeatedly.

## Tools exist only as forum attachments

Every one of these is a single upload on an aging forum. **None of them is mirrored anywhere we
control.**

| Artefact | Size | Posted | Note |
|---|---|---|---|
| `BNKUtils.zip` (BlackDemon's BNK Utils) | 90 KB | 2013, Keshire | extract/list/create banks. **7,851 downloads** |
| `fable3_decompiled_scripts_1.zip` | 223 KB | 2013, Artofeel | the decompiled/rewritten game scripts |
| `ScriptInjector.zip` | 6.5 KB | 2014, Artofeel | the Lua injection method |
| Catspaw's GFWL emu, v15d | - | 2015, Artofeel | recommended over timeslip's remover |

Some tooling *is* on GitHub under MIT, which is far safer:

| Repo | What | Licence |
|---|---|---|
| [Keshire/Fable3LUADecompiler](https://github.com/Keshire/Fable3LUADecompiler) | decompiler for **KoreVM**, Fable 3's Lua VM. C#, .NET 4.7.2 | MIT |
| [Keshire/Fable-3-GDB-Tool](https://github.com/Keshire/Fable-3-GDB-Tool) | view and edit `.gdb` | MIT |
| [Keshire/Fable-A-BinaryModelUnpacker](https://github.com/Keshire/Fable-A-BinaryModelUnpacker) | unpacks LZO chunks of Anniversary `mesh.bbb` | **GPLv3** |
| [JustSomeGuy1234/Archons-Toolbox](https://github.com/JustSomeGuy1234/Archons-Toolbox) | Fable **2** Lua mod manager and framework | - |

Note the third one is **Fable Anniversary**, and it is GPLv3 because of LZO - the identical licence
trap the Anniversary project documented. Same hazard, different game.

## KoreVM, and why retail resists decompiling

Fable 3 does not run stock Lua. It runs **KoreVM**, a custom VM executing compiled Lua, and the
decompiler above was rewritten from a Call of Duty decompiler to handle its opcodes.

**The critical caveat, from that project's own README:** the retail scripts (`gamescripts_r`)
**lack the debug data the decompiler needs.** It is good at "rebuilding widgets and menus" and poor
at "decompiling big blocks of code used for functionality."

That reframes the 2013 archive. Artofeel described those files as *"scripts that I manually rewrote"*
- reconstruction, not clean automated output. So:

- **[INFERRED]** we probably cannot simply decompile our retail install and read the game's logic.
- The 2013 archive may therefore be **irreplaceable**, not merely convenient.
- Injecting *new* Lua does not require decompiling anything, so the modding route survives regardless.
  What we lose without decompilation is the API documentation.

## An unresolved contradiction

Two different delisting stories surfaced, and they cannot both be right:

- one source says Fable III was pulled from **Steam in October 2025**, tied to the GFWL shutdown
- another says delisted from **GFWL on 2013-08-22 and Steam on 2013-12-05**

**[UNKNOWN]** which is correct. The 2013 dates are more specific and fit the GFWL timeline better, but
this has not been verified. Recorded rather than guessed, because the Anniversary project's
[[Prior Art|worst mistakes]] all came from stating unverified things confidently.

## What should happen, in order

1. **Mirror the forum.** 776 topics is a bounded job, and the Formats and Tools sections are the
   irreplaceable parts.
2. **Capture the four attachments** above.
3. **Fork the MIT GitHub tools** into `third_party/`, licences intact, as the Anniversary project did.
4. Only then start building.

The Anniversary project learned this ordering the expensive way. Do the capture first.

## Related

- [[Lua Scripting]] · [[Child System]] · [[Prior Art]] · [[Open Questions]]
