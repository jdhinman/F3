# HANDOFF: Fable III modding toolchain

Paste this into a new session. Everything below is verified unless marked otherwise.

We are building a modding toolchain and research vault for **Fable III** (PC) at
`C:\Users\jhinm\Documents\Projects\Fable3`, pushed to `github.com/jdhinman/F3`. Sibling
project `github.com/jdhinman/fa` (Fable Anniversary) is **complete and closed** - do not
touch it.

## Read these first, in this order

1. `Notes/Hard Lessons.md` - **twelve rules, each paid for with a wasted session or a broken
   thing in game.** Read before writing any mod code. Rule 1 is the important one.
2. `Notes/Reference Index.md` - where every artefact, tool and link is.
3. `Notes/Child System.md` - the target feature and exactly how far it got.
4. `Notes/Lua Scripting.md` - the complete channel table: what works, what is dead.

## State: code runs in the game

**Arbitrary Lua executes in retail Fable III, live-editable, no restart.** The loop is: edit
`mods/injector/MyScript01.lua`, syntax-check, copy to
`C:\Games\Fable 3\data\scripts\MyMod\MyScript01.lua`, and it applies in about a second.

```bash
python tools/syntax-check.py mods/injector    # MUST pass, and you MUST read the result
cp mods/injector/MyScript01.lua "/c/Games/Fable 3/data/scripts/MyMod/MyScript01.lua"
```

Currently installed and working (v27):

- **HUD inspector** - look at any NPC, a non-modal counter widget shows type, age band, sex,
  age scalar. Updates silently, no popups.
- **Dog menu** - target the dog for a yes/no chain: set gold to an exact figure (numeric
  spinner), refill health, set the last-inspected NPC's age scalar, toggle the inspector.

The install also has the community `ScriptInjector` DLC at `DLC/10_ScriptInjector` and two
lines appended to `data/dir.manifest`. `pwsh -File tools/mod-uninstall.ps1` reverts all of it
and never touches saves.

## The headline finding

**The age scalar is authoritative; the age group derives from it.** `Age.SetAge(npc, 25)`
alone flips `GetAgeGroup` from CHILD to ADULT, and the adult AI and interaction set follow
immediately - confirmed in game. Children read scalar 10, adults 20; the boundary is ~18,
exactly as a 2014 forum post claimed and nobody had tested.

**The body does not follow.** A `GraphicAppearanceMorph.SetCharacterRecord` attempt using a
creature type name as a record name left the test NPC permanently invisible - he was an adult
in every field, with nothing to draw. Creature types and character records are different
namespaces. That is Hard Lesson 1.

## Next action

**Find the real character record names**, then the child-growth mod is two calls.

`crates/gdb` now parses `globals.gdb` (114,796 objects, 23,470 named, 28,739 labels) straight
out of `levels.bnk`:

```bash
cargo run --release -p gdb --bin gdbdump -- \
  --bank "C:\Games\Fable 3\data\levels.bnk" --entry 'globals\globals.gdb' --find Dog --names
```

A first search for the in-game creature type names found nothing, which is consistent with the
failure. Next: search the **label table** rather than object names, and dump a known-good
record - the dog breeds passed to `SetCharacterRecord` in
`oncarriedactionusebonuseffects.lua` are real record names, so find those objects in the GDB
and see what kind of object they are. That gives the shape to search for.

When testing the swap again: **capture the original record first** with
`GraphicAppearanceMorph.IsUsingCharacterRecordWithName` so it is reversible, and use an
ambient villager, never a quest NPC.

## Also open

- `Debug.CreateInstantFamily()` is confirmed present in retail and would create a real hero
  family on demand, so the child mod can be tested without playing to marriage. Untried.
- 5 shipped Lionhead bugs found: `EAgeGroup.EAGE_CHILD` does not exist (it is
  `EAGE_GROUP_CHILD`), so 5 comparisons test against nil. One makes a branch of child home
  behaviour unreachable in every copy of the game. We can patch these live by redefining the
  functions - that is Lionhead's own `WatchDog` pattern from `postscriptsloaded.lua`.
- The 39 group minds for citizen AI / lifesim work.

## Tools built, all working

| Crate / script | Does |
|---|---|
| `crates/korevm` | KoreVM bytecode -> Lua. **797/797 files valid Lua 5.1**, 713 with nothing unrecovered |
| `crates/bnk` | read and write BNK banks; repacks the community bank byte-identically |
| `crates/gdb` | read GDB object databases |
| `tools/syntax-check.py` | Lua 5.1 parse gate |
| `tools/mod-uninstall.ps1` | restore install to stock |

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
