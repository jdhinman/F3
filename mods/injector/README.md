# injector

A corrected build of the community script injector, matched to **this** install.

The mechanism is not loose files. It is a DLC package whose `package_info.xml` sets
`mountOrder 9150`, above the base game, so its copy of `scripts/quests/questsetupscript.lua`
wins. That copy has one line appended, which registers a quest, and the quest then
`RunScript`s loose files by explicit path. → `Notes/Lua Scripting.md`

## What is corrected

The community bank's `questsetupscript.lua` came from a different build. It is a superset of
this install's: nothing is lost, but it adds six `RunScript` calls for files that exist
**neither** in the gamescripts banks nor in the DLC banks here -
`DLC1_Unlocks`, `DLC2_Unlocks`, `DLC_DogSkin_Unlocks`, `ChapterProgress_DLC_EP1`,
`QOTA_AssassinateManager2`, `QOTS_ShoppingListManager`.

`bank/scripts/quests/questsetupscript.lua` is instead rebuilt from this install's own
`gamescripts_r.bnk`, decompiled, plus the single hook line. Every one of its 48 `RunScript`
targets is verified to exist. The other three files in the bank are the community's,
unchanged.

## Building and installing

```bash
cargo run --release -p bnk --bin bnkpack -- mods/injector/bank /tmp/ScriptInjector.bnk --meta 0,0,0,0,0,0,16
```

Then:

- `/tmp/ScriptInjector.bnk` and `.bnk.dat` -> `<install>\DLC\10_ScriptInjector\Content\`
- `MyScript01.lua`, `MyScript02.lua` -> `<install>\data\scripts\MyMod\`
- append to `<install>\data\dir.manifest`, CRLF line endings:
  ```
  scripts\MyMod\MyScript01.lua
  scripts\MyMod\MyScript02.lua
  ```

`content.xbx` and `package_collection_info.xmb` come from the community package and are not
rebuilt; copy the whole `DLC/10_ScriptInjector` folder first, then overwrite the two bank
files.

## Scheduling

`MyScript01.lua` runs once per 60 frames. `MyScript02.lua` runs only while the screen fades.
That is the quest's doing, not the engine's - see `bank/scripts/quests/demo001_scriptinjector.lua`.

## Uninstalling

Delete `DLC\10_ScriptInjector` and `data\scripts\MyMod`, and restore `dir.manifest` from
`dir.manifest.stock-backup`. Nothing else is modified.
