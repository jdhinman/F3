---
title: "Child System"
description: "What Fable III's children do, where the age data reportedly lives, and what growing them up would actually require"
updated: 2026-08-05
confidence: documented
tags:
  - target
  - gameplay
---

The project's target feature. **[DOCUMENTED] only** - nothing verified against the install yet.

## What the game does today

Fable III lets the hero marry and have children. A child is born as a baby and grows **once**, into a
child. Then it stops, permanently. There is no adulthood, no continued ageing, and no generational
play.

This is a well-known complaint rather than an obscure gap, which matters for two reasons: there is
demonstrated player demand, and there is a decent chance someone has already tried, so
[[Prior Art|check before building]].

## Where the data reportedly lives

Traced to its source: **Artofeel** on the fable3mod forums, 2014-02-18, in a thread about making
children killable. Retrieved 2026-08-05. Paraphrasing closely:

- *"killable children is hardcoded with AGE parameter"*
- set age for all children above 18 and *"they will be killable and they no more will be children"*
- GDB route: edit `globals.gdb`, main children offset **`101BF01F`**, find **`AgeComponent`**, change
  `Age` to **> 18** - or to **0**, which yields a month-old baby
- hex route: offset **`0019176C`**, change the value to **> 12 (hex)**, or to 0
- *"this offsets for latest DLC"*
- **"this effects only for new children's, not to already exist"**

Three things in that are load-bearing:

1. **Age is not cosmetic.** The author says being a child is *hardcoded against the AGE parameter*,
   and that crossing 18 stops them being children. That is a real category boundary, not a label.
2. **It only affects newly created children.** Existing saves keep their existing children unchanged,
   which shapes any mod's testing plan and its user instructions.
3. **The offsets are version-specific** - quoted as being for the latest DLC. They will not be
   trusted until re-derived locally.

> [!warning] The author never tested the consequences
> The same post says outright *"I never tested!!"* about what happens afterwards. So we have a
> located field and a stated threshold, and **no evidence at all** about whether the result is a
> functioning adult.

**[UNKNOWN]** whether the two quoted offsets are the same field reached two ways, or two different
things. They are not obviously related.

## The Lua angle, which changes the plan

[[Lua Scripting|The decompiled script list]] contains two files aimed straight at this:

- **`scripts\miscellaneous\agegroupenum.lua`** - the age-group enumeration
- **`scripts\miscellaneous\playerfamily.lua`** - the player's family logic, in readable Lua

That is potentially far better than poking a byte at a fixed offset. If age groups are an enum the
Lua layer reads, and family behaviour is Lua we can read and replace, then "grow up" may be
expressible **as a script** rather than as a hex edit - version-independent, hot-reloadable, and
reviewable.

**Read those two files before designing anything.**

## The machinery already exists  **[DOCUMENTED]** - found 2026-08-05

> [!success] This reframes the whole feature
> "Children never grow up" is **not a missing feature**. The growing-up machinery ships with the
> game: a cutscene, a quest that plays it, and a debug function that triggers it. What is missing is
> whatever normally *calls* it.

Recovered from `functions.txt`, a 707 KB index of **15,104 Lua function signatures** grouped by source
file, mirrored from the fable3mod forums. → [[Preservation]]

| Symbol | Source file |
|---|---|
| **`Debug.MakeChildGrowUpThroughTime()`** | `./ai/opinionsdebug.lua` |
| **`Debug.PlayChildGrownUpICS()`** | debug ICS players |
| **`QU090_ChildGrownICS:PlayChildGrownCutscene(self)`** | `./quests/qu090_childgrownics.lua` |
| `QU080_ChildBirthICS:PlayScene(self,spouse,baby)` | `./quests/qu080_childbirthics.lua` |
| `Debug.CreateHeroChildren()`, `Debug.CreateInstantFamily()`, `Debug.CreateSpouse()`, `Debug.CreateFamily(player,world_name,level_name)` | `./ai/opinionsdebug.lua` |
| `Debug.TogglePregnancyCertainty()`, `Debug.ResetCurrentRelationshipStage(hero,stage)` | `./ai/opinionsdebug.lua` |

`QU090_ChildGrownICS` is a **complete quest** - `Init`, a state machine, camera setup,
`SetChildAndParentPositions`, `GetParent`, `GetMaritalHomeMarkers`, `CheckLineOfSight`. Someone built
the entire child-grown-up scene.

### The surrounding family simulation is also richer than expected

| Area | Evidence |
|---|---|
| Parent/child AI | `behaviourparentchildinteraction.lua` - `BehaviourChildTalkToParent`, `BehaviourParentTalkToChild` |
| Child labour | `behaviourchildlabour.lua` - goto table, work at table, clean floor, hammer, carry |
| Spouse AI | `behaviourspouse.lua` - `BehaviourSpousePostChildBirth`, `BehaviourSpouseHoneymoonPeriod`, `GetLineAboutChild(self,child)` |
| Divorce | `familydivorcegroupmind.lua` |
| Orphanage | `orphanagegroupmind.lua` |
| Family queries | `ScriptFunction.IsPlayersChild(entity)`, `GetNonHeroParentForChild`, `GetNannyForChild`, `GetNonHeroGuardianForChild` |
| World map | `worldmap/family.lua` - `NewFamilyMember(mesh_id,offset,is_child)` |

Note `NewFamilyMember` takes a **`mesh_id`** and an **`is_child`** flag, which is the first hint that
child and adult family members are distinct meshes rather than one scaled model.

### Why this is probably a one-line mod, and why that needs proving

[[Lua Scripting|The injector's own worked example is `Debug.SetUseFreeCamera(true)`]] - a `Debug.*`
call, dropped in a script file, taking effect on the next tick. `Debug.MakeChildGrowUpThroughTime()`
is the same shape of symbol in the same namespace.

**So the first experiment is a single line in `MyScript01.lua`.**

**[UNKNOWN]** and not to be assumed:

- whether these `Debug.*` functions survive in the **retail** build or were stripped
- whether "grow up through time" advances one step (baby to child, the step that already works) or
  goes further
- whether the result is a functioning adult, or the broken thing the section below warns about
- what `agegroupenum.lua` actually enumerates - it contains no functions, so it is pure data and its
  contents were not recoverable from `functions.txt`

## The hard question nobody has answered

**Does raising the age value produce a functioning adult, or a broken child?**

An NPC is not just an age number. Growing one up plausibly needs all of:

| Concern | Why it might break |
|---|---|
| Mesh and skeleton | child and adult bodies are different assets; scaling a child is not an adult |
| Animation set | child animation may not exist for adult actions, and vice versa |
| Dialogue and voice | children have their own lines; an adult using them reads as broken |
| AI and schedules | village-member behaviour may be gated on being an adult |
| Save compatibility | an entity changing category mid-save is a classic corruption source |

**Assume the naive edit produces something visibly wrong.** The interesting work is what happens
after that, and the honest first milestone is *finding out precisely how it breaks*.

## Two routes, and they are complementary

**Data route - `globals.gdb`.** Change the age or the growth definition directly. Static, applies at
load, no runtime code. Simplest to try, easiest to get wrong silently.

**Script route - Lua.** [[Prior Art|Scripts run on a schedule and hot-reload]], so a script could
observe a child entity, drive a transition, or swap what the data route cannot express. Far more
capable, and the reason this platform was chosen over Anniversary.

The likely answer is both: data defines what an adult child *is*, script drives the transition and
patches up whatever the data model cannot say.

## First milestones, in order

1. **Find a child entity in a real save or level** and read what the game actually stores about it.
2. **Establish the Lua API surface** - what can a script see and call? Without this the script route
   is speculation.
3. **Change the age by the documented route** and observe, in game, exactly what breaks.
4. Only then decide whether "grow up" means a category change, an asset swap, or a new entity.

## Related

- [[Prior Art]] · [[Open Questions]]
