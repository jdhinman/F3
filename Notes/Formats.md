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

### The BNK format, complete  **[VERIFIED]** 2026-08-05

Recovered by decompiling **BlackDemon's `BnkBrowser.exe`** - it is managed .NET, so `ilspycmd` turns
it back into readable C#, and its `OpenArchive` and `Extract` methods are the specification. No
guessing required, and no need to run an unknown 2013 binary.

**Everything is big-endian.**

**Index file (`x.bnk`):**

```
BE32   total file size          (ignored by the reader)
BE32   version                  (4)
byte   compressedFlag           non-zero -> entries use the 5-field form
repeat to EOF:
    BE32  chunkCompressedLen
    BE32  chunkUncompressedLen  (summed for the total)
    bytes[chunkCompressedLen]
```

> [!warning] The trap that cost the most time
> Those chunk payloads **concatenate into a single zlib stream**. They are not independent streams.
> Treating each as its own stream caps recovery at the first 64 KB and silently loses everything
> after it.

**Inflated index:**

```
BE32   (ignored)
BE32   fileCount
per file, if compressedFlag:
    BE32 hash, BE32 offset, BE32 realSize, BE32 size, BE32 numChunks
    skip numChunks * 4
per file, otherwise:
    BE32 hash, BE32 offset, BE32 size
then per file:
    BE32 pathLen
    bytes[pathLen-1]  path
    byte 0
    7 x BE32          metadata
```

**Payload (`x.bnk.dat`):** seek to `offset`. Uncompressed entries are `size` bytes verbatim.
Compressed entries hold `numChunks` zlib streams, **each occupying a fixed 32,768-byte slot** in the
compressed data - so chunk *n* starts at `offset + n*32768`, and only the final chunk is short.

**Hashes** are **FNV-1** over the lowercased path: basis `2166136261`, prime `16777619`, multiply
then XOR.

### Writing banks  **[VERIFIED]** 2026-08-06

`crates/bnk` reads and writes banks; `bnkpack` builds one from a directory, `bnkinfo` dumps an
index including the fields whose meaning is unknown.

Two details the spec above did not capture, read off the community's DLC bank and now reproduced:

- **Payload entries are 16-byte aligned**, and the payload is padded to a 16-byte boundary at the
  end. Their four entries sit at 0, 688, 1504, 4272 - each the previous end rounded up to 16.
- **The seventh metadata word is the alignment.** It is `16` on every entry. The other six are zero
  there, so `DEFAULT_META` is `[0, 0, 0, 0, 0, 0, 16]`. The writer carries all seven through
  verbatim on a repack rather than guessing at the unknown ones.

The proof is a round-trip against a bank the game actually loads: unpack the community
`ScriptInjector.bnk`, repack it with `bnkpack`, and the **payload is byte-for-byte identical**,
with every decoded index field matching. The index bytes themselves differ, because the index is
zlib-compressed and the compressor is not the same one - which is expected and does not matter,
since the reader inflates it.

The writer emits only the uncompressed-entry form (`compressedFlag = 0`), which is what the DLC
bank uses. That avoids having to reproduce the game's chunked-zlib payload layout, where each chunk
occupies a fixed 32,768-byte slot.

### It works, end to end  **[VERIFIED]**

`tools/bnk-extract.ps1` implements the above.

| Bank | Entries | Result |
|---|---|---|
| `guiscripts.bnk` | 157 | index inflates to 14,454 B exactly |
| `gamescripts.bnk` | **803** | **803 files extracted, 0 failed, 16.3 MB** |

**803 entries against the 804 files listed in [[Preservation|`functions.txt`]]** - independent
confirmation that the extraction is complete rather than partial.

Of 797 `.lua` files, a 400-file sample was **400/400 valid Lua chunks**, and **367 carried a `source`
string**, so the debug data survives extraction. → [[KoreVM]]

This supersedes the earlier scanning approach, which recovered ~31 of 803 and produced a misleading
"47 scripts" inventory.

**Do not extract payloads by scanning for zlib headers.** It loses most of the data: a scan recovered
only 31-47 distinct scripts from `gamescripts`, against **804 script files** listed in
[[Preservation|`functions.txt`]]. Any inventory taken that way is a floor, not a census. Use the index.

> [!warning] Two engineering traps, both paid for
> **Never slice the byte array to feed a stream.** `$bytes[$i..$end]` copies the whole remainder at
> every candidate offset and makes scanning quadratic - it ran over six minutes on a 4.5 MB file
> before being killed. Use `MemoryStream($bytes, $offset, $count, $false)`, which is a view.
>
> **PowerShell variables are case-insensitive.** A `$out` accumulator silently aliases the `-Out`
> parameter and becomes a string, so every `.Write()` fails at runtime. Name it something else.

## Save games  **[VERIFIED]** 2026-08-06

Saves live in `%USERPROFILE%\Saved Games\Lionhead Studios\Fable 3\<XUID>\`. Under Catspaw's
GFWL emulator the XUID comes from `xlive.ini`, which on this install is the default
`1122334400000000` with profile `Player1`.

Nine `.bin` files per slot, and three slots (`hero2autosave`, `hero2save1`, `hero2save2`):

| File | Size, one slot |
|---|---|
| `_mainsave.bin` | ~400-550 KB |
| `_failquestmainsave.bin` | ~650 KB |
| `_herosave.bin`, `_failquestherosave.bin` | ~27-29 KB |
| `_chaptersave.bin` | 4 KB |
| `_leaderboardstatssave.bin` | 7 KB |
| `_checksumsave.bin`, `_entityuid.bin`, `_saveuid.bin` | 12-16 B |

**The container is the same chunked zlib as a BNK index**, with no outer header at all - the file
begins with the first chunk:

```
repeat to EOF:
    BE32  compressedLen
    BE32  uncompressedLen   (65536 except the last)
    bytes[compressedLen]
```

and, exactly as with BNK indexes, **the chunk payloads concatenate into one zlib stream**.
`hero2save1_mainsave.bin` is 30 chunks over 412,707 of its 412,715 bytes and inflates to
**1,921,883 bytes, matching the declared total exactly**. The 8 trailing bytes are a footer.

Having already paid for that lesson on the index made this a ten-minute job rather than a day.

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
