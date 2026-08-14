# HANDOFF: Fable III modding toolchain

Paste this into a new session. Everything below is verified unless marked otherwise.

We are building a modding toolchain and research vault for **Fable III** (PC) at
`C:\Users\jhinm\Documents\Projects\Fable3`, pushed to `github.com/jdhinman/F3`. Sibling
project `github.com/jdhinman/fa` (Fable Anniversary) is **complete and closed** - do not
touch it.

## Read these first, in this order

1. `Notes/Hard Lessons.md` - **twenty-two rules, each paid for with a wasted session, a
   crash, or a broken thing in game.** Read before writing any mod code. Rule 1 is the
   important one, rules 10-11 crashed the game twice in one session, and **16-17 are the
   pair that decide whether a format job is safe to build on** - both were paid for by a
   black screen that every one of our own tools said was fine.
2. `Notes/Reference Index.md` - where every artefact, tool and link is.
3. `Notes/Child System.md` - the target feature and exactly how far it got.
4. `Notes/Lua Scripting.md` - the complete channel table: what works, what is dead.

## State: a real mod menu, on a real keybind

**Press F1 in game.** A menu line appears on the HUD; up/down cycles; Enter runs the entry.
Gold +50,000 / refill health / +50 guild seals / evolve held weapon / age last inspected NPC
to 25 / toggle the inspector. No dog, no modal boxes - both were removed.

That works through `crates/bridge`, a 32-bit proxy DLL installed as **`dinput8.dll`**
(`tools/bridge-install.ps1`), which leaves `d3d9.dll` free for **DXVK** - both run together.
The DLL does one thing: **poll the keyboard in a per-frame hook and write a file.** Lua reads
it with `RunScript` and draws the menu with `GUI.SetCounter`. It deliberately draws nothing
itself - **drawing through D3D gets the hook silently bypassed after one frame in this game**,
and threads or a `WH_KEYBOARD_LL` hook stop it launching. All four dead ends are written up in
[[Bridge DLL]] with the evidence, and as Hard Lessons 19-22. If the game ever fails to launch,
delete `C:\Games\Fable 3\dinput8.dll`. DXVK needs `d3d9.deviceLossOnFocusLoss = True` or
alt-tab breaks; `tools/dxvk.conf` has it.

**CHILD GROWTH IS SOLVED** - the project's original target, ambient children *and* the hero's
own, with family membership preserved (`was mine=true -> now mine=true`). Entity replacement,
not appearance patching: the skeleton belongs to the creature type. Full recipe, the three
relink calls, and the two crash-causing argument shapes are in [[Child System]].

**Weapon evolution is fully reverse engineered and cheatable** - see [[Weapon Augments]].
`tools/weapon-unlock.py` did a one-time GDB pass so any weapon completes from the menu.

**NEW CONTENT WORKS END TO END, PROVEN IN GAME.** `The Sovereign` is an original weapon -
an item record, a component graph, a display name and a description that never shipped with
Fable III - built by `tools/build-dragonstomper.sh` and rendered by the game. The GDB and
BABEL are both fully writable, and they join on FNV-1 of the id string. -> [[Formats]]

**THE GDB IS FULLY WRITABLE, PROVEN IN GAME.** Both remaining unknowns fell on 2026-08-11,
so every block is now regenerated rather than preserved verbatim, and the game reads the
result: `GDB: BOTH OK  NameTag=F3ProofLabel  mult=7.5` is a **record and a label string that
never shipped with Fable III**, resolved live by the engine's own lookups. New records, new
names, new label strings, and edits to existing records of any size all work end to end.
Delivery is `tools/bnk-replace.py`. -> [[Formats]]

## State: code runs in the game

**Arbitrary Lua executes in retail Fable III, live-editable, no restart.** The loop is: edit
`mods/injector/MyScript01.lua`, syntax-check, copy to
`C:\Games\Fable 3\data\scripts\MyMod\MyScript01.lua`, and it applies in about a second.

```bash
python tools/syntax-check.py mods/injector    # MUST pass, and you MUST read the result
cp mods/injector/MyScript01.lua "/c/Games/Fable 3/data/scripts/MyMod/MyScript01.lua"
```

Currently installed and working (v61):

- **HUD inspector** - look at any NPC, a non-modal counter widget shows type, age band, sex,
  age scalar. Updates silently, no popups.
- **F1 menu** - see above. The dog trigger and every modal yes/no box are gone.

The install also has the community `ScriptInjector` DLC at `DLC/10_ScriptInjector` and two
lines appended to `data/dir.manifest`. `pwsh -File tools/mod-uninstall.ps1` reverts all of it
and never touches saves.

## The headline findings

**The age scalar is authoritative; the age group derives from it.** `Age.SetAge(npc, 25)`
alone flips `GetAgeGroup` from CHILD to ADULT and the adult AI follows. Children read scalar
10, adults 20, boundary ~18 - exactly as a 2014 forum post claimed and nobody had tested.

**But growth is entity replacement, not appearance patching.** A character record supplies
meshes only; the skeleton, proportions and animation belong to the creature type, which no
call can change. Limbo the child and create the adult type in its place. -> [[Child System]]

**GDB character records are addressable by ALIAS.** The engine resolves them by FNV-1 hash
through a name map in `globals.gdb`, so an 8-char preimage works exactly like the real name.
That makes all 1,619 records usable even though 1,546 names are unrecoverable. Proven in game
by turning the hero's dog into a collie with the string `n_rtphaa`.

## Next actions

- **Package the child-growth mod for release.** It works; it has never been shipped by anyone.
- **Build something real now that content works.** New weapons, items, character records and
  their names/descriptions are all reachable. `tools/build-dragonstomper.sh` is the working
  template for an item.
- **GDB templates are the nearest wall.** A clone gets its source's field set and no more, so
  a record cannot gain a field the source lacks - that is why the Dragonstomper's firearm
  stats had to be overridden on a cloned *base* record. Writing new templates is the next
  feature in `crates/gdb`, not a new format.
- **Grown children do not walk home.** `SetHomeForMarriageOrAdoption` registers the property
  but does not run move-in behaviour. Cosmetic, unsolved.
- **The clockwork dog record is unidentified** (a DLC record with no name we can crack). With
  aliases working, it is findable by brute-forcing `IsUsingCharacterRecordWithName` over the
  1,619 record aliases.
- 5 shipped Lionhead bugs found: `EAgeGroup.EAGE_CHILD` does not exist (it is
  `EAGE_GROUP_CHILD`), so 5 comparisons test against nil. One makes a branch of child home
  behaviour unreachable in every copy of the game. Patchable live via Lionhead's own
  `WatchDog` pattern from `postscriptsloaded.lua`.
- The 39 group minds for citizen AI / lifesim work.
- **Kingdom sim** is the researched flagship candidate; town wealth is a real simulation
  variable (-100..+100, gates gift tables, villager money, gossip). -> [[Kingdom Sim]]
- **Unfinished RE, blocking content creation** - see the "Open reverse engineering" section.

## Open reverse engineering

These are the decoding jobs that gate what can still be built. Nothing else blocks.

| Target | State | What it unlocks |
|---|---|---|
| ~~**GDB label index**~~ | **DECODED AND PROVEN IN GAME** 2026-08-11. 65536-slot open-addressing table on `hash & 0xFFFF`, linear probing, inserted in file order, serialized occupied-slots-only. Regenerated on every write; **147/147 shipped GDBs round trip byte for byte**, and the engine resolves a label we invented | done - new label strings, so new string field values |
| ~~**TEX textures**~~ | **DECODED** 2026-08-11. The header is not in the file - it is a 92-byte record in a sibling `x_texture_headers.bnk`. 35 = DXT1, 39 = DXT5, flag 2 = cubemap, **no swizzling**. Every texture's payload size predicted from its header: **9,561 of 9,561**. `tools/tex.py` exports and re-encodes | done - retextures and new item art. NOT yet tested in game |
| ~~**MDL models**~~ | **READING DECODED, NO HEURISTIC** 2026-08-13. The material chain parses (type = block count; 10,727 materials across types 1/2/6/7/11), so submeshes are walked to exactly rather than scanned for. **4,511 of 4,623 models fully resolved, 10,635 submeshes**; the remaining 152 fail explicitly. Positions verified against the model header's own bbox. Open: **writing MDL at all** | reading any mesh; authoring still needs a writer |
| ~~**BABEL text tables**~~ | **DECODED AND PROVEN IN GAME** 2026-08-11. Big-endian; records keyed by **FNV-1 of the id, the same hash the GDB uses for labels**; 16 KB zlib chunks whose streams omit the trailing checksum; text is UTF-16 **BE**. `tools/babel.py`; **37/37 files round trip byte for byte** | done - new records can carry new words |
| **Save format** | Timeslip's editor decodes herosave / mainsave / checksums / XUIDs / hero x,y,z. The `.save` files inside banks are **plain XML** and are a different thing | persistent state edits the other layers cannot reach |
| ~~**GHF heightfields**~~ | **DECODED** 2026-08-13. Plain **gzip**; inflates ~480x to `f32 scaleX/scaleY, u32 w, u32 h`, then 14 bytes per cell. Grids 385x385 up to 673x769 | terrain shape is readable |
| ~~**WAV audio**~~ | **DECODED** 2026-08-13. NOT XMA2. A 4-byte `xwma` prefix on a standard RIFF/xWMA file, fmt tag `0x0161` = WMAv2. **ffmpeg decodes it directly** - proven, 2.8s 44.1kHz mono voice line | all 56,865 audio entries are readable |
| ~~**ADB audio db**~~ | **DECODED** 2026-08-13. `LhCoMpRe` + BE lengths + plain **zlib**, wrapping an inner `LhBiNaRy####` container | the audio database opens |
| ~~**Per-object u16 array**~~ | **DECODED** 2026-08-11. A random-access accelerator for the variable-length record array: `word[i] = startOfRecord(i) - ((i * stride) >> 10)` with `stride = 1024 * blockWords / count`, all in u32 words. Exact on **147 files, 2,069,537 objects**. Regenerated on write | done - and it was silently corrupting clones |

## Tools built, all working

| Crate / script | Does |
|---|---|
| `crates/korevm` | KoreVM bytecode -> Lua. **797/797 files valid Lua 5.1**, 713 with nothing unrecovered |
| `crates/bnk` | read and write BNK banks; repacks the community bank byte-identically |
| `crates/gdb` | read **and write** GDB. `gdbdump`, `fnvpre`, `gdbwrite` (`--verify-all` round-trips every GDB in a bank; `--clone` adds records, `--set Field="text"` adds labels) |
| `tools/bnk-replace.py` | swap one entry's payload inside a bank without repacking it, and `revert` exactly. How a size-changed `globals.gdb` reaches the game |
| `tools/bnk-extract.py` | Python BNK reader, for research where a REPL beats a rebuild |
| `tools/babel.py` | read/edit/add BABEL text. `verify` round-trips 37/37 files byte for byte |
| `tools/tex.py` | list/export/import textures. `verify` predicts 9,561/9,561 payload sizes |
| `tools/tex-patch.py` | replace a texture in place, same size so no index moves. Exact revert |
| `tools/mdl.py` | read MDL headers, skeletons, static + skinned geometry, export OBJ. 4,653 models |
| `tools/formats.py` | classify every extension in every bank; crack GHF, ADB and xWMA audio |
| `tools/mdl-validate.py` | check decoded geometry against the header bbox, manifoldness and UV range |
| `tools/build-dragonstomper.sh` | builds **The Sovereign**, an original weapon, end to end. The template for any new item |
| `tools/api-index.py` | index all 5,401 API calls in the corpus, with a shipped call site each |
| `crates/bridge` | 32-bit proxy DLL (dinput8 or d3d9 host): real keyboard -> the F1 menu. -> [[Bridge DLL]] |
| `tools/record-chain.py` | creature type -> character records, with ready-to-use aliases |
| `tools/weapon-unlock.py` | one-time GDB pass; every weapon augment becomes completable |
| `tools/syntax-check.py` | Lua 5.1 parse gate |
| `tools/bridge-install.ps1` | install / `-Remove` the bridge, and DXVK with `-Dxvk` |
| `tools/dxvk.conf` | tuned DXVK config, incl. the alt-tab fix |
| `tools/mod-uninstall.ps1` | restore install to stock (removes the DLL too) |

## Do NOT redo

- Do not re-derive the BNK, KoreVM or GDB formats. All three are documented and verified.
- Do not chase `Debug.DrawText`, hotkeys, `ShowTopBoxMessage`, `DisplayInfoBoxParams`,
  `SetApplicationName`, `io`, or expression-message triggers. **All confirmed dead in retail**,
  each with the evidence recorded.
- Do not call `Debug.SetUseFreeCamera(true)`. It is an input trap with no way out.
- Do not rebuild the injector bank. The community one works; ours hung the game and the cause
  was never isolated.
- Do not install the mirrored save game. It was uploaded because it was broken.

## House rules

- Author is Jake Hinman. No AI/Claude attribution anywhere, no emoji, no em/en dashes.
- Confidence markers [VERIFIED] / [DOCUMENTED] / [INFERRED] / [UNKNOWN] are load-bearing.
- Game data is never committed. `work/` is gitignored and regenerable.
