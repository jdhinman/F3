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

> [!warning] TWO sorted tables, and a new record must be inserted into both
> **[VERIFIED]** 2026-08-11, each found by a separate failed in-game test.
>
> | Table | Sorted by | Holds in |
> |---|---|---|
> | object hashes | object hash | 93 of 93 shipped GDBs with objects |
> | name map | FNV-1 of the name | 140 of 140 shipped GDBs with >1 entry |
>
> Both are binary-searched by the engine. `--clone` originally appended to each, which put
> the new record past the sort break: correct bytes, verifiably loaded, and still reported
> missing by `GDB.RecordExists`. Both now insert in order.
>
> Inserting into the object array is safe because **nothing addresses an object by index** -
> `parent` fields and the name map both hold object hashes - so only the index-parallel
> arrays (objects, hashes, the per-object u16) move together, and the u16 array is
> recomputed anyway.

Changed records get into the game with `tools/bnk-replace.py`, which appends the new blob
to the payload and rewrites just that entry's offset and size in the bank index. Repacking
a 2.1 GB `levels.bnk.dat` to change one entry is not on, and the in-place dword patching
the older GDB tools use stops working the moment a record or a label makes the file longer.

```bash
python tools/bnk-replace.py apply  "C:\Games\Fable 3\data\levels.bnk" "globals\globals.gdb" work/globals-proof.gdb
python tools/bnk-replace.py revert "C:\Games\Fable 3\data\levels.bnk"
```

### Proven in game  **[VERIFIED]** 2026-08-11

A record and a label that never shipped with Fable III, read back live through the engine's
own lookups:

```
GDB: BOTH OK  NameTag=F3ProofLabel  mult=7.5
```

`ExpressionThumbsUp` was cloned to `F3ProofRecord`, its `NameTag` pointed at a **new label**
`F3ProofLabel`, and a float changed. In game, `GDB.RecordExists("F3ProofRecord")` is true,
`GetString("NameTag")` returns the new string, and `GetFloat` returns the new value. So the
label index decode is right at the level that matters: the engine resolved a hash we
computed and inserted into a table we regenerated.

Editing an existing record works too - the control for this test set
`ExpressionThumbsUp.IndirectEffectMultiplier` to 3.25 against a stock 0.2 and read it back.
That already exceeds `augment-patch.py` and `weapon-unlock.py`, which can only write
same-size dwords in place.

The delivery route is sound: the game launches and plays with `globals.gdb` relocated to the
end of a 2.1 GB payload and the bank index rewritten. It needs the index chunk framing above
to be exactly right; the first attempt black-screened and crashed on launch.

Four separate things had to be true, and each was found by a failed test in this order:
correct index chunk framing, all three DLC copies patched, object hashes inserted in order,
name map inserted in order.

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

## BABEL, the text tables  **[VERIFIED]** 2026-08-11

`book.babel` is the localisation store: every display name, description and subtitle. It was
the last format gating new *content*, and **nothing in the scene had it** - the mirrored
forums carry no `.babel` documentation and neither does the wider web. `tools/babel.py`
reads, edits and adds entries.

**Everything is big-endian**, like BNK and unlike GDB.

```
@0    u32   0x5B010000                     version
@4    u32   record count
@8          records: u32 key, u32 chunkId, u32 byteOffset    sorted by key
      u32   chunk count
            per chunk: u32 chunkId, u32 compressedLen, u32 uncompressedLen, bytes
      u32   16384                          chunk size
      u32   second index count
            second index: u32 key, u32 chunkId, u24 offset   (11 bytes, sorted by key)
      ...   two further regions, NOT decoded, preserved verbatim
            trailing: (u32 key, u32 charCount, UTF-16BE) speaker tags, sorted by key
```

**The key is FNV-1 of the id string - the same hash `crates/gdb` computes for labels.** That
is the join between the two formats: a GDB string field holds
`INV_ITEM_WEAPON_DRAGONSTOMPER_NAME`, and the same hash indexes the text here. Knowing that
is most of why this took an afternoon rather than a week: the GDB says exactly what to look
for, and confirming it was one `find()`.

A chunk inflates to a run of `u32 charCount` + that many UTF-16BE units, NUL included in the
count. A record's `byteOffset` is a byte offset into the **decompressed** chunk.

> [!warning] Two things that make this look like a custom codec when it is not
> **The zlib streams carry no trailing checksum inside `compressedLen`.**
> `zlib.decompress` calls them truncated and every chunk appears to be a bespoke bitstream;
> `decompressobj().decompress()` on exactly `compressedLen` bytes returns exactly
> `uncompressedLen`. That one detail is most of the format.
>
> **The text is UTF-16 BIG endian.** Searching the whole 13 GB installation for
> `Dragonstomper` in ASCII and UTF-16LE returns nothing at all, which reads as "the text is
> compressed and unreachable" rather than "you are searching for the wrong bytes".

Chunks are kept compressed and only recompressed when their contents change, so an
unmodified rebuild is byte-identical: **37 of 37 BABEL files in the installation**, loose
and in-bank, across 8 languages.

```bash
python tools/babel.py verify "C:\Games\Fable 3\data\language\en-uk\text\book.babel"
python tools/babel.py get    "...\book.babel" INV_ITEM_WEAPON_DRAGONSTOMPER_NAME
python tools/babel.py add    "...\book.babel" MY_ID "My text" out.babel
```

### Proven in game

`tools/build-dragonstomper.sh` defines a weapon with **its own ids on both sides** - new GDB
labels `F3MOD_DRAGONSTOMPER_NAME` / `_DESC`, new BABEL entries under the same FNV-1 hashes -
and the game renders them:

> **The Sovereign** - *Forged from a Marksman that someone had clearly stopped respecting. It
> does not kick, it does not miss, and it does not leave much to bury.*

Two things that worked but are worth knowing are inference, not proof: the new entry goes in
a **new chunk with an invented chunk id** (chunk ids are not sorted, so the engine appears to
map them at load), and only the **base loose `en-uk` file** was patched, on the reasoning
that the DLC copies must merge rather than shadow - 10k DLC strings cannot be replacing 68k
base ones. Both held.

Still undecoded and preserved verbatim: the 11-byte second index over the same keys, and two
regions between it and the speaker-tag block. Neither is needed to read or write display
text; they are most likely dialogue and audio linkage.

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

## TEX, decoded  **[VERIFIED]** 2026-08-11

**The header was never in the file.** A `.tex` is raw DXT blocks from byte zero, which is why
every attempt to parse one finds nothing and the community settled on "compression unknown,
swizzling possible".

Every `x_textures.bnk` has a sibling **`x_texture_headers.bnk`** holding a 92-byte
little-endian record per texture:

```
@0  u32 0xABCBBBF3 magic   @20 u32 width      @36 u32 0
@4  u32 4 version          @24 u32 height     @40 u32 mip count
@8  u32 data size          @28 u32 format     @44 u32 92 header size
@12 u32 flags (2=cubemap)  @32 u32 13
@16 u32 usage
```

`format` 35 = **DXT1**, 39 = **DXT5**, 2 and 4 = uncompressed 32-bit. Cubemaps store six
faces, so six times the size.

**Proof: the payload size of every texture in the game is predicted from its header alone,
9,561 of 9,561**, mip chains and cubemaps included.

**There is no swizzling and no byte swapping.** Real DXT1 blocks are 90-100% `c0 > c1` as
stored; byte-swapping drops that to 40-70%, which is what getting it wrong looks like.

The reason nobody found the header bank is probably that **the texture bank indexes are
nested inside `levels.bnk`** while their payloads sit loose on disk as `.bnk.dat` with no
`.bnk` beside them.

`tools/tex.py` lists, exports to PNG (Pillow's BCn decoder), and re-encodes PNG back to
`.tex` plus its header.

## MDL, static geometry decoded  **[VERIFIED]** 2026-08-13

Same two-bank split as textures: `globals_models.bnk` (index, nested inside `levels.bnk`)
plus `globals_models.bnk.dat` (payload, loose, 345 MB). Payloads are the standard chunked
zlib. 6,923 model headers, 4,782 model payloads.

Read against **BlackDemon's `35-mdl.hsl`**, the only prior art that exists. Every field it
names is confirmed by the `tVerts == nTris * 3` invariant holding on real files.

**Header** (little-endian, after decompression):

```
u32   FNV hash            u32   nBones2, then nBones2 * 11 floats (bind transforms)
8     zero padding        10    floats  root origin
u8    nFlags              u32   nMaterials, nSubmeshes, nSkelSubmeshes,
u32   flags[nFlags][2]          nPlanes, nUnk, nWTF
u32   nBones1             u8    pad
u32   bones[nBones1][2]   u32   nNodes, then nNodes NUL-terminated strings
        (name hash, parent index; the root's parent is 0xFFFFFFFF)
```

The dog collie reads 92 bones with a `0xFFFFFFFF` root, 2 materials and 2 skinned submeshes,
which is what a quadruped should look like.

**Static submesh:** name zstring, u8, meshId, materialId, `nTris`, `tVerts`, `nVerts`, 10
origin floats, `nElements` then 37 bytes each, then **two float16 vertex streams**
(`[nVerts][6]` = x,y,z,?,u,v then `[nVerts][8]`), then `u16 tris[nTris][3]`, then 4 bytes pad.

**Positions are float16.** `occlusionwall.mdl` comes out as 8 vertices at x = +/-10,
y = +/-0.0709, z = 0..20 - a 20x20 panel 0.14 thick, in clean round numbers, which is what
an occlusion wall is.

### Coverage

| | Models |
|---|---|
| **static, every submesh located** | **3,588** |
| skinned only, `AnimatedMesh` not yet read | 1,077 |
| no static submeshes | 75 |
| header failed to parse | 42 |

**Zero models were partially located** - where static submeshes exist, all of them are found.
Exported crates, swords and tables render as recognisable objects.

### Verified against evidence the decoder never sees  **[VERIFIED]** 2026-08-13

Renders looking plausible is not proof, and the first previews looked soft. They were soft
because the preview renderer used a painter's sort instead of a z-buffer; with a real depth
buffer the same data draws clean. The decode was checked properly instead:

**The oracle: `globals_model_headers.bnk` carries a bounding sphere and a bbox per model.**
The geometry decoder never reads it, so it is independent evidence.

| Test | Result |
|---|---|
| decoded vertices inside the header bbox | **555 / 555** |
| ...and **filling** it to within 2% | **554 / 555** (the miss is a morph target, which should differ) |
| static submeshes with all triangle indices in range | **1,228 / 1,228** |
| skinned submeshes with all triangle indices in range | 82 / 84 - **2% are wrong** |
| welded edge manifoldness, closed props | `esa_crate_ind_02` **1.000**, `esa_f_table_worn` **1.000**, 0 boundary edges |

Filling the authored bounding box to 2% is the strong result: a wrong stride, a wrong
component order or wrong units would land inside the box or outside it, but would not
reproduce its exact extent on 554 models.

Low average manifoldness across the library (0.71) is **not** a decode error - it is real
open geometry. Closed props come out exactly watertight; `occlusionwall` (a 4-triangle panel)
and `sword_blade_base_small` (a segment that mates with a hilt) are open because they are.

**Vertex components, confirmed one at a time** on static meshes:

| | |
|---|---|
| A0-A2 | position, float16 |
| A3 | 0.58 .. 1.00 per-vertex scalar, **unidentified** (the template guessed illumination) |
| A4-A5 | **UV**, measured 0.00 .. 1.00 |
| B0-B2 | **normal**, unit vectors, measured \|n\| = 1.0000 |
| B3 | always zero |
| B4-B7 | 8 bytes that are **not float16** (30% decode as NaN), **unidentified**, probably a packed tangent |

`tools/mdl.py` now exports normals and **refuses to emit any submesh whose triangles point
outside its vertex buffer**, so the 2% skinned failures are reported rather than written out
as garbage. `tools/mdl-validate.py` re-runs all of this.

### The invariant scan produces FALSE POSITIVES, and they look plausible  **[VERIFIED]** 2026-08-13

Found by someone looking at a render and saying the dog's face was wrong. It was.

`tVerts == nTris * 3` is necessary but **not sufficient**. It fires on positions inside the
vertex data, and a false positive still reads the model's own numbers, so it produces
geometry that sits roughly on the real surface and passes a glance. The collie's first
skinned submesh was one:

| | false positive | the real submesh |
|---|---|---|
| non-manifold edges | **213** | 0 |
| median edge length | 5.9% of the diagonal | 0.8% |
| UV range | **-0.51 .. 4.12** | 0.002 .. 0.998 |

Worse, **the false positive hid the real one**: the true second submesh is 2,151 vertices,
and the scan never reached it because it stopped at the bogus 606-vertex hit.

`_plausible()` now gates every candidate on UV range and on the triangle list referencing
most of the vertex buffer, and keeps scanning when one fails. Characters get a tight UV gate
because they never tile; environment props get a loose one because they tile constantly.
Measured over 874 models:

| | no gate | tight gate | tuned gate |
|---|---|---|---|
| every submesh located | ~844 | 451 | **817** |
| partial | 12 | 393 | **27** |
| submeshes with any non-manifold edge | 13% | - | **7%** |

That is a real trade and not a clean win: the gate rejects some true positives too. **7% of
submeshes still contain non-manifold edges**, so some false positives survive.

### What "the face looks wrong" actually was

Connected-component analysis settled it. The collie's main skinned submesh is exactly five
parts:

| part | verts | closed | extent |
|---|---|---|---|
| body | 2,633 | **yes** | 0.32 x 1.57 x 1.04 |
| ear | 288 | no | 0.08 x 0.11 x 0.04 |
| ear | 278 | no | 0.10 x 0.13 x 0.04 |
| **eyeball** | 79 | **yes** | 0.031 x 0.032 x 0.031 |
| **eyeball** | 79 | **yes** | 0.031 x 0.032 x 0.031 |

Two identical closed 3.1 cm spheres are the eyes, modelled as separate balls in the sockets,
which is how character eyes are always built. The LOD carries the same five parts. Nothing
was scrambled - untextured double-sided flat shading just makes intersecting eyeballs look
like damage.

**Lesson for previews: a bad preview and a bad decode look the same.** The original smeared
renders were a painter's sort with no z-buffer; the "wonky barrel rim" was backface culling
on an open-topped barrel. Neither was a decode error. But the dog's face was, so the only way
to tell is to measure - manifoldness, UV range, edge length, component structure - rather
than to look.

> [!warning] The submesh start is FOUND, not walked to
> The material blocks between the header and the first submesh are **not decoded**.
> `mdl.hsl` describes them as a type-switched chain of hash+size blocks and its sizes do not
> line up on these files. So `tools/mdl.py` scans for a position where `tVerts == nTris * 3`
> and every declared buffer fits inside the file. It is self-validating and it works on 3,588
> models, but it is a heuristic and is not a substitute for parsing the material chain.

**Still open:** the material chain, `AnimatedMesh` (all characters and creatures), the second
float16 vertex stream (normals or tangents), `Plane` meshes, LODs, and writing MDL at all.
Reading static geometry is not the same as being able to author a mesh the game will load.

Tooling, **corrected 2026-08-11 by looking rather than repeating the forum post**: the only
model/texture artifact actually captured is **`35-mdl.hsl`**, a hex-editor template - and it is
more useful than "a template" suggests, describing `AnimatedVertex` (halffloat xyz, 4 bone
indices, 4 weights summing to 255, halffloat UV) and the material blocks, which carry texture
**names as plain zstrings**.

The **Blender 2.82 importer** and the **TEX converter** the forum mentions are **NOT captured**;
`reference/` has neither. The only TEX artifact is `171-Fable3TextureResFormat.xlsx`, a
resolution/filesize spreadsheet - inference, not a codec. Do not plan around tools we do not have.

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
