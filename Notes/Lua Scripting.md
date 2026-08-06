---
title: "Lua Scripting"
description: "Fable III's game logic is extensively Lua, the scripts have been decompiled, and mod scripts hot-reload without relaunching"
updated: 2026-08-06
confidence: verified
tags:
  - runtime
  - scripting
---

> [!success] This is why the project moved here
> Fable III does not merely *permit* scripting - large parts of its game logic **are** Lua, and the
> shipped scripts have been decompiled by the community. Mod scripts reload while the game runs.
>
> The Anniversary project spent a day failing to execute a single line of new code. Here the loop is
> edit-file, alt-tab, see it.

## The game declares its own mod hook  **[VERIFIED]** 2026-08-06

> [!success] No manifest edit, no quest hijack, no injector
> The shipped `scripts/startup/startup.lua` ends with:
>
> ```lua
> AddOptionalStartupScript("MyStartup.lua")
> ```
>
> and `scripts/startup/StartupConsoleScript.lua` ends with:
>
> ```lua
> Debug.AddOptionalStartupConsoleScript("MyStartupConsoleScript.lua")
> ```

Three facts, each checked against this install:

1. **`data/dir.manifest` already lists them.** It is plain CRLF text, one relative path per
   line, 530 lines. Four of those lines are
   `scripts\startup\mystartup.lua`, `scripts\startup\mystartupconsolescript.lua` and their
   `scripts_r\` twins.
2. **Neither file exists** - not loose on disk, and not inside `gamescripts.bnk`. The manifest
   entries are dangling.
3. **The loader calls them anyway**, because the call is `AddOptional...`.

So the retail build ships a **declared, empty, sanctioned slot for a user script**. Dropping
`data\scripts\startup\MyStartup.lua` into place should be enough, with no edit to
`dir.manifest` and none of the `DEMO001` quest-code collision the community injector warns about.

### Why loose startup files were never going to be enough  **[VERIFIED]** 2026-08-06

The community injector is mirrored (`reference/fable3mod/files/89-ScriptInjector.zip` and
`167-Fable3_ScriptInjector.zip`). Unpacking it settles the question, and it is **not** a loose-file
method:

```
DLC/10_ScriptInjector/Content/ScriptInjector.bnk       <- a DLC package
source/scripts/quests/DEMO001_ScriptInjector.lua
source/scripts/quests/questsetupscript.lua             <- an OVERRIDE of a shipped script
source/scripts/quests/scriptactivation_additional.lua
```

Their `questsetupscript.lua` is a copy of the shipped one with **one line appended**:

```lua
RunScript("Quests/scriptactivation_additional.lua")
```

which registers a quest that then does the actual work:

```lua
function DEMO001_ScriptInjector:State_START_Main()
    while true do
        coroutine.yield()
        if mod_last_run == nil or mod_last_run + 60 < Timing.GetWorldFrame() then
            RunScript("scripts\\MyMod\\MyScript01.lua")
            mod_last_run = Timing.GetWorldFrame()
        end
        ...
```

**The override mechanism is DLC bank mount order, not loose files.** `package_info.xml` sets
`mountOrder 9150`, above the base game, so the DLC's `questsetupscript.lua` wins. Loose files enter
only at the *end*, once a script they control is already running and can `RunScript` them by
explicit path. That is the chicken-and-egg the DLC exists to solve, and it explains why a loose
`MyStartup.lua` alone did nothing.

Verified with our own tools rather than trusted: extracting `ScriptInjector.bnk` with
`tools/bnk-extract.ps1` gives 4 entries, 0 failures, **all four plaintext**, and the in-bank quest
script is byte-identical to the published source. No binaries. (Their bank also uses
`compressedFlag=False`, an uncompressed index - a case none of the game's own banks use, and one
our extractor handled without changes.)

> [!warning] Their injector does not match this install
> Diffing their `questsetupscript.lua` against the retail one - which needs a decompiler, so nobody
> could do it before - it is a **superset**: nothing retail loads is lost, but it adds six
> `RunScript` calls, and **none of those six files exist in this install**, in the gamescripts banks
> or in the DLC banks:
> `DLC1_Unlocks`, `DLC2_Unlocks`, `DLC_DogSkin_Unlocks`, `ChapterProgress_DLC_EP1`,
> `QOTA_AssassinateManager2`, `QOTS_ShoppingListManager`.
> Their copy came from a different build. Installing it unchanged asks the game to load six missing
> scripts.

### Lionhead's own patch hook, already installed  **[VERIFIED]** 2026-08-06

`DLC\99_dlc2_fixes\Content\dlc2_fixes.bnk` contains three files, one of which is
`scripts/miscellaneous/saveload/postscriptsloaded.lua` - an **override of a base-game script**
(the base copy is 113 KB, the DLC's is 120 KB).

Nothing in Lua calls it. The engine loads `Miscellaneous/SaveLoad/PostScriptsLoaded.lua` by name
after scripts are loaded, and its content is a `WatchDog` system:

```lua
WatchDog = {}
function WatchDog.AddFunctionReplacementWatchDog(f) ... end
function ApplyWatchDogsWithVersionGreaterThan(v)
    GeneralScriptManager.AddScript(WatchDog.ChestyChessLevelLoad)
    GeneralScriptManager.AddScript(WatchDog.SakerFightMercenaries)
    ...
```

**This is Lionhead's own post-release patching mechanism**: an engine-invoked hook that registers
arbitrary scripts on the scheduler after load, used to ship dozens of bug fixes without repacking
the base banks. It is the natural injection point - engine-invoked, already proven to be
overridable by DLC, and not a quest, so unlike a quest file it would hot-reload.

The catch: overriding it replaces the ~60 shipped WatchDog fixes, so an override has to carry them
forward. The DLC's copy is compiled and stripped, so our decompile of it is lower fidelity than the
rest of the corpus.

### Tested. First attempt produced nothing.  **[VERIFIED]** 2026-08-06

`MyStartup.lua` was installed to `data\scripts\startup\` and the game launched. **No log file
appeared.** What that does and does not tell us:

**Ruled out - the hook is in the code retail runs.** `startup.vfsconfig` mounts
`gamescripts_r.bnk`, not `gamescripts.bnk`, so retail runs the **stripped** bank. Extracting it
(770 entries, 0 failures) and decompiling its `startup.lua` gives content identical to the debug
bank's, `AddOptionalStartupScript("MyStartup.lua")` included. So the earlier worry that the bank
held a development-only startup is wrong: **the hook is present in the bank the game mounts.**

**Ruled out - the path.** Both banks store their scripts under the `scripts\` prefix, so
`data\scripts\startup\MyStartup.lua` is the right location and the manifest's `scripts_r\`
entries are vestigial. **Ruled out - the DLC layer**: the four DLC folders carry banks but no
scripts and no manifest.

**The likely fault is the test, not the hook.** The only output channel it used was `io.open`,
and `io` appears **once** in 797 shipped scripts, in `gameface\qbtext.lua`, against a hardcoded
`d:\Dev\Fable3\...` path. That is a development-only library as far as the evidence goes. A
script that ran perfectly would have produced exactly the observed result.

**Second attempt** uses `SetApplicationName("Fable III [F3MOD]")` as the primary signal -
`startup.lua` calls that same function four lines earlier to set the name to `Fable III`, so it
demonstrably exists and our call runs later and wins. Observable in the window title. → `mods/`

Still **[UNKNOWN]**: whether `AddOptionalStartupScript` is a no-op in a release build, and
whether the VFS serves loose files at all on this install.

### Hot reload is real, and quests are excluded

`miscellaneous/GeneralSetupScript.lua` defines what the engine calls when a script file changes:

```lua
function RefreshFile(file_name)
    if string.regfind(string.lower(file_name), "ai[%\\%/]") then      Debug.ReloadAI()
    elseif string.regfind(string.lower(file_name), "camera[%\\%/]") then Debug.ReloadCameras()
    elseif string.regfind(string.lower(file_name), "crescendo") then  RunScript("miscellaneous/CrescendoSetupScript.lua")
    elseif string.regfind(string.lower(file_name), "qot") then        cprint("Skipping Refresh for Template Quest")
    elseif string.regfind(string.lower(file_name), "q%a%d+") then     cprint("Skipping Refresh for Quest File")
    else                                                              RunScript(file_name)
    end
end
```

This is the mechanism behind "edit file, alt-tab, see it", and it carries a constraint the forum
posts never mention: **quest files do not hot-reload.** Anything matching `q<letter><digits>` or
`qot` is explicitly skipped, so quest work needs a relaunch. AI and camera files get a
subsystem-wide reload rather than a plain re-run.

### What a mod can call

Read off the corpus, so these are names the engine really binds:

| Need | Call | Uses |
|---|---|---|
| console output | `cprint(...)` | 1690 |
| plain output | `print(...)` | 137 |
| on-screen text | `Debug.DrawText(text, CI32Vector2(x, y))` | 39 |
| **file output** | `io.open(path, "r"/"w")` | the `io` library is present |
| run another file | `RunScript("miscellaneous/Utils.lua")` | ~150 |

`io` being available matters: a mod can write its own log file, so the **smoke test does not
depend on getting the debug console open**.

## The injection method  **[DOCUMENTED]** - the community route

Posted by **Artofeel**, 2014-11-16, "Improved script injection method (Console workaround)":

1. use **Catspaw's GFWL emu**
2. put the **DLC folder** in the Fable 3 game directory
3. create `data\scripts\MyMod\`
4. create `MyScript01.lua` and `MyScript02.lua` inside it
5. open `data\dir.manifest` and add:
   ```
   scripts\MyMod\MyScript01.lua
   scripts\MyMod\MyScript02.lua
   ```

**Scheduling is by filename:**

| File | When it runs |
|---|---|
| `MyScript01.lua` | once per **60 frames** (about 1s at 60fps) |
| `MyScript02.lua` | only **while the screen is fading** |

**The hot-reload loop**, quoted from the post: start the game, alt-tab, write
`Debug.SetUseFreeCamera(true)` into `MyScript01.lua`, alt-tab back and you can fly around. Change it
to `false`, alt-tab, and the camera returns. **No relaunch.**

`ScriptInjector.zip` (6.49 KB) is attached to that thread. The author notes it uses the `DEMO001`
quest code, so a mod already using that code has to replace it.

**[VERIFIED-ADJACENT]** `Debug.SetUseFreeCamera(bool)` is a real API call quoted from a working
example, which is the only concrete piece of the Lua API we currently hold.

## The shipped scripts are the API documentation  **[DOCUMENTED]**

Artofeel posted decompiled scripts in 2013 (`fable3_decompiled_scripts_1.zip`, 223 KB). The file list
shows how much of the game lives in Lua:

**AI, per creature family.** `scripts\ai\combatsequences\` and `scripts\ai\combatstyles\` carry
separate files for balverine, bandit, cultist, deadriser, dog, flocking, guard, highwaymen, hobbe,
hollowman, juggernaut, logansoldier, minion, nightcrawler, renegade, sentinel, shadow, soldier,
troll, undead, unique, wolf, plus `fable2legacy*`. The author's note: *"with these scripts, you can
dramatically change the behavior of the AI in battle."*

**About 150 files under `scripts\miscellaneous\`**, mostly enums and managers - `creaturetypes`,
`appearanceenum`, `factionidenum`, `entitymodeenum`, `expressiontypes`, `opinionaxesenum`,
`moodaxesenum`, `gossipenums`, `villagetype`, `towndemandenums`, `shoptypes`, `crimetypeenum`,
`ambientpopulationmanager`, `combatbalance`, `herolocomotionstates`.

**Quests and startup.** `scripts\quests\` including `qc999_sandbox.lua` and `questsetupscript.lua`;
`scripts\startup\startup.lua` and several E3/GDC demo startups left in.

### The two files that matter for this project

| File | Why |
|---|---|
| **`scripts\miscellaneous\agegroupenum.lua`** | the age-group enumeration the engine presumably branches on |
| **`scripts\miscellaneous\playerfamily.lua`** | **the player's family logic, in readable Lua** |

→ [[Child System]]

**[VERIFIED]** the install ships them as compiled Lua and we decompile them ourselves. **803 scripts
extracted, 797 decompiled to valid Lua**, against the 2013 archive's partial file list. The
13-year-old zip is now a cross-check, not a dependency. → [[KoreVM]]

## KoreVM, and the fact that makes everything possible

Fable 3's scripts ship compiled for **KoreVM**, which is not stock Lua. From the fable3mod
"Lua decompiler?" thread:

> *"This isn't vanilla LUA we're dealing with. It's primarily KoreVM with a bunch of other plugins
> added into it. Like **LUA++ and Pluto**."*

and

> *"KoreVM made things worse by completely rearranging the opcodes and bitwise of lua."*

**Reading** the shipped scripts is therefore hard. **Writing** new ones is not:

> *"Thankfully, Fable 3 doesn't have a problem with plaintext uncompiled LUA. Otherwise we'd really
> be screwed."*

> [!success] Arbitrary code execution is already available
> The engine **compiles plain-text Lua at runtime**. The injector drops `.lua` source into
> `data\scripts\` and it runs. We do not need to compile to KoreVM bytecode, and we do not need a
> decompiler to *write* code - only to *read* the game's own.
>
> That is the whole ballgame for "run our own code", and it was solved by the community in 2014.

### The reading problem, and four ways around it

| Route | State |
|---|---|
| **Disassembler** - `ChunkSpy_kvm.lua`, run as `lua.exe ChunkSpy_kvm.lua <script.lua> -o out.txt` | **works** |
| **Decompiler** - `crates/korevm`, ours | **solved.** 797 of 797 files emit valid Lua 5.1, 713 with nothing unrecovered. → [[KoreVM]] |
| Keshire's `Fable3LUADecompiler` | superseded. Good at widgets and menus, poor at large functional blocks. *"no one experienced has come in to write the new decompiler that's needed"* |
| **`functions.txt`** - 15,104 signatures with parameter names, by source file | **captured**. → [[Preservation]] |
| **Fable 2's scripts** - Fable 2 does *not* use KoreVM and **has** a working decompiler, and *"a lot of the scripts are the same between the two games"* | **a Rosetta stone.** Read F2's readable source to understand F3's compiled equivalent |

That last one is the underused lever. [[Prior Art|Archon's Toolbox and the Fable2Modding repo]] exist
precisely because Fable 2's Lua is tractable.

### Two more useful details

**`script` vs `script_r`.** *"There shouldn't be a difference between the script and script_r other
than one contains compiler debug information. Which is REALLY helpful as it contains line information
and local variables."* The forum's conclusion that retail ships only the stripped `_r` bank is
**wrong for this install**: `data\` holds **both**, and `gamescripts.bnk` retains full debug data -
source paths, line numbers, local names. That is why decompiled output carries real variable names.
→ [[KoreVM]]

**But not uniformly, and the exception explains itself.** 33 chunks in `gamescripts.bnk` carry no
debug data at all. Diffing the two banks:

| | entries |
|---|---|
| `gamescripts.bnk` (debug) | 803 |
| `gamescripts_r.bnk` (retail, the one mounted) | 770 |
| difference | **33** |

The 33 files missing from the retail bank are **exactly** the 33 with no debug data, and all 33 are
under `scripts/gameface/`. They are duplicates: retail's UI scripts come from **`guiscripts.bnk`**,
which `startup.vfsconfig` mounts separately. The gameface copies inside `gamescripts.bnk` are
leftovers from a different build path, which is why they alone were compiled stripped.

### `guiscripts.bnk`, a third corpus  **[VERIFIED]** 2026-08-06

157 entries, 0 extraction failures, 4.97 MB: the Anark Gameface UI middleware (`.bgf`, `.bsg`,
`.fac`) plus **55 `.lua` files**. Of those:

- **33 are compiled** and decompile to valid Lua, stripped, with synthesised local names.
- **22 are plaintext, uncompiled Lua source**, shipped as-is. All 22 parse as valid Lua 5.1.

That is the "plaintext survivors" the forum mentioned, and there are far more of them here than the
6 `.txt` files in `gamescripts.bnk`. They also reveal a third loading mechanism - `dofile` (12 uses)
against a `g_GUIScriptDirectory` global (10 uses):

```lua
function self:onInitialize()
    dofile(g_GUIScriptDirectory .. "HUD\\ScreenCenterToggle.lua")
    self:onInitializeReal()
end
```

**Some plaintext survived.** *"They actually put plaintext, uncompiled lua in copies of certain
files. Like `scriptactivation.lua`."* Worth hunting for every such file in the install; each one is
free documentation.

## Why this beats the Anniversary position

| | Anniversary | Fable III |
|---|---|---|
| Run new code | unsolved after a full day | documented, with a working example |
| Iterate | rebuild, relaunch | **edit file, alt-tab** |
| Read the game's own logic | compiled defs, reverse-engineered | **decompiled Lua source** |
| AI behaviour | opaque | per-creature Lua files |

## Preservation risk - act early

`fable3mod.com` / `.net` has a **broken TLS certificate** and only responds over plain HTTP, and the
key threads date from 2013-2014. This is the identical failure mode the Anniversary project found on
fabletlcmod.com, where the response was to mirror the whole wiki.

**Retrieval note:** `WebFetch` force-upgrades to HTTPS and fails. Use `curl.exe -s -L` over `http://`.

**Not yet captured:** `fable3_decompiled_scripts_1.zip`, `ScriptInjector.zip`, and the forum threads
themselves. Mirroring these should be an early task, not a late one.

## Related

- [[Child System]] · [[Prior Art]] · [[Open Questions]]
