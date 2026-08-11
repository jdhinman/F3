# HANDOFF: Fable III modding toolchain

Paste this into a new session. Everything below is verified unless marked otherwise.

We are building a modding toolchain and research vault for **Fable III** (PC) at
`C:\Users\jhinm\Documents\Projects\Fable3`, pushed to `github.com/jdhinman/F3`. Sibling
project `github.com/jdhinman/fa` (Fable Anniversary) is **complete and closed** - do not
touch it.

## Read these first, in this order

1. `Notes/Hard Lessons.md` - **twenty rules, each paid for with a wasted session, a crash,
   or a broken thing in game.** Read before writing any mod code. Rule 1 is the important
   one, and rules 10-11 are the ones that crashed the game twice in one session.
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
[[Bridge DLL]] with the evidence, and as Hard Lessons 17-20. If the game ever fails to launch,
delete `C:\Games\Fable 3\dinput8.dll`. DXVK needs `d3d9.deviceLossOnFocusLoss = True` or
alt-tab breaks; `tools/dxvk.conf` has it.

**CHILD GROWTH IS SOLVED** - the project's original target, ambient children *and* the hero's
own, with family membership preserved (`was mine=true -> now mine=true`). Entity replacement,
not appearance patching: the skeleton belongs to the creature type. Full recipe, the three
relink calls, and the two crash-causing argument shapes are in [[Child System]].

**Weapon evolution is fully reverse engineered and cheatable** - see [[Weapon Augments]].
`tools/weapon-unlock.py` did a one-time GDB pass so any weapon completes from the menu.

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
| **GDB label index** | trailing u32-per-label block, hash table with local probing, ~1,789 displacements off `hash & 0xFFFF`. Written back verbatim; `add_label` refuses | adding new label STRINGS, so new display names and new string field values |
| **TEX textures** | "likely DXTn, compression unknown, swizzling possible". Community artifact is a filesize spreadsheet, not a codec | custom textures - retextures, new item art |
| **MDL models** | community Blender **importer** only; its authors planned export and never shipped it | custom meshes: furniture, weapons, dog breeds, map geometry |
| **Save format** | Timeslip's editor decodes herosave / mainsave / checksums / XUIDs / hero x,y,z | persistent state edits the other layers cannot reach |
| **Per-object u16 array** | one u16 per object in the GDB index block, purpose unknown, preserved verbatim | unknown; clone copies the source value |

## Tools built, all working

| Crate / script | Does |
|---|---|
| `crates/korevm` | KoreVM bytecode -> Lua. **797/797 files valid Lua 5.1**, 713 with nothing unrecovered |
| `crates/bnk` | read and write BNK banks; repacks the community bank byte-identically |
| `crates/gdb` | read **and write** GDB. `gdbdump`, `fnvpre`, `gdbwrite` (byte-identical round trip; `--clone` adds records) |
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
