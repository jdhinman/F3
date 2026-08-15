# HANDOFF: Fable III modding toolchain

Paste this into a new session. Everything below is verified unless marked otherwise.

We are building a modding toolchain and research vault for **Fable III** (PC) at
`C:\Users\jhinm\Documents\Projects\Fable3`, pushed to `github.com/jdhinman/F3`. Sibling
project `github.com/jdhinman/fa` (Fable Anniversary) is **complete and closed** - do not
touch it.

## The state of the install RIGHT NOW

**Stock.** Everything is reverted and verified: `levels.bnk` is 39,456 bytes with a
2,109,341,899-byte payload, all 4,782 models read back at their declared size and original
offsets, `globals_models.bnk.dat` truncated back to 345,153,079, and all 77 GDBs in
`levels.bnk` round trip byte for byte.

The mod layer (`dinput8.dll` bridge, `MyScript01.lua` v65, ScriptInjector DLC) is still
installed and working. `pwsh -File tools/mod-uninstall.ps1` removes it.

## Read these first, in this order

1. `Notes/Hard Lessons.md` - **twenty-three rules, each paid for.** Rule 1 is the important
   one, 10-11 crashed the game twice, 16-17 decide whether a format job is safe to build on,
   and **18 is the one that would have saved the most time this session.**
2. `Notes/Formats.md` - every file format, what is decoded, and what is not.
3. `Notes/Reference Index.md` · `Notes/Child System.md` · `Notes/Lua Scripting.md`

## What works, all proven in the running game

| | |
|---|---|
| **Arbitrary Lua, live** | edit, syntax-check, copy, applies in ~1s. No restart |
| **F1 mod menu** | real keybind via a 32-bit `dinput8.dll` proxy, DXVK alongside |
| **Child growth** | the original target. Ambient children and the hero's own, family preserved |
| **Weapon evolution** | fully reverse engineered, any weapon completable |
| **GDB read+write** | 147 files byte-identical. New records, names, labels, edits of any size |
| **BABEL read+write** | 37 files byte-identical. New display text |
| **TEX read+write** | 9,561 textures. Export to PNG, re-encode, patch in place |
| **MDL read** | 4,511 of 4,623 models fully walked, static and skinned, export OBJ |
| **MDL edit** | geometry edits **at unchanged vertex/triangle counts**, in place |
| **Audio** | xWMA, ffmpeg decodes it. GHF terrain is gzip. ADB is zlib |

**New content works end to end.** `The Sovereign` is an original weapon - item record,
component graph, display name and description that never shipped with Fable III - built by
`tools/build-dragonstomper.sh` and rendered by the game. `FABLE III: ALBION REFORGED` is a
generated title-screen logo that renders on the menu.

## THE ONE OPEN PROBLEM: changing MDL vertex/triangle counts

Everything else about MDL works. **Changing the counts does not**, and this is where the next
session should start. → `Notes/Formats.md`, "Writing MDL"

Failure escalates with the number of models changed:

| test | result |
|---|---|
| generated obelisk replacing 3 barrel models | props render as nothing |
| half a barrel (its own data, fewer verts and tris) | props render as nothing |
| 37 models, barrels -2 tris / crates +2 verts | **game crashes while loading a save** |

### DO NOT re-derive these - all measured against untouched game data

Each was a real conformance bug, each is fixed in the tools, and **none of them was the
cause**:

- **Winding**: the game winds triangles **opposite** to the stored vertex normals - agreement
  is 0.000-0.003 on stock meshes. Any OBJ tool winds the other way. The writer flips.
- **The submesh's 10 floats are BOUNDS, not an origin**: bbox min (3), bbox max (3), centre
  (3), radius as the half-diagonal (1). Exact on `occlusionwall`: `(-10,-0.071,0)`,
  `(10,0.071,20)`, `(0,0,10)`, `14.142`. The writer recomputes them.
- **Stream B bytes 8..16 are a 4 x int16 TANGENT** normalised to 32767, handedness in the
  fourth. Zeros collapse the shader's TBN and the model vanishes. The writer generates real
  tangents.
- **The model header bbox** in `globals_model_headers.bnk` must be updated. It is.
- **`bnk-replace.deflate_index` needs `compressed_flag`**: `globals_models.bnk` uses the
  5-field entry form. Writing flag 0 makes the reader parse 3-field entries and walk off the
  end of the index.
- **Element table**: `nElem=1`, mark `FFFFFFFF`, flag 0, `nTris`, start 0, then bbox. Matches
  stock exactly.
- **Not the cause**: material blocks (shader floats only), MDL header flag pairs (all zero on
  static models), per-entry `meta` (`meta[4]=115` is the header size, `meta[6]=4` alignment,
  `meta[0..3]` are not a validated checksum - the self-rebuild changed the payload and still
  rendered).

### What IS proven about the container, so do not re-test it

- **In-place edits at unchanged counts work.** 3x barrels rendered.
- **The nested-index rewrite works.** Proven by writing a model's byte-identical geometry
  **4096 bytes longer at a new offset** - barrels rendered normally. So offsets, sizes, the
  chunk table and the `globals_models.bnk` rebuild are all correct.
- Payloads are chunked zlib in **fixed 32,768-byte slots**; keeping the split and padding each
  slot back to its original length keeps the entry byte count identical and needs no index
  change at all.

### Where to look next

Something is sized by or derived from the vertex/triangle count and is not in the parts of MDL
this project has decoded. Candidates, roughly in order:

1. The **3 unexplained bytes** at the end of the 115-byte model header (`40 1c 46`, constant
   across models) and the 11 trailing header floats.
2. **`.gmd` files** - "game mesh data, metadata about a model, not the model. Most models have
   one." Never examined. If a GMD carries counts, that is the answer.
3. **`globals_streaming.bnk`** - models may be streamed through it.
4. Whatever the **save load** walks that a count change corrupts. The crash-on-save-load is
   the strongest signal available and has not been chased.

**Start by bisecting, not by fixing.** The single most useful next test: change the counts on
**one** model that is definitely in view, and see whether the crash is the count change itself
or the *number* of changed models.

## Method, non-negotiable

- **Rule 1**: never call a game function whose argument shape you have not seen in a shipped
  call site passing a literal. Two crashes came from breaking it.
- **Rule 18**: design the test so a negative result means something. Patch *every* model that
  shares a visual role; never ask for a comparison across areas the player cannot reach; a
  pass condition of "looks like the original" proves nothing; order tests container → size →
  counts → content.
- **Fixing a real bug is not evidence you fixed THE bug.** Four genuine conformance errors
  were fixed this session without resolving the failure. Bisect against a known-good control.
- `python tools/api-index.py search <text>` before assuming an API does not exist. 5,401 calls
  across 679 namespaces.
- Prove format work with a **byte-identical round trip** before building on it.
- The user plays live and can test in seconds. **Tell them exactly what to look at, and make
  sure they can reach it.**

## Tools

| Crate / script | Does |
|---|---|
| `crates/korevm` | KoreVM bytecode -> Lua. 797/797 valid Lua 5.1 |
| `crates/bnk` | read/write BNK. Test asserts the per-chunk index property |
| `crates/gdb` | read/write GDB. `gdbdump`, `fnvpre`, `gdbwrite` (`--verify-all`, `--clone`, `--edit`, `--set`) |
| `crates/bridge` | 32-bit proxy DLL: real keyboard -> the F1 menu |
| `tools/babel.py` | read/edit/add BABEL text. `verify` round-trips 37/37 |
| `tools/tex.py` · `tools/tex-patch.py` | textures: list/export/import, and in-place replace |
| `tools/mdl.py` | MDL headers, skeletons, static + skinned geometry, OBJ export |
| `tools/mdl-patch.py` | edit geometry in place at unchanged counts. `verify` proves the repack |
| `tools/mdl-import.py` | **count-changing import. Works mechanically, breaks in game** |
| `tools/mdl-validate.py` | geometry vs the header bbox, manifoldness, UV range |
| `tools/formats.py` | classify every extension; crack GHF, ADB, xWMA |
| `tools/bnk-replace.py` | swap one entry's payload in a bank, exact revert |
| `tools/bnk-extract.py` | Python BNK reader |
| `tools/build-dragonstomper.sh` | builds **The Sovereign** end to end. The template for new items |
| `tools/api-index.py` · `tools/syntax-check.py` · `tools/record-chain.py` | corpus index, Lua gate, record chains |
| `tools/weapon-unlock.py` · `tools/augment-patch.py` | one-time GDB passes |
| `tools/bridge-install.ps1` · `tools/dxvk.conf` · `tools/mod-uninstall.ps1` | install/remove |

## Reverting anything

```bash
python tools/bnk-replace.py revert "C:\Games\Fable 3\data\levels.bnk"
python tools/mdl-patch.py revert <model>
python tools/tex-patch.py revert-all
bash tools/build-dragonstomper.sh revert
pwsh -File tools/mod-uninstall.ps1
```

`bnk-replace revert` restores the index and truncates the payload, which un-references
everything appended. **`mdl-import.py` appends to `globals_models.bnk.dat` and never
truncates it** - check `max(offset+size)` against the file size and truncate the orphaned
tail by hand.

## Open reverse engineering

| Target | State |
|---|---|
| ~~GDB, BABEL, TEX, GHF, ADB, xWMA~~ | **decoded and proven in game** |
| **MDL count changes** | the one open problem, above |
| **MDL skinned authoring** | needs the bind matrices handled, not just vertices |
| Save format | Timeslip's editor decodes it; we have not |
| `.gmd`, `BFT` fonts, `bin` lipsync, `flpb`/`ppd`/`hdb` | untouched, none gate content |
| Kynapse (`AIMRT`/`FDL`/`PDL`), Havok, Bink | middleware, documented elsewhere |

## Next actions beyond MDL

- **Package the child-growth mod for release.** It works; nobody has shipped it.
- **Build an expansion pack.** The DLC mechanism is proven (`DLC/<name>/content.xbx` + a
  bank). New quests, items, characters, systems, names and descriptions are all reachable now.
- **GDB templates**: a clone gets its source's field set and no more, so a record cannot gain
  a field its source lacks. Writing new templates is the next feature in `crates/gdb`.
- Grown children do not walk home; the clockwork dog record is unidentified; 5 shipped
  Lionhead bugs are patchable live; 39 group minds for lifesim work; Kingdom Sim is the
  researched flagship. → `Notes/Kingdom Sim.md`

## House rules

- Author is Jake Hinman. No AI/Claude attribution anywhere, no emoji, no em/en dashes.
- Confidence markers [VERIFIED] / [DOCUMENTED] / [INFERRED] / [UNKNOWN] are load-bearing.
- Game data is never committed. `work/` is gitignored and regenerable.
