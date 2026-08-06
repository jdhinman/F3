---
title: "Lua Scripting"
description: "Fable III's game logic is extensively Lua, the scripts have been decompiled, and mod scripts hot-reload without relaunching"
updated: 2026-08-05
confidence: documented
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

All **[DOCUMENTED]**. Sources are the fable3mod forums, retrieved 2026-08-05.

## The injection method  **[DOCUMENTED]**

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

**[UNKNOWN]** whether the retail PC install ships these as compiled Lua that we can decompile
ourselves, or whether we depend on that 2013 archive. Establish this first - a self-serve decompile
is worth far more than a 13-year-old zip.

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
| **Decompiler** - Keshire's `Fable3LUADecompiler` | partial. Good at widgets and menus, poor at large functional blocks. *"no one experienced has come in to write the new decompiler that's needed"* |
| **`functions.txt`** - 15,104 signatures with parameter names, by source file | **captured**. → [[Preservation]] |
| **Fable 2's scripts** - Fable 2 does *not* use KoreVM and **has** a working decompiler, and *"a lot of the scripts are the same between the two games"* | **a Rosetta stone.** Read F2's readable source to understand F3's compiled equivalent |

That last one is the underused lever. [[Prior Art|Archon's Toolbox and the Fable2Modding repo]] exist
precisely because Fable 2's Lua is tractable.

### Two more useful details

**`script` vs `script_r`.** *"There shouldn't be a difference between the script and script_r other
than one contains compiler debug information. Which is REALLY helpful as it contains line information
and local variables."* Retail ships `_r`, the stripped one - which is why decompiling our own install
is the hard path.

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
