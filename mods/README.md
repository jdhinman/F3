# mods

Mod scripts, written as plain-text Lua. The engine compiles Lua source at runtime, so
nothing here needs compiling to KoreVM bytecode.

**Nothing in here has been run in game.** Every API name is verified to exist in the game's
own decompiled scripts (`work/decompiled/`), which makes the names right. It does not make
the behaviour right.

## Installing

Copy the mod's `MyStartup.lua` to:

```
<install>\data\scripts\startup\MyStartup.lua
```

**No edit to `dir.manifest` is required.** The shipped `scripts/startup/startup.lua` ends with
`AddOptionalStartupScript("MyStartup.lua")`, and `dir.manifest` already declares
`scripts\startup\mystartup.lua` - a slot that ships empty. → `Notes/Lua Scripting.md`

Only one `MyStartup.lua` can be installed at a time. To combine mods, concatenate them.

To uninstall, delete the file. Nothing else is modified.

## What is here

| Mod | What it does |
|---|---|
| `smoke-test/` | Writes `f3mod-smoke.txt` next to `Fable3.exe`. Proves the hook fires. |
| `growup/` | Promotes the hero's children from child to adult. Writes `f3mod-growup.txt`. |

**Run `smoke-test` first.** If it produces no log, the hook is not firing and nothing else
in here is worth debugging. That is the open question: `AddOptionalStartupScript` may be
compiled out of a release build.

## Writing more

The game's own scheduler is the right way to run something repeatedly:

```lua
local Watcher = { _Name = "MyWatcher" }
function Watcher:Update()
    while true do
        -- work
        coroutine.yield()   -- one frame
    end
end
GeneralScriptManager.AddScript(Watcher)
```

`AddScript` turns `Update` into a coroutine and resumes it once per tick. Optional
`IsStillRunnable` and `OnExit` methods are honoured. See
`work/decompiled/scripts/miscellaneous/generalscriptmanager.lua`.

Two things worth knowing before writing a lot:

- **Quest files do not hot-reload.** `RefreshFile` explicitly skips anything matching
  `q<letter><digits>` or `qot`. AI and camera files trigger a subsystem-wide reload instead
  of a plain re-run.
- **Check names against the corpus before using them.** `grep -r "Age.SetAgeGroup"
  work/decompiled/` is the API documentation. The community's own example scripts contain
  calls that do not exist - `Layer.ActivateLayer` for `Layers.ActivateLayer`, in an
  attachment on the forum - and they fail silently.

## Syntax-checking before install

```bash
python tools/syntax-check.py mods/growup
```
