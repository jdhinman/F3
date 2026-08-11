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

> [!danger] Reading it that way does not mean you may WRITE it that way  **[VERIFIED]** 2026-08-11
> It is one stream, but it is **sync-flushed at every 64 KB boundary**, so each chunk also
> decodes to exactly its declared uncompressed length *on its own*. BnkBrowser concatenates
> before inflating and cannot tell the difference; **the game inflates chunk by chunk**. A
> proportional split of the compressed bytes reads back perfectly in every tool we own and
> hands the game a truncated index - black screen, crash on launch, nothing in any log.
>
> The shipped framing says it outright: `levels.bnk` is `27179, 3885, 3881, 4470` compressed
> for four 64 KB blocks. One big chunk then small ones, because the dictionary carries across
> the flush. Compressing that way reproduces it to within a byte (`...4469`). `crates/bnk` now
> has a test asserting the per-chunk property and `tools/bnk-replace.py` refuses to write an
> index that fails it.
>
> It only bites indexes over 64 KB, which is why the byte-identical `ScriptInjector.bnk`
> repack below never caught it: that index is a single chunk. → Hard Lesson 16

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

## The GDB object database  **[VERIFIED]** 2026-08-06

`crates/gdb` reads it; `gdbdump` is the CLI. Format taken from **BlackDemon's `GDB_Dump.cpp`**
(mirrored in `122-GDB_Dump.zip`) by reading the source, the same approach that recovered BNK
from BnkBrowser. The 2013 binary is never run.

**There is no loose `.gdb` on disk.** `globals\globals.gdb` lives inside `levels.bnk`, 4.7 MB,
stored uncompressed, so the bnk crate hands it over directly:

```bash
cargo run --release -p gdb --bin gdbdump -- --bank "C:\Games\Fable 3\data\levels.bnk"     --entry 'globals\globals.gdb' --find Dog --names
```

Result on this install: **114,796 objects, 23,470 named, 11,287 templates, 28,739 labels.**

**Little-endian**, unlike BNK. The dumper's `endian32_swap` only makes its printed hex look
big-endian; it is not in the data.

```
@0    u32   (unread)
@4    u32   object count
@8    u32   template block offset, relative to 0x18
@12   u32   index block offset, relative to the template block
@16   u32   unknown-hash count
@0x18       objects: u32 template pointer, then one u32 per template field
            templates: u8 components, u16 field count, u8 pad,
                       field-count hashes, then field-count (u16 array, u16 type)
            object hashes: u32 each, in object order
            unknown words: u16 each, padded to 4
            unknown table: (u32 float bits, u32 hash) per entry
            labels: u32 pad, u32 index size, u32 count, then (u32 hash, NUL string)
```

An object is a template pointer plus raw words; the **template** names and types each field and
the **label table** turns hashes into strings. Field name is `label(template.hash[i])`; for
string fields the value is `label(data[i])`.

Two traps, both paid for:

- **Type constants are literal.** The reference comments write `0400 = string hash`, meaning
  `0x0400`, not `4`. Reading them as small integers makes every field print as unknown type
  while names still resolve, so it looks almost right.
- **An object's name is not its hash.** It is the value of its first string-typed field.
  Using the hash names 1 object out of 114,796; using the field names 23,470.

`0xC59D1C81` is the sentinel for an empty string.

## Writing a GDB  **[VERIFIED]** 2026-08-10

`crates/gdb` can now write, not just read. `gdbwrite --verify` round-trips `globals.gdb`
**byte for byte** (4,699,186 bytes identical), which is the bar that makes anything built on
top trustworthy - the same standard the BNK repacker was held to.

Two corrections to the layout above came out of this:

- **`index size` in the label header is the byte length of the label string region**
  (866,714 here), not a count.
- **There is a trailing block the reader used to ignore**: one u32 per label, each an exact
  offset of a label entry. It is the label index. → decoded below.

### The label index, decoded  **[VERIFIED]** 2026-08-11

The trailing block is an **open-addressing hash table, serialized sparse-to-dense**:

```
slots      = the FIRST word of the label block header, 65536   (called "pad" before)
bucket     = label hash & (slots - 1)
collision  = linear probe forward one slot, wrapping at the end
insertion  = labels in file order
serialize  = walk slots 0..slots, emit the label's byte offset for every OCCUPIED slot
```

Empty slots emit nothing. That is why the block is one u32 per **label** rather than one
per slot, and why it looks *almost* sorted by `hash & 0xFFFF`: the ~1,789 apparent
inversions are displaced entries parked past a run of collisions. In `globals.gdb` the
longest probe run is 24 and the load factor is 0.44.

Two things fell out of the same look and both matter:

- **The first word of the label header is the table size, not padding.** It is 65536 in
  every GDB the game ships, including the ones with no labels at all, so it is a fixed
  constant rather than anything derived from the contents.
- **A label's hash is FNV-1 of its own text, case-sensitive** - true for all 28,739 labels
  in `globals.gdb`. So a new label's hash is computed, not chosen, and two different
  strings whose hashes collide cannot both exist. `add_label` refuses that case rather
  than let the engine resolve the new hash to the old string.

The index is now **rebuilt from scratch on every write**, nothing is preserved verbatim,
and the proof is every GDB in the installation:

```bash
gdbwrite --verify-all --bank "C:\Games\Fable 3\data\levels.bnk"
```

**147 GDB files across 134 banks - base game, all four DLCs - round trip byte for byte,
0 failed.** From `morphs.gdb` with no labels at all to `globals.gdb` with 28,739. Since
the index is regenerated rather than copied, each of those files is an independent test of
the probing scheme.

`add_label` therefore works, and `--set Field="text"` on `gdbwrite --clone` adds the label
and points a string field at it in one step.

### The per-object u16, decoded  **[VERIFIED]** 2026-08-11

The one u16 per object in the index block is a **random-access accelerator for a
variable-length record array**. Records are not fixed size, so finding object `i` would
normally mean walking every record before it. Instead the engine estimates the offset with
one multiply and a shift, and this array holds the exact correction:

```
stride  = (1024 * objectsBlockWords) / objectCount       integer division
word[i] = startOfRecord(i) - ((i * stride) >> 10)        both in u32 words
```

Two bytes per object instead of four for a full offset table, and O(1) indexing. The
correction is signed and small (-586..1886 in `globals.gdb`) because it only tracks how far
the running record size has drifted from the file's mean - which is also why it looked like
smooth positional noise and matched nothing about the object itself.

**Exact on every GDB in the installation: 147 files, 2,069,537 objects, no exceptions.**
The shift is 10 and nothing else - 8, 9, 11, 12 and 16 each fit under half the files,
because too small a shift quietly matches any file whose stride happens to be even at that
precision. That near-miss is what made this look unsolvable: a shift of 9 fits 76 of 147
files perfectly and fails the rest at object 512, exactly where a one-bit error in the
stride first shows.

> [!warning] This is why a clone cannot copy the source object's word
> Inserting a record changes every later record's start **and** the stride, so the whole
> array has to be recomputed. Copying the source value left ~7,600 objects after the
> insertion point pointing at the wrong bytes. It is now regenerated on every write.

Nothing in the scene had this. The community's GDBEditor calls it `partition`, groups
records by it in a tree "for research purposes", and says in as many words that it does not
know what it does. That tool also **writes a wrong label index**: read its
`GDBFileExport.cs`, and it emits the offsets in label file order, with the comment
*"There's some type of sorting going on here. Not sure what it is though."* - the correct
verbatim write is commented out just above it.

> [!note] A new label is an id, not necessarily visible text
> Labels carry two different kinds of string. Asset paths and internal names
> (`art\gui\wheelicons\items\icon_tofu5.tex`, `Character.Carry.Hand.Right`) are used
> directly. Names and descriptions (`INV_ITEM_WEAPON_HAMMER_RUSTYBASE_NAME`) are
> **localisation ids** resolved through the `.babel` text tables, so inventing one gets a
> valid id with no text behind it until BABEL is also decoded. → [[Open Questions]]

Adding records works by **cloning an existing object**:

```bash
gdbwrite --bank "...\levels.bnk" --entry "globals\globals.gdb" --clone DogCollet --name MyDog
```

Reusing the source object's template is what makes it safe: template pointers are offsets
into a block written back verbatim, so no pointer moves. The tool re-parses what it wrote
before reporting success.

> [!warning] Object hashes are SORTED, and a new record must be inserted, not appended
> **[VERIFIED]** 2026-08-11. Every one of the 93 shipped GDBs that has any objects at all
> holds its object-hash array in ascending order, which is what lets the engine find a
> record by binary search. `--clone` originally appended, which put the new record past the
> sort break where no search can reach it - correct bytes, unreachable record. It now
> inserts in hash order. That is safe because **nothing addresses an object by index**:
> `parent` fields and the name map both hold object hashes. Only the three index-parallel
> arrays (objects, hashes, the per-object u16) have to move together.

Changed records get into the game with `tools/bnk-replace.py`, which appends the new blob
to the payload and rewrites just that entry's offset and size in the bank index. Repacking
a 2.1 GB `levels.bnk.dat` to change one entry is not on, and the in-place dword patching
the older GDB tools use stops working the moment a record or a label makes the file longer.

```bash
python tools/bnk-replace.py apply  "C:\Games\Fable 3\data\levels.bnk" "globals\globals.gdb" work/globals-proof.gdb
python tools/bnk-replace.py revert "C:\Games\Fable 3\data\levels.bnk"
```

**[VERIFIED]** 2026-08-11: the game launches and plays with an entry relocated to the end of
a 2.1 GB payload and its index rewritten, so the delivery route works. It needs the index
chunk framing above to be right; the first attempt crashed on launch.

Relocating an entry leaves the old bytes orphaned in the payload, which is why
`weapon-unlock.py` no longer hardcodes its offset - it reads the entry position out of the
bank index, or it would silently patch the copy the game no longer reads.

> [!warning] There are THREE copies of `globals.gdb` and the DLC ones win
> Base `levels.bnk`, `traitors_keep\dlc2free.bnk`, and
> `understone_quest\dlc_freeforall.bnk` each carry one, and **the game loads the newest
> DLC's copy**. `augment-patch.py` recorded this in 2026-08-09 and it still cost a test
> round: a record added only to the base copy is simply not there in game. Patch all three.

**Limitation, by design:** `add_label` refuses and returns `None` rather than corrupt the
file, because a new label would leave the undecoded index one entry short. This costs less
than it sounds - the name map stores `(FNV-1 of the name, object hash)` and never the
string, so **naming a new object needs no label at all**. That is the same property that
makes 8-character aliases work. → [[Child System]]

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
