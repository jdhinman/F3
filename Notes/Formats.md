---
title: "Formats"
description: "Fable III's file formats, from the community's own checklist, plus what tooling exists for each"
updated: 2026-08-05
confidence: documented
tags:
  - format
  - reference
---

All **[DOCUMENTED]**, from the mirrored fable3mod Formats forum. The checklist below was posted by
**Keshire** in 2013, copied from the Fable 2 forum, with his own caveat: *"This may be woefully out of
date."* Nothing here has been checked against an install. → [[Preservation]]

## The install, measured  **[VERIFIED]** - 2026-08-05, `C:\Games\Fable 3`

First facts checked against a real install rather than a forum post. **Baseline is the repack**, so
container-level numbers are provisional. → [[Preservation]]

**776 files, 13.6 GB.** Dominated by `.dat` (437 files, 11.8 GB) and `.bik` video (19, 1.4 GB).

| Directory | Files | Size |
|---|---|---|
| `data` | 574 | 11.3 GB |
| `DLC` | 68 | 2.1 GB |
| `Bonus Content` | 36 | 514 MB |

**All four DLCs are present**, each with a valid `content.xbx`: `understone_quest` (387 MB),
`traitors_keep` (1.68 GB), `inquisitor_pack`, `99_dlc2_fixes`. Per [[Preservation|the forum threads]]
this set is no longer obtainable.

`XLiveEmu\` exists with `Title1.dat` and `Achievements.txt`, so the GFWL emulator is already wired in.

> [!success] Both script banks ship, not just the stripped one
> The community's position was that retail only has `gamescripts_r` (no debug data), which is why
> decompiling is hard. **This install has both:**
>
> | Bank | Index | Data |
> |---|---|---|
> | `gamescripts.bnk` | 21,880 B | **4,587,359 B** |
> | `gamescripts_r.bnk` | 20,721 B | 3,222,157 B |
>
> The non-`_r` bank is **1.37 MB larger**, exactly what retained line information and local variable
> names would cost. **[INFERRED]** this is the debug build, which would make
> [[Lua Scripting|the decompilation problem]] far easier than the forums assume. **Test this early.**

## The BNK container  **[VERIFIED, partially decoded]**

Banks are split into a small **index** (`x.bnk`) and a large **payload** (`x.bnk.dat`) - structurally
the same idea as Anniversary's `.dep` index paired with its `.bbb`.

**The header is big-endian**, which fits Fable 3 being an Xbox 360 title first:

```
@0   uint32 BE   total size of the index file      (guiscripts.bnk: 4101 = its own length)
@4   uint32 BE   4                                 (version?)
@8   uint32 BE   0x01xxxxxx - low 24 bits look like an entry count
@17              zlib stream (78 DA) for small banks
```

Observed `@8` low-24 values: `guiscripts` 15, `gamescripts` 76, `gamescripts_r` 73, `levels` 106.
`levels` has a `0x00` high byte where the others have `0x01`, so that byte is probably a flag.

**`guiscripts.bnk` decodes end to end:** the zlib stream at offset 17 expands **4,101 -> 14,454
bytes** and contains the file table, with entries like

```
art\gui\gameface\hud.lua
art\gui\gameface\bedmenubox.bgf
art\gui\gameface\interactionmenurightcontrol.lua
```

### Index compression solved  **[VERIFIED]** 2026-08-05

The earlier "does not decompress" note was wrong twice over: the zlib header sits at **offset 17**
(deflate data at 19, not 17 - feeding DeflateStream the 2-byte header fails silently), and the index
is **block-compressed**, not one stream.

**Block layout, repeated to the end of the index:**

```
byte    flag              (varies per block; purpose unknown)
BE32    uncompressed size (65536, or less for the final block)
zlib    stream
```

Confirmed on `guiscripts.bnk`: header declares `0x3876` = **14,454**, and it inflates to exactly
14,454 in **1 block, 0 short**. The larger indexes stop at exactly 65,536 with a single stream, which
is the 64 KB block cap rather than corruption.

`tools/bnk-inflate.ps1` implements this.

### The payload is a different structure  **[UNKNOWN]**

`.bnk.dat` does **not** use the block format - it begins with a zlib stream at offset 0 with no block
header. Running the block reader over it yields less data than went in, which is impossible and
proves the model is wrong for payloads.

**[INFERRED]** each file in the bank is separately compressed, and the index carries per-file offset
and size. That matches the index's shape: a repeating record of roughly 24 bytes containing a 4-byte
value that looks like a **filename hash** (`9DBF3677`, `10AB0522`, `1CAB184F`...) followed by BE32
fields that look like offset and two sizes. Record stride alternates 20 and 28 bytes, so entries are
variable-length and the layout is not yet pinned.

**Do not extract payloads by scanning for zlib headers.** It loses most of the data: a scan recovered
only 31-47 distinct scripts from `gamescripts`, against **804 script files** listed in
[[Preservation|`functions.txt`]]. Any inventory taken that way is a floor, not a census.

**Next step:** finish the index record layout, then extract payload entries by offset. BlackDemon's
BNK Utils already does this correctly and is [[Preservation|captured]], so its behaviour is the
reference.

> [!warning] Two engineering traps, both paid for
> **Never slice the byte array to feed a stream.** `$bytes[$i..$end]` copies the whole remainder at
> every candidate offset and makes scanning quadratic - it ran over six minutes on a 4.5 MB file
> before being killed. Use `MemoryStream($bytes, $offset, $count, $false)`, which is a view.
>
> **PowerShell variables are case-insensitive.** A `$out` accumulator silently aliases the `-Out`
> parameter and becomes a string, so every `.Write()` fails at runtime. Name it something else.

## The container story

**Everything lives in a Virtual File System.** `.bnk` files are *"compressed archives. Part of the
Virtual File System (VFS)"*, and `data\dir.manifest` plus `startup.vfsconfig` control what the VFS
mounts.

That is the mechanism the whole modding scene rests on: **register a loose file in `dir.manifest` and
it overrides the archived one.** Structurally the same idea as Anniversary's WAD override folder, and
it is why [[Lua Scripting|dropping a `.lua` into `data\scripts\` works]].

`dir.manifest` is therefore both the entry point **and the obvious collision point**: every mod
appends to one shared file. → [[Open Questions]]

## Models, textures and related

| Ext | What |
|---|---|
| `MDL` | models |
| `GMD` | game mesh data - metadata about a model, not the model. Most models have one |
| `HKX` | model physics, resembles `HAVOK_SCENARIO` |
| `HPB` | model-related |
| `MOF` | skeletal morphs. **plain text** |
| `TEX` | textures. Likely DXTn, compression unknown, swizzling possible |
| `DDS` | image container |
| `BGF`, `BSG` | GUI art, third-party |
| `FAC` | GUI art, lists of UVs. **plain text** |

Tooling: **BlackDemon's BNK Utils** (extract/list/create banks), a **Blender 2.82 model importer**, a
**TEX converter**, and `mdl.hsl` (a hex-editor template). All captured.

## Animation

`ANIMATION_DATA`, `ANIMATION_TOC`, and `LOCO` - *"looks like animation data. The top looks to
determine what animations are used and when. The bottom has what looks like a list of animations."*

## Audio and text

| Ext | What |
|---|---|
| `ADB` | audio, compressed |
| `WAV` | audio, XMA2. *"No XMA2 codec exists"* |
| `AMP` | audio settings. **XML/plain text** |
| `CSV` | file hashes - one for audio, one for language |
| `BIN` | **lip sync data** |
| `BABEL` | region-specific text |
| `BFT` | region-specific fonts |

A **WAV converter** exists and is captured.

## Level data

Height fields dominate: `AMA`, `AMM`, `AMR` (all *"ADMP"*), `EHF` (*"HeightFieldGraphicsFile"*),
`HDB`, `GHF`, `LMP`. Note `GHF` starts `1F 8B 08 08` - that is a **gzip magic**, so those are very
likely compressed streams rather than a custom header.

Pathfinding is **Kynapse** middleware: `AIM` (Kynogon Mesh), `FDL` (Kynogon FindNearest Data),
`PDL` (Kynogon Spatial graph), `PPD`, plus `AI_CONFIG` as **XML/plain text**.

Also `GENV` (environment maps), `MIST`, `WATER`, `DAT` (lightprobes), `ENGINE_DATA`
(*"EngineResourceList"*), **`ENGINE_LEVEL`** (*"stores links to other files such as heightmaps and
flora models and has instancing data for flora"*), `HAVOK_SCENARIO`, `TEXTURE_ATLAS`, and `SAVE`
(**XML/plain text**, UIDs).

## Everything else

| Ext | What |
|---|---|
| **`GDB`** | **Global DataBase.** The main data store → [[Child System]] |
| `LUA` | scripts. *"There's one for nearly every component of the game"* |
| `BNK` | VFS archives |
| `SBK` | shader data, `ShaderBankFile` |
| `SWF` | **pub games, Flash 8 / AS2** - decompiles to FLA and ActionScript |
| `XML` | pub game settings and some in-game text |
| `BIK` | Bink video |
| `LIST` | plain text file lists |

## What this suggests about difficulty

**Easy, already text or near-text:** `LUA`, `MOF`, `FAC`, `AMP`, `AI_CONFIG`, `SAVE`, `XML`, `LIST`.
**Tooled already:** `BNK`, `MDL`, `TEX`, `WAV`, `GDB`.
**Middleware, so documented elsewhere:** Havok physics, Kynapse AI, Bink video, Flash pub games.
**Genuinely unknown:** the height-field family, `ENGINE_DATA`, `TEXTURE_ATLAS`, `HKX`/`HPB`.

The gameplay-relevant surface - scripts, the GDB, and the VFS - is the best-covered part, which is
fortunate given [[Child System|what this project is aiming at]].

## Related

- [[Lua Scripting]] · [[Child System]] · [[Preservation]] · [[Open Questions]]
